import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'transport.dart';

class WifiDirectTransport implements Transport {
  final _peersCtrl = StreamController<List<Peer>>.broadcast();
  final _msgCtrl = StreamController<Message>.broadcast();
  final _fileCtrl = StreamController<ReceivedFile>.broadcast();
  DiscoveryState _state = DiscoveryState.idle;
  final List<Peer> _currentPeers = [];
  final String deviceName; // 🔧 เพิ่ม device name
  
  // 📍 เก็บ mapping ระหว่าง peerId กับ actual device name
  final Map<String, String> _peerNames = {};

  static const platform = MethodChannel('wifi_direct');
  static const eventChannel = EventChannel('wifi_direct/events');
  StreamSubscription? _eventSub;
  Timer? _discoveryTimer; // เพิ่ม timer สำหรับค้นหาซ้ำ
  Timer? _gpsTimer; // เพิ่ม timer สำหรับส่ง GPS
  
  // 🔧 ป้องกัน "System busy"
  bool _isDiscovering = false;
  DateTime? _lastDiscoveryAttempt;
  int _failedAttempts = 0;
  static const _minDiscoveryInterval = Duration(seconds: 45); // เพิ่มจาก 15s → 45s เพื่อลด busy
  
  WifiDirectTransport({String? deviceName}) 
      : deviceName = deviceName ?? 'WiFi Device';

  @override
  DiscoveryState get discoveryState => _state;

  @override
  Stream<List<Peer>> get onPeers => _peersCtrl.stream;

  @override
  Stream<Message> get onMessage => _msgCtrl.stream;
  
  Stream<ReceivedFile> get onFileReceived => _fileCtrl.stream;

  @override
  Future<void> startDiscovery() async {
    try {
      _state = DiscoveryState.scanning;
      print('📶 [WiFi Direct] Starting peer discovery...');
      print('📶 [WiFi Direct] Device name: $deviceName');
      
      // 🔧 ส่ง device name ไปยัง native code
      try {
        await platform.invokeMethod('setDeviceName', {'name': deviceName});
        print('✅ [WiFi Direct] Device name set successfully');
      } catch (e) {
        print('⚠️ [WiFi Direct] Failed to set device name: $e');
      }
      
      // เริ่มค้นหาครั้งแรก
      await _triggerDiscovery();
      
      // ✅ ตั้ง timer ให้ค้นหาซ้ำทุก 30 วินาที (เพิ่มจาก 20 เพื่อให้เวลาเชื่อมต่อ)
      _discoveryTimer?.cancel();
      _discoveryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        print('🔄 [WiFi Direct] Periodic discovery...');
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
            print('🔌 [WiFi Direct] Connection status: ${isConnected ? "Connected" : "Disconnected"} (role: $role)');
            
            if (isConnected) {
              // ส่ง DEVICE_NAME เมื่อเชื่อมต่อสำเร็จ
              Future.delayed(const Duration(milliseconds: 500), () {
                print('📤 [WiFi Direct] Sending device name after connection: $deviceName');
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
              print('📶 [WiFi Direct] Found ${_currentPeers.length} peers');
            }
            
          } else if (type == 'message') {
            final fromPeerId = event['fromPeerId']?.toString() ?? 'unknown';
            final body = event['body']?.toString() ?? '';
            
            print('📶 [WiFi Direct] Raw message received: fromPeerId=$fromPeerId, body=${body.length > 100 ? '${body.substring(0, 100)}...' : body}');
            
            // 🔧 จัดการ DEVICE_NAME message แยกต่างหาก
            if (body.startsWith('DEVICE_NAME:')) {
              final deviceName = body.substring(12); // ตัด "DEVICE_NAME:" ออก
              _peerNames[fromPeerId] = deviceName;
              print('📝 [WiFi Direct] Updated peer name: $fromPeerId -> $deviceName');
              
              // อัปเดต peer list ใหม่
              final peerIndex = _currentPeers.indexWhere((p) => p.id == fromPeerId);
              if (peerIndex >= 0) {
                _currentPeers[peerIndex] = Peer(
                  id: fromPeerId,
                  name: deviceName,
                  nearby: true,
                );
                // ✅ เช็คว่า stream ยังเปิดอยู่ก่อน emit
                if (!_peersCtrl.isClosed) {
                  _peersCtrl.add(List.from(_currentPeers));
                }
              }
              return; // ⚠️ DEVICE_NAME ไม่ส่งต่อไปยัง message stream
            }
            
            // 🔧 ใช้ชื่อที่บันทึกไว้ หรือ fallback เป็น peerId
            final fromName = _peerNames[fromPeerId] ?? fromPeerId;
            
            // ✅ ส่งต่อข้อความทั้งหมด (รวม SOS_STATUS, RESCUE_STATUS) ไปยัง app_state
            print('📶 [WiFi Direct] Forwarding to app: from=$fromName, body=${body.substring(0, body.length > 80 ? 80 : body.length)}...');
            _msgCtrl.add(Message(
              fromPeerId: fromPeerId,
              body: body,
              time: DateTime.now(),
            ));
          }
        }
      }, onError: (error) {
        print('❌ [WiFi Direct] Event stream error: $error');
      });
      
      print('✅ [WiFi Direct] Discovery started successfully (periodic mode)');
    } catch (e) {
      print('❌ [WiFi Direct] Failed to start discovery: $e');
      _state = DiscoveryState.idle;
      rethrow;
    }
  }
  
  /// เรียก native discovery พร้อมป้องกัน "System busy"
  Future<void> _triggerDiscovery() async {
    // 🔒 ป้องกันการเรียกซ้อนทับกัน
    if (_isDiscovering) {
      print('⏭️ [WiFi Direct] Discovery already in progress, skipping...');
      return;
    }
    
    // ⏱️ ตรวจสอบช่วงเวลาจากครั้งล่าสุด
    final now = DateTime.now();
    if (_lastDiscoveryAttempt != null) {
      final elapsed = now.difference(_lastDiscoveryAttempt!);
      if (elapsed < _minDiscoveryInterval) {
        final remaining = _minDiscoveryInterval.inSeconds - elapsed.inSeconds;
        print('⏸️ [WiFi Direct] Too soon, waiting ${remaining}s before next discovery');
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
        print('✅ [WiFi Direct] Discovery triggered successfully');
      } else if (result == false) {
        // System busy (ไม่ throw error แต่ return false)
        _failedAttempts++;
        print('⚠️ [WiFi Direct] System busy (attempt $_failedAttempts), will retry later...');
        
        // 🔧 เพิ่มระยะเวลารอตาม failed attempts (exponential backoff)
        // เริ่มที่ 60s แทน 20s และเพิ่ม 20s แทน 10s
        final waitTime = Duration(seconds: 60 + (_failedAttempts * 20));
        _lastDiscoveryAttempt = now.add(waitTime);
        
        print('⏳ [WiFi Direct] Will retry after ${waitTime.inSeconds}s');
      }
    } catch (e) {
      _failedAttempts++;
      
      // 🔴 ถ้า error เป็น "System busy" → รอนานขึ้น
      if (e.toString().contains('System busy') || e.toString().contains('BUSY')) {
        print('⚠️ [WiFi Direct] System busy (attempt $_failedAttempts), will retry later...');
        
        // 🔧 เพิ่มระยะเวลารอตาม failed attempts (exponential backoff)
        final waitTime = Duration(seconds: 60 + (_failedAttempts * 20));
        _lastDiscoveryAttempt = now.add(waitTime);
        
        print('⏳ [WiFi Direct] Will retry after ${waitTime.inSeconds}s');
      } else {
        print('⚠️ [WiFi Direct] Discovery trigger failed: $e');
      }
    } finally {
      _isDiscovering = false;
    }
  }

  @override
  Future<void> stopDiscovery() async {
    try {
      _state = DiscoveryState.idle;
      print('📶 [WiFi Direct] Stopping discovery...');
      
      // หยุด timer ทั้งหมด
      _discoveryTimer?.cancel();
      _discoveryTimer = null;
      _gpsTimer?.cancel();
      _gpsTimer = null;
      
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
      
      print('✅ [WiFi Direct] Discovery stopped');
    } catch (e) {
      print('❌ [WiFi Direct] Failed to stop discovery: $e');
    }
  }

  @override
  Future<void> sendMessage(String body, {Peer? to}) async {
    try {
      // 🔧 เช็คว่ามี peer หรือยัง
      if (_currentPeers.isEmpty) {
        print('⚠️ [WiFi Direct] No peers available, message queued');
        // ส่ง echo กลับเพื่อไม่ให้ app หาย
        _msgCtrl.add(Message(
          fromPeerId: 'me',
          toPeerId: to?.id,
          body: body,
          time: DateTime.now(),
        ));
        return; // ไม่ส่งจริงถ้าไม่มี peer
      }
      
      print('📶 [WiFi Direct] Sending message to ${to?.name ?? "all"}: ${body.length > 100 ? '${body.substring(0, 100)}...' : body}');
      
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
      
      print('✅ [WiFi Direct] Message sent successfully');
    } catch (e) {
      print('❌ [WiFi Direct] Failed to send message: $e');
      // ⚠️ ไม่ rethrow เพื่อไม่ให้ app crash
    }
  }

  @override
  Future<void> sendFile(String filePath, {Peer? to}) async {
    try {
      print('📶 [WiFi Direct] Sending file: $filePath to ${to?.name ?? "all"}');
      
      // Read file as bytes
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('File not found: $filePath');
      }
      
      final bytes = await file.readAsBytes();
      final fileName = filePath.split('/').last;
      
      // Send file metadata first
      await sendMessage('FILE:$fileName:${bytes.length}', to: to);
      
      // TODO: Implement chunked file transfer over socket
      // For now, we'll send a simple notification
      print('⚠️ [WiFi Direct] File transfer: sending metadata only (TODO: implement chunked transfer)');
      
      print('✅ [WiFi Direct] File metadata sent');
    } catch (e) {
      print('❌ [WiFi Direct] Failed to send file: $e');
      rethrow;
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await stopDiscovery();
      _discoveryTimer?.cancel(); // หยุด discovery timer
      _gpsTimer?.cancel(); // หยุด GPS timer
      _eventSub?.cancel();
      await _peersCtrl.close();
      await _msgCtrl.close();
      await _fileCtrl.close();
      print('✅ [WiFi Direct] Disposed');
    } catch (e) {
      print('❌ [WiFi Direct] Error during dispose: $e');
    }
  }
}
