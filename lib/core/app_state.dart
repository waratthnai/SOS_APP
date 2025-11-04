import 'dart:collection';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart'; // เพิ่มสำหรับ MaterialPageRoute
import 'package:geolocator/geolocator.dart';
import 'transport.dart';
import 'chat_models.dart';
import '../cloud/firebase_service.dart';
import 'nearby_transport.dart';
// import 'mock_transport.dart';
import 'wifi_direct_transport.dart';
import 'ble_transport.dart';
import 'chat_db.dart';
import 'notification_service.dart';
import 'friend_service.dart';
import 'friend_models.dart'; // เพิ่มสำหรับ Friend class
import 'friend_db.dart';
import 'fcm_service.dart'; // เพิ่ม FCM Service
import '../ui/emergency_chat_screen.dart'; // เพิ่มสำหรับเปิดหน้าแชท
import '../ui/friend_chat_screen.dart'; // เพิ่มสำหรับเปิดหน้าแชทเพื่อน
import '../main.dart'; // เพิ่มสำหรับ navigatorKey

class AppState extends ChangeNotifier with WidgetsBindingObserver {
  Transport transport;
  String selectedProtocol = 'nearby';
  String _deviceName = 'My Device'; // เพิ่มตัวแปรเก็บชื่อเครื่อง
  Timer? _onlineStatusTimer; // Timer สำหรับอัปเดตสถานะออนไลน์
  bool _isAppInForeground = true; // ติดตามสถานะแอพ
  
  // 🚑 โหมดหน่วยกู้ภัย (Rescue Mode)
  bool _isRescueMode = false;
  bool get isRescueMode => _isRescueMode;

  AppState({required this.transport}) {
    _subs();
    _loadLocalMessages();
    // Initialize friend service
    _initFriendService();
    // เริ่มฟัง App Lifecycle
    WidgetsBinding.instance.addObserver(this);
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
    _isRescueMode = !_isRescueMode;
    
    // Broadcast สถานะหน่วยกู้ภัยไปยังอุปกรณ์ใกล้เคียง
    if (_isRescueMode) {
      await _broadcastRescueStatus(true);
      debugPrint('🚑 เปิดโหมดหน่วยกู้ภัย');
    } else {
      await _broadcastRescueStatus(false);
      debugPrint('🚑 ปิดโหมดหน่วยกู้ภัย');
    }
    
    notifyListeners();
  }
  
  // Broadcast สถานะหน่วยกู้ภัย
  Future<void> _broadcastRescueStatus(bool isRescue) async {
    final status = isRescue ? 'RESCUE_MODE_ON' : 'RESCUE_MODE_OFF';
    final message = 'RESCUE_STATUS:$_deviceName:$status';
    await transport.sendMessage(message);
    debugPrint('📡 Broadcast: $message');
  }

  void _updateTransportDeviceName() {
    if (transport is NearbyTransport) {
      (transport as NearbyTransport).updateDeviceName(_deviceName);
    }
  }

  Future<void> _initFriendService() async {
    await friendService.init();
  }

  Future<void> switchTransport(String protocol) async {
    await transport.dispose();
    switch (protocol) {
      case 'nearby':
        transport = NearbyTransport(deviceName: _deviceName);
        break;
      case 'wifi':
        transport = WifiDirectTransport();
        break;
      case 'ble':
        transport = BleTransport();
        break;
      default:
        transport = NearbyTransport(deviceName: _deviceName);
    }
    selectedProtocol = protocol;
    _subs();
    notifyListeners();
  }

  // ====== Nearby ======
  final List<Peer> _peers = [];
  final List<Message> _messages = [];

  UnmodifiableListView<Peer> get peers => UnmodifiableListView(_peers);
  UnmodifiableListView<Message> get messages => UnmodifiableListView(_messages);

  void _subs() {
    transport.onPeers.listen((list) {
      _peers
        ..clear()
        ..addAll(list);
      notifyListeners();
    });
    transport.onMessage.listen((m) {
      debugPrint('📨 ได้รับข้อความจาก ${m.fromPeerId}: ${m.body}');
      
      // ⚠️ เปลี่ยนจาก: ต้องมี user ล็อกอินก่อน
      // เป็น: ถ้าไม่ได้ login ก็ใช้ anonymous ID
      final currentUserId = friendService.currentUser?.id ?? 'anonymous';
      
      // 🚑 ตรวจสอบสถานะหน่วยกู้ภัย
      if (m.body.startsWith('RESCUE_STATUS:')) {
        _handleRescueStatus(m.body, m.fromPeerId);
        return;
      }
      
      // 🚨 ตรวจสอบสถานะ SOS
      if (m.body.startsWith('SOS_STATUS:')) {
        _handleSOSStatus(m.body, m.fromPeerId);
        return;
      }
      
      // 🌐 ตรวจสอบว่าเป็นข้อความที่ต้อง relay หรือไม่
      if (m.body.startsWith('RELAY:')) {
        _handleRelayMessage(m.body, m.fromPeerId);
        return;
      }
      
      // ตรวจสอบว่าเป็นข้อความจากเพื่อนหรือไม่
      if (m.body.startsWith('FRIEND_MSG:')) {
        debugPrint('🔔 ได้รับข้อความเพื่อน: ${m.body}');
        debugPrint('🔔 currentUser: ${friendService.currentUser?.id}');
        // ข้อความเพื่อน - ต้อง login ถึงจะใช้ได้
        if (friendService.currentUser != null) {
          _handleFriendMessage(m.body, m.fromPeerId);
        } else {
          debugPrint('🔔 ไม่สามารถแสดงการแจ้งเตือนได้เพราะยังไม่ได้ login');
        }
      } else if (m.fromPeerId != 'me') {
        // ⚠️ เพิ่มเงื่อนไข: ไม่รับข้อความจากตัวเอง
        // ข้อความทั่วไป/ฉุกเฉิน - ไม่ต้อง login
        
        // หา peer name จาก peers list
        final peer = _peers.firstWhere(
          (p) => p.id == m.fromPeerId,
          orElse: () => Peer(id: m.fromPeerId, name: 'Device', nearby: false),
        );
        
        final msg = ChatMessage(
          id: 'in_${_chatMessages.length + 1}',
          from: m.fromPeerId,
          type: ChatType.text,
          text: m.body,
          time: DateTime.now(),
          isEmergency: m.body.contains('SOS') || m.body.contains('ฉุกเฉิน'),
          status: MessageStatus.delivered, // ได้รับข้อความแล้ว
        );
        _messages.add(m);
        _chatMessages.add(msg);
        
        // เก็บ local (ถ้า login แล้วก็เก็บด้วย userId, ถ้าไม่ก็เก็บด้วย anonymous)
        ChatDB.insertMessage(msg, currentUserId, receiver: m.fromPeerId);
        
        // แจ้งเตือนเมื่อรับข้อความใหม่ (ใช้ชื่อจริงของ peer)
        NotificationService().showMessageNotification(
          peer.name.isNotEmpty ? peer.name : 'อุปกรณ์ใกล้เคียง',
          m.body,
          senderId: m.fromPeerId, // ส่ง Peer ID เพื่อเปิดแชทได้
          onReply: () {
            // เปิดหน้าแชทเมื่อกดปุ่มตอบกลับ
            _openChatScreen(peer);
          },
        );
        
        debugPrint('✅ เพิ่มข้อความใน chatMessages แล้ว (รวม ${_chatMessages.length} ข้อความ)');
        notifyListeners();
      } else {
        debugPrint('⏭️ ข้ามข้อความจากตัวเอง');
      }
    });
    
    // 📁 รับไฟล์
    if (transport is NearbyTransport) {
      (transport as NearbyTransport).onFileReceived.listen((file) {
        debugPrint('📁 ได้รับไฟล์จาก ${file.fromPeerId}: ${file.filePath}');
        
        final currentUserId = friendService.currentUser?.id ?? 'anonymous';
        
        // สร้าง ChatMessage สำหรับรูปภาพที่ได้รับ
        final msg = ChatMessage(
          id: 'file_${_chatMessages.length + 1}',
          from: file.fromPeerId,
          type: ChatType.image, // สมมติว่าเป็นรูปภาพ TODO: ตรวจสอบ extension
          filePath: file.filePath,
          time: file.time,
          isEmergency: false,
        );
        
        _chatMessages.add(msg);
        
        // เก็บ local
        ChatDB.insertMessage(msg, currentUserId, receiver: file.fromPeerId);
        
        // แจ้งเตือน
        NotificationService().showMessageNotification(
          file.fromPeerId.length > 8 ? '${file.fromPeerId.substring(0, 8)}...' : file.fromPeerId,
          '📷 ส่งรูปภาพมาให้',
          senderId: file.fromPeerId, // ส่ง Peer ID เพื่อเปิดแชทได้
          onReply: () {
            // หา peer จาก ID
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
        
        debugPrint('✅ เพิ่มไฟล์ใน chatMessages แล้ว (รวม ${_chatMessages.length} ข้อความ)');
        notifyListeners();
      });
    }
  }

  Future<void> startScan() => transport.startDiscovery();
  Future<void> stopScan() => transport.stopDiscovery();

  Future<void> send(String body, {Peer? to}) async {
    debugPrint('📤 ส่งข้อความ: $body ${to != null ? "ถึง ${to.name}" : "(broadcast)"}');
    
    final currentUserId = friendService.currentUser?.id ?? 'anonymous';
    final deviceName = _deviceName;
    
    // สร้าง message ID ที่ unique
    final messageId = 'msg_${DateTime.now().millisecondsSinceEpoch}_$currentUserId';
    
    // 🌐 ถ้ามีหลาย peers ให้ส่งแบบ RELAY เพื่อให้ข้อความส่งต่อกันได้
    if (_peers.length > 1 && !body.startsWith('RELAY:') && !body.startsWith('SOS_STATUS:') && !body.startsWith('RESCUE_STATUS:')) {
      // TTL = 5 (ส่งต่อได้ไม่เกิน 5 hops)
      final relayMsg = 'RELAY:$messageId:5:$currentUserId:$deviceName:$body';
      await transport.sendMessage(relayMsg, to: to);
      debugPrint('🌐 ส่งข้อความแบบ Mesh (TTL=5)');
    } else {
      // ส่งข้อความปกติ
      await transport.sendMessage(body, to: to);
      debugPrint('📤 ส่งข้อความปกติ');
    }
    
    // ⚠️ ไม่เพิ่มข้อความที่นี่ - ให้ transport._msgCtrl.add() จัดการ
    // เพราะ NearbyTransport จะ emit message ที่ส่งออกมาแล้ว
    // หาก emit ที่นี่ด้วยจะทำให้ซ้ำ
    
    debugPrint('✅ ส่งข้อความเรียบร้อย');
    notifyListeners();
  }

  // ====== Chat ======
  final List<ChatMessage> _chatMessages = [];
  UnmodifiableListView<ChatMessage> get chatMessages => UnmodifiableListView(_chatMessages);

  /// ดึงข้อความในห้องแชทระหว่าง user กับ peer
  Future<List<ChatMessage>> getChatConversation(String peerId) async {
    if (friendService.currentUser == null) return [];
    return await ChatDB.getConversation(friendService.currentUser!.id, peerId);
  }

  void sendChatText(String text, {String? receiverId}) {
  // ถ้าไม่ได้ login ใช้ anonymous ID
  final currentUserId = friendService.currentUser?.id ?? 'anonymous';
  final deviceName = _deviceName;
  
  // สร้าง message ID ที่ unique
  final messageId = 'msg_${DateTime.now().millisecondsSinceEpoch}_$currentUserId';
  
  final msg = ChatMessage(
    id: messageId,
    from: 'me',
    type: ChatType.text,
    text: text,
    time: DateTime.now(),
    isEmergency: text.contains('SOS') || text.contains('ฉุกเฉิน'),
    status: MessageStatus.pending, // เริ่มต้นเป็น pending
  );
  _chatMessages.add(msg);
  
  // เก็บ local
  ChatDB.insertMessage(msg, currentUserId, receiver: receiverId);
  
  // 🌐 ส่งข้อความแบบ Mesh ถ้ามีหลาย peers
  if (_peers.length > 1) {
    final relayMsg = 'RELAY:$messageId:5:$currentUserId:$deviceName:$text';
    transport.sendMessage(relayMsg);
    debugPrint('🌐 ส่งข้อความแบบ Mesh (TTL=5)');
  } else {
    // ส่งข้อความผ่าน Nearby Connections
    final targetPeer = receiverId != null 
        ? _peers.firstWhere((p) => p.id == receiverId, orElse: () => _peers.first)
        : null;
    transport.sendMessage(text, to: targetPeer);
    debugPrint('📤 ส่งข้อความไปยัง: ${targetPeer?.name ?? "broadcast"}');
  }
  
  // อัปเดตสถานะเป็น sent
  final index = _chatMessages.indexWhere((m) => m.id == messageId);
  if (index != -1) {
    _chatMessages[index] = msg.copyWith(status: MessageStatus.sent);
  }
  
  // บันทึกไปยัง Firebase (ถ้า login แล้ว)
  if (friendService.currentUser != null) {
    firebaseService.saveChatMessage(
      type: 'text',
      text: text,
      time: msg.time,
    ).then((_) {
      // อัปเดตสถานะเป็น synced หลัง Firebase save สำเร็จ
      final idx = _chatMessages.indexWhere((m) => m.id == messageId);
      if (idx != -1) {
        _chatMessages[idx] = _chatMessages[idx].copyWith(status: MessageStatus.synced);
        notifyListeners();
      }
    });
  }
  
  debugPrint('✅ ส่งข้อความ: $text (รวม ${_chatMessages.length} ข้อความ)');
  notifyListeners();
}

void addChatImage(String path) {
  if (friendService.currentUser == null) return; // ต้อง login ก่อน
  
  final msg = ChatMessage(
    id: 'me_${_chatMessages.length + 1}',
    from: 'me',
    type: ChatType.image,
    filePath: path,
    time: DateTime.now(),
  );
  _chatMessages.add(msg);
  ChatDB.insertMessage(msg, friendService.currentUser!.id); // เก็บ local พร้อม userId
  firebaseService.saveChatMessage(
    type: 'image',
    text: '[image]',
    time: msg.time,
  );
  notifyListeners();
}

void addChatVideo(String path) {
  if (friendService.currentUser == null) return; // ต้อง login ก่อน
  
  final msg = ChatMessage(
    id: 'me_${_chatMessages.length + 1}',
    from: 'me',
    type: ChatType.video,
    filePath: path,
    time: DateTime.now(),
  );
  _chatMessages.add(msg);
  ChatDB.insertMessage(msg, friendService.currentUser!.id); // เก็บ local พร้อม userId
  firebaseService.saveChatMessage(
    type: 'video',
    text: '[video]',
    time: msg.time,
  );
  notifyListeners();
}

  Future<void> _loadLocalMessages() async {
    if (friendService.currentUser == null) return; // ต้อง login ก่อน
    
    final local = await ChatDB.getMessages(friendService.currentUser!.id);
    _chatMessages
      ..clear()
      ..addAll(local);
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
  
  UnmodifiableMapView<String, List<FriendChatMessage>> get friendChats => 
      UnmodifiableMapView(_friendChats);

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
    _friendChats[friendUserId]!.add(message);

    // บันทึกลงฐานข้อมูลท้องถิ่น
    await FriendDB.saveFriendChatMessage(friendUserId, message.toJson());

    // อัพเดทข้อความสุดท้ายของเพื่อน
    await friendService.updateFriendLastMessage(friendUserId, text, DateTime.now());

    // ส่งผ่าน transport หากออฟไลน์ (Nearby/BLE/WiFi Direct)
    try {
      await transport.sendMessage('FRIEND_MSG:${friendService.currentUser!.id}:$text', to: null);
      debugPrint('📡 [P2P] ส่งข้อความผ่าน Bluetooth/WiFi Direct');
    } catch (e) {
      debugPrint('[AppState] Error sending via transport: $e');
    }

    // ส่งผ่าน FCM หากมีอินเทอร์เน็ต (Push Notification)
    try {
      await FCMService().sendNotificationToFriend(
        friendUserId: friendUserId,
        message: text,
      );
      debugPrint('🔔 [FCM] ส่ง Push Notification แล้ว');
    } catch (e) {
      debugPrint('[AppState] Error sending FCM: $e');
    }

    // บันทึกบน Firebase หากออนไลน์
    if (firebaseService.isOnline && firebaseService.isSignedIn) {
      await firebaseService.saveFriendChatMessage(
        fromUserId: friendService.currentUser!.id,
        toUserId: friendUserId,
        type: 'text',
        text: text,
        time: DateTime.now(),
        messageId: message.id, // ส่ง ID ไปด้วยเพื่อใช้ ID เดียวกัน
      );
    }

    notifyListeners();
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
    _friendChats[friendUserId]!.add(message);

    // บันทึกลงฐานข้อมูลท้องถิ่น
    await FriendDB.saveFriendChatMessage(friendUserId, message.toJson());

    // อัพเดทข้อความสุดท้าย
    await friendService.updateFriendLastMessage(friendUserId, '📷 รูปภาพ', DateTime.now());

    // ส่งผ่าน transport หากออนไลน์ (P2P)
    // TODO: ส่งไฟล์จริงผ่าน transport.sendFile() ถ้า friend อยู่ใน nearby peers
    try {
      await transport.sendMessage(
        'FRIEND_MSG:${friendService.currentUser!.id}:📷 ส่งรูปภาพ', 
        to: null,
      );
    } catch (e) {
      debugPrint('[AppState] Error sending image via transport: $e');
    }

    // บันทึก metadata บน Firebase (ไม่อัพโหลดรูปจริง - เพราะ Free Plan ไม่มี Storage)
    if (firebaseService.isOnline && firebaseService.isSignedIn) {
      await firebaseService.saveFriendChatMessage(
        fromUserId: friendService.currentUser!.id,
        toUserId: friendUserId,
        type: 'image',
        text: '[Image - P2P/Local only]', // metadata อย่างเดียว
        time: DateTime.now(),
        messageId: message.id,
      );
    }

    notifyListeners();
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
    _friendChats[friendUserId]!.add(message);

    // บันทึกลงฐานข้อมูลท้องถิ่น
    await FriendDB.saveFriendChatMessage(friendUserId, message.toJson());

    // อัพเดทข้อความสุดท้าย
    await friendService.updateFriendLastMessage(friendUserId, '🎥 วิดีโอ', DateTime.now());

    // ส่งผ่าน transport หากออนไลน์ (P2P)
    // TODO: ส่งไฟล์จริงผ่าน transport.sendFile() ถ้า friend อยู่ใน nearby peers
    try {
      await transport.sendMessage(
        'FRIEND_MSG:${friendService.currentUser!.id}:🎥 ส่งวิดีโอ', 
        to: null,
      );
    } catch (e) {
      debugPrint('[AppState] Error sending video via transport: $e');
    }

    // บันทึก metadata บน Firebase (ไม่อัพโหลดวิดีโอจริง - เพราะ Free Plan ไม่มี Storage)
    if (firebaseService.isOnline && firebaseService.isSignedIn) {
      await firebaseService.saveFriendChatMessage(
        fromUserId: friendService.currentUser!.id,
        toUserId: friendUserId,
        type: 'video',
        text: '[Video - P2P/Local only]', // metadata อย่างเดียว
        time: DateTime.now(),
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
      if (!_friendChats.containsKey(friendUserId)) {
        _friendChats[friendUserId] = [];
      }
      _friendChats[friendUserId]!.add(message);

      // บันทึกลงฐานข้อมูลท้องถิ่น
      await FriendDB.saveFriendChatMessage(friendUserId, message.toJson());

      // อัพเดทข้อความสุดท้าย
      await friendService.updateFriendLastMessage(friendUserId, '📍 ตำแหน่ง', DateTime.now());

      // ส่งผ่าน transport
      try {
        await transport.sendMessage(
          'FRIEND_MSG:${friendService.currentUser!.id}:$locationText',
          to: null,
        );
      } catch (e) {
        debugPrint('[AppState] Error sending location via transport: $e');
      }

      // บันทึก metadata บน Firebase
      if (firebaseService.isOnline && firebaseService.isSignedIn) {
        await firebaseService.saveFriendChatMessage(
          fromUserId: friendService.currentUser!.id,
          toUserId: friendUserId,
          type: 'text',
          text: locationText,
          time: DateTime.now(),
          messageId: message.id,
        );
      }

      notifyListeners();
    } catch (e) {
      debugPrint('[AppState] Error getting location: $e');
      throw e; // ส่ง error กลับไปให้ UI จัดการ
    }
  }

  /// โหลดข้อความแชทกับเพื่อน
  Future<void> loadFriendChatMessages(String friendUserId, {bool forceRefresh = false}) async {
    if (_friendChats.containsKey(friendUserId) && !forceRefresh) return; // โหลดแล้ว

    // โหลดจากฐานข้อมูลท้องถิ่น
    final localMessages = await FriendDB.getFriendChatMessages(friendUserId);
    final messages = localMessages.map((json) => FriendChatMessage.fromJson(json)).toList();
    
    _friendChats[friendUserId] = messages;

    // โหลดจาก Firebase หากออนไลน์
    if (firebaseService.isOnline && firebaseService.isSignedIn && friendService.currentUser != null) {
      try {
        debugPrint('[AppState] 🔄 กำลังดึงข้อความจาก Firebase...');
        final firebaseMessages = await firebaseService.getFriendChatMessages(
          friendService.currentUser!.id, 
          friendUserId
        );
        
        debugPrint('[AppState] 📩 ได้รับ ${firebaseMessages.length} ข้อความจาก Firebase');
        
        for (final msgData in firebaseMessages) {
          final message = FriendChatMessage.fromJson(msgData);
          
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
            debugPrint('[AppState] ➕ เพิ่มข้อความใหม่: ${message.text}');
          } else {
            debugPrint('[AppState] ⏭️ ข้าม: ข้อความซ้ำ "${message.text}"');
          }
        }
        
        // เรียงตามเวลา
        messages.sort((a, b) => a.time.compareTo(b.time));
        _friendChats[friendUserId] = messages;
        debugPrint('[AppState] ✅ รวมข้อความทั้งหมด: ${messages.length} ข้อความ');
      } catch (e) {
        debugPrint('[AppState] Error loading Firebase messages: $e');
      }
    }

    notifyListeners();
  }

  /// รับข้อความจากเพื่อน (เมื่อได้รับผ่าน transport)
  void _handleFriendMessage(String message, String fromPeerId) {
    debugPrint('🔔 _handleFriendMessage ถูกเรียก: $message จาก $fromPeerId');
    // Format: "FRIEND_MSG:fromUserId:message"
    final parts = message.split(':');
    if (parts.length >= 3 && parts[0] == 'FRIEND_MSG') {
      final fromUserId = parts[1];
      final messageText = parts.sublist(2).join(':');
      debugPrint('🔔 fromUserId: $fromUserId, messageText: $messageText');
      
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
      _friendChats[fromUserId]!.add(friendMessage);

      // บันทึกลงฐานข้อมูลท้องถิ่น
      FriendDB.saveFriendChatMessage(fromUserId, friendMessage.toJson());

      // อัพเดทข้อความสุดท้ายของเพื่อนและเพิ่มจำนวนข้อความที่ยังไม่อ่าน
      friendService.updateFriendLastMessage(fromUserId, messageText, DateTime.now(), incrementUnread: true);

      // แจ้งเตือนข้อความจากเพื่อน
      final friend = friendService.friends.where((f) => f.id == fromUserId).firstOrNull;
      final senderName = friend?.name ?? fromUserId;
      debugPrint('🔔 กำลังแจ้งเตือน: friend=$friend, senderName=$senderName');
      debugPrint('🔔 จำนวนเพื่อนทั้งหมด: ${friendService.friends.length}');
      NotificationService().showMessageNotification(
        senderName, 
        messageText,
        senderId: fromUserId,
        onReply: friend != null ? () => _openFriendChatScreen(friend) : null,
      );
      debugPrint('🔔 เรียก showMessageNotification แล้ว');

      notifyListeners();
    }
  }
  
  /// 🚑 รับสถานะหน่วยกู้ภัยจากเครื่องอื่น
  void _handleRescueStatus(String message, String fromPeerId) {
    // Format: "RESCUE_STATUS:deviceName:status"
    final parts = message.split(':');
    if (parts.length >= 3 && parts[0] == 'RESCUE_STATUS') {
      final deviceName = parts[1];
      final status = parts[2];
      final isRescue = status == 'RESCUE_MODE_ON';
      
      debugPrint('🚑 ${isRescue ? "เปิด" : "ปิด"}โหมดหน่วยกู้ภัย: $deviceName ($fromPeerId)');
      
      // อัพเดท peer metadata (จะใช้ใน UI แสดง badge)
      // เก็บสถานะใน map เพื่อให้ UI access ได้
      _rescuePeers[fromPeerId] = isRescue;
      
      // แจ้งเตือน
      if (isRescue) {
        NotificationService().showInAppNotification(
          title: '🚑 หน่วยกู้ภัยใกล้เคียง',
          message: '$deviceName พร้อมให้ความช่วยเหลือ',
          type: NotificationType.info,
        );
      }
      
      notifyListeners();
    }
  }
  
  /// 🚨 รับสถานะ SOS จากเครื่องอื่น
  void _handleSOSStatus(String message, String fromPeerId) {
    // Format: "SOS_STATUS:deviceName:status:lat:lng"
    final parts = message.split(':');
    if (parts.length >= 3 && parts[0] == 'SOS_STATUS') {
      final deviceName = parts[1];
      final status = parts[2];
      final isSOS = status == 'SOS_ACTIVE';
      
      // ดึงพิกัด GPS ถ้ามี
      String? latitude;
      String? longitude;
      if (parts.length >= 5) {
        latitude = parts[3];
        longitude = parts[4];
      }
      
      debugPrint('🚨 ${isSOS ? "เปิด" : "ปิด"} SOS: $deviceName ($fromPeerId)');
      if (latitude != null && longitude != null) {
        debugPrint('📍 Location: $latitude, $longitude');
      }
      
      // อัพเดท peer metadata
      _sosPeers[fromPeerId] = isSOS;
      
      // แจ้งเตือนแบบด่วน
      if (isSOS) {
        String locationInfo = '';
        if (latitude != null && longitude != null) {
          locationInfo = '\n📍 Location: https://www.google.com/maps?q=$latitude,$longitude';
        }
        
        NotificationService().showInAppNotification(
          title: '🚨 SOS! ขอความช่วยเหลือ',
          message: '$deviceName ต้องการความช่วยเหลือเร่งด่วน!$locationInfo',
          type: NotificationType.emergency,
        );
      }
      
      notifyListeners();
    }
  }
  
  // เก็บสถานะหน่วยกู้ภัยของแต่ละ peer
  final Map<String, bool> _rescuePeers = {};
  
  // เก็บสถานะ SOS ของแต่ละ peer
  final Map<String, bool> _sosPeers = {};
  
  // 🌐 Mesh Network: เก็บ ID ข้อความที่เคยส่งต่อแล้ว (ป้องกันการส่งซ้ำ)
  final Set<String> _forwardedMessages = {};
  final Map<String, int> _messageTTL = {}; // Time To Live สำหรับแต่ละข้อความ
  
  // Getters สำหรับ UI
  bool isRescuePeer(String peerId) => _rescuePeers[peerId] ?? false;
  bool isSOSPeer(String peerId) => _sosPeers[peerId] ?? false;
  Map<String, bool> get rescuePeers => Map.unmodifiable(_rescuePeers);
  
  // เช็คว่า peer เป็นหน่วยกู้ภัยหรือไม่
  bool isPeerRescue(String peerId) {
    return _rescuePeers[peerId] ?? false;
  }

  /// รีเซ็ตจำนวนข้อความที่ยังไม่อ่านของเพื่อน
  Future<void> markFriendMessagesAsRead(String friendUserId) async {
    await friendService.markFriendMessagesAsRead(friendUserId);
    
    // อัพเดทสถานะ isRead ของข้อความ
    if (_friendChats.containsKey(friendUserId)) {
      for (int i = 0; i < _friendChats[friendUserId]!.length; i++) {
        final message = _friendChats[friendUserId]![i];
        if (!message.isRead && message.fromUserId != friendService.currentUser?.id) {
          _friendChats[friendUserId]![i] = message.copyWith(isRead: true);
        }
      }
    }
    
    notifyListeners();
  }

  /// ฟังก์ชันสำหรับ Logout - ลบข้อมูลแชททั้งหมด
  Future<void> logout() async {
    // ยกเลิก timer อัปเดตสถานะออนไลน์
    _stopOnlineStatusUpdates();
    
    // ตั้งสถานะออฟไลน์ก่อน logout
    if (friendService.currentUser != null) {
      await firebaseService.updateOnlineStatus(friendService.currentUser!.id, false);
      
      // ลบข้อความทั่วไปของ user นี้จาก database
      await ChatDB.clearUserMessages(friendService.currentUser!.id);
    }
    
    // ล้างข้อมูลใน memory
    _chatMessages.clear();
    _friendChats.clear();
    _messages.clear();
    _peers.clear();
    
    // ล้างข้อมูลเพื่อนและแชทเพื่อนทั้งหมด
    await FriendDB.clearAllData();
    
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
      debugPrint('🔁 ข้อความ $messageId เคยส่งต่อแล้ว ไม่ส่งซ้ำ');
      return;
    }

    // ตรวจสอบ TTL (หมดอายุหรือไม่)
    if (ttl <= 0) {
      debugPrint('⏰ ข้อความ $messageId หมดอายุ (TTL=0)');
      return;
    }

    // บันทึกว่าเคยส่งต่อแล้ว
    _forwardedMessages.add(messageId);
    _messageTTL[messageId] = ttl;

    debugPrint('🌐 รับข้อความ Relay จาก $fromPeerId: $content (TTL=$ttl)');

    // แสดงข้อความในแชท (ถ้าเป็นแชทกับผู้ส่งเดิม)
    final msg = ChatMessage(
      id: messageId,
      from: originalSender,
      type: ChatType.text,
      text: content,
      time: DateTime.now(),
      status: MessageStatus.delivered,
    );
    
    _chatMessages.add(msg);
    
    // เก็บลง DB
    final currentUserId = friendService.currentUser?.id ?? 'anonymous';
    await ChatDB.insertMessage(msg, currentUserId, receiver: originalSender);
    
    notifyListeners();

    // Relay ต่อไปยัง peers อื่นๆ (ยกเว้นคนที่ส่งมา)
    final newTTL = ttl - 1;
    if (newTTL > 0 && _peers.isNotEmpty) {
      final relayMsg = 'RELAY:$messageId:$newTTL:$originalSender:$senderName:$content';
      
      for (final peer in _peers) {
        if (peer.id != fromPeerId && peer.id != originalSender) {
          try {
            await transport.sendMessage(relayMsg);
            debugPrint('📡 ส่งต่อไปยัง ${peer.name} (TTL=$newTTL)');
          } catch (e) {
            debugPrint('❌ ส่งต่อไปยัง ${peer.name} ล้มเหลว: $e');
          }
        }
      }
    }

    // แสดง notification
    NotificationService().showMessageNotification(
      '📡 Mesh จาก $senderName',
      content,
    );
  }

  /// เริ่มอัปเดตสถานะออนไลน์แบบอัตโนมัติ (ทุก 5 วินาที)
  void _startOnlineStatusUpdates() {
    debugPrint('[AppState] 🔧 เริ่มต้น _startOnlineStatusUpdates...');
    _stopOnlineStatusUpdates(); // ยกเลิก timer เก่าก่อน (ถ้ามี)
    
    if (friendService.currentUser == null) {
      debugPrint('[AppState] ⚠️ ไม่มี currentUser - ข้าม timer');
      return;
    }
    
    if (!_isAppInForeground) {
      debugPrint('[AppState] ⚠️ แอพไม่ได้อยู่ foreground - ข้าม timer');
      return;
    }
    
    debugPrint('[AppState] ✅ สร้าง Timer สำหรับ ${friendService.currentUser!.name} (${friendService.currentUser!.id})');
    _onlineStatusTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      // เช็คว่าแอพยังอยู่ foreground หรือไม่
      if (!_isAppInForeground) {
        debugPrint('[AppState] ⚠️ [Heartbeat] แอพไม่ได้อยู่ foreground - ข้ามการอัปเดต');
        return;
      }
      
      if (friendService.currentUser != null && firebaseService.isOnline && firebaseService.isSignedIn) {
        debugPrint('[AppState] 🔄 [Heartbeat] อัปเดตสถานะออนไลน์สำหรับ: ${friendService.currentUser!.name}');
        await firebaseService.updateOnlineStatus(friendService.currentUser!.id, true);
      } else {
        debugPrint('[AppState] ⚠️ [Heartbeat] ข้ามการอัปเดต - currentUser=${friendService.currentUser?.name}, online=${firebaseService.isOnline}, signedIn=${firebaseService.isSignedIn}');
      }
    });
    debugPrint('[AppState] ✅ Timer สร้างเสร็จแล้ว - จะอัปเดตทุก 5 วินาที');
  }

  /// หยุดอัปเดตสถานะออนไลน์
  void _stopOnlineStatusUpdates() {
    if (_onlineStatusTimer != null) {
      debugPrint('[AppState] 🛑 หยุด Timer heartbeat');
    }
    _onlineStatusTimer?.cancel();
    _onlineStatusTimer = null;
  }

  /// ฟังก์ชันสำหรับ Login - โหลดข้อมูลแชทของ user
  Future<void> onUserLogin() async {
    debugPrint('[AppState] 🔑 เริ่มต้น onUserLogin...');
    
    // โหลดข้อความทั่วไป
    await _loadLocalMessages();
    
    // ดึงโปรไฟล์จาก Firebase และ sync ข้อมูล (จะตั้งสถานะออนไลน์ภายในแล้ว)
    debugPrint('[AppState] 🔄 กำลัง init friendService...');
    await friendService.init();
    debugPrint('[AppState] ✅ init friendService เสร็จสิ้น');
    
    // อัปเดตชื่อเครื่องให้เป็นชื่อ User
    if (friendService.currentUser != null) {
      final userName = friendService.currentUser!.name;
      debugPrint('[AppState] 📱 อัปเดตชื่อเครื่องเป็น: $userName');
      setDeviceName(userName);
      
      // เริ่ม timer อัปเดตสถานะออนไลน์
      _startOnlineStatusUpdates();
      debugPrint('[AppState] ✅ เริ่ม auto-update สถานะออนไลน์');
    }
    
    notifyListeners();
  }

  /// ฟังการเปลี่ยนแปลงสถานะของแอพ (foreground/background)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    debugPrint('[AppState] 🔄 App Lifecycle เปลี่ยนเป็น: $state');
    
    switch (state) {
      case AppLifecycleState.resumed:
        // แอพกลับมา foreground (กำลังใช้งาน)
        debugPrint('[AppState] ✅ แอพกลับมาใช้งาน - ตั้งสถานะออนไลน์');
        _isAppInForeground = true;
        _setOnlineStatus(true);
        _startOnlineStatusUpdates(); // เริ่ม heartbeat ใหม่
        break;
        
      case AppLifecycleState.paused:
        // แอพไป background (ออกไปใช้แอพอื่น)
        debugPrint('[AppState] ⏸️ แอพไป background - ตั้งสถานะออฟไลน์');
        _isAppInForeground = false;
        _stopOnlineStatusUpdates(); // หยุด heartbeat
        _setOnlineStatus(false);
        break;
        
      case AppLifecycleState.inactive:
        // แอพกำลังจะเปลี่ยนสถานะ (เช่น มีโทรศัพท์เข้า)
        debugPrint('[AppState] ⏸️ แอพ inactive');
        break;
        
      case AppLifecycleState.detached:
        // แอพกำลังจะปิด
        debugPrint('[AppState] 🛑 แอพกำลังปิด - ตั้งสถานะออฟไลน์');
        _isAppInForeground = false;
        _setOnlineStatus(false);
        break;
        
      case AppLifecycleState.hidden:
        // แอพถูกซ่อน
        debugPrint('[AppState] 🔒 แอพถูกซ่อน');
        break;
    }
  }

  /// ตั้งสถานะออนไลน์/ออฟไลน์
  void _setOnlineStatus(bool isOnline) async {
    if (friendService.currentUser != null && firebaseService.isSignedIn) {
      debugPrint('[AppState] 🔄 ตั้งสถานะ: ${isOnline ? "ออนไลน์" : "ออฟไลน์"} สำหรับ ${friendService.currentUser!.name}');
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
      debugPrint('⚠️ ไม่สามารถเปิดหน้าแชทได้: Navigator context is null');
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
      debugPrint('⚠️ ไม่สามารถเปิดหน้าแชทเพื่อนได้: Navigator context is null');
    }
  }

  /// Public method สำหรับให้ FCM Service เรียกใช้
  void openFriendChatScreenPublic(Friend friend) {
    _openFriendChatScreen(friend);
  }

  @override
  void dispose() {
    _stopOnlineStatusUpdates();
    WidgetsBinding.instance.removeObserver(this);
    transport.dispose();
    super.dispose();
  }
}

// สร้าง instance แบบง่ายๆ (เลี่ยงการเพิ่มแพ็กเกจ state management)

final appState = AppState(
  transport: NearbyTransport(deviceName: 'SOS Device'),
);