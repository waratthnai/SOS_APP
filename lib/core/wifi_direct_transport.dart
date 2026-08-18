import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'transport.dart';
import 'package:offgrid_sos/core/logger.dart';

class WifiDirectTransport implements Transport {
  final _peersCtrl = StreamController<List<Peer>>.broadcast();
  final _msgCtrl = StreamController<Message>.broadcast();
  final _fileCtrl = StreamController<ReceivedFile>.broadcast();
  DiscoveryState _state = DiscoveryState.idle;
  final List<Peer> _currentPeers = [];
  final String deviceName; // 🔧 เพิ่ม device name
  
  // 📍 เก็บ mapping ระหว่าง peerId กับ actual device name
  final Map<String, String> _peerNames = {};
  // 🔗 แปลง IP → MAC เพื่อให้ fromPeerId ตรงกับ peer.id ที่มาจาก WifiP2pDevice.deviceAddress
  final Map<String, String> _ipToMac = {};

  static const platform = MethodChannel('wifi_direct');
  static const eventChannel = EventChannel('wifi_direct/events');
  StreamSubscription? _eventSub;
  Timer? _discoveryTimer; // เพิ่ม timer สำหรับค้นหาซ้ำ

  // 🔧 ป้องกัน "System busy"
  bool _isDiscovering = false;
  DateTime? _lastDiscoveryAttempt;
  int _failedAttempts = 0;
  static const _minDiscoveryInterval = Duration(seconds: 20);
  
  WifiDirectTransport({String? deviceName}) 
      : deviceName = deviceName ?? 'WiFi Device';

  @override
  DiscoveryState get discoveryState => _state;

  @override
  Stream<List<Peer>> get onPeers => _peersCtrl.stream;

  @override
  Stream<Message> get onMessage => _msgCtrl.stream;
  
  @override
  Stream<ReceivedFile> get onFileReceived => _fileCtrl.stream;

  @override
  Future<void> startDiscovery() async {
    try {
      _state = DiscoveryState.scanning;
      Log.d('📶 [WiFi Direct] Starting peer discovery...');
      Log.d('📶 [WiFi Direct] Device name: $deviceName');
      
      // 🔧 ส่ง device name ไปยัง native code
      try {
        await platform.invokeMethod('setDeviceName', {'name': deviceName});
        Log.d('✅ [WiFi Direct] Device name set successfully');
      } catch (e) {
        Log.d('⚠️ [WiFi Direct] Failed to set device name: $e');
      }
      
      // เริ่มค้นหาครั้งแรก
      await _triggerDiscovery();
      
      // ✅ ตั้ง timer ให้ค้นหาซ้ำทุก 30 วินาที (เพิ่มจาก 20 เพื่อให้เวลาเชื่อมต่อ)
      _discoveryTimer?.cancel();
      _discoveryTimer = Timer.periodic(const Duration(seconds: 20), (_) {
        Log.d('🔄 [WiFi Direct] Periodic discovery...');
        _triggerDiscovery(); // ฟังก์ชันนี้จะเช็คเงื่อนไขเองแล้ว
      });
      
      // 🔧 ส่ง device name broadcast ทันทีเมื่อเริ่ม scan
      Future.delayed(const Duration(seconds: 2), () {
        sendMessage('DEVICE_NAME:$deviceName');
      });
      
      _eventSub?.cancel();
      _eventSub = eventChannel.receiveBroadcastStream().listen((event) {
        if (event is Map) {
          final type = event['type'];
          
          if (type == 'connectionStatus') {
            // 🔧 จัดการ connection status จาก native
            final isConnected = event['isConnected'] as bool? ?? false;
            final role = event['role']?.toString() ?? 'unknown';
            Log.d('🔌 [WiFi Direct] Connection status: ${isConnected ? "Connected" : "Disconnected"} (role: $role)');
            
            if (isConnected) {
              // ส่ง DEVICE_NAME เมื่อเชื่อมต่อสำเร็จ
              Future.delayed(const Duration(milliseconds: 500), () {
                Log.d('📤 [WiFi Direct] Sending device name after connection: $deviceName');
                sendMessage('DEVICE_NAME:$deviceName');
              });
            }
            
          } else if (type == 'peers') {
            final peersList = (event['peers'] as List?) ?? [];
            _currentPeers.clear();
            
            for (var p in peersList) {
              if (p is Map) {
                final peerId = p['id']?.toString() ?? '';
                final peerName = p['name']?.toString() ?? 'Unknown';
                
                // 🔧 บันทึกชื่อของ peer
                _peerNames[peerId] = peerName;
                
                final peer = Peer(
                  id: peerId,
                  name: peerName,
                  nearby: true,
                );
                _currentPeers.add(peer);
              }
            }
            
            // ✅ เช็คว่า stream ยังเปิดอยู่ก่อน emit
            if (!_peersCtrl.isClosed) {
              _peersCtrl.add(List.from(_currentPeers));
              Log.d('📶 [WiFi Direct] Found ${_currentPeers.length} peers');
            }
            
          } else if (type == 'message') {
            final fromPeerId = event['fromPeerId']?.toString() ?? 'unknown';
            final body = event['body']?.toString() ?? '';
            
            Log.d('📶 [WiFi Direct] Raw message received: fromPeerId=$fromPeerId, body=${body.length > 100 ? '${body.substring(0, 100)}...' : body}');
            
            // จัดการ DEVICE_NAME message แยกต่างหาก
            if (body.startsWith('DEVICE_NAME:')) {
              final peerDeviceName = body.substring(12);
              _peerNames[fromPeerId] = peerDeviceName;
              Log.d('📝 [WiFi Direct] Updated peer name: $fromPeerId -> $peerDeviceName');

              // สร้าง IP→MAC mapping โดย lookup จาก _currentPeers ด้วยชื่อ
              // ทำให้ GPS_LOC และ message อื่นๆ ใช้ MAC (peer.id) แทน IP ได้
              final match = _currentPeers.where((p) => p.name == peerDeviceName).firstOrNull;
              if (match != null && match.id != fromPeerId) {
                _ipToMac[fromPeerId] = match.id;
                Log.d('🔗 [WiFi Direct] IP→MAC: $fromPeerId → ${match.id}');
              }

              // อัปเดต peer list ใหม่
              final peerIndex = _currentPeers.indexWhere((p) => p.id == fromPeerId);
              if (peerIndex >= 0) {
                _currentPeers[peerIndex] = Peer(
                  id: fromPeerId,
                  name: peerDeviceName,
                  nearby: true,
                );
                if (!_peersCtrl.isClosed) {
                  _peersCtrl.add(List.from(_currentPeers));
                }
              }
              return; // DEVICE_NAME ไม่ส่งต่อไปยัง message stream
            }

            // แปลง IP → MAC ก่อน emit เพื่อให้ fromPeerId ตรงกับ peer.id ใน UI
            final resolvedId = _ipToMac[fromPeerId] ?? fromPeerId;
            final fromName = _peerNames[fromPeerId] ?? fromPeerId;

            Log.d('📶 [WiFi Direct] Forwarding to app: from=$fromName ($resolvedId), body=${body.substring(0, body.length > 80 ? 80 : body.length)}...');
            _msgCtrl.add(Message(
              fromPeerId: resolvedId,
              body: body,
              time: DateTime.now(),
            ));
          } else if (type == 'file') {
            final fromPeerId = event['fromPeerId']?.toString() ?? 'unknown';
            final filePath = event['filePath']?.toString() ?? '';
            Log.d('📁 [WiFi Direct] ได้รับไฟล์จาก $fromPeerId: $filePath');
            if (filePath.isNotEmpty && !_fileCtrl.isClosed) {
              _fileCtrl.add(ReceivedFile(
                fromPeerId: fromPeerId,
                filePath: filePath,
                time: DateTime.now(),
              ));
            }
          }
        }
      }, onError: (error) {
        Log.d('❌ [WiFi Direct] Event stream error: $error');
      });
      
      Log.d('✅ [WiFi Direct] Discovery started successfully (periodic mode)');
    } catch (e) {
      Log.d('❌ [WiFi Direct] Failed to start discovery: $e');
      _state = DiscoveryState.idle;
      rethrow;
    }
  }
  
  /// เรียก native discovery พร้อมป้องกัน "System busy"
  Future<void> _triggerDiscovery() async {
    // 🔒 ป้องกันการเรียกซ้อนทับกัน
    if (_isDiscovering) {
      Log.d('⏭️ [WiFi Direct] Discovery already in progress, skipping...');
      return;
    }
    
    // ⏱️ ตรวจสอบช่วงเวลาจากครั้งล่าสุด
    final now = DateTime.now();
    if (_lastDiscoveryAttempt != null) {
      final elapsed = now.difference(_lastDiscoveryAttempt!);
      if (elapsed < _minDiscoveryInterval) {
        final remaining = _minDiscoveryInterval.inSeconds - elapsed.inSeconds;
        Log.d('⏸️ [WiFi Direct] Too soon, waiting ${remaining}s before next discovery');
        return;
      }
    }
    
    _isDiscovering = true;
    _lastDiscoveryAttempt = now;
    
    try {
      final result = await platform.invokeMethod('discoverPeers');
      
      // 🔧 ตรวจสอบผลลัพธ์จาก native
      if (result == true) {
        _failedAttempts = 0; // รีเซ็ตถ้าสำเร็จ
        Log.d('✅ [WiFi Direct] Discovery triggered successfully');
      } else if (result == false) {
        // System busy (ไม่ throw error แต่ return false)
        _failedAttempts++;
        Log.d('⚠️ [WiFi Direct] System busy (attempt $_failedAttempts), will retry later...');
        
        // 🔧 เพิ่มระยะเวลารอตาม failed attempts (exponential backoff)
        // เริ่มที่ 60s แทน 20s และเพิ่ม 20s แทน 10s
        final waitTime = Duration(seconds: 60 + (_failedAttempts * 20));
        _lastDiscoveryAttempt = now.add(waitTime);
        
        Log.d('⏳ [WiFi Direct] Will retry after ${waitTime.inSeconds}s');
      }
    } catch (e) {
      _failedAttempts++;
      
      // 🔴 ถ้า error เป็น "System busy" → รอนานขึ้น
      if (e.toString().contains('System busy') || e.toString().contains('BUSY')) {
        Log.d('⚠️ [WiFi Direct] System busy (attempt $_failedAttempts), will retry later...');
        
        // 🔧 เพิ่มระยะเวลารอตาม failed attempts (exponential backoff)
        final waitTime = Duration(seconds: 60 + (_failedAttempts * 20));
        _lastDiscoveryAttempt = now.add(waitTime);
        
        Log.d('⏳ [WiFi Direct] Will retry after ${waitTime.inSeconds}s');
      } else {
        Log.d('⚠️ [WiFi Direct] Discovery trigger failed: $e');
      }
    } finally {
      _isDiscovering = false;
    }
  }

  @override
  Future<void> stopDiscovery() async {
    try {
      _state = DiscoveryState.idle;
      Log.d('📶 [WiFi Direct] Stopping discovery...');
      
      // หยุด timer ทั้งหมด
      _discoveryTimer?.cancel();
      _discoveryTimer = null;

      // 🔧 รีเซ็ต discovery state
      _isDiscovering = false;
      _lastDiscoveryAttempt = null;
      _failedAttempts = 0;
      
      await platform.invokeMethod('stopDiscovery');
      _eventSub?.cancel();
      _currentPeers.clear();
      
      // ✅ เช็คว่า stream ยังเปิดอยู่ก่อน emit
      if (!_peersCtrl.isClosed) {
        _peersCtrl.add([]);
      }
      
      Log.d('✅ [WiFi Direct] Discovery stopped');
    } catch (e) {
      Log.d('❌ [WiFi Direct] Failed to stop discovery: $e');
    }
  }

  @override
  Future<void> sendMessage(String body, {Peer? to}) async {
    try {
      // 🔧 เช็คว่ามี peer หรือยัง
      if (_currentPeers.isEmpty) {
        Log.d('⚠️ [WiFi Direct] No peers available, message queued');
        // ส่ง echo กลับเพื่อไม่ให้ app หาย
        _msgCtrl.add(Message(
          fromPeerId: 'me',
          toPeerId: to?.id,
          body: body,
          time: DateTime.now(),
        ));
        return; // ไม่ส่งจริงถ้าไม่มี peer
      }
      
      Log.d('📶 [WiFi Direct] Sending message to ${to?.name ?? "all"}: ${body.length > 100 ? '${body.substring(0, 100)}...' : body}');
      
      await platform.invokeMethod('sendMessage', {
        'message': body,
        'peerId': to?.id,
      });
      
      // Echo back our own message
      _msgCtrl.add(Message(
        fromPeerId: 'me',
        toPeerId: to?.id,
        body: body,
        time: DateTime.now(),
      ));
      
      Log.d('✅ [WiFi Direct] Message sent successfully');
    } catch (e) {
      Log.d('❌ [WiFi Direct] Failed to send message: $e');
      // ⚠️ ไม่ rethrow เพื่อไม่ให้ app crash
    }
  }

  @override
  Future<void> sendFile(String filePath, {Peer? to}) async {
    try {
      Log.d('📶 [WiFi Direct] Sending file: $filePath to ${to?.name ?? "all"}');

      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('File not found: $filePath');
      }

      // ฝั่ง native จะอ่านไฟล์และส่ง metadata + binary chunk ผ่าน socket ให้เอง
      await platform.invokeMethod('sendFile', {
        'filePath': filePath,
        'peerId': to?.id,
      });

      Log.d('✅ [WiFi Direct] File sent successfully');
    } catch (e) {
      Log.d('❌ [WiFi Direct] Failed to send file: $e');
      rethrow;
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await stopDiscovery();
      _discoveryTimer?.cancel(); // หยุด discovery timer
      _eventSub?.cancel();
      await _peersCtrl.close();
      await _msgCtrl.close();
      await _fileCtrl.close();
      Log.d('✅ [WiFi Direct] Disposed');
    } catch (e) {
      Log.d('❌ [WiFi Direct] Error during dispose: $e');
    }
  }
}
