import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'transport.dart';
import 'package:offgrid_sos/core/logger.dart';

// Service / characteristic UUIDs ต้องตรงกันทุกเครื่อง
final _svcUUID = UUID.fromString('12345678-1234-1234-1234-1234567890ab');
final _rxUUID  = UUID.fromString('12345678-1234-1234-1234-1234567890ac'); // central writes → peripheral reads
final _txUUID  = UUID.fromString('12345678-1234-1234-1234-1234567890ad'); // peripheral notifies → central reads
final _cccUUID = UUID.fromString('00002902-0000-1000-8000-00805f9b34fb'); // CCCD descriptor

const _headerMsg  = 'MSG:';
const _headerMeta = 'META:';
const _headerFile = 'FILE:';
const _headerEnd  = 'END:';
const _chunkSize  = 500;

/// BLE P2P Transport — ทำงาน 2 บทบาทพร้อมกัน:
/// - Peripheral: advertise + GATT server (รับ write บน RX, notify ออก TX)
/// - Central: scan + connect + write RX, subscribe TX
class BleTransport implements Transport {
  final String deviceName;
  bool _isDisposed = false;
  DiscoveryState _state = DiscoveryState.idle;

  final _central    = CentralManager();
  final _peripheral = PeripheralManager();

  final _peersCtrl = StreamController<List<Peer>>.broadcast();
  final _msgCtrl   = StreamController<Message>.broadcast();
  final _fileCtrl  = StreamController<ReceivedFile>.broadcast();

  // Central role: อุปกรณ์ที่เราค้นพบและเชื่อมต่อในฐานะ Central
  final Map<String, Peripheral> _foundPeripherals     = {};
  final Map<String, Peripheral> _connectedPeripherals = {};
  final Map<String, GATTCharacteristic> _rxChars      = {}; // cache RX char per peer

  // Peripheral role: centrals ที่ subscribe TX characteristic ของเรา
  GATTCharacteristic? _txChar;
  final Map<String, Central> _subscribedCentrals = {}; // centralId -> Central

  // ชื่อจริงของแต่ละ peer (จาก advertisement หรือ BNAME exchange)
  final Map<String, String> _peripheralNames = {};

  // File assembly buffer: peerId → bytes
  final Map<String, List<int>> _fileBuffer = {};
  final Map<String, Map<String, dynamic>> _fileMeta = {};

  final List<StreamSubscription> _subs = [];
  Timer? _scanTimer;

  BleTransport({this.deviceName = 'SOS Device'});

  // ─── Transport interface ───────────────────────────────────────────────

  @override DiscoveryState get discoveryState => _state;
  @override Stream<List<Peer>> get onPeers    => _peersCtrl.stream;
  @override Stream<Message> get onMessage     => _msgCtrl.stream;
  @override Stream<ReceivedFile> get onFileReceived => _fileCtrl.stream;

  // ─── Discovery ────────────────────────────────────────────────────────

  @override
  Future<void> startDiscovery() async {
    if (_isDisposed || _state == DiscoveryState.scanning) return;
    if (!await _requestPermissions()) {
      Log.d('[BLE] Permission denied');
      return;
    }
    _state = DiscoveryState.scanning;
    // ทำงานพร้อมกัน: ทั้ง advertise และ scan
    await Future.wait([_setupPeripheral(), _setupCentral()]);
  }

  // ─── Peripheral role ──────────────────────────────────────────────────

  Future<void> _setupPeripheral() async {
    try {
      final rxChar = GATTCharacteristic.mutable(
        uuid: _rxUUID,
        properties: [
          GATTCharacteristicProperty.write,
          GATTCharacteristicProperty.writeWithoutResponse,
        ],
        permissions: [GATTCharacteristicPermission.write],
        descriptors: [],
      );

      _txChar = GATTCharacteristic.mutable(
        uuid: _txUUID,
        properties: [GATTCharacteristicProperty.notify],
        permissions: [],
        descriptors: [
          // CCCD descriptor ให้ central enable/disable notify ได้
          GATTDescriptor.mutable(
            uuid: _cccUUID,
            permissions: [
              GATTCharacteristicPermission.read,
              GATTCharacteristicPermission.write,
            ],
          ),
        ],
      );

      final service = GATTService(
        uuid: _svcUUID,
        isPrimary: true,
        includedServices: [],
        characteristics: [rxChar, _txChar!],
      );

      await _peripheral.addService(service);

      // รับ write จาก central (incoming messages / files)
      _subs.add(_peripheral.characteristicWriteRequested.listen((event) async {
        final centralId = event.central.uuid.toString();
        _subscribedCentrals[centralId] = event.central;

        if (event.characteristic.uuid == _rxUUID) {
          final value = event.request.value;
          _handleIncoming(centralId, value);
        }
        // ตอบกลับเพื่อไม่ให้ central timeout
        await _peripheral.respondWriteRequest(event.request);
      }));

      // ติดตาม central ที่ subscribe TX (เพื่อส่ง notify กลับ)
      _subs.add(_peripheral.characteristicNotifyStateChanged.listen((event) {
        if (event.characteristic.uuid != _txUUID) return;
        final centralId = event.central.uuid.toString();
        if (event.state) {
          _subscribedCentrals[centralId] = event.central;
          Log.d('[BLE] Central subscribed: $centralId');
        } else {
          _subscribedCentrals.remove(centralId);
          Log.d('[BLE] Central unsubscribed: $centralId');
        }
      }));

      // advertise โดยไม่ต้องระบุ serviceUUIDs ใน Advertisement —
      // service UUID จะถูกส่งผ่าน GATT service ที่ addService() ไปแล้ว
      await _peripheral.startAdvertising(
        Advertisement(
          name: deviceName,
          manufacturerSpecificData: [],
        ),
      );
      Log.d('[BLE] Advertising as: $deviceName');
    } catch (e) {
      Log.d('[BLE] Peripheral setup error: $e');
    }
  }

  // ─── Central role ─────────────────────────────────────────────────────

  Future<void> _setupCentral() async {
    // พบเครื่องใหม่ → ลอง connect
    _subs.add(_central.discovered.listen((event) {
      final id = event.peripheral.uuid.toString();
      // เก็บชื่อจาก advertisement ทุกครั้งที่เห็น (อาจอัปเดตถ้าเคยว่าง)
      final advName = event.advertisement.name;
      if (advName != null && advName.isNotEmpty) {
        _peripheralNames[id] = advName;
      }
      if (!_foundPeripherals.containsKey(id)) {
        _foundPeripherals[id] = event.peripheral;
        _connectToPeer(id, event.peripheral);
      }
    }));

    // สถานะการเชื่อมต่อเปลี่ยน
    _subs.add(_central.connectionStateChanged.listen((event) {
      final id = event.peripheral.uuid.toString();
      if (event.state == ConnectionState.connected) {
        _connectedPeripherals[id] = event.peripheral;
        _discoverAndSubscribe(id, event.peripheral);
        _emitPeers();
      } else {
        _connectedPeripherals.remove(id);
        _rxChars.remove(id);
        _emitPeers();
      }
    }));

    // รับ notify จาก TX characteristic ของ peer
    _subs.add(_central.characteristicNotified.listen((event) {
      final peerId = event.peripheral.uuid.toString();
      _handleIncoming(peerId, event.value);
    }));

    await _central.startDiscovery(serviceUUIDs: [_svcUUID]);

    // scan ซ้ำทุก 15 วินาทีเพื่อไม่ให้พลาดเครื่องใหม่
    _scanTimer?.cancel();
    _scanTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (!_isDisposed && _state == DiscoveryState.scanning) {
        await _central.stopDiscovery();
        await _central.startDiscovery(serviceUUIDs: [_svcUUID]);
      }
    });
    Log.d('[BLE] Central scanning started');
  }

  Future<void> _connectToPeer(String peerId, Peripheral peripheral) async {
    try {
      await _central.connect(peripheral);
    } catch (e) {
      Log.d('[BLE] Connect error $peerId: $e');
    }
  }

  Future<void> _discoverAndSubscribe(String peerId, Peripheral peripheral) async {
    try {
      final services = await _central.discoverGATT(peripheral);
      for (final service in services) {
        if (service.uuid != _svcUUID) continue;
        for (final char in service.characteristics) {
          if (char.uuid == _rxUUID) {
            _rxChars[peerId] = char;
          }
          if (char.uuid == _txUUID) {
            await _central.setCharacteristicNotifyState(
              peripheral,
              char,
              state: true,
            );
            Log.d('[BLE] Subscribed to TX from $peerId');
          }
        }
      }
      // แจ้งชื่อเครื่องเราให้ peer รู้ (เพื่อให้ฝั่ง Peripheral ได้ชื่อจริง)
      if (_rxChars.containsKey(peerId)) {
        await _sendTo(peerId, Uint8List.fromList(utf8.encode('BNAME:$deviceName')));
      }
    } catch (e) {
      Log.d('[BLE] GATT discover error $peerId: $e');
    }
  }

  // ─── Send ──────────────────────────────────────────────────────────────

  @override
  Future<void> sendMessage(String body, {Peer? to}) async {
    final data = Uint8List.fromList(utf8.encode('$_headerMsg$body'));
    for (final id in _resolveTargets(to?.id)) {
      await _sendTo(id, data);
    }
  }

  @override
  Future<void> sendFile(String filePath, {Peer? to}) async {
    final file = File(filePath);
    if (!await file.exists()) throw Exception('File not found: $filePath');

    final bytes   = await file.readAsBytes();
    final name    = filePath.split('/').last;
    final targets = _resolveTargets(to?.id);

    for (final id in targets) {
      // 1. metadata
      await _sendTo(id, Uint8List.fromList(
          utf8.encode('$_headerMeta${json.encode({'name': name, 'size': bytes.length})}')));

      // 2. chunks
      int offset = 0, seq = 0;
      while (offset < bytes.length) {
        final end    = (offset + _chunkSize).clamp(0, bytes.length);
        final header = utf8.encode('$_headerFile$seq:');
        await _sendTo(id, Uint8List.fromList([...header, ...bytes.sublist(offset, end)]));
        offset = end;
        seq++;
        await Future.delayed(const Duration(milliseconds: 20));
      }

      // 3. end marker
      await _sendTo(id, Uint8List.fromList(utf8.encode('$_headerEnd$name')));
    }
  }

  List<String> _resolveTargets(String? toId) {
    if (toId != null) return [toId];
    return {
      ..._connectedPeripherals.keys,
      ..._subscribedCentrals.keys,
    }.toList();
  }

  Future<void> _sendTo(String peerId, Uint8List data) async {
    // Route 1: เราเชื่อมต่อกับ peer ในฐานะ Central → write ไปที่ RX char ของ peer
    final peripheral = _connectedPeripherals[peerId];
    final rxChar     = _rxChars[peerId];
    if (peripheral != null && rxChar != null) {
      try {
        await _central.writeCharacteristic(
          peripheral,
          rxChar,
          value: data,
          type: GATTCharacteristicWriteType.withResponse,
        );
        return;
      } catch (e) {
        Log.d('[BLE] Write failed $peerId: $e');
      }
    }

    // Route 2: peer เชื่อมต่อมาหาเราในฐานะ Central → notify ผ่าน TX char
    final central = _subscribedCentrals[peerId];
    if (central != null && _txChar != null) {
      try {
        await _peripheral.notifyCharacteristic(
          central,
          _txChar!,
          value: data,
        );
        return;
      } catch (e) {
        Log.d('[BLE] Notify failed $peerId: $e');
      }
    }

    Log.d('[BLE] No route to $peerId');
  }

  // ─── Receive ───────────────────────────────────────────────────────────

  void _handleIncoming(String peerId, Uint8List bytes) {
    final raw = utf8.decode(bytes, allowMalformed: true);

    // ── ชื่อเครื่องจาก peer ──
    if (raw.startsWith('BNAME:')) {
      final name = raw.substring('BNAME:'.length).trim();
      if (name.isNotEmpty) {
        _peripheralNames[peerId] = name;
        Log.d('[BLE] Received peer name: "$name" ($peerId)');
        _emitPeers(); // อัปเดต UI ทันที
        // ตอบกลับด้วยชื่อเราเพื่อให้ฝั่งที่ส่งมารู้ชื่อเราด้วย
        _sendTo(peerId, Uint8List.fromList(utf8.encode('BNAME:$deviceName')));
      }
      return;
    }

    if (raw.startsWith(_headerMsg)) {
      if (!_msgCtrl.isClosed) {
        _msgCtrl.add(Message(
          fromPeerId: peerId,
          body: raw.substring(_headerMsg.length),
          time: DateTime.now(),
        ));
      }
    } else if (raw.startsWith(_headerMeta)) {
      try {
        _fileMeta[peerId]   = json.decode(raw.substring(_headerMeta.length)) as Map<String, dynamic>;
        _fileBuffer[peerId] = [];
      } catch (_) {}
    } else if (raw.startsWith(_headerFile)) {
      // format: FILE:<seq>:<binary data>
      final colonIdx = raw.indexOf(':', _headerFile.length);
      if (colonIdx == -1) return;
      // คำนวณ header length ใน bytes เพื่อป้องกัน multi-byte UTF-8 shift
      final headerLen = utf8.encode(raw.substring(0, colonIdx + 1)).length;
      if (headerLen < bytes.length) {
        _fileBuffer[peerId]?.addAll(bytes.sublist(headerLen));
      }
    } else if (raw.startsWith(_headerEnd)) {
      _saveReceivedFile(peerId);
    }
  }

  Future<void> _saveReceivedFile(String peerId) async {
    final buffer = _fileBuffer.remove(peerId);
    final meta   = _fileMeta.remove(peerId);
    if (buffer == null || meta == null) return;
    try {
      final dir  = await getApplicationDocumentsDirectory();
      final name = (meta['name'] as String?) ?? 'ble_${DateTime.now().millisecondsSinceEpoch}';
      final path = '${dir.path}/$name';
      await File(path).writeAsBytes(buffer);
      if (!_fileCtrl.isClosed) {
        _fileCtrl.add(ReceivedFile(fromPeerId: peerId, filePath: path, time: DateTime.now()));
      }
    } catch (e) {
      Log.d('[BLE] Save file error: $e');
    }
  }

  // ─── Helpers ───────────────────────────────────────────────────────────

  // แสดง peers ที่ connect สำเร็จทั้ง 2 ทิศทาง พร้อมชื่อจริง
  void _emitPeers() {
    if (_peersCtrl.isClosed) return;
    final allIds = {
      ..._connectedPeripherals.keys,
      ..._subscribedCentrals.keys,
    };
    final peers = allIds.map((id) {
      final name = _peripheralNames[id] ??
          'BLE-${id.length >= 4 ? id.substring(id.length - 4).toUpperCase() : id}';
      return Peer(id: id, name: name, nearby: true);
    }).toList();
    _peersCtrl.add(peers);
  }

  Future<bool> _requestPermissions() async {
    if (Platform.isAndroid) {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
      ].request();
      return statuses.values.every((s) => s.isGranted);
    }
    // iOS: จัดการผ่าน Info.plist (NSBluetoothAlwaysUsageDescription)
    return true;
  }

  // ─── Stop / Dispose ────────────────────────────────────────────────────

  @override
  Future<void> stopDiscovery() async {
    _state = DiscoveryState.idle;
    _scanTimer?.cancel();
    _scanTimer = null;

    try { await _central.stopDiscovery(); } catch (_) {}
    try { await _peripheral.stopAdvertising(); } catch (_) {}
    try { await _peripheral.removeAllServices(); } catch (_) {}

    for (final p in _connectedPeripherals.values) {
      try { await _central.disconnect(p); } catch (_) {}
    }

    _foundPeripherals.clear();
    _connectedPeripherals.clear();
    _rxChars.clear();
    _subscribedCentrals.clear();
    _peripheralNames.clear();

    if (!_peersCtrl.isClosed) _peersCtrl.add([]);
  }

  @override
  Future<void> dispose() async {
    _isDisposed = true;
    await stopDiscovery();
    for (final sub in _subs) { await sub.cancel(); }
    _subs.clear();
    if (!_peersCtrl.isClosed) _peersCtrl.close();
    if (!_msgCtrl.isClosed)   _msgCtrl.close();
    if (!_fileCtrl.isClosed)  _fileCtrl.close();
  }
}
