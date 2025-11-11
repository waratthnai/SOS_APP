import 'dart:async';
import 'transport.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleTransport implements Transport {
  final _peersCtrl = StreamController<List<Peer>>.broadcast();
  final _msgCtrl = StreamController<Message>.broadcast();
  DiscoveryState _state = DiscoveryState.idle;

  final List<BluetoothDevice> _devices = [];
  StreamSubscription? _scanSub;

  @override
  DiscoveryState get discoveryState => _state;

  @override
  Stream<List<Peer>> get onPeers => _peersCtrl.stream;

  @override
  Stream<Message> get onMessage => _msgCtrl.stream;

  @override
  Future<void> startDiscovery() async {
    _state = DiscoveryState.scanning;
    _devices.clear();
    // ✅ เช็คว่า stream ยังเปิดอยู่ก่อน emit
    if (!_peersCtrl.isClosed) {
      _peersCtrl.add([]);
    }
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      final peers = <Peer>[];
      for (var r in results) {
        peers.add(Peer(id: r.device.id.id, name: r.device.name.isEmpty ? 'BLE Device' : r.device.name));
        if (!_devices.any((d) => d.id.id == r.device.id.id)) _devices.add(r.device);
      }
      // ✅ เช็คว่า stream ยังเปิดอยู่ก่อน emit
      if (!_peersCtrl.isClosed) {
        _peersCtrl.add(peers);
      }
    });
  }

  @override
  Future<void> stopDiscovery() async {
    _state = DiscoveryState.idle;
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    // ✅ เช็คว่า stream ยังเปิดอยู่ก่อน emit
    if (!_peersCtrl.isClosed) {
      _peersCtrl.add([]);
    }
  }

  @override
  Future<void> sendMessage(String body, {Peer? to}) async {
    if (to != null) {
      final device = _devices.firstWhere((d) => d.id.id == to.id, orElse: () => throw Exception('Device not found'));
      if (device.connectionState != BluetoothConnectionState.connected) {
        await device.connect();
      }
      List<BluetoothService> services = await device.discoverServices();
      for (var s in services) {
        for (var c in s.characteristics) {
          if (c.properties.write) {
            await c.write(body.codeUnits);
            break;
          }
        }
      }
      // ไม่ disconnect ทันที เพื่อรอการสื่อสารอื่น ๆ
    }
    _msgCtrl.add(Message(
      fromPeerId: 'me',
      toPeerId: to?.id,
      body: '[BLE] $body',
      time: DateTime.now(),
    ));
  }

  @override
  Future<void> sendFile(String filePath, {Peer? to}) async {
    // TODO: Implement BLE file transfer (Feature #7)
    throw UnimplementedError('BLE file transfer not yet implemented');
  }

  @override
  Future<void> dispose() async {
    await _scanSub?.cancel();
    await _peersCtrl.close();
    await _msgCtrl.close();
  }
}
