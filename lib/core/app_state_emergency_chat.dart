part of 'app_state.dart';

/// แชทฉุกเฉิน P2P (emergency chat) และแชทเพื่อนออนไลน์ (friend cloud chat) —
/// ก้อนใหญ่ที่สุดที่แยกออกจาก [AppState] หลัก (Phase 1 ของ CLEANUP_PLAN.md) เพราะทั้งสองระบบ
/// ใช้ helper ร่วมกัน (`_peerForFriend`, `_generateChatId`, message queue, E2EE) จึงต้องอยู่
/// mixin เดียวกันแทนที่จะแยกย่อยเหมือนกลุ่มก่อนหน้า — ดูรายละเอียดเหตุผลใน CLEANUP_PLAN.md
///
/// หมายเหตุ: `_subs()`, `onUserLogin()`, `logout()` ยังอยู่ใน AppState หลัก เพราะเป็นจุด
/// orchestration ข้าม concern หลายตัว แต่เรียกใช้ field/method ของ mixin นี้ได้ตามปกติ
/// (เป็น library เดียวกันผ่าน part-of)
mixin AppStateEmergencyChatMixin on ChangeNotifier, AppStateMeshPeerMixin {
  // ต้องมีสมาชิกเหล่านี้จาก AppState เอง (ประกาศเป็น concrete member อยู่แล้ว)
  @override
  List<Peer> get peers;
  bool isActiveFriendChat(String friendUserId);
  E2EEService get _e2ee;
  MessageQueueService get _messageQueue;
  void _openFriendChatScreen(Friend friend);
  Future<void> _enqueuePendingFriendSync({
    required String fromUserId,
    required String toUserId,
    required String type,
    String? text,
    required DateTime time,
    required String messageId,
  });

  // 👥 mapping: Firebase userId ของเพื่อน -> peerId ที่กำลังเชื่อมต่ออยู่ตอนนี้ (ถ้ามี)
  // ใช้เพื่อส่งข้อความเพื่อนแบบ unicast เจาะจงเครื่อง ไม่ broadcast ให้คนแปลกหน้าใกล้เคียงเห็นด้วย
  final Map<String, String> _friendUserIdToPeerId = {};

  // ====== Chat ======
  List<ChatMessage> _chatMessages =
      []; // 🔥 เปลี่ยนจาก final เป็น var เพื่อให้สามารถสร้าง List ใหม่ได้
  UnmodifiableListView<ChatMessage> get chatMessages =>
      UnmodifiableListView(_chatMessages);

  /// ดึงข้อความในห้องแชทระหว่าง user กับ peer
  Future<List<ChatMessage>> getChatConversation(String peerId) async {
    if (friendService.currentUser == null) return [];
    return await ChatDB.getConversation(friendService.currentUser!.id, peerId);
  }

  /// ห่อ chat message ด้วย id ก่อนส่ง (ก่อนเข้ารหัส) format: `CHATMSG:<id>:<text>`
  /// ทำให้ผู้รับรู้ id เดียวกับที่ผู้ส่งใช้ ใช้อ้างอิงตอนส่ง read receipt (`READ:<id>`) กลับ
  String _composeChatWireBody(String messageId, String text) {
    return 'CHATMSG:$messageId:$text';
  }

  /// แกะ `CHATMSG:<id>:<text>` — คืน (id, text) ถ้าไม่ใช่ format นี้ id จะเป็น '' และ text คือ body เดิม
  ({String id, String text}) _parseChatWireBody(String body) {
    if (!body.startsWith('CHATMSG:')) return (id: '', text: body);
    final rest = body.substring('CHATMSG:'.length);
    final sep = rest.indexOf(':');
    if (sep == -1) return (id: '', text: rest);
    return (id: rest.substring(0, sep), text: rest.substring(sep + 1));
  }

  Future<void> sendChatText(String text, {String? receiverId}) async {
    // ถ้าไม่ได้ login ใช้ anonymous ID
    final currentUserId = friendService.currentUser?.id ?? 'anonymous';

    // 🆔 ใช้ Device ID ถาวรแทน 'me' เพื่อให้สามารถหาแชทเดิมเจอ
    final myDeviceId = await DeviceIdManager.getCurrentId();

    // สร้าง message ID ที่ unique
    final messageId =
        'msg_${DateTime.now().millisecondsSinceEpoch}_$currentUserId';

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
    if (actualReceiverId == null && peers.isNotEmpty) {
      actualReceiverId = peers.first.id;
    }

    // 💾 บันทึกชื่อ peer เพื่อให้ห้องแชทคงชื่อไว้ (ไม่ await)
    if (actualReceiverId != null) {
      final targetPeer = peers.firstWhere(
        (p) => p.id == actualReceiverId,
        orElse: () => Peer(id: '', name: ''),
      );
      if (targetPeer.id.isNotEmpty && targetPeer.name.isNotEmpty) {
        ChatDB.savePeerName(actualReceiverId, targetPeer.name); // ⚡ ไม่ await
      }
    }

    // เก็บ local พร้อม receiver (ไม่ await)
    if (actualReceiverId != null) {
      ChatDB.insertMessage(
        msg,
        currentUserId,
        receiver: actualReceiverId,
      ); // ⚡ ไม่ await
      Log.d('💾 บันทึกข้อความ sender=$myDeviceId, receiver=$actualReceiverId');
    }

    // 📤 ส่งข้อความแบบ Point-to-Point (เฉพาะคนที่เลือก)
    final targetPeer = actualReceiverId != null
        ? peers.firstWhere(
            (p) => p.id == actualReceiverId,
            orElse: () => Peer(id: '', name: ''),
          )
        : null;

    final index = _chatMessages.indexWhere((m) => m.id == messageId);
    bool sentOk = false;

    if (targetPeer != null && targetPeer.id.isNotEmpty) {
      try {
        // ใส่ id ข้อความไว้ในตัว payload (ก่อนเข้ารหัส) เพื่อให้ผู้รับใช้ id เดียวกันได้
        // — จำเป็นสำหรับ read receipt (READ:<id>) ที่ต้องอ้างอิง id ที่ผู้ส่งรู้จัก
        final wireBody = _composeChatWireBody(messageId, text);
        // 🔐 Encrypt if we have an E2EE session with this peer
        final toSend = _e2ee.hasSession(targetPeer.id)
            ? await _e2ee.encrypt(wireBody, targetPeer.id)
            : wireBody;
        await transport.sendMessage(toSend, to: targetPeer);
        sentOk = true;
        Log.d(
          '📤 ส่งข้อความไปยัง: ${targetPeer.name} (${targetPeer.id}) [E2EE: ${_e2ee.hasSession(targetPeer.id)}]',
        );
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
        ChatDB.updateMessageStatus(
          messageId,
          MessageStatus.sent,
        ); // ⚡ ไม่ await
      }
      Log.d('✅ ส่งข้อความ: $text (สถานะ: sent)');
    } else {
      // 📥 ส่งไม่สำเร็จ (offline/peer ไม่อยู่) → เข้าคิวรอ retry อัตโนมัติเมื่อเชื่อมต่อกลับมา
      await _messageQueue.addToPendingQueue(msg);
      Log.d('📥 เข้าคิวรอส่งใหม่: $text (สถานะ: pending)');
    }

    // 🔄 Auto sync ขึ้น Firebase ถ้าส่งสำเร็จ + online + login แล้ว
    if (sentOk &&
        index != -1 &&
        firebaseService.isOnline &&
        friendService.currentUser != null) {
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
    ChatDB.insertMessage(
      msg,
      friendService.currentUser!.id,
      receiver: receiverId,
    ); // เก็บ local พร้อม userId
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
    ChatDB.insertMessage(
      msg,
      friendService.currentUser!.id,
      receiver: receiverId,
    ); // เก็บ local พร้อม userId
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
    if (friendService.currentUser == null) return;

    final userId = friendService.currentUser!.id;
    // ใช้ getUserChatMessages() ซึ่งอ่านจาก users/{uid}/chats ตรงกับที่ syncChatMessageToCloud เขียน
    final cloudMessages = await firebaseService.getUserChatMessages();

    for (final m in cloudMessages) {
      final timeVal = m['time'];
      final DateTime msgTime;
      if (timeVal is int) {
        msgTime = DateTime.fromMillisecondsSinceEpoch(timeVal);
      } else if (timeVal is Timestamp) {
        msgTime = timeVal.toDate();
      } else if (timeVal is String) {
        msgTime = DateTime.tryParse(timeVal) ?? DateTime.now();
      } else {
        msgTime = DateTime.now();
      }

      final msg = ChatMessage(
        id: m['id'] ?? 'cloud_${msgTime.millisecondsSinceEpoch}',
        from: m['from'] ?? 'unknown',
        receiver: m['receiver'] as String?,
        type: ChatType.values.firstWhere(
          (e) => e.name == (m['type'] ?? 'text'),
          orElse: () => ChatType.text,
        ),
        text: m['text'] as String?,
        filePath: m['filePath'] as String?,
        time: msgTime,
        isEmergency: m['isEmergency'] as bool? ?? false,
        status: MessageStatus.synced,
      );
      await ChatDB.insertMessage(msg, userId);
    }

    final local = await ChatDB.getMessages(userId);
    _chatMessages
      ..clear()
      ..addAll(local);
    notifyListeners();
  }

  // ====== Friend Chat Management ======
  final Map<String, List<FriendChatMessage>> _friendChats = {};
  // real-time Firestore listener per friend — cancel เมื่อออกจากห้องแชท
  final Map<String, StreamSubscription<List<Map<String, dynamic>>>>
  _friendChatSubs = {};
  // global inbox listeners — ทำงานตลอดเวลา (ไม่ต้องอยู่ใน chat screen) เพื่อ trigger notification
  final Map<String, StreamSubscription<List<Map<String, dynamic>>>>
  _globalInboxSubs = {};
  final Set<String> _processedInboxMessageIds = {};

  UnmodifiableMapView<String, List<FriendChatMessage>> get friendChats =>
      UnmodifiableMapView(_friendChats);

  /// เริ่ม real-time listener สำหรับข้อความแชทกับเพื่อน
  /// เรียกเมื่อเปิดหน้า FriendChatScreen — แทนที่ polling 5 วินาที
  void startFriendChatListener(String friendUserId) {
    if (_friendChatSubs.containsKey(friendUserId)) {
      return; // listener มีอยู่แล้ว
    }
    if (friendService.currentUser == null) return;
    if (!firebaseService.isOnline || !firebaseService.isSignedIn) return;

    final currentUserId = friendService.currentUser!.id;
    final sub = firebaseService
        .streamFriendChatMessages(currentUserId, friendUserId)
        .listen(
          (rawMessages) {
            _mergeFirebaseMessagesIntoState(friendUserId, rawMessages);
          },
          onError: (e) {
            Log.d('[AppState] ❌ friendChatListener error: $e');
          },
        );

    _friendChatSubs[friendUserId] = sub;
    Log.d(
      '[AppState] 🔴 เริ่ม real-time listener สำหรับ friend: $friendUserId',
    );
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
          .listen(
            (rawMessages) {
              for (final data in rawMessages) {
                final msgId = data['id'] as String?;
                if (msgId == null || _processedInboxMessageIds.contains(msgId)) {
                  continue;
                }
                _processedInboxMessageIds.add(msgId);

                final msg = FriendChatMessage.fromJson(data);

                // เพิ่มข้อความเข้า local state ถ้ายังไม่มี
                final alreadyExists =
                    _friendChats[friendUserId]?.any((m) => m.id == msgId) ??
                    false;
                if (!alreadyExists) {
                  _friendChats[friendUserId] = [
                    ...(_friendChats[friendUserId] ?? []),
                    msg,
                  ];
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
                if (!isActiveFriendChat(friendUserId)) {
                  NotificationService().showMessageNotification(
                    friend.name,
                    msg.text?.isNotEmpty == true
                        ? msg.text!
                        : '📎 ส่งไฟล์มาให้',
                    senderId: friendUserId,
                    onReply: () => _openFriendChatScreen(friend),
                  );
                }
              }
            },
            onError: (e) {
              Log.d(
                '[AppState] ❌ globalInboxListener error for $friendUserId: $e',
              );
            },
          );
      _globalInboxSubs[friendUserId] = sub;
    }

    Log.d(
      '[AppState] 🔔 เริ่ม global inbox listener: ${_globalInboxSubs.length} เพื่อน',
    );
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
    String friendUserId,
    List<Map<String, dynamic>> rawMessages,
  ) {
    final existing = List<FriendChatMessage>.from(
      _friendChats[friendUserId] ?? [],
    );
    bool changed = false;

    for (final data in rawMessages) {
      final msg = FriendChatMessage.fromJson(data);
      final existingIndex = existing.indexWhere(
        (m) =>
            m.id == msg.id ||
            (m.text == msg.text &&
                m.fromUserId == msg.fromUserId &&
                m.toUserId == msg.toUserId &&
                m.time.difference(msg.time).abs().inSeconds < 2),
      );

      if (existingIndex == -1) {
        existing.add(msg);
        FriendDB.saveFriendChatMessage(friendUserId, msg.toJson());
        changed = true;
        continue;
      }

      // ข้อความมีอยู่แล้ว — เช็คว่า isRead เปลี่ยนจาก false → true ไหม (read receipt จากอีกฝั่ง)
      // ทางเดียว (ไม่ sync true → false กลับ) กัน race กับ optimistic update ในเครื่อง
      if (!existing[existingIndex].isRead && msg.isRead) {
        final updated = existing[existingIndex].copyWith(isRead: true);
        existing[existingIndex] = updated;
        FriendDB.saveFriendChatMessage(friendUserId, updated.toJson());
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
  Future<void> sendFriendChatMessage(
    String friendUserId,
    String text, {
    bool isEmergency = false,
  }) async {
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
    FriendDB.saveFriendChatMessage(
      friendUserId,
      message.toJson(),
    ); // ⚡ ไม่ await

    // อัพเดทข้อความสุดท้ายของเพื่อน (ไม่ await)
    friendService.updateFriendLastMessage(
      friendUserId,
      text,
      DateTime.now(),
    ); // ⚡ ไม่ await

    // ส่งผ่าน transport หากออฟไลน์ (Nearby/BLE/WiFi Direct) - ไม่ await
    // ถ้ารู้ peer ของเพื่อนคนนี้อยู่แล้ว (เคยแลก FRIEND_ID/FRIEND_MSG กันมา) ส่งตรงเจาะจงเครื่อง
    // ไม่ broadcast ให้คนแปลกหน้าใกล้เคียงเห็นข้อความส่วนตัว
    try {
      final targetPeer = _peerForFriend(friendUserId);
      transport.sendMessage(
        'FRIEND_MSG:${friendService.currentUser!.id}:$text',
        to: targetPeer,
      ); // ⚡ ไม่ await
      Log.d(
        '📡 [P2P] ส่งข้อความผ่าน Bluetooth/WiFi Direct ${targetPeer != null ? "(unicast: ${targetPeer.name})" : "(broadcast - ยังไม่รู้ peer ของเพื่อนคนนี้)"}',
      );
    } catch (e) {
      Log.d('[AppState] Error sending via transport: $e');
    }

    // ส่งผ่าน FCM หากมีอินเทอร์เน็ต (Push Notification) - ไม่ await
    try {
      FCMService().sendNotificationToFriend(
        // ⚡ ไม่ await
        friendUserId: friendUserId,
        message: text,
      );
      Log.d('🔔 [FCM] ส่ง Push Notification แล้ว');
    } catch (e) {
      Log.d('[AppState] Error sending FCM: $e');
    }

    // บันทึกบน Firebase หากออนไลน์ ไม่งั้นเข้าคิวรอ sync
    if (firebaseService.isOnline && firebaseService.isSignedIn) {
      firebaseService.saveFriendChatMessage(
        // ⚡ ไม่ await
        fromUserId: friendService.currentUser!.id,
        toUserId: friendUserId,
        type: 'text',
        text: text,
        time: message.time,
        messageId: message.id,
      );
    } else {
      _enqueuePendingFriendSync(
        // ⚡ ไม่ await
        fromUserId: friendService.currentUser!.id,
        toUserId: friendUserId,
        type: 'text',
        text: text,
        time: message.time,
        messageId: message.id,
      );
    }
  }

  /// ส่งรูปภาพให้เพื่อน — อัพโหลด Firebase Storage ถ้าออนไลน์ หรือ P2P ถ้าอยู่ใกล้
  Future<void> sendFriendImageMessage(
    String friendUserId,
    String imagePath,
  ) async {
    if (friendService.currentUser == null) return;

    final msgId = 'img_${DateTime.now().millisecondsSinceEpoch}';
    final msgTime = DateTime.now();
    final myUserId = friendService.currentUser!.id;

    // แสดงรูปใน UI ทันทีจาก local path
    var message = FriendChatMessage(
      id: msgId,
      fromUserId: myUserId,
      toUserId: friendUserId,
      type: ChatType.image,
      filePath: imagePath,
      time: msgTime,
      isEmergency: false,
    );

    if (!_friendChats.containsKey(friendUserId)) {
      _friendChats[friendUserId] = [];
    }
    _friendChats[friendUserId] = [..._friendChats[friendUserId]!, message];
    notifyListeners();

    friendService.updateFriendLastMessage(friendUserId, '📷 รูปภาพ', msgTime);

    // ส่งผ่าน P2P ถ้า friend อยู่ใกล้
    try {
      final targetPeer = _peerForFriend(friendUserId);
      if (targetPeer != null) {
        transport.sendFile(imagePath, to: targetPeer);
        Log.d('📡 [P2P] ส่งรูปภาพผ่าน P2P → ${targetPeer.name}');
      }
    } catch (e) {
      Log.d('[AppState] Error sending image via P2P: $e');
    }

    // อัพโหลด Firebase Storage แล้วบันทึก URL ใน Firestore
    if (firebaseService.isOnline && firebaseService.isSignedIn) {
      final ext = imagePath.split('.').last;
      final storagePath =
          'chat_media/${_generateChatId(myUserId, friendUserId)}/$msgId.$ext';
      final fileUrl = await firebaseService.uploadFile(imagePath, storagePath);

      // อัปเดต message ใน memory ด้วย fileUrl
      if (fileUrl != null) {
        message = message.copyWith(fileUrl: fileUrl);
        final idx = _friendChats[friendUserId]!.indexWhere(
          (m) => m.id == msgId,
        );
        if (idx != -1) {
          final updated = [..._friendChats[friendUserId]!];
          updated[idx] = message;
          _friendChats[friendUserId] = updated;
          notifyListeners();
        }
      }

      FriendDB.saveFriendChatMessage(friendUserId, message.toJson());

      firebaseService.saveFriendChatMessage(
        fromUserId: myUserId,
        toUserId: friendUserId,
        type: 'image',
        fileUrl: fileUrl,
        time: msgTime,
        messageId: msgId,
      );
    } else {
      FriendDB.saveFriendChatMessage(friendUserId, message.toJson());
      _enqueuePendingFriendSync(
        fromUserId: myUserId,
        toUserId: friendUserId,
        type: 'image',
        text: '[Image - offline]',
        time: msgTime,
        messageId: msgId,
      );
    }
  }

  /// ส่งวิดีโอให้เพื่อน — อัพโหลด Firebase Storage ถ้าออนไลน์ หรือ P2P ถ้าอยู่ใกล้
  Future<void> sendFriendVideoMessage(
    String friendUserId,
    String videoPath,
  ) async {
    if (friendService.currentUser == null) return;

    final msgId = 'vid_${DateTime.now().millisecondsSinceEpoch}';
    final msgTime = DateTime.now();
    final myUserId = friendService.currentUser!.id;

    // แสดงวิดีโอใน UI ทันทีจาก local path
    var message = FriendChatMessage(
      id: msgId,
      fromUserId: myUserId,
      toUserId: friendUserId,
      type: ChatType.video,
      filePath: videoPath,
      time: msgTime,
      isEmergency: false,
    );

    if (!_friendChats.containsKey(friendUserId)) {
      _friendChats[friendUserId] = [];
    }
    _friendChats[friendUserId] = [..._friendChats[friendUserId]!, message];
    notifyListeners();

    friendService.updateFriendLastMessage(friendUserId, '🎥 วิดีโอ', msgTime);

    // ส่งผ่าน P2P ถ้า friend อยู่ใกล้
    try {
      final targetPeer = _peerForFriend(friendUserId);
      if (targetPeer != null) {
        transport.sendFile(videoPath, to: targetPeer);
        Log.d('📡 [P2P] ส่งวิดีโอผ่าน P2P → ${targetPeer.name}');
      }
    } catch (e) {
      Log.d('[AppState] Error sending video via P2P: $e');
    }

    // อัพโหลด Firebase Storage แล้วบันทึก URL ใน Firestore
    if (firebaseService.isOnline && firebaseService.isSignedIn) {
      final ext = videoPath.split('.').last;
      final storagePath =
          'chat_media/${_generateChatId(myUserId, friendUserId)}/$msgId.$ext';
      final fileUrl = await firebaseService.uploadFile(videoPath, storagePath);

      if (fileUrl != null) {
        message = message.copyWith(fileUrl: fileUrl);
        final idx = _friendChats[friendUserId]!.indexWhere(
          (m) => m.id == msgId,
        );
        if (idx != -1) {
          final updated = [..._friendChats[friendUserId]!];
          updated[idx] = message;
          _friendChats[friendUserId] = updated;
          notifyListeners();
        }
      }

      FriendDB.saveFriendChatMessage(friendUserId, message.toJson());

      firebaseService.saveFriendChatMessage(
        fromUserId: myUserId,
        toUserId: friendUserId,
        type: 'video',
        fileUrl: fileUrl,
        time: msgTime,
        messageId: msgId,
      );
    } else {
      FriendDB.saveFriendChatMessage(friendUserId, message.toJson());
      _enqueuePendingFriendSync(
        fromUserId: myUserId,
        toUserId: friendUserId,
        type: 'video',
        text: '[Video - offline]',
        time: msgTime,
        messageId: msgId,
      );
    }
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
      final lat = position.latitude.toStringAsFixed(6);
      final lng = position.longitude.toStringAsFixed(6);
      final googleMapsUrl =
          'https://www.google.com/maps?q=${position.latitude},${position.longitude}';
      final locationText =
          '📍 ตำแหน่งของฉัน\nละติจูด: $lat\nลองติจูด: $lng\n$googleMapsUrl';

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
      FriendDB.saveFriendChatMessage(
        friendUserId,
        message.toJson(),
      ); // ⚡ ไม่ await

      // อัพเดทข้อความสุดท้าย (ไม่ await)
      friendService.updateFriendLastMessage(
        friendUserId,
        '📍 ตำแหน่ง',
        DateTime.now(),
      ); // ⚡ ไม่ await

      // ส่งผ่าน transport (ไม่ await)
      try {
        transport.sendMessage(
          // ⚡ ไม่ await
          'FRIEND_MSG:${friendService.currentUser!.id}:$locationText',
          to: _peerForFriend(friendUserId),
        );
      } catch (e) {
        Log.d('[AppState] Error sending location via transport: $e');
      }

      // บันทึก metadata บน Firebase (ไม่ await)
      if (firebaseService.isOnline && firebaseService.isSignedIn) {
        firebaseService.saveFriendChatMessage(
          // ⚡ ไม่ await
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
      rethrow; // ส่ง error กลับไปให้ UI จัดการ
    }
  }

  /// โหลดข้อความแชทกับเพื่อน
  Future<void> loadFriendChatMessages(
    String friendUserId, {
    bool forceRefresh = false,
  }) async {
    if (_friendChats.containsKey(friendUserId) && !forceRefresh) {
      return; // โหลดแล้ว
    }

    final myUserId = friendService.currentUser?.id;

    // โหลด last read timestamp ที่รอดตาย logout
    final lastRead = myUserId != null
        ? await FriendDB.getLastReadTime(myUserId, friendUserId)
        : null;

    // โหลดจากฐานข้อมูลท้องถิ่น
    final localMessages = await FriendDB.getFriendChatMessages(friendUserId);
    final messages = localMessages
        .map((json) => FriendChatMessage.fromJson(json))
        .toList();

    _friendChats[friendUserId] = messages;

    // โหลดจาก Firebase หากออนไลน์
    if (firebaseService.isOnline &&
        firebaseService.isSignedIn &&
        myUserId != null) {
      try {
        // 🔋 ดึงเฉพาะข้อความใหม่กว่าที่มีในเครื่องแล้ว (incremental sync) แทนดึงประวัติทั้งหมดทุกครั้ง
        // ลบ buffer 5 วิ กันเคส clock skew/ข้อความที่ time ใกล้เคียงกันมาก — dedup logic ด้านล่างช่วยกันซ้ำอยู่แล้ว
        DateTime? since;
        if (messages.isNotEmpty) {
          final latest = messages
              .map((m) => m.time)
              .reduce((a, b) => a.isAfter(b) ? a : b);
          since = latest.subtract(const Duration(seconds: 5));
        }

        Log.d(
          '[AppState] 🔄 กำลังดึงข้อความจาก Firebase${since != null ? " (ตั้งแต่ $since)" : " (ครั้งแรก)"}...',
        );
        final firebaseMessages = await firebaseService.getFriendChatMessages(
          myUserId,
          friendUserId,
          since: since,
        );

        Log.d(
          '[AppState] 📩 ได้รับ ${firebaseMessages.length} ข้อความจาก Firebase',
        );

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
          final isDuplicate = messages.any(
            (m) =>
                m.id == message.id || // เช็ค ID ตรงกัน
                (m.text == message.text && // หรือเนื้อหาเหมือนกัน
                    m.fromUserId == message.fromUserId && // จากคนเดียวกัน
                    m.toUserId == message.toUserId && // ถึงคนเดียวกัน
                    m.time.difference(message.time).abs().inSeconds <
                        2), // เวลาห่างกันไม่เกิน 2 วินาที
          );

          if (!isDuplicate) {
            messages.add(message);
            // บันทึกลงฐานข้อมูลท้องถิ่น
            await FriendDB.saveFriendChatMessage(
              friendUserId,
              message.toJson(),
            );
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
  String _generateChatId(String user1Id, String user2Id) {
    final users = [user1Id, user2Id]..sort();
    return '${users[0]}_${users[1]}';
  }

  Peer? _peerForFriend(String friendUserId) {
    final peerId = _friendUserIdToPeerId[friendUserId];
    if (peerId == null) return null;
    final peer = peers.firstWhere(
      (p) => p.id == peerId,
      orElse: () => const Peer(id: '', name: ''),
    );
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
      friendService.updateFriendLastMessage(
        fromUserId,
        messageText,
        DateTime.now(),
        incrementUnread: true,
      );

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

  /// รีเซ็ตจำนวนข้อความที่ยังไม่อ่านของเพื่อน
  Future<void> markFriendMessagesAsRead(String friendUserId) async {
    await friendService.markFriendMessagesAsRead(friendUserId);

    final myUserId = friendService.currentUser?.id;
    final newlyReadIds = <String>[];

    // อัพเดทสถานะ isRead ของข้อความ และ persist ลง SharedPreferences
    if (_friendChats.containsKey(friendUserId)) {
      for (int i = 0; i < _friendChats[friendUserId]!.length; i++) {
        final message = _friendChats[friendUserId]![i];
        if (!message.isRead && message.fromUserId != myUserId) {
          final updated = message.copyWith(isRead: true);
          _friendChats[friendUserId]![i] = updated;
          await FriendDB.saveFriendChatMessage(friendUserId, updated.toJson());
          newlyReadIds.add(updated.id);
        }
      }
    }

    // บันทึก last read timestamp ที่ไม่ถูกลบตอน logout
    // เพื่อให้ข้ามเซสชันได้ถูกต้องเมื่อ login ใหม่
    if (myUserId != null) {
      await FriendDB.setLastReadTime(myUserId, friendUserId, DateTime.now());
    }

    // 🔵 sync isRead กลับขึ้น Firebase ให้ผู้ส่งเห็นสถานะ "อ่านแล้ว" จริง (real-time ถ้าเขาเปิดแชทอยู่)
    if (newlyReadIds.isNotEmpty &&
        myUserId != null &&
        firebaseService.isOnline &&
        firebaseService.isSignedIn) {
      firebaseService.markFriendChatMessagesAsRead(
        myUserId,
        friendUserId,
        newlyReadIds,
      ); // ไม่ await
    }

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
      final messageMaps = messages
          .map(
            (msg) => {
              'id': msg.id,
              'from': msg.from,
              'type': msg.type.toString().split('.').last,
              'text': msg.text,
              'filePath': msg.filePath,
              'time': msg.time.millisecondsSinceEpoch,
              'isEmergency': msg.isEmergency,
              'status': msg.status.toString().split('.').last,
            },
          )
          .toList();

      final syncedCount = await firebaseService.syncPendingMessages(
        messageMaps,
      );
      Log.d(
        '[Sync] ✅ Synced $syncedCount/${messages.length} messages to Firebase',
      );
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
              final peer = peers.firstWhere(
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

          final success = await firebaseService.syncChatMessageToCloud(
            messageMap,
          );
          if (success) {
            // อัพเดทสถานะเป็น synced
            await ChatDB.updateMessageStatus(msg.id, MessageStatus.synced);
            syncedCount++;
          }
        } catch (e) {
          Log.d('[Sync] ❌ Error syncing message ${msg.id}: $e');
        }
      }

      Log.d(
        '[Sync] ✅ Synced $syncedCount/${allUnsynced.length} messages to Firebase',
      );

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
        await firebaseService.deleteChatMessage(
          friendService.currentUser!.id,
          messageId,
        );
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

  /// รับ read receipt จาก peer (format: `READ:<id1>,<id2>,...`) — อัปเดตข้อความที่เราส่งไปแล้ว
  /// เป็น isRead: true เพื่อให้ UI ขึ้นสถานะ "อ่านแล้ว" ได้ผลเฉพาะตอน peer ยังเชื่อมต่ออยู่ (P2P
  /// ไม่มี cloud fallback แบบแชทเพื่อนออนไลน์)
  void _handleReadReceipt(String body, String fromPeerId) {
    final ids = body
        .substring('READ:'.length)
        .split(',')
        .where((s) => s.isNotEmpty);
    if (ids.isEmpty) return;

    var changed = false;
    for (final id in ids) {
      final index = _chatMessages.indexWhere((m) => m.id == id);
      if (index != -1 && !_chatMessages[index].isRead) {
        _chatMessages[index] = _chatMessages[index].copyWith(isRead: true);
        ChatDB.markMessageAsRead(id); // ⚡ ไม่ await
        changed = true;
      }
    }

    if (changed) {
      Log.d('✅ [ReadReceipt] อัปเดต isRead จาก $fromPeerId: $ids');
      notifyListeners();
    }
  }

  /// ทำเครื่องหมายข้อความจาก peer นี้ว่าอ่านแล้ว + ส่ง read receipt กลับไปถ้ายังเชื่อมต่ออยู่
  /// เรียกตอนเปิดห้องแชทฉุกเฉิน (เทียบเท่า markFriendMessagesAsRead ของฝั่งแชทเพื่อนออนไลน์)
  Future<void> markPeerMessagesAsRead(String peerId) async {
    final userId = friendService.currentUser?.id ?? 'anonymous';
    await ChatDB.markConversationRead(userId, peerId);

    final newlyReadIds = <String>[];
    for (int i = 0; i < _chatMessages.length; i++) {
      final message = _chatMessages[i];
      if (message.from == peerId && !message.isRead) {
        _chatMessages[i] = message.copyWith(isRead: true);
        newlyReadIds.add(message.id);
      }
    }

    if (newlyReadIds.isEmpty) return;

    final peer = peers.firstWhere(
      (p) => p.id == peerId,
      orElse: () => const Peer(id: '', name: ''),
    );
    if (peer.id.isNotEmpty) {
      transport.sendMessage(
        'READ:${newlyReadIds.join(',')}',
        to: peer,
      ); // ⚡ ไม่ await — best-effort
    }

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
    if (newTTL > 0 && peers.isNotEmpty) {
      final relayMsg =
          'RELAY:$messageId:$newTTL:$originalSender:$senderName:$content';

      // บันทึก network topology
      _networkTopology[fromPeerId] = peers.map((p) => p.id).toSet();
      _messageTimestamps[messageId] = DateTime.now();

      for (final peer in peers) {
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
}
