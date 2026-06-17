import 'dart:collection';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart'; // เพิ่มสำหรับ MaterialPageRoute
import 'package:flutter/services.dart'; // เพิ่มสำหรับ HapticFeedback
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart'; // เพิ่มสำหรับบันทึกค่า
import 'transport.dart';
import 'chat_models.dart';
import '../cloud/firebase_service.dart';
import 'nearby_transport.dart';
import 'ble_transport.dart'; // BLE Transport สำหรับ iOS และ Android
import 'device_id_manager.dart'; // เพิ่มสำหรับ Device ID
// import 'mock_transport.dart';
import 'wifi_direct_transport.dart';
import 'mesh_transport.dart'; // เพิ่ม Mesh Transport
import 'chat_db.dart';
import 'message_queue_service.dart';
import 'notification_service.dart';
import 'friend_service.dart';
import 'friend_models.dart'; // เพิ่มสำหรับ Friend class
import 'friend_db.dart';
import 'fcm_service.dart'; // เพิ่ม FCM Service
import '../ui/emergency_chat_screen.dart'; // เพิ่มสำหรับเปิดหน้าแชท
import '../ui/friend_chat_screen.dart'; // เพิ่มสำหรับเปิดหน้าแชทเพื่อน
import '../main.dart'; // เพิ่มสำหรับ navigatorKey
import '../services/background_service.dart'; // เพิ่ม Background Service
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:offgrid_sos/core/logger.dart';

// 📍 Model สำหรับเก็บตำแหน่ง GPS ของ peer
class PeerLocation {
  final double latitude;
  final double longitude;
  final DateTime timestamp;

  PeerLocation({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });

  @override
  String toString() => '$latitude,$longitude,${timestamp.millisecondsSinceEpoch}';

  factory PeerLocation.fromString(String str) {
    final parts = str.split(',');
    if (parts.length < 2) throw FormatException('Invalid location format');
    return PeerLocation(
      latitude: double.parse(parts[0]),
      longitude: double.parse(parts[1]),
      timestamp: parts.length >= 3 
          ? DateTime.fromMillisecondsSinceEpoch(int.parse(parts[2]))
          : DateTime.now(),
    );
  }
}

class AppState extends ChangeNotifier with WidgetsBindingObserver {
  Transport transport;
  String selectedProtocol = 'nearby';
  String _deviceName = 'My Device'; // เพิ่มตัวแปรเก็บชื่อเครื่อง
  Timer? _onlineStatusTimer; // Timer สำหรับอัปเดตสถานะออนไลน์
  StreamSubscription<Position>? _locationStreamSubscription; // 📍 Real-time GPS Stream
  Timer? _keepAliveTimer; // 🔄 Timer สำหรับ keep alive
  Timer? _reconnectTimer; // 🔁 Timer สำหรับ auto reconnect
  bool _isAppInForeground = true; // ติดตามสถานะแอพ
  String? _lastSyncedUserId; // เก็บ userId ล่าสุดที่ซิงก์แล้ว เพื่อป้องกันซิงก์ซ้ำ

  // ติดตามว่าผู้ใช้เปิดห้องแชทไหนอยู่ — ใช้ suppress notification ที่ซ้ำซ้อน
  String? _activePeerChatId;    // peerId ของ EmergencyChatScreen ที่เปิดอยู่
  String? _activeFriendChatId;  // friendUserId ของ FriendChatScreen ที่เปิดอยู่

  void setActivePeerChat(String? peerId) => _activePeerChatId = peerId;
  void setActiveFriendChat(String? friendUserId) => _activeFriendChatId = friendUserId;

  bool get isInPeerChat => _activePeerChatId != null;
  bool get isInFriendChat => _activeFriendChatId != null;

  /// ใช้ใน FCMService เพื่อตรวจว่าผู้ใช้อยู่ในห้องแชทเพื่อนคนนี้หรือไม่
  bool isActiveFriendChat(String friendUserId) => _activeFriendChatId == friendUserId;
  int _reconnectAttempts = 0; // 🔁 นับจำนวนครั้งที่พยายามเชื่อมต่อใหม่
  static const int _maxReconnectAttempts = 5; // 🔁 จำนวนครั้งสูงสุด
  Position? _myCurrentPosition; // เก็บตำแหน่งปัจจุบันของตัวเอง
  
  // 🎯 Background Service
  final BackgroundService _backgroundService = BackgroundService();
  bool _isBackgroundServiceEnabled = false;
  bool get isBackgroundServiceEnabled => _isBackgroundServiceEnabled;
  
  // 📍 GPS Locations ของ peers
  final Map<String, PeerLocation> _peerLocations = {};

  // 👥 mapping: Firebase userId ของเพื่อน -> peerId ที่กำลังเชื่อมต่ออยู่ตอนนี้ (ถ้ามี)
  // ใช้เพื่อส่งข้อความเพื่อนแบบ unicast เจาะจงเครื่อง ไม่ broadcast ให้คนแปลกหน้าใกล้เคียงเห็นด้วย
  final Map<String, String> _friendUserIdToPeerId = {};
  
  // 🔒 ป้องกันการกดปุ่มซ้ำ
  bool _isTogglingRescue = false;
  bool _isTogglingSOS = false;
  
  // 🔒 ป้องกัน broadcast ซ้ำเร็วเกินไป
  DateTime? _lastSOSBroadcast;
  DateTime? _lastRescueBroadcast;
  static const Duration _minBroadcastInterval = Duration(seconds: 2);

  // 🚑 โหมดหน่วยกู้ภัย (Rescue Mode)
  bool _isRescueMode = false;
  bool get isRescueMode => _isRescueMode;

  // 🚨 โหมด SOS (Emergency SOS Mode)
  bool _isSOSActive = false;
  bool get isSOSActive => _isSOSActive;
  
  // 📍 Getter สำหรับตำแหน่งปัจจุบัน (real-time)
  Position? get myCurrentPosition => _myCurrentPosition;

  // 📡 Auto-Discovery Mode (Passive Listening)
  bool _isPassiveListening = false;
  bool get isPassiveListening => _isPassiveListening;

  // 🔄 Stable Peer List - เก็บ peers ที่เคยพบไว้ชั่วคราว
  final Map<String, Peer> _stablePeers = {};
  Timer? _peerCleanupTimer;
  final Map<String, DateTime> _peerLastSeen = {};
  // 💓 เพิ่ม timeout เป็น 45 วินาที (Keep Alive ส่งทุก 30 วินาที + buffer 15 วินาที)
  // เพื่อให้มั่นใจว่าไม่ timeout ก่อนรับ Keep Alive ครั้งถัดไป
  static const Duration _peerTimeout = Duration(seconds: 45);

  // Getter สำหรับ stable peers
  UnmodifiableListView<Peer> get stablePeers => UnmodifiableListView(_stablePeers.values);

  // 📥 คิวข้อความที่รอส่ง/รอซิงก์ (retry เมื่อเชื่อมต่อกลับมา)
  final MessageQueueService _messageQueue = MessageQueueService();

  // 📥 คิว friend messages ที่ยังไม่ได้ sync ขึ้น Firebase (ส่งตอนออฟไลน์)
  final List<Map<String, dynamic>> _pendingFriendSync = [];

  AppState({required this.transport}) {
    _subs();
    _loadLocalMessages();
    // Initialize friend service
    _initFriendService();
    // โหลด protocol ที่เลือกไว้จาก SharedPreferences
    _loadSelectedProtocol();
    // 📥 เริ่มคิวข้อความ + ตั้ง handler ส่งจริง/ซิงก์จริง
    _initMessageQueue();
    // เริ่มฟัง App Lifecycle
    WidgetsBinding.instance.addObserver(this);
    // 🔄 เริ่ม Passive Listening อัตโนมัติ (หลังจากรอให้ app พร้อม)
    Future.delayed(const Duration(milliseconds: 500), () {
      _startPassiveListening();
    });
  }
  
  /// 🔄 โหลด protocol ที่เลือกไว้จาก SharedPreferences
  Future<void> _loadSelectedProtocol() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedProtocol = prefs.getString('selected_protocol');
      
      if (savedProtocol != null && savedProtocol.isNotEmpty) {
        selectedProtocol = savedProtocol;
        Log.d('📡 Loaded saved protocol: $selectedProtocol');
        notifyListeners(); // อัพเดท UI
      } else {
        Log.d('📡 No saved protocol, using default: $selectedProtocol');
      }
    } catch (e) {
      Log.d('❌ Error loading saved protocol: $e');
    }
  }
  
  /// 📥 เริ่มคิวข้อความ และผูก handler ส่งจริง (Transport) / ซิงก์จริง (Firebase)
  Future<void> _initMessageQueue() async {
    _messageQueue.setSendHandler((msg) async {
      final peer = _peers.firstWhere(
        (p) => p.id == msg.receiver,
        orElse: () => const Peer(id: '', name: ''),
      );
      if (peer.id.isEmpty) return false; // peer ไม่ได้เชื่อมต่ออยู่ตอนนี้
      await transport.sendMessage(msg.text ?? '', to: peer);
      return true;
    });

    _messageQueue.setSyncHandler((msg) async {
      if (!firebaseService.isOnline) return false;
      return _autoSyncMessage(msg);
    });

    // อัปเดตสถานะออนไลน์ของคิวตามสถานะ Firebase (เผื่อ sync ทันทีที่เน็ตกลับมา)
    firebaseService.addListener(() {
      _messageQueue.updateOnlineStatus(firebaseService.isOnline);
      // flush friend sync queue เมื่อกลับมาออนไลน์
      if (firebaseService.isOnline && firebaseService.isSignedIn) {
        _flushPendingFriendSync();
      }
    });

    await _messageQueue.init();
    await _loadPendingFriendSync();
  }

  /// โหลด pending friend sync queue จาก SharedPreferences
  Future<void> _loadPendingFriendSync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('pending_friend_sync');
      if (raw != null) {
        final List<dynamic> list = jsonDecode(raw);
        _pendingFriendSync.clear();
        _pendingFriendSync.addAll(list.cast<Map<String, dynamic>>());
        Log.d('📦 โหลด friend sync queue: ${_pendingFriendSync.length} รายการ');
      }
    } catch (e) {
      Log.d('❌ โหลด friend sync queue ไม่สำเร็จ: $e');
    }
  }

  /// บันทึก pending friend sync queue ลง SharedPreferences
  Future<void> _savePendingFriendSync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_friend_sync', jsonEncode(_pendingFriendSync));
    } catch (e) {
      Log.d('❌ บันทึก friend sync queue ไม่สำเร็จ: $e');
    }
  }

  /// เพิ่ม friend message เข้าคิวรอ sync ขึ้น Firebase
  Future<void> _enqueuePendingFriendSync({
    required String fromUserId,
    required String toUserId,
    required String type,
    String? text,
    required DateTime time,
    required String messageId,
  }) async {
    _pendingFriendSync.add({
      'fromUserId': fromUserId,
      'toUserId': toUserId,
      'type': type,
      'text': text,
      'time': time.millisecondsSinceEpoch,
      'messageId': messageId,
    });
    await _savePendingFriendSync();
    Log.d('📥 [FriendSync] enqueue $type → $toUserId (${_pendingFriendSync.length} รายการในคิว)');
  }

  /// flush คิว: sync ทุกข้อความที่ค้างอยู่ขึ้น Firebase
  Future<void> _flushPendingFriendSync() async {
    if (_pendingFriendSync.isEmpty) return;
    if (!firebaseService.isOnline || !firebaseService.isSignedIn) return;

    Log.d('☁️ [FriendSync] เริ่ม flush ${_pendingFriendSync.length} รายการ...');

    for (final item in List.from(_pendingFriendSync)) {
      try {
        await firebaseService.saveFriendChatMessage(
          fromUserId: item['fromUserId'] as String,
          toUserId: item['toUserId'] as String,
          type: item['type'] as String,
          text: item['text'] as String?,
          time: DateTime.fromMillisecondsSinceEpoch(item['time'] as int),
          messageId: item['messageId'] as String,
        );
        _pendingFriendSync.remove(item);
        Log.d('✅ [FriendSync] synced ${item['messageId']}');
      } catch (e) {
        Log.d('❌ [FriendSync] sync error ${item['messageId']}: $e');
        break; // หยุดถ้า error (จะลองใหม่รอบหน้า)
      }
    }

    await _savePendingFriendSync();
    Log.d('☁️ [FriendSync] flush เสร็จ เหลือ ${_pendingFriendSync.length} รายการ');
  }

  /// 📡 เริ่ม Passive Listening - รับสัญญาณได้โดยไม่ต้องเปิดโหมดใดๆ
  Future<void> _startPassiveListening() async {
    if (_isPassiveListening) {
      Log.d('⏭️ Passive Listening already active, skip');
      return;
    }
    
    try {
      Log.d('📡 [PASSIVE] เริ่ม Passive Listening Mode...');
      Log.d('📡 [PASSIVE] Device name: "$_deviceName"');
      await startScan();
      _isPassiveListening = true;
      Log.d('✅ [PASSIVE] Passive Listening เริ่มทำงานแล้ว - พร้อมรับสัญญาณ SOS');
    } catch (e) {
      Log.d('❌ [PASSIVE] Error starting passive listening: $e');
      
      // ⚡ ลด retry delay จาก 3 วินาที → 2 วินาที
      if (e.toString().contains('Failed to start discovery')) {
        Log.d('🔄 [PASSIVE] จะลองเริ่ม Passive Listening ใหม่ในอีก 2 วินาที...');
        Future.delayed(const Duration(seconds: 2), () {
          if (!_isPassiveListening) {
            _startPassiveListening();
          }
        });
      }
    }
  }

  /// 🔄 อัปเดต Stable Peers List - เก็บ peers ที่เคยเห็นไว้ชั่วคราว
  void _updateStablePeers(List<Peer> currentPeers) {
    final now = DateTime.now();
    bool hasChanges = false;
    
    // เพิ่ม/อัปเดต peers ที่เห็นอยู่
    for (final peer in currentPeers) {
      if (!_stablePeers.containsKey(peer.id)) {
        hasChanges = true;
        Log.d('✅ เพิ่ม stable peer: ${peer.name} (${peer.id})');
      }
      _stablePeers[peer.id] = peer;
      _peerLastSeen[peer.id] = now;
    }
    
    // ลบ peers ที่ไม่เห็นนานเกินไป (15 วินาที)
    _peerLastSeen.removeWhere((peerId, lastSeen) {
      if (now.difference(lastSeen) > _peerTimeout) {
        _stablePeers.remove(peerId);
        Log.d('🔄 ลบ peer $peerId (timeout after ${_peerTimeout.inSeconds}s)');
        hasChanges = true;
        return true;
      }
      return false;
    });
    
    // ⚡ เพิ่ม cleanup frequency จาก 10 วินาที → 5 วินาที
    // เพื่อให้ UI อัปเดตไวขึ้น
    _peerCleanupTimer ??= Timer.periodic(const Duration(seconds: 5), (_) {
      _updateStablePeers([]); // เรียกเพื่อทำ cleanup
    });
    
    // ⚡ แจ้ง UI ทันทีเมื่อมีการเปลี่ยนแปลง
    if (hasChanges) {
      notifyListeners();
    }
  }

  // Getter และ Setter สำหรับชื่อเครื่อง
  String get deviceName => _deviceName;
  
  void setDeviceName(String name) {
    _deviceName = name.isNotEmpty ? name : 'My Device';
    // อัปเดต transport ที่ใช้งานอยู่
    _updateTransportDeviceName();
    notifyListeners();
  }
  
  // 🚑 เปิด/ปิด โหมดหน่วยกู้ภัย
  Future<void> toggleRescueMode() async {
  // 🔒 ป้องกันการกดซ้ำ
  if (_isTogglingRescue) {
    Log.d('⚠️ กำลังประมวลผลอยู่ กรุณารอสักครู่...');
    return;
  }
  
  _isTogglingRescue = true;
  
  // ⚡ อัปเดต state ทันทีและ notify listeners
  _isRescueMode = !_isRescueMode;
  Log.d('🔍 [DEBUG] toggleRescueMode: _isRescueMode = $_isRescueMode');
  notifyListeners(); // ✅ แจ้ง UI ทันทีก่อนทำงาน async
  
  try {
    // ⚠️ ถ้าเปิด Rescue Mode ให้ปิด SOS Mode อัตโนมัติ
    if (_isRescueMode && _isSOSActive) {
      Log.d('⚠️ ปิด SOS Mode เพื่อเปิด Rescue Mode');
      _isSOSActive = false;
      broadcastSOSStatus(isActive: false); // ⚡ ไม่ await
    }
    
    // 🔄 อัพเดท UI ทันที
    notifyListeners();
    
    // Broadcast สถานะหน่วยกู้ภัย
    if (_isRescueMode) {
      Log.d('🚑 กำลังเปิดโหมดหน่วยกู้ภัย...');
      _broadcastRescueStatus(true); // ⚡ ไม่ await
      
      // ✅ ไม่ต้อง stop/start scan เพราะ Passive Listening ทำงานอยู่แล้ว
      // แค่ broadcast สถานะก็พอ
      
      Log.d('🚑 ✅ เปิดโหมดหน่วยกู้ภัย (Passive Listening ทำงานต่อเนื่อง)');
    } else {
      Log.d('🚑 กำลังปิดโหมดหน่วยกู้ภัย...');
      _broadcastRescueStatus(false); // ⚡ ไม่ await
      // 📡 ไม่ stop scan เพื่อให้ Passive Listening ยังทำงาน
      Log.d('🚑 ✅ ปิดโหมดหน่วยกู้ภัย (Passive Listening ยังทำงาน)');
    }
    
    // อัพเดท UI อีกครั้งหลัง operation เสร็จ
    notifyListeners();
  } catch (e) {
    Log.d('❌ Error in toggleRescueMode: $e');
    // ถ้า error ให้ rollback state
    _isRescueMode = !_isRescueMode;
    notifyListeners();
  } finally {
    _isTogglingRescue = false;
  }
}
  
  // Broadcast สถานะหน่วยกู้ภัย
  void _broadcastRescueStatus(bool isRescue) {
    // 🔒 ป้องกัน broadcast ซ้ำเร็วเกินไป
    final now = DateTime.now();
    if (_lastRescueBroadcast != null && 
        now.difference(_lastRescueBroadcast!) < _minBroadcastInterval) {
      Log.d('⏭️ Skip Rescue broadcast (too soon: ${now.difference(_lastRescueBroadcast!).inMilliseconds}ms)');
      return;
    }
    _lastRescueBroadcast = now;
    
    final status = isRescue ? 'RESCUE_MODE_ON' : 'RESCUE_MODE_OFF';
    final message = 'RESCUE_STATUS:$_deviceName:$status';
    Log.d('🔍 [DEBUG] กำลังส่ง Broadcast: $message');
    // ⚡ ไม่ await - ส่งแบบ fire-and-forget เพื่อความเร็ว
    transport.sendMessage(message);
    Log.d('📡 Broadcast: $message');
  }

  // 🚨 เปิด/ปิด โหมด SOS
  // toggle SOS state + broadcast (ใช้โดยทั้งสองปุ่ม)
  Future<void> _toggleSOSState() async {
    _isSOSActive = !_isSOSActive;
    if (_isSOSActive && _isRescueMode) _isRescueMode = false;
    notifyListeners();
    _broadcastSOSMode(isActive: _isSOSActive);
  }

  // ปุ่มใหญ่: ฉุกเฉิน urgent — toggle state + broadcast
  Future<void> toggleSOSMode() async {
    if (_isTogglingSOS) {
      Log.d('⚠️ กำลังประมวลผลอยู่ กรุณารอสักครู่...');
      return;
    }
    _isTogglingSOS = true;
    try {
      await _toggleSOSState();
      Log.d('🚨 toggleSOSMode: isSOSActive=$_isSOSActive');
    } catch (e) {
      Log.d('❌ Error in toggleSOSMode: $e');
      _isSOSActive = !_isSOSActive; // rollback
      notifyListeners();
    } finally {
      _isTogglingSOS = false;
    }
  }

  // ปุ่มเล็ก: ขอความช่วยเหลือ — toggle state + broadcast เหมือนกัน
  Future<void> toggleSOSRequest() async {
    if (_isTogglingSOS) return;
    _isTogglingSOS = true;
    try {
      await _toggleSOSState();
      Log.d('🆘 toggleSOSRequest: isSOSActive=$_isSOSActive');
    } catch (e) {
      Log.d('❌ Error in toggleSOSRequest: $e');
      _isSOSActive = !_isSOSActive; // rollback
      notifyListeners();
    } finally {
      _isTogglingSOS = false;
    }
  }

  // 🚨 Broadcast โหมด SOS (เข้า/ออกโหมด - ยังไม่ขอความช่วยเหลือ)
  void _broadcastSOSMode({
    required bool isActive,
    double? latitude,
    double? longitude,
  }) {
    // 🔒 ป้องกัน broadcast ซ้ำเร็วเกินไป
    final now = DateTime.now();
    if (_lastSOSBroadcast != null && 
        now.difference(_lastSOSBroadcast!) < _minBroadcastInterval) {
      Log.d('⏭️ Skip SOS broadcast (too soon: ${now.difference(_lastSOSBroadcast!).inMilliseconds}ms)');
      return;
    }
    _lastSOSBroadcast = now;
    
    final status = isActive ? 'SOS_MODE_ON' : 'SOS_MODE_OFF';
    
    // ใช้ location ที่ส่งมา หรือ 0,0 (ไม่บังคับต้องมี location สำหรับ SOS Mode)
    final lat = latitude ?? 0.0;
    final lng = longitude ?? 0.0;
    
    final message = 'SOS_STATUS:$_deviceName:$status:$lat:$lng:0'; // timestamp = 0
    Log.d('📡 Broadcast SOS Mode: $message');
    
    // ⚡ ไม่ await - ส่งแบบ fire-and-forget เพื่อความเร็ว
    transport.sendMessage(message);
  }

  // 🚨 Broadcast สถานะ SOS (กดปุ่มขอความช่วยเหลือ)
  void broadcastSOSStatus({
    required bool isActive,
    double? latitude,
    double? longitude,
    bool isEmergency = false,
  }) {
    final String status;
    if (!isActive) {
      status = 'SOS_INACTIVE';
    } else if (isEmergency) {
      status = 'SOS_EMERGENCY';
    } else {
      status = 'SOS_ACTIVE';
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    
    String message;
    if (latitude != null && longitude != null) {
      message = 'SOS_STATUS:$_deviceName:$status:$latitude:$longitude:$timestamp';
      Log.d('📡 Broadcast SOS: $message');
      Log.d('📍 Location: https://www.google.com/maps?q=$latitude,$longitude');
      Log.d('⏰ Timestamp: ${DateTime.now()}');
    } else {
      message = 'SOS_STATUS:$_deviceName:$status:0:0:$timestamp';
      Log.d('📡 Broadcast SOS (no location): $message');
      Log.d('⏰ Timestamp: ${DateTime.now()}');
    }
    
    // ⚡ ไม่ await - ส่งแบบ fire-and-forget เพื่อความเร็ว
    transport.sendMessage(message);
  }

  // ดึงตำแหน่งปัจจุบัน
  Future<Position?> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        Log.d('❌ Location services ถูกปิด');
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          Log.d('❌ Location permission ถูกปฏิเสธ');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        Log.d('❌ Location permission ถูกปฏิเสธถาวร');
        return null;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      return position;
    } catch (e) {
      Log.d('❌ Error getting location: $e');
      return null;
    }
  }

  void _updateTransportDeviceName() {
    if (transport is NearbyTransport) {
      (transport as NearbyTransport).updateDeviceName(_deviceName);
    }
  }

  // 🔄 สลับ Transport Protocol
  Future<void> switchTransport(String protocol) async {
    if (selectedProtocol == protocol) {
      Log.d('⏭️ Already using $protocol protocol');
      return;
    }

    try {
      Log.d('🔄 Switching transport from $selectedProtocol to $protocol...');
      
      // ⚡ อัปเดต state ทันทีเพื่อให้ UI แสดงสถานะการเปลี่ยน
      final oldProtocol = selectedProtocol;
      selectedProtocol = protocol;
      notifyListeners(); // ✅ แจ้ง UI ทันทีว่ากำลังสลับ
      
      // หยุด transport เก่า
      final wasScanning = transport.discoveryState == DiscoveryState.scanning;
      if (wasScanning) {
        await transport.stopDiscovery();
      }
      await transport.dispose();
      
      // สร้าง transport ใหม่
      switch (protocol) {
        case 'nearby':
          transport = NearbyTransport(deviceName: _deviceName);
          break;
        case 'ble':
        case 'bluetooth':
          // ✅ BLE Transport — รองรับทั้ง Android และ iOS
          transport = BleTransport(deviceName: _deviceName);
          break;
        case 'wifi':
        case 'wifi_direct':
          transport = WifiDirectTransport(deviceName: _deviceName); // 🔧 ส่ง deviceName
          break;
        case 'radio':
        case 'mesh':
          // 📡 Radio Mesh Transport - Multi-Hop Routing
          final deviceId = await DeviceIdManager.getCurrentId();
          transport = MeshTransport(
            deviceId: deviceId,
            deviceName: _deviceName,
          );
          Log.d('📡 Created MeshTransport with deviceId: $deviceId');
          break;
        default:
          // ⚡ Rollback ถ้า protocol ไม่ถูกต้อง
          selectedProtocol = oldProtocol;
          notifyListeners();
          throw ArgumentError('Unknown protocol: $protocol');
      }
      
      // ตั้งค่า listeners ใหม่
      _subs();
      
      // เริ่ม scan ใหม่ถ้าเดิมกำลัง scan อยู่
      if (wasScanning) {
        await startScan();
      }
      
      // บันทึกค่า
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selected_protocol', protocol);
      
      notifyListeners();
      Log.d('✅ Switched to $protocol successfully');
    } catch (e) {
      Log.d('❌ Failed to switch transport: $e');
      rethrow;
    }
  }

  Future<void> _initFriendService() async {
    await friendService.init();
    
    // ฟัง login event เพื่อ sync แชทจาก Firebase
    friendService.addListener(_onFriendServiceChanged);
  }

  void _onFriendServiceChanged() async {
    // ตรวจสอบว่า user login เข้ามาใหม่หรือไม่
    if (friendService.currentUser != null) {
      final currentUserId = friendService.currentUser!.id;
      
      // 🛡️ ป้องกันการซิงก์ซ้ำ - ถ้า userId เดิม ไม่ต้องทำอะไร
      if (_lastSyncedUserId == currentUserId) {
        Log.d('[AppState] ⏭️ Skip - already synced for user: $currentUserId');
        return;
      }
      
      Log.d('[AppState] 🔄 User login detected: ${friendService.currentUser!.name}');
      
      // 🔄 Migrate ข้อความ anonymous เป็น userId ปัจจุบัน (รอให้เสร็จก่อน)
      Log.d('[AppState] 🔄 Starting migration...');
      await ChatDB.migrateAnonymousMessages(currentUserId);
      
      // โหลดข้อความ local ก่อน (ข้อความที่คุยกับ nearby peers)
      Log.d('[AppState] 📥 Loading local messages...');
      await _loadLocalMessages();
      
      // จากนั้นโหลดจาก Firebase (ถ้า online)
      if (firebaseService.isOnline) {
        Log.d('[AppState] 📥 Loading from Firebase...');
        await _loadChatsFromFirebase();
      }
      
      // 💾 บันทึก userId ที่ซิงก์แล้ว
      _lastSyncedUserId = currentUserId;
      
      Log.d('[AppState] ✅ Login sequence completed');
    }
  }

  // ====== Nearby ======
  final List<Peer> _peers = [];
  final List<Message> _messages = [];

  UnmodifiableListView<Peer> get peers => UnmodifiableListView(_peers);
  UnmodifiableListView<Message> get messages => UnmodifiableListView(_messages);

  /// IDs ของ friend messages ที่ยังรอ sync ขึ้น Firebase (ออฟไลน์)
  Set<String> get pendingFriendSyncIds =>
      _pendingFriendSync.map((e) => e['messageId'] as String).toSet();

  // ignore: non_constant_identifier_names
  void DEBUG_addMockPeer() {
    final mocks = [
      const Peer(id: 'mock-001', name: 'iPhone 14 – Warat', distance: 48),
      const Peer(id: 'mock-002', name: 'Samsung Galaxy S24 – Arm', distance: 120),
      const Peer(id: 'mock-003', name: 'Pixel 8 – Noon', distance: 310),
      const Peer(id: 'mock-004', name: 'Oppo Find X7 – Malee', distance: 85),
    ];
    for (final m in mocks) {
      if (!_peers.any((p) => p.id == m.id)) _peers.add(m);
    }
    // mock-002 สถานะ SOS ปกติ
    _sosModePeers['Samsung Galaxy S24 – Arm'] = true;
    _sosPeers['Samsung Galaxy S24 – Arm'] = DateTime.now();
    // mock-003 สถานะ Rescue
    _rescuePeers['Pixel 8 – Noon'] = true;
    // mock-004 สถานะ SOS ฉุกเฉิน (กดค้าง 5 วินาที)
    _sosModePeers['Oppo Find X7 – Malee'] = true;
    _sosPeers['Oppo Find X7 – Malee'] = DateTime.now();
    _emergencySOSPeers['Oppo Find X7 – Malee'] = DateTime.now();

    // mock messages — ถ้ายังไม่มีให้เพิ่ม
    if (_chatMessages.any((m) => m.id.startsWith('mock-'))) {
      notifyListeners();
      return;
    }
    final now = DateTime.now();
    final msgs = <ChatMessage>[
      // ── mock-001: แชทปกติ ──
      ChatMessage(id: 'mock-m01', from: 'mock-001', receiver: 'me', type: ChatType.text, text: 'สวัสดี ได้ยินไหม?', time: now.subtract(const Duration(minutes: 10)), status: MessageStatus.delivered),
      ChatMessage(id: 'mock-m02', from: 'me', receiver: 'mock-001', type: ChatType.text, text: 'ได้ยิน สัญญาณดีมาก', time: now.subtract(const Duration(minutes: 9)), status: MessageStatus.delivered),
      ChatMessage(id: 'mock-m03', from: 'mock-001', receiver: 'me', type: ChatType.text, text: 'โอเค ฉันอยู่แถวทางเข้าป่า', time: now.subtract(const Duration(minutes: 8)), status: MessageStatus.delivered),

      // ── mock-002: SOS ปกติ ──
      ChatMessage(id: 'mock-m04', from: 'mock-002', receiver: 'me', type: ChatType.text, text: '🆘 ขอความช่วยเหลือ ฉันหลงทาง', time: now.subtract(const Duration(minutes: 6)), isEmergency: false, status: MessageStatus.delivered),
      ChatMessage(id: 'mock-m05', from: 'mock-002', receiver: 'me', type: ChatType.text, text: 'อยู่แถวทางแยกน้ำตก ไม่รู้จะไปทางไหน', time: now.subtract(const Duration(minutes: 5)), status: MessageStatus.delivered),
      ChatMessage(id: 'mock-m06', from: 'me', receiver: 'mock-002', type: ChatType.text, text: 'เห็นแล้ว กำลังส่งแผนที่ไปให้', time: now.subtract(const Duration(minutes: 4)), status: MessageStatus.delivered),

      // ── mock-003: Rescue ──
      ChatMessage(id: 'mock-m07', from: 'mock-003', receiver: 'me', type: ChatType.text, text: '🚑 หน่วยกู้ภัยออกเดินทางแล้ว', time: now.subtract(const Duration(minutes: 3)), status: MessageStatus.delivered),
      ChatMessage(id: 'mock-m08', from: 'mock-003', receiver: 'me', type: ChatType.text, text: 'ประมาณ 15 นาทีถึง ระบุตำแหน่งได้ไหม?', time: now.subtract(const Duration(minutes: 2)), status: MessageStatus.delivered),
      ChatMessage(id: 'mock-m09', from: 'me', receiver: 'mock-003', type: ChatType.text, text: 'ขอบคุณมาก รีบมาเลย 🙏', time: now.subtract(const Duration(minutes: 1)), status: MessageStatus.sent),

      // ── mock-004: SOS ฉุกเฉิน ──
      ChatMessage(id: 'mock-m10', from: 'mock-004', receiver: 'me', type: ChatType.text, text: '🚨 SOS ฉุกเฉิน! ต้องการความช่วยเหลือด่วน!', time: now.subtract(const Duration(seconds: 90)), isEmergency: true, status: MessageStatus.delivered),
      ChatMessage(id: 'mock-m11', from: 'mock-004', receiver: 'me', type: ChatType.text, text: 'ขาบาดเจ็บ เคลื่อนไหวไม่ได้ อยู่ใกล้ต้นไม้ใหญ่ริมลำธาร', time: now.subtract(const Duration(seconds: 75)), isEmergency: true, status: MessageStatus.delivered),
    ];
    _chatMessages = [..._chatMessages, ...msgs];
    notifyListeners();
  }

  void _subs() {
    // เริ่ม broadcast GPS location ทุก 8 วินาที
    _startLocationBroadcast();
    
    // 🔄 เริ่ม Keep Alive ทุก 30 วินาที
    _startKeepAlive();
    
    // 🔁 ตรวจสอบการเชื่อมต่อและ reconnect ทุก 10 วินาที
    _startConnectionMonitor();
    
    transport.onPeers.listen((list) {
      final oldPeersCount = _peers.length;
      _peers
        ..clear()
        ..addAll(list);
      
      // � อัปเดต Stable Peers List
      _updateStablePeers(list);

      // 📥 แจ้งคิวข้อความว่ามี/ไม่มี peer เชื่อมต่ออยู่ → trigger retry อัตโนมัติ
      _messageQueue.updateP2PConnection(list.isNotEmpty);

      // �🔁 Reset reconnect attempts เมื่อมี peer เชื่อมต่อสำเร็จ
      if (list.isNotEmpty && _reconnectAttempts > 0) {
        _reconnectAttempts = 0;
        Log.d('✅ เชื่อมต่อสำเร็จ - Reset reconnect attempts');
      }
      
      // 🔄 เมื่อมี peer ใหม่เชื่อมต่อ → ส่งสถานะโหมดปัจจุบันให้ peer รู้
      if (list.length > oldPeersCount) {
        Log.d('🔍 [DEBUG] มี peer ใหม่เชื่อมต่อ (${list.length} peers) → ส่งสถานะโหมดปัจจุบัน');
        
        // ⚡ ลด delay จาก 300ms → 200ms เพื่อความเร็ว
        Future.delayed(const Duration(milliseconds: 200), () {
          // 👥 ประกาศ Firebase userId ของเราให้ peer ใหม่รู้จัก (เพื่อ map userId เพื่อน <-> peerId)
          _announceFriendIdToPeers();

          // ส่งสถานะ Rescue Mode (ถ้าเปิดอยู่)
          if (_isRescueMode) {
            Log.d('🔍 [DEBUG] กำลังส่ง Rescue status หลังเชื่อมต่อใหม่...');
            _broadcastRescueStatus(true);
          }
          
          // ส่งสถานะ SOS Mode (ถ้าเปิดอยู่)
          if (_isSOSActive) {
            Log.d('🔍 [DEBUG] กำลังส่ง SOS status หลังเชื่อมต่อใหม่...');
            _getCurrentLocation().then((position) {
              broadcastSOSStatus(
                isActive: true,
                latitude: position?.latitude,
                longitude: position?.longitude,
              );
            });
          }
        });
      }
      
      notifyListeners();
    });
    transport.onMessage.listen((m) async { // เพิ่ม async
      Log.d('📨 ได้รับข้อความจาก ${m.fromPeerId}: ${m.body}');
      Log.d('🔍 [DEBUG] กำลังประมวลผลข้อความ...');
      
      // ⚠️ เปลี่ยนจาก: ต้องมี user ล็อกอินก่อน
      // เป็น: ถ้าไม่ได้ login ก็ใช้ anonymous ID
      final currentUserId = friendService.currentUser?.id ?? 'anonymous';
      
      // 💓 ตรวจสอบข้อความ Keep Alive (อัปเดต timestamp เพื่อไม่ให้ peer ถูก timeout)
      if (m.body.startsWith('KEEP_ALIVE:')) {
        Log.d('💓 Keep Alive received from ${m.fromPeerId}');
        // ⚡ อัปเดต lastSeen เพื่อไม่ให้ stable peer timeout
        _peerLastSeen[m.fromPeerId] = DateTime.now();
        return;
      }
      
      // 📍 ตรวจสอบข้อความ GPS location (ต้องเช็คก่อนเพื่อไม่ให้บันทึกลง chat)
      if (m.body.startsWith('GPS_LOC:')) {
        _handleGPSLocation(m.body, m.fromPeerId);
        // ⚡ อัปเดต lastSeen
        _peerLastSeen[m.fromPeerId] = DateTime.now();
        return; // ❗ สำคัญ: return ทันทีเพื่อไม่ให้ไปบันทึกใน ChatMessage
      }
      
      // � ตรวจสอบข้อความ DEVICE_NAME (สำหรับ WiFi Direct/Mesh)
      if (m.body.startsWith('DEVICE_NAME:')) {
        Log.d('📝 Received DEVICE_NAME from ${m.fromPeerId}');
        // WiFi Direct จัดการเองแล้ว ไม่ต้องทำอะไร
        return;
      }
      
      // �🚑 ตรวจสอบสถานะหน่วยกู้ภัย
      if (m.body.startsWith('RESCUE_STATUS:')) {
        Log.d('🔍 [DEBUG] ✅ พบข้อความ RESCUE_STATUS! กำลังเรียก _handleRescueStatus()');
        _handleRescueStatus(m.body, m.fromPeerId);
        // ⚡ อัปเดต lastSeen
        _peerLastSeen[m.fromPeerId] = DateTime.now();
        return;
      }
      
      // 🚨 ตรวจสอบสถานะ SOS
      if (m.body.startsWith('SOS_STATUS:')) {
        Log.d('🔍 [DEBUG] ✅ พบข้อความ SOS_STATUS! กำลังเรียก _handleSOSStatus()');
        _handleSOSStatus(m.body, m.fromPeerId);
        // ⚡ อัปเดต lastSeen
        _peerLastSeen[m.fromPeerId] = DateTime.now();
        return;
      }
      
      // 🌐 ตรวจสอบว่าเป็นข้อความที่ต้อง relay หรือไม่
      if (m.body.startsWith('RELAY:')) {
        _handleRelayMessage(m.body, m.fromPeerId);
        return;
      }
      
      // 👥 ประกาศ userId ของเพื่อน -> เก็บ mapping กับ peerId ปัจจุบัน (ไม่ต้องเป็นเพื่อนกันก่อนก็บันทึกได้ แค่จำว่า peer นี้คือใคร)
      if (m.body.startsWith('FRIEND_ID:')) {
        final announcedUserId = m.body.substring('FRIEND_ID:'.length);
        if (announcedUserId.isNotEmpty) {
          _friendUserIdToPeerId[announcedUserId] = m.fromPeerId;
          Log.d('👥 บันทึก mapping userId เพื่อน: $announcedUserId -> ${m.fromPeerId}');
        }
        return;
      }

      // ตรวจสอบว่าเป็นข้อความจากเพื่อนหรือไม่
      if (m.body.startsWith('FRIEND_MSG:')) {
        Log.d('🔔 ได้รับข้อความเพื่อน: ${m.body}');
        Log.d('🔔 currentUser: ${friendService.currentUser?.id}');
        // ข้อความเพื่อน - ต้อง login ถึงจะใช้ได้
        if (friendService.currentUser != null) {
          _handleFriendMessage(m.body, m.fromPeerId);
        } else {
          Log.d('🔔 ไม่สามารถแสดงการแจ้งเตือนได้เพราะยังไม่ได้ login');
        }
      } else if (m.fromPeerId != 'me') {
        // ⚠️ เพิ่มเงื่อนไข: ไม่รับข้อความจากตัวเอง
        // ข้อความทั่วไป/ฉุกเฉิน - ไม่ต้อง login
        
        // ⚡ อัปเดต lastSeen สำหรับ chat messages
        _peerLastSeen[m.fromPeerId] = DateTime.now();
        
        // หา peer name จาก peers list
        final peer = _peers.firstWhere(
          (p) => p.id == m.fromPeerId,
          orElse: () => Peer(id: m.fromPeerId, name: 'Device', nearby: false),
        );
        
        // 💾 บันทึกชื่อ peer เพื่อให้ห้องแชทคงชื่อไว้แม้ตัดการเชื่อมต่อ
        if (peer.name.isNotEmpty) {
          ChatDB.savePeerName(m.fromPeerId, peer.name);
        }
        
        // ดึง Device ID ของเราเพื่อใช้เป็น receiver
        final myDeviceId = await DeviceIdManager.getCurrentId();
        
        final msg = ChatMessage(
          id: 'in_${DateTime.now().millisecondsSinceEpoch}_${m.fromPeerId.hashCode.abs()}',
          from: m.fromPeerId,
          receiver: myDeviceId, // เพื่อนส่งมาหาเรา
          type: ChatType.text,
          text: m.body,
          time: DateTime.now(),
          isEmergency: m.body.contains('SOS') || m.body.contains('ฉุกเฉิน'),
          status: MessageStatus.delivered, // ได้รับข้อความแล้ว
          isRead: false, // ข้อความใหม่ที่เข้ามา - ยังไม่ได้อ่าน
        );
        _messages.add(m);
        // 🔥 สร้าง List ใหม่แทนการ add
        _chatMessages = [..._chatMessages, msg];
        
        // เก็บ local (ถ้า login แล้วก็เก็บด้วย userId, ถ้าไม่ก็เก็บด้วย anonymous)
        ChatDB.insertMessage(msg, currentUserId, receiver: myDeviceId);
        
        // 📱 แจ้งเตือนเมื่อรับข้อความใหม่ — ข้ามถ้าผู้ใช้เปิดห้องแชทนั้นอยู่แล้ว
        final senderName = peer.name.isNotEmpty ? peer.name : 'อุปกรณ์ใกล้เคียง';
        final userAlreadyInChat = _activePeerChatId == m.fromPeerId;

        if (!userAlreadyInChat) {
          // 1. In-app notification (popup ในแอพ)
          NotificationService().showMessageNotification(
            senderName,
            m.body,
            senderId: m.fromPeerId,
            onReply: () {
              _openChatScreen(peer);
            },
          );

          // 2. System notification (เด้งเข้าโทรศัพท์ - ทำงานแม้จอดับ)
          try {
            await _backgroundService.showMessageNotification(
              senderName: senderName,
              message: m.body,
            );
            Log.d('📱 ส่ง system notification แล้ว');
          } catch (e) {
            Log.d('⚠️ ส่ง system notification ล้มเหลว: $e');
          }
        } else {
          Log.d('⏭️ ข้าม notification — ผู้ใช้อยู่ในห้องแชทกับ ${peer.name} อยู่แล้ว');
        }
        
        Log.d('✅ เพิ่มข้อความใน chatMessages แล้ว (รวม ${_chatMessages.length} ข้อความ)');
        notifyListeners();
      } else {
        Log.d('⏭️ ข้ามข้อความจากตัวเอง');
      }
    });
    
    // 📁 รับไฟล์ (ใช้ได้กับทุก transport ที่ implement onFileReceived)
    transport.onFileReceived.listen((file) async {
        Log.d('📁 ได้รับไฟล์จาก ${file.fromPeerId}: ${file.filePath}');

        // ตรวจสอบประเภทไฟล์จาก extension
        final lowerPath = file.filePath.toLowerCase();
        final isVideo = lowerPath.endsWith('.mp4') ||
                        lowerPath.endsWith('.mov') ||
                        lowerPath.endsWith('.avi') ||
                        lowerPath.endsWith('.mpeg') ||
                        lowerPath.endsWith('.mkv') ||
                        lowerPath.contains('video') ||
                        lowerPath.contains('received_videos');
        final fileType = isVideo ? ChatType.video : ChatType.image;
        Log.d('📋 ไฟล์ประเภท: ${isVideo ? "วิดีโอ" : "รูปภาพ"}');

        // หาว่าผู้ส่งเป็นเพื่อน (friend) หรือ emergency peer
        final senderEntry = _friendUserIdToPeerId.entries.firstWhere(
          (e) => e.value == file.fromPeerId,
          orElse: () => const MapEntry('', ''),
        );
        final senderFriendUserId = senderEntry.key;
        final isFromFriend = senderFriendUserId.isNotEmpty && friendService.isFriend(senderFriendUserId);

        if (isFromFriend) {
          // ไฟล์มาจากเพื่อน → บันทึกเป็น FriendChatMessage
          final myUserId = friendService.currentUser?.id ?? 'anonymous';
          final friendMsg = FriendChatMessage(
            id: 'file_${DateTime.now().millisecondsSinceEpoch}_${file.fromPeerId.hashCode.abs()}',
            fromUserId: senderFriendUserId,
            toUserId: myUserId,
            type: fileType,
            filePath: file.filePath,
            time: file.time,
            isRead: false,
          );

          if (!_friendChats.containsKey(senderFriendUserId)) {
            _friendChats[senderFriendUserId] = [];
          }
          _friendChats[senderFriendUserId] = [..._friendChats[senderFriendUserId]!, friendMsg];
          FriendDB.saveFriendChatMessage(senderFriendUserId, friendMsg.toJson());
          friendService.updateFriendLastMessage(
            senderFriendUserId,
            isVideo ? '🎥 วิดีโอ' : '📷 รูปภาพ',
            file.time,
          );

          final friendName = friendService.friends
              .firstWhere((f) => f.userId == senderFriendUserId, orElse: () => Friend(id: '', name: senderFriendUserId, userId: senderFriendUserId, addedAt: DateTime.now(), lastSeen: DateTime.now()))
              .name;
          NotificationService().showMessageNotification(
            friendName,
            isVideo ? '🎥 ส่งวิดีโอมาให้' : '📷 ส่งรูปภาพมาให้',
            senderId: senderFriendUserId,
          );
          Log.d('✅ บันทึกไฟล์จาก friend $senderFriendUserId แล้ว (${isVideo ? "วิดีโอ" : "รูปภาพ"})');
        } else {
          // ไฟล์มาจาก emergency peer → บันทึกเป็น ChatMessage
          final currentUserId = friendService.currentUser?.id ?? 'anonymous';
          final myDeviceId = await DeviceIdManager.getCurrentId();
          final msg = ChatMessage(
            id: 'file_${DateTime.now().millisecondsSinceEpoch}_${file.fromPeerId.hashCode.abs()}',
            from: file.fromPeerId,
            receiver: myDeviceId,
            type: fileType,
            filePath: file.filePath,
            time: file.time,
            isEmergency: false,
            isRead: false,
          );
          _chatMessages = [..._chatMessages, msg];
          ChatDB.insertMessage(msg, currentUserId, receiver: myDeviceId);

          NotificationService().showMessageNotification(
            file.fromPeerId.length > 8 ? '${file.fromPeerId.substring(0, 8)}...' : file.fromPeerId,
            isVideo ? '🎥 ส่งวิดีโอมาให้' : '📷 ส่งรูปภาพมาให้',
            senderId: file.fromPeerId,
            onReply: () {
              final peer = _peers.firstWhere(
                (p) => p.id == file.fromPeerId,
                orElse: () => Peer(
                  id: file.fromPeerId,
                  name: file.fromPeerId.length > 8 ? '${file.fromPeerId.substring(0, 8)}...' : file.fromPeerId,
                ),
              );
              _openChatScreen(peer);
            },
          );
          Log.d('✅ เพิ่มไฟล์ใน chatMessages แล้ว (${isVideo ? "วิดีโอ" : "รูปภาพ"}, รวม ${_chatMessages.length} ข้อความ)');
        }

        notifyListeners();
    });
  }

  Future<void> startScan() {
    Log.d('🔍 [AppState] startScan() called - Device name: "$_deviceName"');
    // ⚡ Notify listeners ทันทีก่อนเริ่ม scan
    notifyListeners();
    return transport.startDiscovery();
  }
  
  Future<void> stopScan() {
    // ⚡ Notify listeners ทันทีก่อนหยุด scan
    notifyListeners();
    return transport.stopDiscovery();
  }

  void send(String body, {Peer? to}) {
    Log.d('📤 ส่งข้อความ: $body ${to != null ? "ถึง ${to.name}" : "(broadcast)"}');
    
    final currentUserId = friendService.currentUser?.id ?? 'anonymous';
    final deviceName = _deviceName;
    
    // สร้าง message ID ที่ unique
    final messageId = 'msg_${DateTime.now().millisecondsSinceEpoch}_$currentUserId';
    
    // 🌐 ถ้ามีหลาย peers ให้ส่งแบบ RELAY เพื่อให้ข้อความส่งต่อกันได้
    if (_peers.length > 1 && !body.startsWith('RELAY:') && !body.startsWith('SOS_STATUS:') && !body.startsWith('RESCUE_STATUS:')) {
      // TTL = 5 (ส่งต่อได้ไม่เกิน 5 hops)
      final relayMsg = 'RELAY:$messageId:5:$currentUserId:$deviceName:$body';
      transport.sendMessage(relayMsg, to: to); // ⚡ ไม่ await
      Log.d('🌐 ส่งข้อความแบบ Mesh (TTL=5)');
    } else {
      // ส่งข้อความปกติ
      transport.sendMessage(body, to: to); // ⚡ ไม่ await
      Log.d('📤 ส่งข้อความปกติ');
    }
    
    // ⚠️ ไม่เพิ่มข้อความที่นี่ - ให้ transport._msgCtrl.add() จัดการ
    // เพราะ NearbyTransport จะ emit message ที่ส่งออกมาแล้ว
    // หาก emit ที่นี่ด้วยจะทำให้ซ้ำ
    
    Log.d('✅ ส่งข้อความเรียบร้อย');
    notifyListeners();
  }

  // ====== Chat ======
  List<ChatMessage> _chatMessages = []; // 🔥 เปลี่ยนจาก final เป็น var เพื่อให้สามารถสร้าง List ใหม่ได้
  UnmodifiableListView<ChatMessage> get chatMessages => UnmodifiableListView(_chatMessages);

  /// ดึงข้อความในห้องแชทระหว่าง user กับ peer
  Future<List<ChatMessage>> getChatConversation(String peerId) async {
    if (friendService.currentUser == null) return [];
    return await ChatDB.getConversation(friendService.currentUser!.id, peerId);
  }

  Future<void> sendChatText(String text, {String? receiverId}) async {
  // ถ้าไม่ได้ login ใช้ anonymous ID
  final currentUserId = friendService.currentUser?.id ?? 'anonymous';
  
  // 🆔 ใช้ Device ID ถาวรแทน 'me' เพื่อให้สามารถหาแชทเดิมเจอ
  final myDeviceId = await DeviceIdManager.getCurrentId();
  
  // สร้าง message ID ที่ unique
  final messageId = 'msg_${DateTime.now().millisecondsSinceEpoch}_$currentUserId';
  
  final msg = ChatMessage(
    id: messageId,
    from: myDeviceId, // ใช้ Device ID แทน 'me'
    receiver: receiverId, // เพิ่ม receiver
    type: ChatType.text,
    text: text,
    time: DateTime.now(),
    isEmergency: text.contains('SOS') || text.contains('ฉุกเฉิน'),
    status: MessageStatus.pending, // เริ่มต้นเป็น pending
  );
  // 🔥 สร้าง List ใหม่แทนการ add
  _chatMessages = [..._chatMessages, msg];
  
  // ⚡ อัปเดต UI ทันที
  notifyListeners();
  
  // กำหนด receiver: ถ้าไม่ได้ระบุ ให้ใช้ peer แรกที่เชื่อมต่ออยู่
  String? actualReceiverId = receiverId;
  if (actualReceiverId == null && _peers.isNotEmpty) {
    actualReceiverId = _peers.first.id;
  }
  
  // 💾 บันทึกชื่อ peer เพื่อให้ห้องแชทคงชื่อไว้ (ไม่ await)
  if (actualReceiverId != null) {
    final targetPeer = _peers.firstWhere(
      (p) => p.id == actualReceiverId,
      orElse: () => Peer(id: '', name: ''),
    );
    if (targetPeer.id.isNotEmpty && targetPeer.name.isNotEmpty) {
      ChatDB.savePeerName(actualReceiverId, targetPeer.name); // ⚡ ไม่ await
    }
  }
  
  // เก็บ local พร้อม receiver (ไม่ await)
  if (actualReceiverId != null) {
    ChatDB.insertMessage(msg, currentUserId, receiver: actualReceiverId); // ⚡ ไม่ await
    Log.d('💾 บันทึกข้อความ sender=$myDeviceId, receiver=$actualReceiverId');
  }
  
  // 📤 ส่งข้อความแบบ Point-to-Point (เฉพาะคนที่เลือก)
  final targetPeer = actualReceiverId != null
      ? _peers.firstWhere((p) => p.id == actualReceiverId, orElse: () => Peer(id: '', name: ''))
      : null;

  final index = _chatMessages.indexWhere((m) => m.id == messageId);
  bool sentOk = false;

  if (targetPeer != null && targetPeer.id.isNotEmpty) {
    try {
      await transport.sendMessage(text, to: targetPeer);
      sentOk = true;
      Log.d('📤 ส่งข้อความไปยัง: ${targetPeer.name} (${targetPeer.id})');
    } catch (e) {
      Log.d('❌ ส่งข้อความไม่สำเร็จ: $e');
    }
  } else {
    Log.d('❌ ไม่พบ peer ที่ต้องการส่ง (receiverId=$actualReceiverId)');
  }

  if (sentOk) {
    // อัปเดตสถานะเป็น sent หลังส่งสำเร็จ
    if (index != -1) {
      _chatMessages[index] = msg.copyWith(status: MessageStatus.sent);
      ChatDB.updateMessageStatus(messageId, MessageStatus.sent); // ⚡ ไม่ await
    }
    Log.d('✅ ส่งข้อความ: $text (สถานะ: sent)');
  } else {
    // 📥 ส่งไม่สำเร็จ (offline/peer ไม่อยู่) → เข้าคิวรอ retry อัตโนมัติเมื่อเชื่อมต่อกลับมา
    await _messageQueue.addToPendingQueue(msg);
    Log.d('📥 เข้าคิวรอส่งใหม่: $text (สถานะ: pending)');
  }
  
  // 🔄 Auto sync ขึ้น Firebase ถ้าส่งสำเร็จ + online + login แล้ว
  if (sentOk && index != -1 && firebaseService.isOnline && friendService.currentUser != null) {
    await _autoSyncMessage(_chatMessages[index]);
  }
  
  notifyListeners();
}

/// 🔄 Auto sync ข้อความเดี่ยวขึ้น Firebase
Future<bool> _autoSyncMessage(ChatMessage msg) async {
  try {
    final messageMap = {
      'id': msg.id,
      'from': msg.from,
      'type': msg.type.toString().split('.').last,
      'text': msg.text,
      'filePath': msg.filePath,
      'time': msg.time.millisecondsSinceEpoch,
      'isEmergency': msg.isEmergency,
      'status': msg.status.toString().split('.').last,
    };

    final success = await firebaseService.syncChatMessageToCloud(messageMap);
    if (success) {
      // อัพเดทสถานะเป็น synced
      await ChatDB.updateMessageStatus(msg.id, MessageStatus.synced);
      Log.d('[AutoSync] ✅ Synced message: ${msg.id}');
    }
    return success;
  } catch (e) {
    Log.d('[AutoSync] ❌ Error: $e');
    return false;
  }
}

void addChatImage(String path, {String? receiverId}) async {
  if (friendService.currentUser == null) return; // ต้อง login ก่อน
  
  final myDeviceId = await DeviceIdManager.getCurrentId();
  
  final msg = ChatMessage(
    id: 'me_img_${DateTime.now().millisecondsSinceEpoch}',
    from: myDeviceId,
    receiver: receiverId,
    type: ChatType.image,
    filePath: path,
    time: DateTime.now(),
  );
  // 🔥 สร้าง List ใหม่แทนการ add
  _chatMessages = [..._chatMessages, msg];
  ChatDB.insertMessage(msg, friendService.currentUser!.id, receiver: receiverId); // เก็บ local พร้อม userId
  firebaseService.saveChatMessage(
    type: 'image',
    text: '[image]',
    time: msg.time,
  );
  
  // 🔄 Auto sync
  if (firebaseService.isOnline) {
    _autoSyncMessage(msg);
  }
  
  notifyListeners();
}

void addChatVideo(String path, {String? receiverId}) async {
  if (friendService.currentUser == null) return; // ต้อง login ก่อน
  
  final myDeviceId = await DeviceIdManager.getCurrentId();
  
  final msg = ChatMessage(
    id: 'me_vid_${DateTime.now().millisecondsSinceEpoch}',
    from: myDeviceId,
    receiver: receiverId,
    type: ChatType.video,
    filePath: path,
    time: DateTime.now(),
  );
  // 🔥 สร้าง List ใหม่แทนการ add
  _chatMessages = [..._chatMessages, msg];
  ChatDB.insertMessage(msg, friendService.currentUser!.id, receiver: receiverId); // เก็บ local พร้อม userId
  firebaseService.saveChatMessage(
    type: 'video',
    text: '[video]',
    time: msg.time,
  );
  
  // 🔄 Auto sync
  if (firebaseService.isOnline) {
    _autoSyncMessage(msg);
  }
  
  notifyListeners();
}

  Future<void> _loadLocalMessages() async {
    if (friendService.currentUser == null) {
      Log.d('[AppState] ⚠️ Cannot load messages: No user logged in');
      return;
    }
    
    final userId = friendService.currentUser!.id;
    Log.d('[AppState] 📂 Loading messages for user: $userId');
    
    final local = await ChatDB.getMessages(userId);
    Log.d('[AppState] 📊 Found ${local.length} local messages');
    
    _chatMessages
      ..clear()
      ..addAll(local);
    
    Log.d('[AppState] ✅ Loaded ${_chatMessages.length} messages into memory');
    notifyListeners();
    
    // sync firebase → local
    await syncFirebaseToLocal();
  }

  Future<void> syncFirebaseToLocal() async {
  if (friendService.currentUser == null) return; // ต้อง login ก่อน
  
  // ดึงข้อความทั้งหมดจาก Firebase
  final firebaseMessages = await firebaseService.getAllChatMessages();
  // แปลงเป็น ChatMessage แล้วบันทึกลง local DB
  for (final m in firebaseMessages) {
    final msg = ChatMessage(
      id: m['id'] ?? UniqueKey().toString(),
      from: m['from'] ?? 'unknown',
      type: ChatType.values.firstWhere((e) => e.name == (m['type'] ?? 'text')),
      text: m['text'],
      filePath: m['filePath'],
      time: (m['time'] is DateTime)
          ? m['time']
          : DateTime.fromMillisecondsSinceEpoch(m['time']),
    );
    await ChatDB.insertMessage(msg, friendService.currentUser!.id);
  }
  // โหลดใหม่เข้า state
  final local = await ChatDB.getMessages(friendService.currentUser!.id);
  _chatMessages
    ..clear()
    ..addAll(local);
  notifyListeners();
}

  // ====== Friend Chat Management ======
  final Map<String, List<FriendChatMessage>> _friendChats = {};
  // real-time Firestore listener per friend — cancel เมื่อออกจากห้องแชท
  final Map<String, StreamSubscription<List<Map<String, dynamic>>>> _friendChatSubs = {};
  // global inbox listeners — ทำงานตลอดเวลา (ไม่ต้องอยู่ใน chat screen) เพื่อ trigger notification
  final Map<String, StreamSubscription<List<Map<String, dynamic>>>> _globalInboxSubs = {};
  final Set<String> _processedInboxMessageIds = {};

  UnmodifiableMapView<String, List<FriendChatMessage>> get friendChats =>
      UnmodifiableMapView(_friendChats);

  /// เริ่ม real-time listener สำหรับข้อความแชทกับเพื่อน
  /// เรียกเมื่อเปิดหน้า FriendChatScreen — แทนที่ polling 5 วินาที
  void startFriendChatListener(String friendUserId) {
    if (_friendChatSubs.containsKey(friendUserId)) return; // listener มีอยู่แล้ว
    if (friendService.currentUser == null) return;
    if (!firebaseService.isOnline || !firebaseService.isSignedIn) return;

    final currentUserId = friendService.currentUser!.id;
    final sub = firebaseService
        .streamFriendChatMessages(currentUserId, friendUserId)
        .listen((rawMessages) {
      _mergeFirebaseMessagesIntoState(friendUserId, rawMessages);
    }, onError: (e) {
      Log.d('[AppState] ❌ friendChatListener error: $e');
    });

    _friendChatSubs[friendUserId] = sub;
    Log.d('[AppState] 🔴 เริ่ม real-time listener สำหรับ friend: $friendUserId');
  }

  /// หยุด real-time listener เมื่อปิดหน้า FriendChatScreen
  void stopFriendChatListener(String friendUserId) {
    _friendChatSubs.remove(friendUserId)?.cancel();
    Log.d('[AppState] ⬛ หยุด real-time listener สำหรับ friend: $friendUserId');
  }

  /// เริ่ม global inbox listener สำหรับทุกเพื่อน — แจ้งเตือนข้อความใหม่แม้อยู่นอก chat screen
  void startGlobalInboxListener() {
    final currentUserId = friendService.currentUser?.id;
    if (currentUserId == null) return;
    if (!firebaseService.isOnline || !firebaseService.isSignedIn) return;

    stopGlobalInboxListener();

    final since = Timestamp.fromDate(DateTime.now());

    for (final friend in friendService.friends) {
      final friendUserId = friend.userId;
      final sub = firebaseService
          .streamIncomingMessagesFromFriend(currentUserId, friendUserId, since)
          .listen((rawMessages) {
        for (final data in rawMessages) {
          final msgId = data['id'] as String?;
          if (msgId == null || _processedInboxMessageIds.contains(msgId)) continue;
          _processedInboxMessageIds.add(msgId);

          final msg = FriendChatMessage.fromJson(data);

          // เพิ่มข้อความเข้า local state ถ้ายังไม่มี
          final alreadyExists =
              _friendChats[friendUserId]?.any((m) => m.id == msgId) ?? false;
          if (!alreadyExists) {
            _friendChats[friendUserId] = [...(_friendChats[friendUserId] ?? []), msg];
            FriendDB.saveFriendChatMessage(friendUserId, data);
            friendService.updateFriendLastMessage(
              friendUserId,
              msg.text ?? '',
              msg.time,
              incrementUnread: true,
            );
            notifyListeners();
          }

          // แสดง notification ถ้าผู้ใช้ไม่ได้อยู่ในห้องแชทนี้
          if (_activeFriendChatId != friendUserId) {
            NotificationService().showMessageNotification(
              friend.name,
              msg.text?.isNotEmpty == true ? msg.text! : '📎 ส่งไฟล์มาให้',
              senderId: friendUserId,
              onReply: () => _openFriendChatScreen(friend),
            );
          }
        }
      }, onError: (e) {
        Log.d('[AppState] ❌ globalInboxListener error for $friendUserId: $e');
      });
      _globalInboxSubs[friendUserId] = sub;
    }

    Log.d('[AppState] 🔔 เริ่ม global inbox listener: ${_globalInboxSubs.length} เพื่อน');
  }

  /// หยุด global inbox listener ทั้งหมด
  void stopGlobalInboxListener() {
    for (final sub in _globalInboxSubs.values) {
      sub.cancel();
    }
    _globalInboxSubs.clear();
    _processedInboxMessageIds.clear();
    Log.d('[AppState] ⬛ หยุด global inbox listener');
  }

  /// รวม raw messages จาก Firestore เข้า _friendChats โดยไม่ซ้ำ
  void _mergeFirebaseMessagesIntoState(
      String friendUserId, List<Map<String, dynamic>> rawMessages) {
    final existing = List<FriendChatMessage>.from(_friendChats[friendUserId] ?? []);
    bool changed = false;

    for (final data in rawMessages) {
      final msg = FriendChatMessage.fromJson(data);
      final alreadyExists = existing.any((m) =>
          m.id == msg.id ||
          (m.text == msg.text &&
              m.fromUserId == msg.fromUserId &&
              m.toUserId == msg.toUserId &&
              m.time.difference(msg.time).abs().inSeconds < 2));
      if (!alreadyExists) {
        existing.add(msg);
        FriendDB.saveFriendChatMessage(friendUserId, msg.toJson());
        changed = true;
      }
    }

    if (changed) {
      existing.sort((a, b) => a.time.compareTo(b.time));
      _friendChats[friendUserId] = existing;
      notifyListeners();
    }
  }

  /// ล้างประวัติแชทกับเพื่อนทั้งหมด (local + Firebase)
  Future<void> clearFriendChat(String friendUserId) async {
    // 1. ล้าง in-memory
    _friendChats[friendUserId] = [];
    notifyListeners();

    // 2. ล้าง local storage
    await FriendDB.clearFriendChatMessages(friendUserId);

    // 3. ล้าง Firebase ถ้าออนไลน์
    if (firebaseService.isOnline &&
        firebaseService.isSignedIn &&
        friendService.currentUser != null) {
      await firebaseService.deleteFriendChatMessages(
        friendService.currentUser!.id,
        friendUserId,
      );
    }

    // 4. อัปเดต lastMessage ของเพื่อนให้ว่าง
    friendService.updateFriendLastMessage(friendUserId, '', DateTime.now());

    Log.d('[AppState] 🗑️ ล้างแชทกับ $friendUserId เรียบร้อย');
  }

  /// ส่งข้อความแชทให้เพื่อน
  Future<void> sendFriendChatMessage(String friendUserId, String text, {bool isEmergency = false}) async {
    if (friendService.currentUser == null) return;

    final message = FriendChatMessage(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
      fromUserId: friendService.currentUser!.id,
      toUserId: friendUserId,
      type: ChatType.text,
      text: text,
      time: DateTime.now(),
      isEmergency: isEmergency,
    );

    // บันทึกข้อความในแชทท้องถิ่น
    if (!_friendChats.containsKey(friendUserId)) {
      _friendChats[friendUserId] = [];
    }
    // 🔥 สร้าง List ใหม่แทนการ add ลงใน List เดิม
    _friendChats[friendUserId] = [..._friendChats[friendUserId]!, message];
    
    // ⚡ อัปเดต UI ทันที
    notifyListeners();

    // บันทึกลงฐานข้อมูลท้องถิ่น (ไม่ await)
    FriendDB.saveFriendChatMessage(friendUserId, message.toJson()); // ⚡ ไม่ await

    // อัพเดทข้อความสุดท้ายของเพื่อน (ไม่ await)
    friendService.updateFriendLastMessage(friendUserId, text, DateTime.now()); // ⚡ ไม่ await

    // ส่งผ่าน transport หากออฟไลน์ (Nearby/BLE/WiFi Direct) - ไม่ await
    // ถ้ารู้ peer ของเพื่อนคนนี้อยู่แล้ว (เคยแลก FRIEND_ID/FRIEND_MSG กันมา) ส่งตรงเจาะจงเครื่อง
    // ไม่ broadcast ให้คนแปลกหน้าใกล้เคียงเห็นข้อความส่วนตัว
    try {
      final targetPeer = _peerForFriend(friendUserId);
      transport.sendMessage('FRIEND_MSG:${friendService.currentUser!.id}:$text', to: targetPeer); // ⚡ ไม่ await
      Log.d('📡 [P2P] ส่งข้อความผ่าน Bluetooth/WiFi Direct ${targetPeer != null ? "(unicast: ${targetPeer.name})" : "(broadcast - ยังไม่รู้ peer ของเพื่อนคนนี้)"}');
    } catch (e) {
      Log.d('[AppState] Error sending via transport: $e');
    }

    // ส่งผ่าน FCM หากมีอินเทอร์เน็ต (Push Notification) - ไม่ await
    try {
      FCMService().sendNotificationToFriend( // ⚡ ไม่ await
        friendUserId: friendUserId,
        message: text,
      );
      Log.d('🔔 [FCM] ส่ง Push Notification แล้ว');
    } catch (e) {
      Log.d('[AppState] Error sending FCM: $e');
    }

    // บันทึกบน Firebase หากออนไลน์ ไม่งั้นเข้าคิวรอ sync
    if (firebaseService.isOnline && firebaseService.isSignedIn) {
      firebaseService.saveFriendChatMessage( // ⚡ ไม่ await
        fromUserId: friendService.currentUser!.id,
        toUserId: friendUserId,
        type: 'text',
        text: text,
        time: message.time,
        messageId: message.id,
      );
    } else {
      _enqueuePendingFriendSync( // ⚡ ไม่ await
        fromUserId: friendService.currentUser!.id,
        toUserId: friendUserId,
        type: 'text',
        text: text,
        time: message.time,
        messageId: message.id,
      );
    }
  }

  /// ส่งรูปภาพให้เพื่อน (P2P หรือ Local อย่างเดียว - ไม่อัพโหลด Firebase Storage)
  Future<void> sendFriendImageMessage(String friendUserId, String imagePath) async {
    if (friendService.currentUser == null) return;

    final message = FriendChatMessage(
      id: 'img_${DateTime.now().millisecondsSinceEpoch}',
      fromUserId: friendService.currentUser!.id,
      toUserId: friendUserId,
      type: ChatType.image,
      filePath: imagePath, // เก็บ local path
      time: DateTime.now(),
      isEmergency: false,
    );

    // บันทึกข้อความในแชทท้องถิ่น
    if (!_friendChats.containsKey(friendUserId)) {
      _friendChats[friendUserId] = [];
    }
    // 🔥 สร้าง List ใหม่แทนการ add ลงใน List เดิม
    _friendChats[friendUserId] = [..._friendChats[friendUserId]!, message];
    
    // ⚡ อัปเดต UI ทันที
    notifyListeners();

    // บันทึกลงฐานข้อมูลท้องถิ่น (ไม่ await)
    FriendDB.saveFriendChatMessage(friendUserId, message.toJson()); // ⚡ ไม่ await

    // อัพเดทข้อความสุดท้าย (ไม่ await)
    friendService.updateFriendLastMessage(friendUserId, '📷 รูปภาพ', DateTime.now()); // ⚡ ไม่ await

    // ส่งผ่าน P2P ถ้า friend อยู่ใน nearby peers
    try {
      final targetPeer = _peerForFriend(friendUserId);
      if (targetPeer != null) {
        transport.sendFile(imagePath, to: targetPeer); // ⚡ ไม่ await
        Log.d('📡 [P2P] ส่งรูปภาพผ่าน P2P → ${targetPeer.name}');
      } else {
        Log.d('📡 [P2P] friend ไม่อยู่ใน nearby peers - บันทึก local เท่านั้น');
      }
    } catch (e) {
      Log.d('[AppState] Error sending image via transport: $e');
    }

    // บันทึก metadata บน Firebase (ไม่อัพโหลดรูปจริง - Free Plan ไม่มี Storage)
    if (firebaseService.isOnline && firebaseService.isSignedIn) {
      firebaseService.saveFriendChatMessage( // ⚡ ไม่ await
        fromUserId: friendService.currentUser!.id,
        toUserId: friendUserId,
        type: 'image',
        text: '[Image - P2P/Local only]',
        time: message.time,
        messageId: message.id,
      );
    } else {
      _enqueuePendingFriendSync( // ⚡ ไม่ await
        fromUserId: friendService.currentUser!.id,
        toUserId: friendUserId,
        type: 'image',
        text: '[Image - P2P/Local only]',
        time: message.time,
        messageId: message.id,
      );
    }
  }

  /// ส่งวิดีโอให้เพื่อน (P2P หรือ Local อย่างเดียว - ไม่อัพโหลด Firebase Storage)
  Future<void> sendFriendVideoMessage(String friendUserId, String videoPath) async {
    if (friendService.currentUser == null) return;

    final message = FriendChatMessage(
      id: 'vid_${DateTime.now().millisecondsSinceEpoch}',
      fromUserId: friendService.currentUser!.id,
      toUserId: friendUserId,
      type: ChatType.video,
      filePath: videoPath, // เก็บ local path
      time: DateTime.now(),
      isEmergency: false,
    );

    // บันทึกข้อความในแชทท้องถิ่น
    if (!_friendChats.containsKey(friendUserId)) {
      _friendChats[friendUserId] = [];
    }
    // 🔥 สร้าง List ใหม่แทนการ add ลงใน List เดิม
    _friendChats[friendUserId] = [..._friendChats[friendUserId]!, message];
    
    // ⚡ อัปเดต UI ทันที
    notifyListeners();

    // บันทึกลงฐานข้อมูลท้องถิ่น (ไม่ await)
    FriendDB.saveFriendChatMessage(friendUserId, message.toJson()); // ⚡ ไม่ await

    // อัพเดทข้อความสุดท้าย (ไม่ await)
    friendService.updateFriendLastMessage(friendUserId, '🎥 วิดีโอ', DateTime.now()); // ⚡ ไม่ await

    // ส่งผ่าน P2P ถ้า friend อยู่ใน nearby peers
    try {
      final targetPeer = _peerForFriend(friendUserId);
      if (targetPeer != null) {
        transport.sendFile(videoPath, to: targetPeer); // ⚡ ไม่ await
        Log.d('📡 [P2P] ส่งวิดีโอผ่าน P2P → ${targetPeer.name}');
      } else {
        Log.d('📡 [P2P] friend ไม่อยู่ใน nearby peers - บันทึก local เท่านั้น');
      }
    } catch (e) {
      Log.d('[AppState] Error sending video via transport: $e');
    }

    // บันทึก metadata บน Firebase (ไม่อัพโหลดวิดีโอจริง - Free Plan ไม่มี Storage)
    if (firebaseService.isOnline && firebaseService.isSignedIn) {
      firebaseService.saveFriendChatMessage( // ⚡ ไม่ await
        fromUserId: friendService.currentUser!.id,
        toUserId: friendUserId,
        type: 'video',
        text: '[Video - P2P/Local only]',
        time: message.time,
        messageId: message.id,
      );
    } else {
      _enqueuePendingFriendSync( // ⚡ ไม่ await
        fromUserId: friendService.currentUser!.id,
        toUserId: friendUserId,
        type: 'video',
        text: '[Video - P2P/Local only]',
        time: message.time,
        messageId: message.id,
      );
    }

    notifyListeners();
  }

  /// แชร์ตำแหน่งปัจจุบันให้เพื่อน
  Future<void> sendFriendLocationMessage(String friendUserId) async {
    if (friendService.currentUser == null) return;

    // ขอ permission และดึงตำแหน่งปัจจุบัน
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permission denied');
        }
      }

      // ดึงตำแหน่งปัจจุบัน
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      // สร้าง Google Maps link
      final googleMapsUrl = 'https://www.google.com/maps?q=${position.latitude},${position.longitude}';
      final locationText = '📍 ตำแหน่งของฉัน\n$googleMapsUrl';

      final message = FriendChatMessage(
        id: 'loc_${DateTime.now().millisecondsSinceEpoch}',
        fromUserId: friendService.currentUser!.id,
        toUserId: friendUserId,
        type: ChatType.text, // ใช้ text type พร้อม location data
        text: locationText,
        time: DateTime.now(),
        isEmergency: false,
      );

      // บันทึกข้อความในแชทท้องถิ่น
      _friendChats[friendUserId] = [
        ...(_friendChats[friendUserId] ?? []),
        message,
      ];

      // ⚡ อัปเดต UI ทันที
      notifyListeners();

      // บันทึกลงฐานข้อมูลท้องถิ่น (ไม่ await)
      FriendDB.saveFriendChatMessage(friendUserId, message.toJson()); // ⚡ ไม่ await

      // อัพเดทข้อความสุดท้าย (ไม่ await)
      friendService.updateFriendLastMessage(friendUserId, '📍 ตำแหน่ง', DateTime.now()); // ⚡ ไม่ await

      // ส่งผ่าน transport (ไม่ await)
      try {
        transport.sendMessage( // ⚡ ไม่ await
          'FRIEND_MSG:${friendService.currentUser!.id}:$locationText',
          to: _peerForFriend(friendUserId),
        );
      } catch (e) {
        Log.d('[AppState] Error sending location via transport: $e');
      }

      // บันทึก metadata บน Firebase (ไม่ await)
      if (firebaseService.isOnline && firebaseService.isSignedIn) {
        firebaseService.saveFriendChatMessage( // ⚡ ไม่ await
          fromUserId: friendService.currentUser!.id,
          toUserId: friendUserId,
          type: 'text',
          text: locationText,
          time: DateTime.now(),
          messageId: message.id,
        );
      }
    } catch (e) {
      Log.d('[AppState] Error getting location: $e');
      throw e; // ส่ง error กลับไปให้ UI จัดการ
    }
  }

  /// โหลดข้อความแชทกับเพื่อน
  Future<void> loadFriendChatMessages(String friendUserId, {bool forceRefresh = false}) async {
    if (_friendChats.containsKey(friendUserId) && !forceRefresh) return; // โหลดแล้ว

    final myUserId = friendService.currentUser?.id;

    // โหลด last read timestamp ที่รอดตาย logout
    final lastRead = myUserId != null
        ? await FriendDB.getLastReadTime(myUserId, friendUserId)
        : null;

    // โหลดจากฐานข้อมูลท้องถิ่น
    final localMessages = await FriendDB.getFriendChatMessages(friendUserId);
    final messages = localMessages.map((json) => FriendChatMessage.fromJson(json)).toList();

    _friendChats[friendUserId] = messages;

    // โหลดจาก Firebase หากออนไลน์
    if (firebaseService.isOnline && firebaseService.isSignedIn && myUserId != null) {
      try {
        Log.d('[AppState] 🔄 กำลังดึงข้อความจาก Firebase...');
        final firebaseMessages = await firebaseService.getFriendChatMessages(
          myUserId,
          friendUserId
        );

        Log.d('[AppState] 📩 ได้รับ ${firebaseMessages.length} ข้อความจาก Firebase');

        for (final msgData in firebaseMessages) {
          var message = FriendChatMessage.fromJson(msgData);

          // apply last read: ข้อความที่ส่งถึงเราและเก่ากว่าเวลาที่อ่านล่าสุด → isRead: true
          if (lastRead != null &&
              !message.isRead &&
              message.toUserId == myUserId &&
              !message.time.isAfter(lastRead)) {
            message = message.copyWith(isRead: true);
          }

          // ตรวจสอบว่ามีข้อความนี้แล้วหรือไม่ (เช็คทั้ง ID และเนื้อหา+เวลา)
          final isDuplicate = messages.any((m) =>
            m.id == message.id || // เช็ค ID ตรงกัน
            (m.text == message.text && // หรือเนื้อหาเหมือนกัน
             m.fromUserId == message.fromUserId && // จากคนเดียวกัน
             m.toUserId == message.toUserId && // ถึงคนเดียวกัน
             m.time.difference(message.time).abs().inSeconds < 2) // เวลาห่างกันไม่เกิน 2 วินาที
          );

          if (!isDuplicate) {
            messages.add(message);
            // บันทึกลงฐานข้อมูลท้องถิ่น
            await FriendDB.saveFriendChatMessage(friendUserId, message.toJson());
            Log.d('[AppState] ➕ เพิ่มข้อความใหม่: ${message.text}');
          } else {
            Log.d('[AppState] ⏭️ ข้าม: ข้อความซ้ำ "${message.text}"');
          }
        }

        // เรียงตามเวลา
        messages.sort((a, b) => a.time.compareTo(b.time));
        // 🔥 สร้าง List ใหม่เพื่อบังคับให้ Flutter รู้ว่ามีการเปลี่ยนแปลง
        _friendChats[friendUserId] = List.from(messages);
        Log.d('[AppState] ✅ รวมข้อความทั้งหมด: ${messages.length} ข้อความ');
      } catch (e) {
        Log.d('[AppState] Error loading Firebase messages: $e');
      }
    } else if (lastRead != null && myUserId != null) {
      // offline: apply last read ต่อ local messages เพื่อความถูกต้อง
      for (int i = 0; i < messages.length; i++) {
        final m = messages[i];
        if (!m.isRead && m.toUserId == myUserId && !m.time.isAfter(lastRead)) {
          messages[i] = m.copyWith(isRead: true);
        }
      }
      _friendChats[friendUserId] = List.from(messages);
    }

    notifyListeners();
  }

  /// รับข้อความจากเพื่อน (เมื่อได้รับผ่าน transport)
  /// ประกาศ Firebase userId ของเราให้ peer ที่เชื่อมต่ออยู่รู้จัก (broadcast)
  /// เพื่อให้ทั้งสองฝั่งจับคู่ friendUserId <-> peerId ปัจจุบันได้ ใช้ส่งข้อความเพื่อนแบบ unicast ได้แทนการ broadcast
  void _announceFriendIdToPeers() {
    final userId = friendService.currentUser?.id;
    if (userId == null) return;
    transport.sendMessage('FRIEND_ID:$userId', to: null);
  }

  /// หา Peer ที่กำลังเชื่อมต่ออยู่ตอนนี้ของเพื่อนคนนี้ (ถ้ามี mapping และยังเชื่อมต่ออยู่)
  Peer? _peerForFriend(String friendUserId) {
    final peerId = _friendUserIdToPeerId[friendUserId];
    if (peerId == null) return null;
    final peer = _peers.firstWhere((p) => p.id == peerId, orElse: () => const Peer(id: '', name: ''));
    return peer.id.isEmpty ? null : peer;
  }

  void _handleFriendMessage(String message, String fromPeerId) {
    Log.d('🔔 _handleFriendMessage ถูกเรียก: $message จาก $fromPeerId');
    // Format: "FRIEND_MSG:fromUserId:message"
    final parts = message.split(':');
    if (parts.length >= 3 && parts[0] == 'FRIEND_MSG') {
      final fromUserId = parts[1];
      final messageText = parts.sublist(2).join(':');
      Log.d('🔔 fromUserId: $fromUserId, messageText: $messageText');

      // 🔒 รับเฉพาะข้อความจากคนที่เป็นเพื่อนเราจริงๆ เท่านั้น - กันคนแปลกหน้าใกล้เคียง
      // สวมรอยเป็น userId ปลอม (ข้อความนี้ broadcast ไปทุกเครื่อง ไม่ได้เข้ารหัส/ยืนยันตัวตน)
      if (!friendService.isFriend(fromUserId)) {
        Log.d('🔒 ปฏิเสธ FRIEND_MSG จาก $fromUserId - ไม่ใช่เพื่อนเรา');
        return;
      }

      // ✅ บันทึก mapping userId <-> peerId จากข้อความนี้ด้วย (เผื่อยังไม่เคยได้ FRIEND_ID มาก่อน)
      _friendUserIdToPeerId[fromUserId] = fromPeerId;

      final friendMessage = FriendChatMessage(
        id: 'received_${DateTime.now().millisecondsSinceEpoch}',
        fromUserId: fromUserId,
        toUserId: friendService.currentUser?.id ?? 'unknown',
        type: ChatType.text,
        text: messageText,
        time: DateTime.now(),
        isDelivered: true,
      );

      // บันทึกข้อความในแชทท้องถิ่น
      if (!_friendChats.containsKey(fromUserId)) {
        _friendChats[fromUserId] = [];
      }
      // 🔥 สร้าง List ใหม่แทนการ add ลงใน List เดิม
      _friendChats[fromUserId] = [..._friendChats[fromUserId]!, friendMessage];

      // บันทึกลงฐานข้อมูลท้องถิ่น
      FriendDB.saveFriendChatMessage(fromUserId, friendMessage.toJson());

      // อัพเดทข้อความสุดท้ายของเพื่อนและเพิ่มจำนวนข้อความที่ยังไม่อ่าน
      friendService.updateFriendLastMessage(fromUserId, messageText, DateTime.now(), incrementUnread: true);

      // แจ้งเตือนข้อความจากเพื่อน
      final friend = friendService.findFriendByUserId(fromUserId);
      final senderName = friend?.name ?? fromUserId;
      Log.d('🔔 กำลังแจ้งเตือน: friend=$friend, senderName=$senderName');
      Log.d('🔔 จำนวนเพื่อนทั้งหมด: ${friendService.friends.length}');
      NotificationService().showMessageNotification(
        senderName,
        messageText,
        senderId: fromUserId,
        onReply: friend != null ? () => _openFriendChatScreen(friend) : null,
      );
      // 🔔 แจ้งเตือนจริงผ่าน system tray (ใช้งานได้แม้แอปอยู่ background)
      BackgroundService().showMessageNotification(
        senderName: senderName,
        message: messageText,
      );
      Log.d('🔔 เรียก showMessageNotification แล้ว');

      notifyListeners();
    }
  }
  
  /// 🚑 รับสถานะหน่วยกู้ภัยจากเครื่องอื่น
  void _handleRescueStatus(String message, String fromPeerId) {
    Log.d('🔍 [DEBUG] _handleRescueStatus เรียกแล้ว');
    Log.d('🔍 [DEBUG] ข้อความที่ได้รับ: $message');
    Log.d('🔍 [DEBUG] จาก Peer ID: $fromPeerId');
    
    // Format: "RESCUE_STATUS:deviceName:status"
    final parts = message.split(':');
    Log.d('🔍 [DEBUG] แยกข้อความได้ ${parts.length} ส่วน: $parts');
    
    if (parts.length >= 3 && parts[0] == 'RESCUE_STATUS') {
      final deviceName = parts[1];
      final status = parts[2];
      final isRescue = status == 'RESCUE_MODE_ON';
      
      // 🔧 ⚠️ ตรวจสอบว่าเป็นข้อความจากตัวเองหรือไม่ - SKIP ทั้งหมด
      if (deviceName == _deviceName) {
        Log.d('🔇 [SKIP] RESCUE_STATUS จากตัวเอง ($deviceName) - ไม่ประมวลผล');
        return; // ⛔ ออกทันที ไม่ทำอะไรเลย
      }
      
      Log.d('🚑 ${isRescue ? "เปิด" : "ปิด"}โหมดหน่วยกู้ภัย: $deviceName ($fromPeerId)');
      Log.d('🔍 [DEBUG] isRescue = $isRescue');
      Log.d('🔍 [DEBUG] _isSOSActive = $_isSOSActive');
      
      // 🔧 ใช้ device name เป็น key แทน fromPeerId (เพื่อรองรับ mesh ที่มีหลาย ID)
      _rescuePeers[deviceName] = isRescue;
      Log.d('💾 [MESH] Saved rescue status for device name: $deviceName = $isRescue');
      
      // 🚨 ถ้าเราเปิดโหมด SOS อยู่ และพบหน่วยกู้ภัย -> แจ้งเตือนพิเศษ!
      if (isRescue && _isSOSActive) {
        Log.d('🔍 [DEBUG] 🎯 เข้าเงื่อนไขแจ้งเตือนพิเศษ! กำลังแสดงการแจ้งเตือน...');
        
        NotificationService().showInAppNotification(
          title: '🚑💚 มีหน่วยกู้ภัยมาช่วยแล้ว!',
          message: 'พบหน่วยกู้ภัย "$deviceName" อยู่ใกล้คุณ\nกำลังจะมีคนมาช่วยเหลือแล้ว อย่าท้อแท้นะ!',
          type: NotificationType.success,
        );
        
        // 📳 สั่น 5 ครั้ง เพื่อให้กำลังใจและยืนยัน
        for (int i = 0; i < 5; i++) {
          Future.delayed(Duration(milliseconds: i * 300), () {
            HapticFeedback.mediumImpact();
          });
        }
        
        Log.d('💚 ✨ พบหน่วยกู้ภัย! ให้กำลังใจผู้ประสบภัย (สั่น 5 ครั้ง)');
      } else if (isRescue) {
        Log.d('🔍 [DEBUG] เข้าเงื่อนไขแจ้งเตือนปกติ (ไม่ได้เปิด SOS)');
        // กรณีปกติ (ไม่ได้เปิด SOS)
        NotificationService().showInAppNotification(
          title: '🚑 หน่วยกู้ภัยใกล้เคียง',
          message: '$deviceName พร้อมให้ความช่วยเหลือ',
          type: NotificationType.info,
        );
        
        // 📳 สั่น 5 ครั้ง เมื่อพบหน่วยกู้ภัย
        for (int i = 0; i < 5; i++) {
          Future.delayed(Duration(milliseconds: i * 300), () {
            HapticFeedback.mediumImpact();
          });
        }
      } else {
        Log.d('🔍 [DEBUG] ไม่เข้าเงื่อนไขแจ้งเตือนใดๆ');
      }
      
      notifyListeners();
    } else {
      Log.d('🔍 [DEBUG] ❌ ข้อความไม่ตรงรูปแบบ RESCUE_STATUS');
    }
  }
  
  /// 🚨 รับสถานะ SOS จากเครื่องอื่น
  void _handleSOSStatus(String message, String fromPeerId) {
    // Format: "SOS_STATUS:deviceName:status:lat:lng:timestamp"
    final parts = message.split(':');
    if (parts.length >= 3 && parts[0] == 'SOS_STATUS') {
      final deviceName = parts[1];
      final status = parts[2];
      
      // 🔧 ⚠️ ตรวจสอบว่าเป็นข้อความจากตัวเองหรือไม่ - SKIP ทั้งหมด
      if (deviceName == _deviceName) {
        Log.d('🔇 [SKIP] SOS_STATUS จากตัวเอง ($deviceName) - ไม่ประมวลผล');
        return; // ⛔ ออกทันที ไม่ทำอะไรเลย
      }
      
      // แยก status ออกเป็น 3 แบบ:
      // - SOS_MODE_ON = เข้าโหมด SOS (แสดงสีแดง แต่ไม่กระพริบ)
      // - SOS_ACTIVE = กดปุ่มขอความช่วยเหลือ (แสดงสีแดง + กระพริบ + เวลา)
      // - SOS_INACTIVE/SOS_MODE_OFF = ปิด SOS
      
      final isSOSMode = status == 'SOS_MODE_ON';
      final isSOSActive = status == 'SOS_ACTIVE';
      final isSOSEmergency = status == 'SOS_EMERGENCY';
      
      // ดึงพิกัด GPS ถ้ามี
      String? latitude;
      String? longitude;
      if (parts.length >= 5) {
        latitude = parts[3];
        longitude = parts[4];
      }
      
      // ดึง timestamp ถ้ามี (เฉพาะ SOS_ACTIVE)
      DateTime? sosTimestamp;
      if (parts.length >= 6) {
        final timestampMs = int.tryParse(parts[5]);
        if (timestampMs != null && timestampMs > 0) {
          sosTimestamp = DateTime.fromMillisecondsSinceEpoch(timestampMs);
        }
      }
      
      Log.d('🚨 Status: $status from $deviceName ($fromPeerId)');
      if (latitude != null && longitude != null) {
        Log.d('📍 Location: $latitude, $longitude');
      }
      if (sosTimestamp != null) {
        Log.d('⏰ SOS Timestamp: $sosTimestamp');
      }
      
      // 🔧 ใช้ device name เป็น key แทน fromPeerId (เพื่อรองรับ mesh ที่มีหลาย ID)
      if (isSOSMode) {
        // เข้าโหมด SOS - แสดงสีแดงแต่ไม่กระพริบ
        _sosModePeers[deviceName] = true;
        _sosPeers.remove(deviceName); // ❌ ลบออกเพราะยังไม่มี timestamp (ไม่ได้กดปุ่ม)
        Log.d('🚨 $deviceName เข้าโหมด SOS (ยังไม่ขอความช่วยเหลือ)');
        Log.d('💾 [MESH] Saved SOS mode for device name: $deviceName = true');
        
        // 🔔 แจ้งเตือนเมื่อพบอุปกรณ์เข้าโหมด SOS (แต่ยังไม่ขอความช่วยเหลือ)
        String locationInfo = '';
        if (latitude != null && longitude != null && latitude != '0.0' && longitude != '0.0') {
          locationInfo = '\n📍 ตำแหน่ง: https://www.google.com/maps?q=$latitude,$longitude';
        }
        
        // แสดง In-App notification
        NotificationService().showInAppNotification(
          title: '⚠️ พบอุปกรณ์ขอความช่วยเหลือ SOS',
          message: '$deviceName ต้องการความช่วยเหลือ$locationInfo',
          type: NotificationType.warning,
        );
        
        // � สั่น 5 ครั้ง เมื่อพบอุปกรณ์ SOS Mode
        for (int i = 0; i < 5; i++) {
          Future.delayed(Duration(milliseconds: i * 300), () {
            HapticFeedback.mediumImpact();
          });
        }
        
        // �🔔 แสดง System notification
        _showSOSModeNotification(
          senderName: deviceName,
          latitude: latitude != null ? double.tryParse(latitude) : null,
          longitude: longitude != null ? double.tryParse(longitude) : null,
        );
      } else if (isSOSEmergency) {
        // กดปุ่ม SOS แบบฉุกเฉิน (ค้าง 5 วินาที) - แสดงสีแดงกระพริบเด่น
        _sosModePeers[deviceName] = true;
        _sosPeers[deviceName] = sosTimestamp ?? DateTime.now();
        _emergencySOSPeers[deviceName] = sosTimestamp ?? DateTime.now();
        Log.d('🚨🚨 $deviceName กดปุ่ม SOS ฉุกเฉิน!');

        String locationInfo = '';
        if (latitude != null && longitude != null) {
          locationInfo = '\n📍 Location: https://www.google.com/maps?q=$latitude,$longitude';
        }

        NotificationService().showInAppNotification(
          title: '🚨🚨 SOS ฉุกเฉิน! ต้องการความช่วยเหลือด่วนที่สุด!',
          message: '$deviceName อยู่ในสถานการณ์ฉุกเฉิน!$locationInfo',
          type: NotificationType.emergency,
        );

        for (int i = 0; i < 8; i++) {
          Future.delayed(Duration(milliseconds: i * 200), () {
            HapticFeedback.heavyImpact();
          });
        }

        _showSOSNotification(
          senderName: deviceName,
          message: 'ฉุกเฉิน! ต้องการความช่วยเหลือด่วนที่สุด!',
          latitude: latitude != null ? double.tryParse(latitude) : null,
          longitude: longitude != null ? double.tryParse(longitude) : null,
        );
      } else if (isSOSActive) {
        // กดปุ่ม SOS ปกติ - แสดงสีแดง + กระพริบ + เวลา
        _sosModePeers[deviceName] = true;
        _sosPeers[deviceName] = sosTimestamp ?? DateTime.now();
        _emergencySOSPeers.remove(deviceName);
        Log.d('🚨 $deviceName กดปุ่ม SOS - ขอความช่วยเหลือ!');
        Log.d('💾 [MESH] Saved SOS active for device name: $deviceName with timestamp');

        String locationInfo = '';
        if (latitude != null && longitude != null) {
          locationInfo = '\n📍 Location: https://www.google.com/maps?q=$latitude,$longitude';
        }

        NotificationService().showInAppNotification(
          title: '🚨 SOS! ขอความช่วยเหลือด่วน!',
          message: '$deviceName ต้องการความช่วยเหลือเร่งด่วน!$locationInfo',
          type: NotificationType.emergency,
        );

        for (int i = 0; i < 5; i++) {
          Future.delayed(Duration(milliseconds: i * 250), () {
            HapticFeedback.heavyImpact();
          });
        }

        _showSOSNotification(
          senderName: deviceName,
          message: 'ต้องการความช่วยเหลือเร่งด่วน!',
          latitude: latitude != null ? double.tryParse(latitude) : null,
          longitude: longitude != null ? double.tryParse(longitude) : null,
        );
      } else {
        // ปิด SOS
        _sosModePeers.remove(deviceName);
        _sosPeers.remove(deviceName);
        _emergencySOSPeers.remove(deviceName);
        Log.d('🚨 $deviceName ปิดโหมด SOS');
        Log.d('💾 [MESH] Removed SOS status for device name: $deviceName');
      }
      
      notifyListeners();
    }
  }
  
  // เก็บ emergency SOS peers (กด SOS แบบค้าง 5 วินาที)
  final Map<String, DateTime?> _emergencySOSPeers = {};

  bool isEmergencySOSPeer(String peerNameOrId) => _emergencySOSPeers[peerNameOrId] != null;

  // เก็บสถานะหน่วยกู้ภัยของแต่ละ peer
  final Map<String, bool> _rescuePeers = {};
  
  // เก็บว่า peer ไหนอยู่ในโหมด SOS (แต่ยังไม่ได้กดปุ่มขอความช่วยเหลือ)
  final Map<String, bool> _sosModePeers = {}; // peerId -> true = อยู่ในโหมด SOS
  
  // เก็บสถานะ SOS ของแต่ละ peer พร้อมเวลาที่กด SOS (ขอความช่วยเหลือแล้ว)
  final Map<String, DateTime?> _sosPeers = {}; // peerId -> เวลาที่กด SOS (null = ยังไม่ได้กด)
  
  // 🌐 Mesh Network: เก็บ ID ข้อความที่เคยส่งต่อแล้ว (ป้องกันการส่งซ้ำ)
  final Set<String> _forwardedMessages = {};
  final Map<String, int> _messageTTL = {}; // Time To Live สำหรับแต่ละข้อความ
  final Map<String, DateTime> _messageTimestamps = {}; // เก็บเวลาที่รับข้อความ
  
  // 📊 Network Topology: เก็บข้อมูลเครือข่าย
  final Map<String, Set<String>> _networkTopology = {}; // peerId -> connected peers
  
  // 🔧 Getters สำหรับ UI - รับ peer name แทน peer ID (เพื่อรองรับ mesh)
  bool isRescuePeer(String peerNameOrId) {
    // ลองหาทั้ง name และ ID
    return _rescuePeers[peerNameOrId] ?? false;
  }
  
  bool isSOSModePeer(String peerNameOrId) {
    // ลองหาทั้ง name และ ID
    return _sosModePeers[peerNameOrId] ?? false;
  }
  
  bool isSOSPeer(String peerNameOrId) {
    // ต้องเช็คว่ามี key และ value ไม่เป็น null (กดปุ่ม SOS แล้ว)
    final timestamp = _sosPeers[peerNameOrId];
    return timestamp != null; // return true เฉพาะตอนมี timestamp จริงๆ
  }
  
  DateTime? getSOSTimestamp(String peerNameOrId) => _sosPeers[peerNameOrId]; // ดึงเวลาที่กด SOS
  
  Map<String, bool> get rescuePeers => Map.unmodifiable(_rescuePeers);
  
  // เช็คว่า peer เป็นหน่วยกู้ภัยหรือไม่
  bool isPeerRescue(String peerNameOrId) {
    return _rescuePeers[peerNameOrId] ?? false;
  }

  /// รีเซ็ตจำนวนข้อความที่ยังไม่อ่านของเพื่อน
  Future<void> markFriendMessagesAsRead(String friendUserId) async {
    await friendService.markFriendMessagesAsRead(friendUserId);

    final myUserId = friendService.currentUser?.id;

    // อัพเดทสถานะ isRead ของข้อความ และ persist ลง SharedPreferences
    if (_friendChats.containsKey(friendUserId)) {
      for (int i = 0; i < _friendChats[friendUserId]!.length; i++) {
        final message = _friendChats[friendUserId]![i];
        if (!message.isRead && message.fromUserId != myUserId) {
          final updated = message.copyWith(isRead: true);
          _friendChats[friendUserId]![i] = updated;
          await FriendDB.saveFriendChatMessage(friendUserId, updated.toJson());
        }
      }
    }

    // บันทึก last read timestamp ที่ไม่ถูกลบตอน logout
    // เพื่อให้ข้ามเซสชันได้ถูกต้องเมื่อ login ใหม่
    if (myUserId != null) {
      await FriendDB.setLastReadTime(myUserId, friendUserId, DateTime.now());
    }

    notifyListeners();
  }

  /// ฟังก์ชันสำหรับ Logout - ลบข้อมูลแชททั้งหมด
  Future<void> logout() async {
    // ยกเลิก timer อัปเดตสถานะออนไลน์
    _stopOnlineStatusUpdates();
    
    // ยกเลิก GPS location broadcast
    _stopLocationBroadcast();
    
    // ยกเลิก auto sync ของ FriendService
    friendService.stopAutoSync();

    // หยุด global inbox listener
    stopGlobalInboxListener();
    
    // 🔄 Sync แชทขึ้น Firebase ก่อน logout (ถ้า online)
    if (friendService.currentUser != null && firebaseService.isOnline) {
      Log.d('[Logout] 🔄 Syncing chats to Firebase...');
      await _syncChatsToFirebase();
    }
    
    // ตั้งสถานะออฟไลน์ก่อน logout
    if (friendService.currentUser != null) {
      await firebaseService.updateOnlineStatus(friendService.currentUser!.id, false);
      
      // ลบข้อความของ user ที่ login ออก (แต่เก็บข้อความ anonymous ไว้)
      await ChatDB.clearUserMessages(friendService.currentUser!.id);
      Log.d('[Logout] 🗑️ ลบข้อความของ user ${friendService.currentUser!.id} จาก local');
    }
    
    // 🔄 Reset sync flag เพื่อให้ login ครั้งต่อไปทำงานได้
    _lastSyncedUserId = null;
    Log.d('[Logout] 🔄 Reset sync flag');
    
    // 🆔 Reset User ID ใน DeviceIdManager (กลับไปใช้ Device ID)
    DeviceIdManager.setUserId(null);
    Log.d('[Logout] 🆔 Reset to device ID');
    
    // ล้างข้อมูลใน memory
    _chatMessages.clear();
    _friendChats.clear();
    _messages.clear();
    // ไม่ลบ _peers เพื่อให้ยังคุยกับ nearby peers ได้
    
    // ล้างข้อมูลเพื่อนและแชทเพื่อนทั้งหมด
    await FriendDB.clearAllData();
    
    Log.d('[Logout] ✅ Logout เสร็จสิ้น');
    notifyListeners();
  }

  /// 🔄 Sync ข้อความแชททั้งหมดขึ้น Firebase
  Future<void> _syncChatsToFirebase() async {
    if (friendService.currentUser == null) return;
    
    try {
      final userId = friendService.currentUser!.id;
      final messages = await ChatDB.getMessages(userId);
      
      if (messages.isEmpty) {
        Log.d('[Sync] ไม่มีข้อความที่ต้อง sync');
        return;
      }
      
      // แปลง ChatMessage เป็น Map
      final messageMaps = messages.map((msg) => {
        'id': msg.id,
        'from': msg.from,
        'type': msg.type.toString().split('.').last,
        'text': msg.text,
        'filePath': msg.filePath,
        'time': msg.time.millisecondsSinceEpoch,
        'isEmergency': msg.isEmergency,
        'status': msg.status.toString().split('.').last,
      }).toList();
      
      final syncedCount = await firebaseService.syncPendingMessages(messageMaps);
      Log.d('[Sync] ✅ Synced $syncedCount/${messages.length} messages to Firebase');
    } catch (e) {
      Log.d('[Sync] ❌ Error syncing to Firebase: $e');
    }
  }

  /// � Sync ข้อความที่ยังไม่ได้ sync (สถานะ sent) ขึ้น Firebase หลัง login
  Future<void> _syncNearbyMessagesToFirebase() async {
    if (friendService.currentUser == null) return;
    
    try {
      final userId = friendService.currentUser!.id;
      
      // ดึงข้อความที่ยังไม่ได้ sync (สถานะ sent หรือ pending)
      final unsyncedMessages = await ChatDB.getUnsyncedMessages(userId);
      final pendingMessages = await ChatDB.getPendingMessages(userId);
      final allUnsynced = [...unsyncedMessages, ...pendingMessages];
      
      if (allUnsynced.isEmpty) {
        Log.d('[Sync] ✅ ไม่มีข้อความที่รอ sync');
        return;
      }
      
      Log.d('[Sync] 🔄 พบ ${allUnsynced.length} ข้อความที่ต้อง sync');
      
      int syncedCount = 0;
      for (final msg in allUnsynced) {
        try {
          // ดึงข้อมูล sender และ receiver จากฐานข้อมูล
          final database = await ChatDB.db;
          final msgData = await database.query(
            'chat_messages',
            where: 'id = ?',
            whereArgs: [msg.id],
            limit: 1,
          );
          
          String? sender;
          String? receiver;
          String? receiverName;
          
          if (msgData.isNotEmpty) {
            sender = msgData.first['sender'] as String?;
            receiver = msgData.first['receiver'] as String?;
            
            // หาชื่อของ receiver จาก device ID
            if (receiver != null) {
              final peer = _peers.firstWhere(
                (p) => p.id == receiver,
                orElse: () => Peer(id: receiver!, name: receiver),
              );
              receiverName = peer.name;
            }
          }
          
          final messageMap = {
            'id': msg.id,
            'from': sender ?? msg.from,
            'to': receiver,
            'toName': receiverName ?? receiver, // เก็บชื่ออุปกรณ์ที่คุยด้วย
            'type': msg.type.toString().split('.').last,
            'text': msg.text,
            'filePath': msg.filePath,
            'time': msg.time.millisecondsSinceEpoch,
            'isEmergency': msg.isEmergency,
            'status': msg.status.toString().split('.').last,
            'isNearbyChat': true, // ระบุว่าเป็นข้อความ nearby
          };
          
          final success = await firebaseService.syncChatMessageToCloud(messageMap);
          if (success) {
            // อัพเดทสถานะเป็น synced
            await ChatDB.updateMessageStatus(msg.id, MessageStatus.synced);
            syncedCount++;
          }
        } catch (e) {
          Log.d('[Sync] ❌ Error syncing message ${msg.id}: $e');
        }
      }
      
      Log.d('[Sync] ✅ Synced $syncedCount/${allUnsynced.length} messages to Firebase');
      
      // โหลดข้อความใหม่เพื่ออัปเดตสถานะ
      if (syncedCount > 0) {
        await _loadLocalMessages();
      }
    } catch (e) {
      Log.d('[Sync] ❌ Error in _syncNearbyMessagesToFirebase: $e');
    }
  }

  /// �📥 โหลดข้อความแชทจาก Firebase หลัง login
  Future<void> _loadChatsFromFirebase() async {
    if (friendService.currentUser == null) return;
    
    try {
      final cloudMessages = await firebaseService.getUserChatMessages();
      
      if (cloudMessages.isEmpty) {
        Log.d('[Sync] ไม่มีข้อความใน Firebase');
        return;
      }
      
      final userId = friendService.currentUser!.id;
      
      // แปลง Map เป็น ChatMessage และบันทึกลง local
      for (final msgMap in cloudMessages) {
        try {
          final msg = ChatMessage(
            id: msgMap['id'] ?? '',
            from: msgMap['from'] ?? 'unknown',
            type: ChatType.values.firstWhere(
              (e) => e.toString().split('.').last == msgMap['type'],
              orElse: () => ChatType.text,
            ),
            text: msgMap['text'],
            filePath: msgMap['filePath'],
            time: DateTime.fromMillisecondsSinceEpoch(msgMap['time'] ?? 0),
            isEmergency: msgMap['isEmergency'] ?? false,
            status: MessageStatus.values.firstWhere(
              (e) => e.toString().split('.').last == msgMap['status'],
              orElse: () => MessageStatus.synced,
            ),
          );
          
          // บันทึกพร้อม receiver (ถ้ามี)
          final receiver = msgMap['to'] as String?;
          await ChatDB.insertMessage(msg, userId, receiver: receiver);
        } catch (e) {
          Log.d('[Sync] ❌ Error parsing message: $e');
        }
      }
      
      Log.d('[Sync] 📥 Loaded ${cloudMessages.length} messages from Firebase');
      await _loadLocalMessages();
    } catch (e) {
      Log.d('[Sync] ❌ Error loading from Firebase: $e');
    }
  }

  /// 🔄 Force Sync - บังคับซิงก์ข้อความกับ Firebase ทันที
  Future<void> forceSyncWithFirebase() async {
    if (friendService.currentUser == null) {
      Log.d('[ForceSync] ❌ ต้อง login ก่อน');
      return;
    }
    
    if (!firebaseService.isOnline) {
      Log.d('[ForceSync] ❌ ไม่มีอินเทอร์เน็ต');
      return;
    }
    
    Log.d('[ForceSync] 🔄 เริ่ม Force Sync...');
    
    try {
      // 1. Sync ข้อความ local ขึ้น Firebase
      await _syncNearbyMessagesToFirebase();
      
      // 2. ดึงข้อความจาก Firebase ลงมา
      await _loadChatsFromFirebase();
      
      Log.d('[ForceSync] ✅ Force Sync เสร็จสิ้น');
      notifyListeners();
    } catch (e) {
      Log.d('[ForceSync] ❌ Error: $e');
    }
  }

  /// 🗑️ ลบข้อความ (ทั้ง local และ Firebase)
  Future<void> deleteMessage(String messageId) async {
    try {
      // 1. ลบจาก local database
      await ChatDB.deleteMessage(messageId);

      // 2. ลบจาก Firebase (ถ้า login และ online)
      if (friendService.currentUser != null && firebaseService.isOnline) {
        await firebaseService.deleteChatMessage(friendService.currentUser!.id, messageId);
        Log.d('[DeleteMsg] 🗑️ Deleted from Firebase: $messageId');
      }

      // 3. โหลดข้อความใหม่
      await _loadLocalMessages();

      Log.d('[DeleteMsg] ✅ Message deleted: $messageId');
      notifyListeners();
    } catch (e) {
      Log.d('[DeleteMsg] ❌ Error: $e');
    }
  }

  /// Retry ส่งข้อความที่ค้างอยู่ (pending) ชิ้นเดียว — เรียกจาก UI retry button
  Future<void> retrySendMessage(String messageId) async {
    await _messageQueue.retryMessage(messageId);
    notifyListeners();
  }

  // 🌐 Mesh Network: จัดการข้อความที่ต้อง Relay ต่อ
  Future<void> _handleRelayMessage(String body, String fromPeerId) async {
    // รูปแบบ: RELAY:messageId:ttl:originalSender:senderName:content
    final parts = body.split(':');
    if (parts.length < 6) return;

    final messageId = parts[1];
    final ttl = int.tryParse(parts[2]) ?? 0;
    final originalSender = parts[3];
    final senderName = parts[4];
    final content = parts.sublist(5).join(':');

    // ตรวจสอบว่าเคยส่งต่อหรือไม่
    if (_forwardedMessages.contains(messageId)) {
      Log.d('🔁 ข้อความ $messageId เคยส่งต่อแล้ว ไม่ส่งซ้ำ');
      return;
    }

    // ตรวจสอบ TTL (หมดอายุหรือไม่)
    if (ttl <= 0) {
      Log.d('⏰ ข้อความ $messageId หมดอายุ (TTL=0)');
      return;
    }

    // บันทึกว่าเคยส่งต่อแล้ว
    _forwardedMessages.add(messageId);
    _messageTTL[messageId] = ttl;

    Log.d('🌐 รับข้อความ Relay จาก $fromPeerId: $content (TTL=$ttl)');

    // แสดงข้อความในแชท (ถ้าเป็นแชทกับผู้ส่งเดิม)
    final msg = ChatMessage(
      id: messageId,
      from: originalSender,
      type: ChatType.text,
      text: content,
      time: DateTime.now(),
      status: MessageStatus.delivered,
      isRead: false, // ข้อความ relay ใหม่ - ยังไม่ได้อ่าน
    );
    
    // 🔥 สร้าง List ใหม่แทนการ add
    _chatMessages = [..._chatMessages, msg];
    
    // เก็บลง DB
    final currentUserId = friendService.currentUser?.id ?? 'anonymous';
    await ChatDB.insertMessage(msg, currentUserId, receiver: originalSender);
    
    notifyListeners();

    // Relay ต่อไปยัง peers อื่นๆ (ยกเว้นคนที่ส่งมา)
    final newTTL = ttl - 1;
    if (newTTL > 0 && _peers.isNotEmpty) {
      final relayMsg = 'RELAY:$messageId:$newTTL:$originalSender:$senderName:$content';
      
      // บันทึก network topology
      _networkTopology[fromPeerId] = _peers.map((p) => p.id).toSet();
      _messageTimestamps[messageId] = DateTime.now();
      
      for (final peer in _peers) {
        if (peer.id != fromPeerId && peer.id != originalSender) {
          try {
            // 🔧 FIX: ต้องระบุ to: peer เพื่อส่งถึงเป้าหมายเฉพาะ
            await transport.sendMessage(relayMsg, to: peer);
            Log.d('📡 ส่งต่อไปยัง ${peer.name} (TTL=$newTTL)');
          } catch (e) {
            Log.d('❌ ส่งต่อไปยัง ${peer.name} ล้มเหลว: $e');
          }
        }
      }
      
      // ล้างข้อความเก่า (เก็บไว้แค่ 100 ข้อความล่าสุด)
      _cleanupOldMessages();
    }

    // แสดง notification
    NotificationService().showMessageNotification(
      '📡 Mesh จาก $senderName',
      content,
    );
  }
  
  // 🧹 ล้างข้อความเก่าเพื่อป้องกัน memory leak
  void _cleanupOldMessages() {
    const maxMessages = 100;
    
    if (_forwardedMessages.length > maxMessages) {
      // เก็บแค่ข้อความล่าสุด
      final sortedMessages = _messageTimestamps.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      
      final toRemove = sortedMessages.skip(maxMessages).map((e) => e.key).toList();
      
      for (final msgId in toRemove) {
        _forwardedMessages.remove(msgId);
        _messageTTL.remove(msgId);
        _messageTimestamps.remove(msgId);
      }
      
      Log.d('🧹 ล้างข้อความเก่า: ${toRemove.length} ข้อความ (เหลือ ${_forwardedMessages.length})');
    }
  }
  
  // � จัดการข้อความ GPS Location (ไม่บันทึกลง chat)
  void _handleGPSLocation(String message, String fromPeerId) {
    // Format: "GPS_LOC:lat,lng,timestamp"
    final parts = message.split(':');
    Log.d('🔍 [GPS] รับข้อความ GPS: $message');
    
    if (parts.length >= 2 && parts[0] == 'GPS_LOC') {
      try {
        final location = PeerLocation.fromString(parts[1]);
        _peerLocations[fromPeerId] = location;
        Log.d('📍 [Real-time] อัพเดทตำแหน่ง peer $fromPeerId: ${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}');
        Log.d('💾 [GPS] จำนวน peer locations: ${_peerLocations.length}');
        
        // ⚡ คำนวณระยะห่างทันทีและอัพเดท UI
        if (_myCurrentPosition != null) {
          final distance = Geolocator.distanceBetween(
            _myCurrentPosition!.latitude,
            _myCurrentPosition!.longitude,
            location.latitude,
            location.longitude,
          );
          Log.d('📏 [Real-time] ระยะห่างจาก peer $fromPeerId: ${distance.toStringAsFixed(1)}m');
        } else {
          Log.d('⚠️ [GPS] ยังไม่มีตำแหน่งของตัวเอง (_myCurrentPosition = null)');
        }
        
        notifyListeners(); // ⚡ อัพเดท UI ทันที
      } catch (e) {
        Log.d('❌ ไม่สามารถแปลงข้อมูล GPS: $e (message: $message)');
      }
    } else {
      Log.d('⚠️ [GPS] ข้อความ GPS format ไม่ถูกต้อง: $message');
    }
  }
  
  // 📍 คำนวณระยะห่างจาก peer (Real-time version)
  double? getDistanceToPeerSync(String peerId, Position? myPosition) {
    // ⚡ ใช้ตำแหน่งที่เก็บไว้ (real-time) ถ้าไม่ส่งมา
    final position = myPosition ?? _myCurrentPosition;
    if (position == null) {
      Log.d('⚠️ [Distance] ไม่มีตำแหน่งของตัวเอง (position = null)');
      return null;
    }
    
    final peerLoc = _peerLocations[peerId];
    if (peerLoc == null) {
      Log.d('⚠️ [Distance] ไม่มีตำแหน่งของ peer $peerId');
      return null;
    }
    
    // ใช้ Haversine formula คำนวณระยะทาง
    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      peerLoc.latitude,
      peerLoc.longitude,
    );
    
    Log.d('📏 [Distance] คำนวณระยะห่าง peer $peerId: ${distance.toStringAsFixed(1)}m');
    return distance;
  }
  
  // 📍 เริ่ม Real-time GPS Streaming - อัพเดททันทีเมื่อเคลื่อนที่
  // 📍 เริ่ม Real-time GPS Streaming - อัพเดททันทีเมื่อเคลื่อนที่
  void _startLocationBroadcast() async {
    _locationStreamSubscription?.cancel();
    
    try {
      // 🔒 เช็ค GPS permission ก่อน
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        Log.d('❌ GPS ถูกปิด - ไม่สามารถ broadcast ตำแหน่งได้');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          Log.d('❌ ไม่ได้รับ GPS permission - ไม่สามารถ broadcast ตำแหน่งได้');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        Log.d('❌ GPS permission ถูกปฏิเสธถาวร');
        return;
      }
      
      // 🎯 ใช้ LocationSettings สำหรับ real-time tracking
      const LocationSettings locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high, // ความแม่นยำสูง
        distanceFilter: 5, // อัพเดททุกครั้งที่เคลื่อนที่ 5 เมตร (real-time!)
      );
      
      Log.d('📍 กำลังเริ่ม Real-time GPS Stream...');
      
      // 📡 เริ่ม listen GPS stream แบบ real-time
      _locationStreamSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (Position position) {
          // ⚡ อัพเดทตำแหน่งปัจจุบันทันที
          _myCurrentPosition = position;
          
          // 📡 ส่งตำแหน่งไปให้ peers ทันที (ถ้ามี peer)
          if (_peers.isNotEmpty) {
            final location = PeerLocation(
              latitude: position.latitude,
              longitude: position.longitude,
              timestamp: DateTime.now(),
            );
            
            final message = 'GPS_LOC:${location.toString()}';
            transport.sendMessage(message).then((_) {
              Log.d('📍 [Real-time] ส่งตำแหน่ง: ${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)} (±${position.accuracy.toStringAsFixed(1)}m)');
            }).catchError((e) {
              Log.d('❌ ส่งตำแหน่งล้มเหลว: $e');
            });
          }
          
          // 🔄 อัพเดท UI ทันที
          notifyListeners();
        },
        onError: (e) {
          Log.d('❌ GPS Stream Error: $e');
          // 🔄 ลองเริ่มใหม่หลัง 5 วินาที
          Future.delayed(const Duration(seconds: 5), () {
            if (_locationStreamSubscription == null) {
              Log.d('🔄 กำลังลอง restart GPS stream...');
              _startLocationBroadcast();
            }
          });
        },
      );
      
      Log.d('✅ เริ่ม Real-time GPS Stream สำเร็จ (อัพเดททุก 5m หรือเมื่อเคลื่อนที่)');
      
    } catch (e) {
      Log.d('❌ ไม่สามารถเริ่ม GPS stream: $e');
    }
  }
  
  // 📍 หยุด Real-time GPS Stream
  void _stopLocationBroadcast() {
    _locationStreamSubscription?.cancel();
    _locationStreamSubscription = null;
    _myCurrentPosition = null;
    Log.d('📍 หยุด Real-time GPS Stream');
  }
  
  // � Keep Alive - ส่ง heartbeat ทุก 30 วินาที
  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_peers.isNotEmpty) {
        // ส่ง keep alive message เพื่อรักษาการเชื่อมต่อ (ไม่ await)
        try {
          transport.sendMessage('KEEP_ALIVE:${DateTime.now().millisecondsSinceEpoch}'); // ⚡ ไม่ await
          Log.d('💓 Keep Alive sent to ${_peers.length} peers');
        } catch (e) {
          Log.d('❌ Keep Alive failed: $e');
        }
      }
    });
    Log.d('💓 เริ่ม Keep Alive ทุก 30 วินาที');
  }
  
  // 🔁 Connection Monitor - ตรวจสอบและ reconnect ทุก 10 วินาที
  void _startConnectionMonitor() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      // ถ้าเปิดโหมด SOS หรือ Rescue แต่ไม่มี peer → พยายาม reconnect
      if ((_isSOSActive || _isRescueMode) && _peers.isEmpty) {
        if (_reconnectAttempts < _maxReconnectAttempts) {
          _reconnectAttempts++;
          Log.d('🔁 Reconnect attempt $_reconnectAttempts/$_maxReconnectAttempts');
          
          // พยายาม scan ใหม่
          await stopScan();
          await Future.delayed(const Duration(seconds: 1));
          await startScan();
          
        } else if (_reconnectAttempts == _maxReconnectAttempts) {
          Log.d('⚠️ Reconnect failed after $_maxReconnectAttempts attempts');
          _reconnectAttempts++; // เพิ่มอีก 1 เพื่อไม่ให้ log ซ้ำ
        }
      }
      
      // ถ้ามี peer แล้ว reset counter
      if (_peers.isNotEmpty && _reconnectAttempts > 0) {
        _reconnectAttempts = 0;
      }
    });
    Log.d('🔁 เริ่ม Connection Monitor ทุก 10 วินาที');
  }
  
  // �📍 ส่ง GPS Location ของตัวเองไปให้ peers
  Future<void> broadcastMyLocation() async {
    try {
      Position? position;
      
      // พยายามดึง GPS ปัจจุบัน (timeout 15 วินาที)
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium, // ลดความแม่นยำเพื่อความเร็ว
          timeLimit: const Duration(seconds: 15),
        );
      } catch (e) {
        // ถ้าไม่ได้ ให้ใช้ตำแหน่งล่าสุดแทน
        Log.d('⚠️ ไม่สามารถดึง GPS ปัจจุบัน: $e');
        Log.d('📍 กำลังใช้ตำแหน่งล่าสุดแทน...');
        position = await Geolocator.getLastKnownPosition();
      }
      
      if (position == null) {
        Log.d('❌ ไม่มีข้อมูล GPS (ทั้งปัจจุบันและล่าสุด)');
        return;
      }
      
      final location = PeerLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        timestamp: DateTime.now(),
      );
      
      final message = 'GPS_LOC:${location.toString()}';
      transport.sendMessage(message); // ⚡ ไม่ await - broadcast แบบ fire-and-forget
      Log.d('📍 ส่งตำแหน่ง: ${location.latitude}, ${location.longitude} (±${position.accuracy.toStringAsFixed(1)}m)');
    } catch (e) {
      Log.d('❌ ไม่สามารถดึง GPS ได้: $e');
    }
  }
  
  // �📊 ดึงข้อมูล Network Topology
  Map<String, Set<String>> get networkTopology => Map.unmodifiable(_networkTopology);
  
  // 📊 สถิติ Mesh Network
  Map<String, dynamic> getMeshNetworkStats() {
    return {
      'totalForwardedMessages': _forwardedMessages.length,
      'averageTTL': _messageTTL.values.isEmpty 
          ? 0 
          : _messageTTL.values.reduce((a, b) => a + b) / _messageTTL.length,
      'networkNodes': _networkTopology.length,
      'oldestMessage': _messageTimestamps.values.isEmpty
          ? null
          : _messageTimestamps.values.reduce((a, b) => a.isBefore(b) ? a : b),
    };
  }

  /// เริ่มอัปเดตสถานะออนไลน์แบบอัตโนมัติ (ทุก 5 วินาที)
  void _startOnlineStatusUpdates() {
    Log.d('[AppState] 🔧 เริ่มต้น _startOnlineStatusUpdates...');
    _stopOnlineStatusUpdates(); // ยกเลิก timer เก่าก่อน (ถ้ามี)
    
    if (friendService.currentUser == null) {
      Log.d('[AppState] ⚠️ ไม่มี currentUser - ข้าม timer');
      return;
    }
    
    if (!_isAppInForeground) {
      Log.d('[AppState] ⚠️ แอพไม่ได้อยู่ foreground - ข้าม timer');
      return;
    }
    
    Log.d('[AppState] ✅ สร้าง Timer สำหรับ ${friendService.currentUser!.name} (${friendService.currentUser!.id})');
    _onlineStatusTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      // เช็คว่าแอพยังอยู่ foreground หรือไม่
      if (!_isAppInForeground) {
        Log.d('[AppState] ⚠️ [Heartbeat] แอพไม่ได้อยู่ foreground - ข้ามการอัปเดต');
        return;
      }
      
      if (friendService.currentUser != null && firebaseService.isOnline && firebaseService.isSignedIn) {
        Log.d('[AppState] 🔄 [Heartbeat] อัปเดตสถานะออนไลน์สำหรับ: ${friendService.currentUser!.name}');
        await firebaseService.updateOnlineStatus(friendService.currentUser!.id, true);
      } else {
        Log.d('[AppState] ⚠️ [Heartbeat] ข้ามการอัปเดต - currentUser=${friendService.currentUser?.name}, online=${firebaseService.isOnline}, signedIn=${firebaseService.isSignedIn}');
      }
    });
    Log.d('[AppState] ✅ Timer สร้างเสร็จแล้ว - จะอัปเดตทุก 5 วินาที');
  }

  /// หยุดอัปเดตสถานะออนไลน์
  void _stopOnlineStatusUpdates() {
    if (_onlineStatusTimer != null) {
      Log.d('[AppState] 🛑 หยุด Timer heartbeat');
    }
    _onlineStatusTimer?.cancel();
    _onlineStatusTimer = null;
  }

  /// ฟังก์ชันสำหรับ Login - โหลดข้อมูลแชทของ user
  Future<void> onUserLogin() async {
    Log.d('[AppState] 🔑 เริ่มต้น onUserLogin...');

    await friendService.init();
    Log.d('[AppState] ✅ init friendService เสร็จสิ้น');

    if (friendService.currentUser != null) {
      final userId = friendService.currentUser!.id;

      DeviceIdManager.setUserId(userId);

      Log.d('[AppState] 🔄 Starting migration for user: $userId');
      await ChatDB.migrateAnonymousMessages(userId);

      // โหลด local ก่อน → UI แสดงทันที (ไม่รอ Firebase)
      Log.d('[AppState] 📥 Loading local messages...');
      final local = await ChatDB.getMessages(userId);
      _chatMessages = [...local];
      Log.d('[AppState] ✅ Loaded ${_chatMessages.length} local messages');
      notifyListeners();

      setDeviceName(friendService.currentUser!.name);
      _startOnlineStatusUpdates();
      Log.d('[AppState] ✅ เริ่ม auto-update สถานะออนไลน์');
    }

    // เริ่ม global inbox listener — รับ notification จากเพื่อนแม้อยู่นอก chat screen
    if (friendService.currentUser != null && firebaseService.isOnline && firebaseService.isSignedIn) {
      startGlobalInboxListener();
      Log.d('[AppState] ✅ เริ่ม global inbox listener');
    }

    notifyListeners();

    // Firebase sync ทำใน background — ไม่ block UI
    if (friendService.currentUser != null && firebaseService.isOnline) {
      Log.d('[AppState] 🔄 Background: syncing Firebase → local...');
      syncFirebaseToLocal().then((_) {
        Log.d('[AppState] ✅ Background sync Firebase → local เสร็จสิ้น');
      });
      _syncNearbyMessagesToFirebase().then((_) {
        Log.d('[AppState] ✅ Background sync nearby → Firebase เสร็จสิ้น');
      });
    }
  }

  /// ฟังการเปลี่ยนแปลงสถานะของแอพ (foreground/background)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    Log.d('[AppState] 🔄 App Lifecycle เปลี่ยนเป็น: $state');
    
    switch (state) {
      case AppLifecycleState.resumed:
        // แอพกลับมา foreground (กำลังใช้งาน)
        Log.d('[AppState] ✅ แอพกลับมาใช้งาน - ตั้งสถานะออนไลน์');
        _isAppInForeground = true;
        _setOnlineStatus(true);
        _startOnlineStatusUpdates(); // เริ่ม heartbeat ใหม่
        break;
        
      case AppLifecycleState.paused:
        // แอพไป background (ออกไปใช้แอพอื่น)
        Log.d('[AppState] ⏸️ แอพไป background - ตั้งสถานะออฟไลน์');
        _isAppInForeground = false;
        _stopOnlineStatusUpdates(); // หยุด heartbeat
        _setOnlineStatus(false);
        break;
        
      case AppLifecycleState.inactive:
        // แอพกำลังจะเปลี่ยนสถานะ (เช่น มีโทรศัพท์เข้า)
        Log.d('[AppState] ⏸️ แอพ inactive');
        break;
        
      case AppLifecycleState.detached:
        // แอพกำลังจะปิด
        Log.d('[AppState] 🛑 แอพกำลังปิด - ตั้งสถานะออฟไลน์');
        _isAppInForeground = false;
        _setOnlineStatus(false);
        break;
        
      case AppLifecycleState.hidden:
        // แอพถูกซ่อน
        Log.d('[AppState] 🔒 แอพถูกซ่อน');
        break;
    }
  }

  /// ตั้งสถานะออนไลน์/ออฟไลน์
  void _setOnlineStatus(bool isOnline) async {
    if (friendService.currentUser != null && firebaseService.isSignedIn) {
      Log.d('[AppState] 🔄 ตั้งสถานะ: ${isOnline ? "ออนไลน์" : "ออฟไลน์"} สำหรับ ${friendService.currentUser!.name}');
      await firebaseService.updateOnlineStatus(friendService.currentUser!.id, isOnline);
    }
  }

  /// เปิดหน้าแชทจาก notification (ใช้ global navigator key)
  void _openChatScreen(Peer peer) {
    final context = navigatorKey.currentContext;
    if (context != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EmergencyChatScreen(peer: peer),
        ),
      );
    } else {
      Log.d('⚠️ ไม่สามารถเปิดหน้าแชทได้: Navigator context is null');
    }
  }

  void _openFriendChatScreen(Friend friend) {
    final context = navigatorKey.currentContext;
    if (context != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FriendChatScreen(friend: friend),
        ),
      );
    } else {
      Log.d('⚠️ ไม่สามารถเปิดหน้าแชทเพื่อนได้: Navigator context is null');
    }
  }

  /// Public method สำหรับให้ FCM Service เรียกใช้
  void openFriendChatScreenPublic(Friend friend) {
    _openFriendChatScreen(friend);
  }

  // 🔄 Background Service Methods
  
  /// เปิด Background Service
  Future<void> startBackgroundService() async {
    try {
      await _backgroundService.initialize();
      final success = await _backgroundService.startService();
      
      if (success) {
        _isBackgroundServiceEnabled = true;
        Log.d('✅ Background Service เริ่มทำงานแล้ว');
      } else {
        Log.d('❌ ไม่สามารถเริ่ม Background Service ได้');
      }
      
      notifyListeners();
    } catch (e) {
      Log.d('❌ Error starting background service: $e');
    }
  }
  
  /// ปิด Background Service
  Future<void> stopBackgroundService() async {
    try {
      final success = await _backgroundService.stopService();
      
      if (success) {
        _isBackgroundServiceEnabled = false;
        Log.d('⏹️ Background Service หยุดทำงานแล้ว');
      }
      
      notifyListeners();
    } catch (e) {
      Log.d('❌ Error stopping background service: $e');
    }
  }
  
  /// แสดง SOS notification เมื่อได้รับข้อความ SOS
  Future<void> _showSOSNotification({
    required String senderName,
    String? message,
    double? latitude,
    double? longitude,
  }) async {
    // ส่ง system notification เสมอ (ไม่ว่า background service เปิดหรือไม่)
    try {
      await _backgroundService.showSOSNotification(
        senderName: senderName,
        message: message,
        latitude: latitude,
        longitude: longitude,
      );
      Log.d('📱 ส่ง SOS system notification แล้ว');
    } catch (e) {
      Log.d('⚠️ ส่ง SOS system notification ล้มเหลว: $e');
    }
  }

  /// 🔔 แจ้งเตือนเมื่อพบอุปกรณ์เข้าโหมด SOS (ยังไม่ได้กดปุ่มขอความช่วยเหลือ)
  Future<void> _showSOSModeNotification({
    required String senderName,
    double? latitude,
    double? longitude,
  }) async {
    // ส่ง system notification เสมอ (ไม่ว่า background service เปิดหรือไม่)
    try {
      await _backgroundService.showSOSNotification(
        senderName: senderName,
        message: 'อยู่ในโหมดฉุกเฉิน - อาจต้องการความช่วยเหลือ',
        latitude: latitude,
        longitude: longitude,
      );
      Log.d('📱 ส่ง SOS Mode system notification แล้ว');
    } catch (e) {
      Log.d('⚠️ ส่ง SOS Mode system notification ล้มเหลว: $e');
    }
  }

  @override
  void dispose() {
    _stopOnlineStatusUpdates();
    _locationStreamSubscription?.cancel();
    _keepAliveTimer?.cancel();
    _reconnectTimer?.cancel();
    stopBackgroundService(); // ปิด Background Service
    WidgetsBinding.instance.removeObserver(this);
    transport.dispose();
    super.dispose();
  }
}

// สร้าง instance แบบง่ายๆ (เลี่ยงการเพิ่มแพ็กเกจ state management)

final appState = AppState(
  transport: NearbyTransport(deviceName: 'SOS Device'),
);
