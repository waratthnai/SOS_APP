import 'dart:collection';
import 'dart:async';
import 'dart:convert';
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
import 'e2ee_service.dart';

part 'app_state_location.dart';
part 'app_state_connection_monitor.dart';
part 'app_state_stable_peers.dart';
part 'app_state_online_status.dart';
part 'app_state_sos_rescue.dart';
part 'app_state_mesh_peers.dart';
part 'app_state_emergency_chat.dart';

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
  String toString() =>
      '$latitude,$longitude,${timestamp.millisecondsSinceEpoch}';

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

class AppState extends ChangeNotifier
    with
        WidgetsBindingObserver,
        AppStateLocationMixin,
        AppStateConnectionMonitorMixin,
        AppStateStablePeersMixin,
        AppStateOnlineStatusMixin,
        AppStateSOSRescueMixin,
        AppStateMeshPeerMixin,
        AppStateEmergencyChatMixin {
  @override
  Transport transport;
  String selectedProtocol = 'nearby';
  String _deviceName = 'My Device'; // เพิ่มตัวแปรเก็บชื่อเครื่อง
  StreamSubscription? _peersSub;
  StreamSubscription? _msgSub;
  StreamSubscription? _fileSub;
  bool _isAppInForeground = true; // ติดตามสถานะแอพ
  @override
  bool get isAppInForeground => _isAppInForeground;
  String?
  _lastSyncedUserId; // เก็บ userId ล่าสุดที่ซิงก์แล้ว เพื่อป้องกันซิงก์ซ้ำ

  // ติดตามว่าผู้ใช้เปิดห้องแชทไหนอยู่ — ใช้ suppress notification ที่ซ้ำซ้อน
  String? _activePeerChatId; // peerId ของ EmergencyChatScreen ที่เปิดอยู่
  String? _activeFriendChatId; // friendUserId ของ FriendChatScreen ที่เปิดอยู่

  void setActivePeerChat(String? peerId) => _activePeerChatId = peerId;
  void setActiveFriendChat(String? friendUserId) =>
      _activeFriendChatId = friendUserId;

  bool get isInPeerChat => _activePeerChatId != null;
  bool get isInFriendChat => _activeFriendChatId != null;

  /// ใช้ใน FCMService เพื่อตรวจว่าผู้ใช้อยู่ในห้องแชทเพื่อนคนนี้หรือไม่
  @override
  bool isActiveFriendChat(String friendUserId) =>
      _activeFriendChatId == friendUserId;

  // 🔐 E2EE
  @override
  final E2EEService _e2ee = E2EEService();
  final Set<String> _keyMismatchPeers = {};
  bool hasKeyMismatch(String peerId) => _keyMismatchPeers.contains(peerId);

  /// User กดยืนยันรับคีย์ใหม่ของ peer หลังเห็น banner เตือน key mismatch
  Future<void> acceptPeerKeyChange(String peerId) async {
    await _e2ee.acceptNewKey(peerId);
    _keyMismatchPeers.remove(peerId);
    notifyListeners();
  }

  /// User กดปิด banner โดยไม่ยืนยันคีย์ใหม่ — คีย์เดิม (ถ้ามี) ยังใช้อยู่ต่อไป
  void dismissPeerKeyMismatch(String peerId) {
    _e2ee.rejectNewKey(peerId);
    _keyMismatchPeers.remove(peerId);
    notifyListeners();
  }

  // 🎯 Background Service
  final BackgroundService _backgroundService = BackgroundService();
  bool _isBackgroundServiceEnabled = false;
  bool get isBackgroundServiceEnabled => _isBackgroundServiceEnabled;

  // 📡 Auto-Discovery Mode (Passive Listening)
  bool _isPassiveListening = false;
  @override
  bool get isPassiveListening => _isPassiveListening;

  // ❌ scan error message (null = ไม่มีปัญหา)
  String? _scanError;
  String? get scanError => _scanError;

  // 📥 คิวข้อความที่รอส่ง/รอซิงก์ (retry เมื่อเชื่อมต่อกลับมา)
  @override
  final MessageQueueService _messageQueue = MessageQueueService();

  // 📥 คิว friend messages ที่ยังไม่ได้ sync ขึ้น Firebase (ส่งตอนออฟไลน์)
  final List<Map<String, dynamic>> _pendingFriendSync = [];

  AppState({required this.transport}) {
    _e2ee.init(); // generate or load X25519 keypair
    _e2ee.onKeyMismatch.listen((peerId) {
      _keyMismatchPeers.add(peerId);
      notifyListeners();
    });
    _subs();
    _loadLocalMessages();
    // Initialize friend service
    _initFriendService();
    // 📥 เริ่มคิวข้อความ + ตั้ง handler ส่งจริง/ซิงก์จริง
    _initMessageQueue();
    // เริ่มฟัง App Lifecycle
    WidgetsBinding.instance.addObserver(this);
    // โหลด protocol ที่บันทึกไว้ — scan จะถูก trigger จาก HomeScreen หลัง UI พร้อม
    _loadSelectedProtocol();
  }

  /// 🔄 โหลด protocol ที่เลือกไว้จาก SharedPreferences แล้ว switch transport ให้ตรงกัน
  Future<void> _loadSelectedProtocol() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedProtocol = prefs.getString('selected_protocol');

      if (savedProtocol != null && savedProtocol.isNotEmpty) {
        Log.d('📡 Loaded saved protocol: $savedProtocol');
        if (savedProtocol != selectedProtocol) {
          // switch transport object ให้ตรงกับที่ user เลือกไว้
          // (transport ยังไม่ได้ scan ตอนนี้ → wasScanning = false → ไม่ start scan อัตโนมัติ)
          await switchTransport(savedProtocol);
        }
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
      // ใส่ id ข้อความเดิมไปด้วยเสมอ (แม้ retry) เพื่อให้ read receipt (READ:<id>) ยังอ้างอิงถูกต้อง
      await transport.sendMessage(
        _composeChatWireBody(msg.id, msg.text ?? ''),
        to: peer,
      );
      return true;
    });

    _messageQueue.setSyncHandler((msg) async {
      if (!firebaseService.isOnline) return false;
      return _autoSyncMessage(msg);
    });

    // อัปเดตสถานะออนไลน์ของคิวตามสถานะ Firebase (เผื่อ sync ทันทีที่เน็ตกลับมา)
    firebaseService.addListener(() {
      _messageQueue.updateOnlineStatus(firebaseService.isOnline);
      if (firebaseService.isOnline && firebaseService.isSignedIn) {
        _flushPendingFriendSync();
        _flushUnsyncedEmergencyChats();
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
      await prefs.setString(
        'pending_friend_sync',
        jsonEncode(_pendingFriendSync),
      );
    } catch (e) {
      Log.d('❌ บันทึก friend sync queue ไม่สำเร็จ: $e');
    }
  }

  /// เพิ่ม friend message เข้าคิวรอ sync ขึ้น Firebase
  @override
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
    Log.d(
      '📥 [FriendSync] enqueue $type → $toUserId (${_pendingFriendSync.length} รายการในคิว)',
    );
  }

  /// flush emergency chat ที่ยังไม่ sync (sent + delivered) ขึ้น Firebase
  Future<void> _flushUnsyncedEmergencyChats() async {
    if (!firebaseService.isOnline || !firebaseService.isSignedIn) return;
    final userId = friendService.currentUser?.id;
    if (userId == null) return;

    final unsynced = await ChatDB.getUnsyncedMessages(userId);
    if (unsynced.isEmpty) return;

    Log.d(
      '[EmergencySync] 🔄 Flush ${unsynced.length} unsynced emergency messages...',
    );
    for (final msg in unsynced) {
      final ok = await _autoSyncMessage(msg);
      if (!ok) break; // หยุดถ้าเน็ตมีปัญหา รอรอบหน้า
    }
    Log.d('[EmergencySync] ✅ Flush complete');
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
    Log.d(
      '☁️ [FriendSync] flush เสร็จ เหลือ ${_pendingFriendSync.length} รายการ',
    );
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
      _syncBackgroundServiceWithMode(); // 🔋 เปิด background service ให้ discoverable ต่อแม้ย่อแอพ — ไม่ await
      Log.d(
        '✅ [PASSIVE] Passive Listening เริ่มทำงานแล้ว - พร้อมรับสัญญาณ SOS',
      );
    } catch (e) {
      Log.d('❌ [PASSIVE] Error starting passive listening: $e');
      if (e.toString().contains('PERM_PERMANENTLY_DENIED')) {
        Log.d(
          '🚫 [PASSIVE] Permanently denied — หยุด retry, รอ user เปิด settings',
        );
        _scanError =
            'กรุณาเปิด permission ใน Settings ของโทรศัพท์ (Bluetooth + Location)';
        notifyListeners();
        return; // ไม่ retry
      }
      _scanError = e.toString();
      notifyListeners();
      Log.d('🔄 [PASSIVE] จะลองเริ่ม Passive Listening ใหม่ในอีก 3 วินาที...');
      Future.delayed(const Duration(seconds: 3), () {
        if (!_isPassiveListening) {
          _scanError = null;
          _startPassiveListening();
        }
      });
    }
  }


  // Getter และ Setter สำหรับชื่อเครื่อง
  @override
  String get deviceName => _deviceName;

  void setDeviceName(String name) {
    _deviceName = name.isNotEmpty ? name : 'My Device';
    // อัปเดต transport ที่ใช้งานอยู่
    _updateTransportDeviceName();
    notifyListeners();
  }

  /// เปิด background service อัตโนมัติตั้งแต่เริ่ม passive listening (ไม่ต้องรอ SOS/Rescue)
  /// เพื่อให้เครื่องยัง discoverable / เป็นตัวกลาง mesh ได้แม้ย่อแอพ — เป็นความหวังให้ผู้รอความ
  /// ช่วยเหลือเห็นว่ามีคนอยู่ใกล้ ๆ ตลอดเวลา และให้ GPS/online-status ทำงานต่อได้แม้ปิดหน้าจอ
  /// ปิดอัตโนมัติเฉพาะตอนหยุด scan ทั้งหมดจริง ๆ (ไม่ใช่แค่ออกจาก SOS/Rescue)
  @override
  Future<void> _syncBackgroundServiceWithMode() async {
    final shouldRun = _isSOSActive || _isRescueMode || _isPassiveListening;
    if (shouldRun && !_isBackgroundServiceEnabled) {
      Log.d('🔋 เริ่ม scan/SOS/Rescue → เปิด Background Service อัตโนมัติ');
      await startBackgroundService();
    } else if (!shouldRun && _isBackgroundServiceEnabled) {
      Log.d('🔋 หยุด scan ทั้งหมดแล้ว → ปิด Background Service อัตโนมัติ');
      await stopBackgroundService();
    }
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
          transport = WifiDirectTransport(
            deviceName: _deviceName,
          ); // 🔧 ส่ง deviceName
          break;
        case 'radio':
        case 'mesh':
          // 📡 Radio Mesh Transport - Multi-Hop Routing
          final deviceId = await DeviceIdManager.getCurrentId();
          transport = MeshTransport(
            deviceId: deviceId,
            deviceName: _deviceName,
            e2ee: _e2ee,
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

      Log.d(
        '[AppState] 🔄 User login detected: ${friendService.currentUser!.name}',
      );

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

      // ☁️ Sync emergency chat ที่ค้างไว้ขึ้น cloud
      _flushUnsyncedEmergencyChats();

      Log.d('[AppState] ✅ Login sequence completed');
    }
  }

  // ====== Nearby ======
  final List<Peer> _peers = [];
  final List<Message> _messages = [];

  @override
  UnmodifiableListView<Peer> get peers => UnmodifiableListView(_peers);
  UnmodifiableListView<Message> get messages => UnmodifiableListView(_messages);

  /// IDs ของ friend messages ที่ยังรอ sync ขึ้น Firebase (ออฟไลน์)
  Set<String> get pendingFriendSyncIds =>
      _pendingFriendSync.map((e) => e['messageId'] as String).toSet();

  void _subs() {
    // ยกเลิก subscriptions เดิมก่อนสร้างใหม่ (ป้องกัน listener leak เมื่อ switch transport)
    _peersSub?.cancel();
    _msgSub?.cancel();
    _fileSub?.cancel();

    // เริ่ม broadcast GPS location ทุก 8 วินาที
    _startLocationBroadcast();

    // 🔄 เริ่ม Keep Alive ทุก 30 วินาที
    _startKeepAlive();

    // 🔁 ตรวจสอบการเชื่อมต่อและ reconnect ทุก 10 วินาที
    _startConnectionMonitor();

    _peersSub = transport.onPeers.listen((list) {
      final oldPeerIds = _peers.map((p) => p.id).toSet();
      final oldPeersCount = _peers.length;
      _peers
        ..clear()
        ..addAll(list);

      // 🔐 Initiate E2EE handshake with newly connected peers
      for (final peer in list) {
        if (!oldPeerIds.contains(peer.id)) {
          _e2ee.initHandshake(
            peer.id,
            (msg) => transport.sendMessage(msg, to: peer),
          );
        }
      }

      // 🧹 Clear E2EE sessions for disconnected peers
      for (final oldId in oldPeerIds) {
        if (!list.any((p) => p.id == oldId)) {
          _e2ee.clearSession(oldId);
        }
      }

      // อัปเดต Stable Peers List
      _updateStablePeers(list);

      // 📥 แจ้งคิวข้อความว่ามี/ไม่มี peer เชื่อมต่ออยู่ → trigger retry อัตโนมัติ
      _messageQueue.updateP2PConnection(list.isNotEmpty);

      // 🔁 Reset reconnect attempts เมื่อมี peer เชื่อมต่อสำเร็จ
      if (list.isNotEmpty && _reconnectAttempts > 0) {
        _reconnectAttempts = 0;
        Log.d('✅ เชื่อมต่อสำเร็จ - Reset reconnect attempts');
      }

      // 🔄 เมื่อมี peer ใหม่เชื่อมต่อ → ส่งสถานะโหมดปัจจุบันให้ peer รู้
      if (list.length > oldPeersCount) {
        Log.d(
          '🔍 [DEBUG] มี peer ใหม่เชื่อมต่อ (${list.length} peers) → ส่งสถานะโหมดปัจจุบัน',
        );

        Future.delayed(const Duration(milliseconds: 200), () {
          // 👥 ประกาศ Firebase userId ของเราให้ peer ใหม่รู้จัก
          _announceFriendIdToPeers();

          // 📍 ส่ง GPS ทันทีที่ peer เชื่อมต่อ (ไม่ต้องรอขยับ)
          _broadcastCurrentGPS();

          // ส่งสถานะ Rescue Mode (ถ้าเปิดอยู่)
          if (_isRescueMode) {
            _broadcastRescueStatus(true);
          }

          // ส่งสถานะ SOS Mode (ถ้าเปิดอยู่)
          if (_isSOSActive) {
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
    _msgSub = transport.onMessage.listen((m) async {
      // เพิ่ม async
      Log.d('📨 ได้รับข้อความจาก ${m.fromPeerId}: ${m.body}');
      Log.d('🔍 [DEBUG] กำลังประมวลผลข้อความ...');

      // 🔐 E2EE protocol messages (HELLO / ACK) — handle and stop processing
      if (m.body.startsWith('E2E_')) {
        final peer = _peers.firstWhere(
          (p) => p.id == m.fromPeerId,
          orElse: () => Peer(id: m.fromPeerId, name: ''),
        );
        await _e2ee.handleMessage(
          m.fromPeerId,
          m.body,
          (msg) => transport.sendMessage(msg, to: peer),
        );
        return;
      }

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
        Log.d(
          '🔍 [DEBUG] ✅ พบข้อความ RESCUE_STATUS! กำลังเรียก _handleRescueStatus()',
        );
        _handleRescueStatus(m.body, m.fromPeerId);
        // ⚡ อัปเดต lastSeen
        _peerLastSeen[m.fromPeerId] = DateTime.now();
        return;
      }

      // 🚨 ตรวจสอบสถานะ SOS
      if (m.body.startsWith('SOS_STATUS:')) {
        Log.d(
          '🔍 [DEBUG] ✅ พบข้อความ SOS_STATUS! กำลังเรียก _handleSOSStatus()',
        );
        _handleSOSStatus(m.body, m.fromPeerId);
        // ⚡ อัปเดต lastSeen
        _peerLastSeen[m.fromPeerId] = DateTime.now();
        return;
      }

      // ✅ Read receipt จาก peer — เขาเปิดอ่านข้อความที่เราส่งไปแล้ว (format: READ:<id1>,<id2>,...)
      if (m.body.startsWith('READ:')) {
        _handleReadReceipt(m.body, m.fromPeerId);
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
          Log.d(
            '👥 บันทึก mapping userId เพื่อน: $announcedUserId -> ${m.fromPeerId}',
          );
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

        // 🔐 Decrypt if message is encrypted
        final plainBody = await _e2ee.decrypt(m.body, m.fromPeerId);
        // แกะ id ที่ผู้ส่งฝังมา (ถ้ามี) — ใช้ id เดียวกันเพื่อให้ read receipt (READ:<id>) อ้างอิงถูกต้อง
        final parsed = _parseChatWireBody(plainBody);
        final senderMessageId = parsed.id;
        final chatText = parsed.text;

        final msg = ChatMessage(
          id: senderMessageId.isNotEmpty
              ? senderMessageId
              : 'in_${DateTime.now().millisecondsSinceEpoch}_${m.fromPeerId.hashCode.abs()}',
          from: m.fromPeerId,
          receiver: myDeviceId, // เพื่อนส่งมาหาเรา
          type: ChatType.text,
          text: chatText,
          time: DateTime.now(),
          isEmergency: chatText.contains('SOS') || chatText.contains('ฉุกเฉิน'),
          status: MessageStatus.delivered, // ได้รับข้อความแล้ว
          isRead: false, // ข้อความใหม่ที่เข้ามา - ยังไม่ได้อ่าน
        );
        _messages.add(m);
        // 🔥 สร้าง List ใหม่แทนการ add
        _chatMessages = [..._chatMessages, msg];

        // เก็บ local (ถ้า login แล้วก็เก็บด้วย userId, ถ้าไม่ก็เก็บด้วย anonymous)
        ChatDB.insertMessage(msg, currentUserId, receiver: myDeviceId);

        // ☁️ sync ขึ้น Firebase ทันที (ถ้า online + login)
        if (firebaseService.isOnline && friendService.currentUser != null) {
          _autoSyncMessage(msg);
        }

        // 📱 แจ้งเตือนเมื่อรับข้อความใหม่ — ข้ามถ้าผู้ใช้เปิดห้องแชทนั้นอยู่แล้ว
        final senderName = peer.name.isNotEmpty
            ? peer.name
            : 'อุปกรณ์ใกล้เคียง';
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
          Log.d(
            '⏭️ ข้าม notification — ผู้ใช้อยู่ในห้องแชทกับ ${peer.name} อยู่แล้ว',
          );
        }

        Log.d(
          '✅ เพิ่มข้อความใน chatMessages แล้ว (รวม ${_chatMessages.length} ข้อความ)',
        );
        notifyListeners();
      } else {
        Log.d('⏭️ ข้ามข้อความจากตัวเอง');
      }
    });

    // 📁 รับไฟล์ (ใช้ได้กับทุก transport ที่ implement onFileReceived)
    _fileSub = transport.onFileReceived.listen((file) async {
      Log.d('📁 ได้รับไฟล์จาก ${file.fromPeerId}: ${file.filePath}');

      // ตรวจสอบประเภทไฟล์จาก extension
      final lowerPath = file.filePath.toLowerCase();
      final isVideo =
          lowerPath.endsWith('.mp4') ||
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
      final isFromFriend =
          senderFriendUserId.isNotEmpty &&
          friendService.isFriend(senderFriendUserId);

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
        _friendChats[senderFriendUserId] = [
          ..._friendChats[senderFriendUserId]!,
          friendMsg,
        ];
        FriendDB.saveFriendChatMessage(senderFriendUserId, friendMsg.toJson());
        friendService.updateFriendLastMessage(
          senderFriendUserId,
          isVideo ? '🎥 วิดีโอ' : '📷 รูปภาพ',
          file.time,
        );

        final friendName = friendService.friends
            .firstWhere(
              (f) => f.userId == senderFriendUserId,
              orElse: () => Friend(
                id: '',
                name: senderFriendUserId,
                userId: senderFriendUserId,
                addedAt: DateTime.now(),
                lastSeen: DateTime.now(),
              ),
            )
            .name;
        NotificationService().showMessageNotification(
          friendName,
          isVideo ? '🎥 ส่งวิดีโอมาให้' : '📷 ส่งรูปภาพมาให้',
          senderId: senderFriendUserId,
        );
        Log.d(
          '✅ บันทึกไฟล์จาก friend $senderFriendUserId แล้ว (${isVideo ? "วิดีโอ" : "รูปภาพ"})',
        );
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

        // ☁️ sync ขึ้น Firebase ทันที (ถ้า online + login)
        if (firebaseService.isOnline && friendService.currentUser != null) {
          _autoSyncMessage(msg);
        }

        NotificationService().showMessageNotification(
          file.fromPeerId.length > 8
              ? '${file.fromPeerId.substring(0, 8)}...'
              : file.fromPeerId,
          isVideo ? '🎥 ส่งวิดีโอมาให้' : '📷 ส่งรูปภาพมาให้',
          senderId: file.fromPeerId,
          onReply: () {
            final peer = _peers.firstWhere(
              (p) => p.id == file.fromPeerId,
              orElse: () => Peer(
                id: file.fromPeerId,
                name: file.fromPeerId.length > 8
                    ? '${file.fromPeerId.substring(0, 8)}...'
                    : file.fromPeerId,
              ),
            );
            _openChatScreen(peer);
          },
        );
        Log.d(
          '✅ เพิ่มไฟล์ใน chatMessages แล้ว (${isVideo ? "วิดีโอ" : "รูปภาพ"}, รวม ${_chatMessages.length} ข้อความ)',
        );
      }

      notifyListeners();
    });
  }

  @override
  Future<void> startScan() {
    Log.d('🔍 [AppState] startScan() called - Device name: "$_deviceName"');
    // ⚡ Notify listeners ทันทีก่อนเริ่ม scan
    notifyListeners();
    return transport.startDiscovery();
  }

  @override
  Future<void> stopScan() {
    // ⚡ Notify listeners ทันทีก่อนหยุด scan
    notifyListeners();
    return transport.stopDiscovery();
  }

  void send(String body, {Peer? to}) {
    Log.d(
      '📤 ส่งข้อความ: $body ${to != null ? "ถึง ${to.name}" : "(broadcast)"}',
    );

    final currentUserId = friendService.currentUser?.id ?? 'anonymous';
    final deviceName = _deviceName;

    // สร้าง message ID ที่ unique
    final messageId =
        'msg_${DateTime.now().millisecondsSinceEpoch}_$currentUserId';

    // 🌐 ถ้ามีหลาย peers ให้ส่งแบบ RELAY เพื่อให้ข้อความส่งต่อกันได้
    if (_peers.length > 1 &&
        !body.startsWith('RELAY:') &&
        !body.startsWith('SOS_STATUS:') &&
        !body.startsWith('RESCUE_STATUS:')) {
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
      await firebaseService.updateOnlineStatus(
        friendService.currentUser!.id,
        false,
      );

      // ลบข้อความของ user ที่ login ออก (แต่เก็บข้อความ anonymous ไว้)
      await ChatDB.clearUserMessages(friendService.currentUser!.id);
      Log.d(
        '[Logout] 🗑️ ลบข้อความของ user ${friendService.currentUser!.id} จาก local',
      );
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

    // ล้างข้อมูลเพื่อนและแชทเพื่อนทั้งหมด (ทั้ง in-memory list กับ local DB —
    // เดิมเรียก FriendDB.clearAllData() ตรงๆ ซึ่งล้างแค่ local DB ทำให้
    // friendService._friends ในหน่วยความจำยังค้างอยู่ รายชื่อเพื่อนเลยไม่หายหลัง logout)
    await friendService.clearAllData();

    Log.d('[Logout] ✅ Logout เสร็จสิ้น');
    notifyListeners();
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
    if (friendService.currentUser != null &&
        firebaseService.isOnline &&
        firebaseService.isSignedIn) {
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
        Log.d('[AppState] ✅ แอพกลับมาใช้งาน - ตั้งสถานะออนไลน์');
        _isAppInForeground = true;
        _setOnlineStatus(true);
        _startOnlineStatusUpdates();
        // เริ่ม scan ถ้ายังไม่ได้ scan — ทำที่นี่เพราะ Activity พร้อมแน่นอน
        if (!_isPassiveListening) {
          Log.d('[AppState] 🔄 resumed → trigger startScan');
          _startPassiveListening();
        }
        // restart GPS ถ้ายังไม่มี stream — เกิดขึ้นเมื่อ user เพิ่งให้ permission จาก Settings
        if (_locationStreamSubscription == null) {
          Log.d('[AppState] 🔄 resumed → restart GPS stream');
          _startLocationBroadcast();
        }
        break;

      case AppLifecycleState.paused:
        // แอพไป background/ปิดจอ — ⚠️ ตั้งใจไม่ set offline และไม่หยุด heartbeat
        // เพราะผู้ขอความช่วยเหลืออาจปิดจอเพื่อประหยัดแบตโดยไม่ได้เฝ้าหน้าจอ
        // แต่ยังต้องการให้คนอื่นเห็นว่า "ยังออนไลน์ รอความช่วยเหลืออยู่"
        Log.d(
          '[AppState] ⏸️ แอพไป background - คงสถานะออนไลน์ไว้ (heartbeat ทำงานต่อ)',
        );
        _isAppInForeground = false;
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

  /// เปิดหน้าแชทจาก notification (ใช้ global navigator key)
  void _openChatScreen(Peer peer) {
    final context = navigatorKey.currentContext;
    if (context != null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => EmergencyChatScreen(peer: peer)),
      );
    } else {
      Log.d('⚠️ ไม่สามารถเปิดหน้าแชทได้: Navigator context is null');
    }
  }

  @override
  void _openFriendChatScreen(Friend friend) {
    final context = navigatorKey.currentContext;
    if (context != null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => FriendChatScreen(friend: friend)),
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
  @override
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
  @override
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
    _peersSub?.cancel();
    _msgSub?.cancel();
    _fileSub?.cancel();
    stopBackgroundService(); // ปิด Background Service
    WidgetsBinding.instance.removeObserver(this);
    transport.dispose();
    super.dispose();
  }
}

// สร้าง instance แบบง่ายๆ (เลี่ยงการเพิ่มแพ็กเกจ state management)

final appState = AppState(transport: NearbyTransport(deviceName: 'SOS Device'));
