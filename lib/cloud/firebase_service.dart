// lib/cloud/firebase_service.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/friend_models.dart';

class FirebaseService extends ChangeNotifier {
  bool _initialized = false;
  bool _online = false;
  fa.User? _user;
  FirebaseFirestore? _db;

  bool get isInitialized => _initialized;
  bool get isOnline => _online;
  bool get isSignedIn => _user != null;
  fa.User? get currentUser => _user;
  FirebaseFirestore? get db => _db;

  StreamSubscription? _connSub;

  Future<void> sendPasswordResetEmail(String email) async {
    if (!_initialized) throw Exception('Firebase not initialized');
    await fa.FirebaseAuth.instance.sendPasswordResetEmail(email: email);
  }

  Future<void> init() async {
    // ติดตามสถานะเน็ต
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      _online = results.isNotEmpty && !results.contains(ConnectivityResult.none);
      notifyListeners();
    });

    try {
      // พยายาม init โดยไม่ระบุ options (ถ้ามี google-services.json จะใช้ค่าได้)
      await Firebase.initializeApp();
      _initialized = true;
    } catch (e) {
      debugPrint('[Firebase] init failed: $e');
      _initialized = false; // ยังให้แอพทำงานออฟไลน์ได้
      notifyListeners();
      return;
    }

    try {
      _db = FirebaseFirestore.instance;
      _db!.settings = const Settings(persistenceEnabled: true);
    } catch (e) {
      debugPrint('[Firestore] not ready: $e');
    }

    try {
      fa.FirebaseAuth.instance.authStateChanges().listen((u) {
        _user = u;
        notifyListeners();
      });
    } catch (e) {
      debugPrint('[Auth] not ready: $e');
    }

    notifyListeners();
  }

  Future<String?> signUpWithEmail(String email, String password, {String? displayName}) async {
    if (!_initialized) return 'Firebase not initialized';
    try {
      final cred = await fa.FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email, password: password,
      );
      if (displayName != null && displayName.isNotEmpty) {
        await cred.user?.updateDisplayName(displayName);
      }
      _user = cred.user;
      notifyListeners();

      await saveUserProfile({
        'uid': _user!.uid,
        'email': _user!.email,
        'displayName': _user!.displayName,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> signInWithEmail(String email, String password) async {
    if (!_initialized) return 'Firebase not initialized';
    try {
      final cred = await fa.FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email, password: password,
      );
      _user = cred.user;
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> signOut() async {
    if (!_initialized) return;
    await fa.FirebaseAuth.instance.signOut();
    _user = null;
    notifyListeners();
  }

  Future<void> saveUserProfile(Map<String, dynamic> data) async {
    if (_db == null || _user == null) return;
    await _db!.collection('users').doc(_user!.uid).set(data, SetOptions(merge: true));
  }

  Future<void> saveChatMessage({
    required String type, // 'text' | 'image' | 'video'
    String? text,
    String? fileUrl,
    required DateTime time,
  }) async {
    if (_db == null || _user == null) return;
    await _db!.collection('chats').doc(_user!.uid).collection('messages').add({
      'type': type,
      'text': text,
      'fileUrl': fileUrl,
      'time': time.toUtc(),
    });
  }

  // ========== User Profile & Friends Management ==========

  /// สร้าง User ID ที่ไม่ซ้ำ
  String generateUniqueUserId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random().nextInt(99999);
    return 'USER_${timestamp}_$random';
  }

  /// บันทึกข้อมูลโปรไฟล์ผู้ใช้พร้อม User ID
  Future<void> saveFullUserProfile(UserProfile profile) async {
    if (_db == null) return;
    await _db!.collection('users').doc(profile.id).set(profile.toJson());
  }

  /// ค้นหาผู้ใช้จาก User ID
  Future<UserProfile?> findUserByUserId(String userId, {bool forceRefresh = false}) async {
    if (_db == null) {
      debugPrint('[Firebase] ❌ Database ไม่พร้อม');
      return null;
    }
    try {
      debugPrint('[Firebase] 🔍 กำลังค้นหา User ID: $userId ${forceRefresh ? "(force reload)" : ""}');
      
      // Force reload from server (ไม่ใช้ cache)
      final source = forceRefresh ? Source.server : Source.serverAndCache;
      final doc = await _db!.collection('users').doc(userId).get(GetOptions(source: source));
      
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        debugPrint('[Firebase] ✅ พบผู้ใช้: ${data['name']}, isOnline: ${data['isOnline']}');
        return UserProfile.fromJson(data);
      } else {
        debugPrint('[Firebase] ❌ ไม่พบผู้ใช้ ID: $userId');
      }
    } catch (e) {
      debugPrint('[Firebase] ❌ Error finding user: $e');
    }
    return null;
  }

  /// ค้นหาผู้ใช้จาก Email (สำหรับตรวจสอบว่าเคย login มาก่อนหรือไม่)
  Future<UserProfile?> findUserByEmail(String email) async {
    if (_db == null) return null;
    try {
      final query = await _db!
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      
      if (query.docs.isNotEmpty) {
        return UserProfile.fromJson(query.docs.first.data());
      }
    } catch (e) {
      debugPrint('[Firebase] Error finding user by email: $e');
    }
    return null;
  }

  /// ค้นหาผู้ใช้จากชื่อ (สำหรับค้นหาเพื่อน)
  Future<List<UserProfile>> searchUsersByName(String name) async {
    if (_db == null) return [];
    try {
      final query = await _db!
          .collection('users')
          .where('name', isGreaterThanOrEqualTo: name)
          .where('name', isLessThan: name + '\uf8ff')
          .limit(10)
          .get();
      
      return query.docs
          .map((doc) => UserProfile.fromJson(doc.data()))
          .toList();
    } catch (e) {
      debugPrint('[Firebase] Error searching users: $e');
      return [];
    }
  }

  /// อัพเดทสถานะออนไลน์
  Future<void> updateOnlineStatus(String userId, bool isOnline) async {
    if (_db == null) {
      debugPrint('[Firebase] ⚠️ Database ไม่พร้อม - ไม่สามารถอัปเดตสถานะออนไลน์');
      return;
    }
    try {
      debugPrint('[Firebase] 🔄 อัปเดตสถานะออนไลน์: $userId → ${isOnline ? "ออนไลน์" : "ออฟไลน์"}');
      
      // ใช้ set พร้อม merge: true เพื่อสร้าง document ถ้ายังไม่มี หรืออัปเดตถ้ามีแล้ว
      await _db!.collection('users').doc(userId).set({
        'isOnline': isOnline,
        'lastActiveAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
      
      debugPrint('[Firebase] ✅ อัปเดตสถานะออนไลน์สำเร็จ');
      
      // ตรวจสอบว่าข้อมูลบันทึกจริงหรือไม่ (แสดง log เฉพาะตอน init)
      // final verify = await _db!.collection('users').doc(userId).get(GetOptions(source: Source.server));
      // if (verify.exists) {
      //   final data = verify.data();
      //   debugPrint('[Firebase] 🔍 ตรวจสอบข้อมูล: isOnline = ${data?['isOnline']}, lastActiveAt = ${data?['lastActiveAt']}');
      // } else {
      //   debugPrint('[Firebase] ⚠️ ไม่พบ document หลังบันทึก!');
      // }
    } catch (e, stackTrace) {
      debugPrint('[Firebase] ❌ Error updating online status: $e');
      debugPrint('[Firebase] ❌ Stack trace: $stackTrace');
      rethrow;
    }
  }

  // ========== Friend Requests Management ==========

  /// ส่งคำขอเป็นเพื่อน
  Future<bool> sendFriendRequest(FriendRequest request) async {
    if (_db == null) return false;
    try {
      debugPrint('[Firebase] 📤 ส่งคำขอ: ${request.id}');
      debugPrint('[Firebase]   - จาก: ${request.fromUserName} (${request.fromUserId})');
      debugPrint('[Firebase]   - ไปยัง: ${request.toUserId}');
      
      await _db!.collection('friend_requests').doc(request.id).set(request.toJson());
      
      debugPrint('[Firebase] ✅ บันทึกคำขอลง Firebase สำเร็จ');
      return true;
    } catch (e) {
      debugPrint('[Firebase] ❌ Error sending friend request: $e');
      return false;
    }
  }

  /// ดึงคำขอเป็นเพื่อนที่ได้รับ
  Future<List<FriendRequest>> getReceivedFriendRequests(String userId) async {
    if (_db == null) return [];
    try {
      debugPrint('[Firebase] 🔍 ดึงคำขอสำหรับ: $userId');
      
      final query = await _db!
          .collection('friend_requests')
          .where('toUserId', isEqualTo: userId)
          .where('status', isEqualTo: 'pending')
          .get();
      
      final requests = query.docs
          .map((doc) => FriendRequest.fromJson(doc.data()))
          .toList();
      
      debugPrint('[Firebase] ✅ พบ ${requests.length} คำขอที่รอการตอบรับ');
      for (final req in requests) {
        debugPrint('[Firebase]   - จาก: ${req.fromUserName} (${req.fromUserId})');
      }
      
      return requests;
    } catch (e) {
      debugPrint('[Firebase] ❌ Error getting friend requests: $e');
      return [];
    }
  }

  /// ตอบรับ/ปฏิเสธคำขอเป็นเพื่อน
  Future<bool> respondToFriendRequest(String requestId, bool accept) async {
    if (_db == null) return false;
    try {
      debugPrint('[Firebase] 🔄 กำลังตอบรับคำขอ: $requestId (accept=$accept)');
      
      // ดึงข้อมูลคำขอก่อน
      final requestDoc = await _db!.collection('friend_requests').doc(requestId).get();
      if (!requestDoc.exists) {
        debugPrint('[Firebase] ⚠️ ไม่พบคำขอ: $requestId');
        return false;
      }
      
      final requestData = requestDoc.data()!;
      final fromUserId = requestData['fromUserId'];
      final toUserId = requestData['toUserId'];
      
      if (accept) {
        // ถ้ายอมรับ ให้เพิ่มเข้าลิสต์เพื่อนของทั้งสองฝ่าย
        debugPrint('[Firebase] ✅ กำลังเพิ่มเพื่อน 2 ทาง: $fromUserId <-> $toUserId');
        
        // เพิ่มเพื่อนให้กับผู้ส่งคำขอ (fromUserId เพิ่ม toUserId)
        await _addFriendToUserList(fromUserId, toUserId);
        debugPrint('[Firebase] ✅ เพิ่มเพื่อนให้ผู้ส่ง ($fromUserId)');
        
        // เพิ่มเพื่อนให้กับผู้รับคำขอ (toUserId เพิ่ม fromUserId)
        await _addFriendToUserList(toUserId, fromUserId);
        debugPrint('[Firebase] ✅ เพิ่มเพื่อนให้ผู้รับ ($toUserId)');
      }
      
      // 🔥 สำคัญ: ลบคำขอออกจาก Firebase แทนการ update status
      // เพื่อป้องกันคำขอซ้ำ
      await _db!.collection('friend_requests').doc(requestId).delete();
      debugPrint('[Firebase] 🗑️ ลบคำขอออกจาก Firebase แล้ว');
      
      return true;
    } catch (e) {
      debugPrint('[Firebase] ❌ Error responding to friend request: $e');
      return false;
    }
  }

  /// เพิ่มเพื่อนเข้าลิสต์ของผู้ใช้
  Future<void> _addFriendToUserList(String userId, String friendUserId) async {
    if (_db == null) return;
    try {
      debugPrint('[Firebase] 🔄 กำลังเพิ่มเพื่อน');
      debugPrint('[Firebase]   - ให้ผู้ใช้: $userId');
      debugPrint('[Firebase]   - เพิ่มเพื่อน: $friendUserId');
      
      // ดึงข้อมูลของเพื่อน
      final friendDoc = await _db!.collection('users').doc(friendUserId).get();
      if (!friendDoc.exists) {
        debugPrint('[Firebase] ⚠️ ไม่พบข้อมูลผู้ใช้: $friendUserId');
        return;
      }
      
      final friendData = friendDoc.data()!;
      debugPrint('[Firebase] ✅ พบข้อมูลเพื่อน: ${friendData['name']} (ID: ${friendData['id']})');
      
      final friend = Friend(
        id: 'friend_${userId}_$friendUserId',
        name: friendData['name'],
        userId: friendUserId, // 🔥 สำคัญ: userId ของเพื่อน
        avatar: friendData['avatar'],
        addedAt: DateTime.now(),
        lastSeen: DateTime.parse(friendData['lastActiveAt'] ?? DateTime.now().toIso8601String()),
        isOnline: friendData['isOnline'] ?? false,
      );

      debugPrint('[Firebase] 💾 บันทึกเพื่อน: ${friend.name} (userId: ${friend.userId}) -> ลง collection ของ user $userId');
      
      await _db!
          .collection('users')
          .doc(userId)
          .collection('friends')
          .doc(friendUserId)
          .set(friend.toJson());
      
      debugPrint('[Firebase] ✅ เพิ่มเพื่อนสำเร็จ');
    } catch (e, stackTrace) {
      debugPrint('[Firebase] ❌ Error adding friend to user list: $e');
      debugPrint('[Firebase] ❌ Stack trace: $stackTrace');
      rethrow; // throw ต่อเพื่อให้รู้ว่า error จริงๆ
    }
  }

  /// ดึงรายชื่อเพื่อนจาก Firebase
  Future<List<Friend>> getUserFriends(String userId) async {
    if (_db == null) return [];
    try {
      debugPrint('[Firebase] 🔍 กำลังดึงเพื่อนของ: $userId');
      final query = await _db!
          .collection('users')
          .doc(userId)
          .collection('friends')
          .get();
      
      final friends = query.docs
          .map((doc) => Friend.fromJson(doc.data()))
          .toList();
      
      debugPrint('[Firebase] ✅ พบเพื่อน: ${friends.length} คน');
      for (final friend in friends) {
        debugPrint('[Firebase]   - ${friend.name} (${friend.userId})');
      }
      
      return friends;
    } catch (e) {
      debugPrint('[Firebase] ❌ Error getting user friends: $e');
      return [];
    }
  }

  /// ลบเพื่อน
  Future<bool> removeFriend(String userId, String friendUserId) async {
    if (_db == null) return false;
    try {
      // ลบจากลิสต์เพื่อนของตัวเอง
      await _db!
          .collection('users')
          .doc(userId)
          .collection('friends')
          .doc(friendUserId)
          .delete();
      
      // ลบจากลิสต์เพื่อนของอีกฝ่าย
      await _db!
          .collection('users')
          .doc(friendUserId)
          .collection('friends')
          .doc(userId)
          .delete();
      
      return true;
    } catch (e) {
      debugPrint('[Firebase] Error removing friend: $e');
      return false;
    }
  }

  // ========== Friend Chat Messages ==========

  /// บันทึกข้อความแชทกับเพื่อน
  Future<void> saveFriendChatMessage({
    required String fromUserId,
    required String toUserId,
    required String type,
    String? text,
    String? fileUrl,
    required DateTime time,
    String? messageId, // เพิ่มพารามิเตอร์ messageId
  }) async {
    if (_db == null) return;
    try {
      final chatId = _generateChatId(fromUserId, toUserId);
      // ใช้ messageId ถ้ามี ไม่งั้นสร้างใหม่
      final msgId = messageId ?? 'msg_${DateTime.now().millisecondsSinceEpoch}';
      
      debugPrint('[Firebase] 💬 บันทึกข้อความ');
      debugPrint('[Firebase]   - Chat ID: $chatId');
      debugPrint('[Firebase]   - Message ID: $msgId');
      debugPrint('[Firebase]   - จาก: $fromUserId');
      debugPrint('[Firebase]   - ถึง: $toUserId');
      debugPrint('[Firebase]   - ข้อความ: $text');
      
      // ใช้ .doc(msgId).set() แทน .add() เพื่อใช้ ID เดียวกัน
      await _db!.collection('friend_chats').doc(chatId).collection('messages').doc(msgId).set({
        'id': msgId, // เก็บ id ไว้ใน document ด้วย
        'fromUserId': fromUserId,
        'toUserId': toUserId,
        'type': type,
        'text': text,
        'fileUrl': fileUrl,
        'time': time.toUtc(),
        'isRead': false,
      });
      
      debugPrint('[Firebase] ✅ บันทึกข้อความสำเร็จ');
    } catch (e) {
      debugPrint('[Firebase] ❌ Error saving friend chat message: $e');
    }
  }

  /// ดึงข้อความแชทกับเพื่อน
  Future<List<Map<String, dynamic>>> getFriendChatMessages(String user1Id, String user2Id) async {
    if (_db == null) return [];
    try {
      final chatId = _generateChatId(user1Id, user2Id);
      debugPrint('[Firebase] 🔍 ดึงข้อความ Chat ID: $chatId');
      
      final query = await _db!
          .collection('friend_chats')
          .doc(chatId)
          .collection('messages')
          .orderBy('time', descending: false)
          .get();
      
      debugPrint('[Firebase] ✅ พบ ${query.docs.length} ข้อความ');
      
      return query.docs.map((doc) {
        final data = doc.data();
        // ใช้ id จาก document ถ้ามี ไม่งั้นใช้ document ID
        data['id'] = data['id'] ?? doc.id;
        return data;
      }).toList();
    } catch (e) {
      debugPrint('[Firebase] ❌ Error getting friend chat messages: $e');
      return [];
    }
  }

  /// สร้าง Chat ID สำหรับสองคน (เรียงตาม alphabetical order)
  String _generateChatId(String user1Id, String user2Id) {
    final users = [user1Id, user2Id]..sort();
    return '${users[0]}_${users[1]}';
  }

  /// ดึงข้อความแชททั้งหมด (สำหรับ sync)
  Future<List<Map<String, dynamic>>> getAllChatMessages() async {
    if (_db == null) return [];
    try {
      final snapshot = await _db!
          .collection('chat_messages')
          .orderBy('time', descending: false)
          .get();
      return snapshot.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      debugPrint('[Firebase] Error getting all chat messages: $e');
      return [];
    }
  }

  // ========== Chat Sync Management ==========

  /// 💾 บันทึกข้อความแชทขึ้น Firebase (จาก local)
  Future<bool> syncChatMessageToCloud(Map<String, dynamic> message) async {
    if (_db == null || _user == null) return false;
    try {
      await _db!.collection('users').doc(_user!.uid).collection('chats').doc(message['id']).set({
        ...message,
        'userId': _user!.uid,
        'syncedAt': FieldValue.serverTimestamp(),
      });
      debugPrint('[Firebase] ✅ Saved chat message: ${message['id']}');
      return true;
    } catch (e) {
      debugPrint('[Firebase] ❌ Error saving chat message: $e');
      return false;
    }
  }

  /// 📥 ดึงข้อความแชททั้งหมดของ user จาก Firebase
  Future<List<Map<String, dynamic>>> getUserChatMessages() async {
    if (_db == null || _user == null) return [];
    try {
      final snapshot = await _db!
          .collection('users')
          .doc(_user!.uid)
          .collection('chats')
          .orderBy('time', descending: false)
          .get();
      
      final messages = snapshot.docs.map((doc) => doc.data()).toList();
      debugPrint('[Firebase] 📥 Fetched ${messages.length} chat messages');
      return messages;
    } catch (e) {
      debugPrint('[Firebase] ❌ Error fetching user chat messages: $e');
      return [];
    }
  }

  /// 🔄 Sync ข้อความที่ pending ขึ้น Firebase
  Future<int> syncPendingMessages(List<Map<String, dynamic>> pendingMessages) async {
    if (_db == null || _user == null) return 0;
    
    int syncedCount = 0;
    for (final msg in pendingMessages) {
      final success = await syncChatMessageToCloud(msg);
      if (success) syncedCount++;
    }
    
    debugPrint('[Firebase] 🔄 Synced $syncedCount/${pendingMessages.length} messages');
    return syncedCount;
  }

  /// 🗑️ ลบข้อความเดียวจาก Firebase
  Future<bool> deleteChatMessage(String userId, String messageId) async {
    if (_db == null) return false;
    try {
      await _db!
          .collection('users')
          .doc(userId)
          .collection('chats')
          .doc(messageId)
          .delete();
      
      debugPrint('[Firebase] 🗑️ Deleted message: $messageId');
      return true;
    } catch (e) {
      debugPrint('[Firebase] ❌ Error deleting message: $e');
      return false;
    }
  }

  /// 🗑️ ลบข้อความแชททั้งหมดของ user จาก Firebase
  Future<bool> clearUserChatMessages() async {
    if (_db == null || _user == null) return false;
    try {
      final snapshot = await _db!
          .collection('users')
          .doc(_user!.uid)
          .collection('chats')
          .get();
      
      final batch = _db!.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      
      debugPrint('[Firebase] 🗑️ Cleared all user chat messages');
      return true;
    } catch (e) {
      debugPrint('[Firebase] ❌ Error clearing chat messages: $e');
      return false;
    }
  }

  @override
  void dispose() {
    _connSub?.cancel();
    super.dispose();
  }
}

// ✅ singleton ให้ไฟล์อื่นเรียกใช้
final firebaseService = FirebaseService();
