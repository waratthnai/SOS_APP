import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'transport.dart';
import 'package:offgrid_sos/core/logger.dart';

/// UUID สำหรับ SOS BLE Service (ต้องเป็น UUID เดียวกันทุกเครื่อง)
const _sosServiceUuid    = '12345678-1234-1234-1234-1234567890ab';
const _txCharUuid        = '12345678-1234-1234-1234-1234567890ac'; // เครื่องนี้ write → peer อ่าน
const _rxCharUuid        = '12345678-1234-1234-1234-1234567890ad'; // peer write → เครื่องนี้ notify

/// ขนาด chunk สำหรับส่งไฟล์ผ่าน BLE (MTU - 3 bytes overhead)
const _chunkSize = 500;

/// Header สำหรับแยกประเภท payload
const _headerMsg  = 'MSG:';
const _headerFile = 'FILE:';
const _headerMeta = 'META:'; // ส่ง metadata ก่อนไฟล์ (ชื่อไฟล์, ขนาด)
const _headerEnd  = 'END:';  // บอกว่าส่งไฟล์เสร็จแล้ว

class BleTransport implements Transport {
  final String deviceName;

  final _peersCtrl = StreamController<List<Peer>>.broadcast();
  final _msgCtrl   = StreamController<Message>.broadcast();
  final _fileCtrl  = StreamController<ReceivedFile>.broadcast();

  DiscoveryState _state = DiscoveryState.idle;
  bool _isDisposed = false;

  /// เครื่องที่ scan เจอ
  final Map<String, ScanResult>  _found     = {};
  /// เครื่องที่ connect แล้ว: peerId → device
  final Map<String, BluetoothDevice> _connected = {};
  /// characteristic ที่ใช้ write ไปหา peer: peerId → char
  final Map<String, BluetoothCharacteristic> _txChars = {};

  /// buffer รับไฟล์แบบ chunk: peerId → bytes
  final Map<String, List<int>>   _fileBuffer = {};
  /// metadata ของไฟล์ที่กำลังรับ: peerId → {'name': ..., 'size': ...}
  final Map<String, Map<String, dynamic>> _fileMeta = {};

  StreamSubscription? _scanSub;
  Timer? _scanTimer; // scan ซ้ำทุก 15 วินาที

  BleTransport({this.deviceName = 'SOS Device'});

  // ─── Transport interface ───────────────────────────────────────────────────

  @override
  DiscoveryState get discoveryState => _state;

  @override
  Stream<List<Peer>> get onPeers => _peersCtrl.stream;

  @override
  Stream<Message> get onMessage => _msgCtrl.stream;

  @override
  Stream<ReceivedFile> get onFileReceived => _fileCtrl.stream;

  // ─── Discovery ────────────────────────────────────────────────────────────

  @override
  Future<void> startDiscovery() async {
    if (_isDisposed) return;
    if (_state == DiscoveryState.scanning) return;

    if (!await _requestPermissions()) {
      _emitError('ไม่ได้รับ permission สำหรับ Bluetooth');
      return;
    }

    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      _emitError('กรุณาเปิด Bluetooth ก่อนใช้งาน');
      return;
    }

    _state = DiscoveryState.scanning;
    _found.clear();
    _emit([]);

    await _doScan();

    _scanTimer?.cancel();
    _scanTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!_isDisposed && _state == DiscoveryState.scanning) _doScan();
    });
  }

  Future<void> _doScan() async {
    _scanSub?.cancel();

    await FlutterBluePlus.startScan(
      withServices: [Guid(_sosServiceUuid)],
      timeout: const Duration(seconds: 10),
      androidUsesFineLocation: false,
    );

    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      bool changed = false;
      for (final r in results) {
        final id = r.device.remoteId.str;
        if (!_found.containsKey(id)) {
          _found[id] = r;
          changed = true;
        }
      }
      if (changed) _emitPeers();
    });
  }

  @override
  Future<void> stopDiscovery() async {
    _state = DiscoveryState.idle;
    _scanTimer?.cancel();
    _scanTimer = null;
    await _scanSub?.cancel();
    _scanSub = null;
    await FlutterBluePlus.stopScan();
    _emit([]);
  }

  // ─── Connect & setup ──────────────────────────────────────────────────────

  Future<bool> connectPeer(String peerId) async {
    if (_connected.containsKey(peerId)) return true;

    final scanResult = _found[peerId];
    if (scanResult == null) return false;

    final device = scanResult.device;
    try {
      await device.connect(autoConnect: false, timeout: const Duration(seconds: 10));
    } catch (e) {
      _log('❌ connect failed: $e');
      return false;
    }

    _connected[peerId] = device;

    device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _connected.remove(peerId);
        _txChars.remove(peerId);
        _emitPeers();
      }
    });

    final services = await device.discoverServices();
    BluetoothService? sosSvc;
    for (final s in services) {
      if (s.serviceUuid == Guid(_sosServiceUuid)) {
        sosSvc = s;
        break;
      }
    }
    if (sosSvc == null) {
      await device.disconnect();
      _connected.remove(peerId);
      return false;
    }

    for (final c in sosSvc.characteristics) {
      if (c.characteristicUuid == Guid(_txCharUuid) && c.properties.write) {
        _txChars[peerId] = c;
      }
      if (c.characteristicUuid == Guid(_rxCharUuid) && c.properties.notify) {
        await c.setNotifyValue(true);
        c.onValueReceived.listen((bytes) => _handleIncoming(peerId, bytes));
      }
    }

    _emitPeers();
    return _txChars.containsKey(peerId);
  }

  // ─── Send message ─────────────────────────────────────────────────────────

  @override
  Future<void> sendMessage(String body, {Peer? to}) async {
    final payload = utf8.encode('$_headerMsg$body');

    if (to != null) {
      await _ensureConnected(to.id);
      await _writeChunked(to.id, payload);
    } else {
      for (final id in List.of(_connected.keys)) {
        await _writeChunked(id, payload);
      }
    }

    if (!_msgCtrl.isClosed) {
      _msgCtrl.add(Message(
        fromPeerId: 'me',
        toPeerId: to?.id,
        body: body,
        time: DateTime.now(),
      ));
    }
  }

  // ─── Send file ────────────────────────────────────────────────────────────

  @override
  Future<void> sendFile(String filePath, {Peer? to}) async {
    final file = File(filePath);
    if (!await file.exists()) throw Exception('File not found: $filePath');

    final bytes  = await file.readAsBytes();
    final name   = filePath.split('/').last;
    final size   = bytes.length;

    final meta = '$_headerMeta${json.encode({'name': name, 'size': size})}';
    final targets = to != null ? [to.id] : List.of(_connected.keys);

    for (final id in targets) {
      await _ensureConnected(id);
      await _writeChunked(id, utf8.encode(meta));
      int offset = 0;
      int seq = 0;
      while (offset < bytes.length) {
        final end   = (offset + _chunkSize).clamp(0, bytes.length);
        final chunk = bytes.sublist(offset, end);
        final header = utf8.encode('$_headerFile$seq:');
        await _writeChunked(id, Uint8List.fromList([...header, ...chunk]));
        offset = end;
        seq++;
        await Future.delayed(const Duration(milliseconds: 20));
      }
      await _writeChunked(id, utf8.encode('$_headerEnd$name'));
    }
  }

  // ─── Receive ──────────────────────────────────────────────────────────────

  void _handleIncoming(String peerId, List<int> bytes) {
    final raw = utf8.decode(bytes, allowMalformed: true);

    if (raw.startsWith(_headerMsg)) {
      final body = raw.substring(_headerMsg.length);
      if (!_msgCtrl.isClosed) {
        _msgCtrl.add(Message(
          fromPeerId: peerId,
          body: body,
          time: DateTime.now(),
        ));
      }
    } else if (raw.startsWith(_headerMeta)) {
      final metaJson = raw.substring(_headerMeta.length);
      try {
        _fileMeta[peerId]   = json.decode(metaJson) as Map<String, dynamic>;
        _fileBuffer[peerId] = [];
      } catch (_) {}
    } else if (raw.startsWith(_headerFile)) {
      final colonIdx = raw.indexOf(':', _headerFile.length);
      if (colonIdx == -1) return;
      final dataStart = colonIdx + 1;
      final chunkBytes = bytes.sublist(utf8.encode(raw.substring(0, dataStart)).length);
      _fileBuffer[peerId]?.addAll(chunkBytes);
    } else if (raw.startsWith(_headerEnd)) {
      _saveReceivedFile(peerId);
    }
  }

  Future<void> _saveReceivedFile(String peerId) async {
    final buffer = _fileBuffer[peerId];
    final meta   = _fileMeta[peerId];
    if (buffer == null || meta == null) return;

    try {
      final dir  = await getApplicationDocumentsDirectory();
      final name = (meta['name'] as String?) ?? 'ble_file_${DateTime.now().millisecondsSinceEpoch}';
      final path = '${dir.path}/$name';
      await File(path).writeAsBytes(buffer);

      if (!_fileCtrl.isClosed) {
        _fileCtrl.add(ReceivedFile(
          fromPeerId: peerId,
          filePath: path,
          time: DateTime.now(),
        ));
      }
    } catch (e) {
      _log('❌ save file error: $e');
    } finally {
      _fileBuffer.remove(peerId);
      _fileMeta.remove(peerId);
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  Future<void> _ensureConnected(String peerId) async {
    if (!_connected.containsKey(peerId)) {
      final ok = await connectPeer(peerId);
      if (!ok) throw Exception('Cannot connect to $peerId');
    }
  }

  Future<void> _writeChunked(String peerId, List<int> data) async {
    final char = _txChars[peerId];
    if (char == null) return;
    final bytes = data is Uint8List ? data : Uint8List.fromList(data);
    int offset = 0;
    while (offset < bytes.length) {
      final end   = (offset + _chunkSize).clamp(0, bytes.length);
      final chunk = bytes.sublist(offset, end);
      await char.write(chunk, withoutResponse: false);
      offset = end;
    }
  }

  void _emitPeers() {
    final peers = _found.entries.map((e) {
      final name = e.value.device.platformName.isEmpty
          ? 'BLE Device'
          : e.value.device.platformName;
      return Peer(id: e.key, name: name);
    }).toList();
    _emit(peers);
  }

  void _emit(List<Peer> peers) {
    if (!_peersCtrl.isClosed) _peersCtrl.add(peers);
  }

  void _emitError(String msg) {
    _log('⚠️ $msg');
    _emit([]);
  }

  void _log(String msg) => Log.d('[BleTransport] $msg');

  Future<bool> _requestPermissions() async {
    if (Platform.isAndroid) {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
      ].request();
      return statuses.values.every((s) => s.isGranted);
    }
    // iOS — flutter_blue_plus จัดการ permission dialog เองผ่าน Info.plist
    return true;
  }

  // ─── Dispose ──────────────────────────────────────────────────────────────

  @override
  Future<void> dispose() async {
    _isDisposed = true;
    _scanTimer?.cancel();
    await _scanSub?.cancel();
    await FlutterBluePlus.stopScan();
    for (final device in _connected.values) {
      await device.disconnect();
    }
    _connected.clear();
    _txChars.clear();
    if (!_peersCtrl.isClosed) await _peersCtrl.close();
    if (!_msgCtrl.isClosed)   await _msgCtrl.close();
    if (!_fileCtrl.isClosed)  await _fileCtrl.close();
  }
}
