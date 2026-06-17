// lib/cloud/firebase_service.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/friend_models.dart';
import 'package:offgrid_sos/core/logger.dart';

String _friendlyAuthError(Object e) {
  if (e is fa.FirebaseAuthException) {
    switch (e.code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'อีเมลหรือรหัสผ่านไม่ถูกต้อง';
      case 'invalid-email':
        return 'รูปแบบอีเมลไม่ถูกต้อง';
      case 'user-disabled':
        return 'บัญชีนี้ถูกระงับการใช้งาน';
      case 'email-already-in-use':
        return 'อีเมลนี้ถูกใช้สมัครสมาชิกแล้ว';
      case 'weak-password':
        return 'รหัสผ่านไม่ปลอดภัยพอ กรุณาตั้งรหัสผ่านที่ยาวขึ้น';
      case 'too-many-requests':
        return 'พยายามเข้าสู่ระบบบ่อยเกินไป กรุณาลองใหม่อีกครั้งในภายหลัง';
      case 'network-request-failed':
        return 'เชื่อมต่ออินเทอร์เน็ตไม่ได้ กรุณาตรวจสอบการเชื่อมต่อ';
      default:
        return 'เข้าสู่ระบบไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
    }
  }
  return 'เข้าสู่ระบบไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
}

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
    // เช็คสถานะเน็ตปัจจุบันทันที (onConnectivityChanged จะยิงเฉพาะตอนเน็ต "เปลี่ยน"
    // เท่านั้น ถ้าเน็ตต่ออยู่แล้วตั้งแต่แอพเปิด เช่นบน Emulator อาจไม่มี event ยิงเลย
    // ทำให้ _online ค้างเป็น false ตลอด)
    try {
      final initialResult = await Connectivity().checkConnectivity();
      _online = initialResult.isNotEmpty && !initialResult.contains(ConnectivityResult.none);
    } catch (e) {
      Log.d('[Connectivity] checkConnectivity failed: $e');
    }

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
      Log.d('[Firebase] init failed: $e');
      _initialized = false; // ยังให้แอพทำงานออฟไลน์ได้
      notifyListeners();
      return;
    }

    try {
      _db = FirebaseFirestore.instance;
      _db!.settings = const Settings(persistenceEnabled: true);
    } catch (e) {
      Log.d('[Firestore] not ready: $e');
    }

    try {
      fa.FirebaseAuth.instance.authStateChanges().listen((u) {
        _user = u;
        notifyListeners();
      });
    } catch (e) {
      Log.d('[Auth] not ready: $e');
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
      return _friendlyAuthError(e);
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
      return _friendlyAuthError(e);
    }
  }

  Future<void> signOut() async {
    if (!_initialized) return;
    // [Fix 2] ตั้งสถานะออฟไลน์ก่อน sign out
    if (_user != null && _db != null) {
      try {
        await updateOnlineStatus(_user!.uid, false);
      } catch (e) {
        Log.d('[Firebase] ⚠️ Error set offline before signout: $e');
      }
    }
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
      Log.d('[Firebase] ❌ Database ไม่พร้อม');
      return null;
    }
    try {
      Log.d('[Firebase] 🔍 กำลังค้นหา User ID: $userId ${forceRefresh ? "(force reload)" : ""}');
      
      // Force reload from server (ไม่ใช้ cache)
      final source = forceRefresh ? Source.server : Source.serverAndCache;
      final doc = await _db!.collection('users').doc(userId).get(GetOptions(source: source));
      
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        Log.d('[Firebase] ✅ พบผู้ใช้: ${data['name']}, isOnline: ${data['isOnline']}');
        return UserProfile.fromJson(data);
      } else {
        Log.d('[Firebase] ❌ ไม่พบผู้ใช้ ID: $userId');
      }
    } catch (e) {
      Log.d('[Firebase] ❌ Error finding user: $e');
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
      Log.d('[Firebase] Error finding user by email: $e');
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
      Log.d('[Firebase] Error searching users: $e');
      return [];
    }
  }

  /// อัพเดทสถานะออนไลน์
  Future<void> updateOnlineStatus(String userId, bool isOnline) async {
    if (_db == null) {
      Log.d('[Firebase] ⚠️ Database ไม่พร้อม - ไม่สามารถอัปเดตสถานะออนไลน์');
      return;
    }
    try {
      Log.d('[Firebase] 🔄 อัปเดตสถานะออนไลน์: $userId → ${isOnline ? "ออนไลน์" : "ออฟไลน์"}');
      
      // ใช้ set พร้อม merge: true เพื่อสร้าง document ถ้ายังไม่มี หรืออัปเดตถ้ามีแล้ว
      await _db!.collection('users').doc(userId).set({
        'isOnline': isOnline,
        'lastActiveAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
      
      Log.d('[Firebase] ✅ อัปเดตสถานะออนไลน์สำเร็จ');
      
      // ตรวจสอบว่าข้อมูลบันทึกจริงหรือไม่ (แสดง log เฉพาะตอน init)
      // final verify = await _db!.collection('users').doc(userId).get(GetOptions(source: Source.server));
      // if (verify.exists) {
      //   final data = verify.data();
      //   Log.d('[Firebase] 🔍 ตรวจสอบข้อมูล: isOnline = ${data?['isOnline']}, lastActiveAt = ${data?['lastActiveAt']}');
      // } else {
      //   Log.d('[Firebase] ⚠️ ไม่พบ document หลังบันทึก!');
      // }
    } catch (e, stackTrace) {
      Log.d('[Firebase] ❌ Error updating online status: $e');
      Log.d('[Firebase] ❌ Stack trace: $stackTrace');
      rethrow;
    }
  }

  // ========== Friend Requests Management ==========

  /// ส่งคำขอเป็นเพื่อน
  Future<bool> sendFriendRequest(FriendRequest request) async {
    if (_db == null) return false;
    try {
      Log.d('[Firebase] 📤 ส่งคำขอ: ${request.id}');
      Log.d('[Firebase]   - จาก: ${request.fromUserName} (${request.fromUserId})');
      Log.d('[Firebase]   - ไปยัง: ${request.toUserId}');
      
      await _db!.collection('friend_requests').doc(request.id).set(request.toJson());
      
      Log.d('[Firebase] ✅ บันทึกคำขอลง Firebase สำเร็จ');
      return true;
    } catch (e) {
      Log.d('[Firebase] ❌ Error sending friend request: $e');
      return false;
    }
  }

  /// ดึงคำขอเป็นเพื่อนที่ได้รับ
  Future<List<FriendRequest>> getReceivedFriendRequests(String userId) async {
    if (_db == null) return [];
    try {
      Log.d('[Firebase] 🔍 ดึงคำขอสำหรับ: $userId');
      
      final query = await _db!
          .collection('friend_requests')
          .where('toUserId', isEqualTo: userId)
          .where('status', isEqualTo: 'pending')
          .get();
      
      final requests = query.docs
          .map((doc) => FriendRequest.fromJson(doc.data()))
          .toList();
      
      Log.d('[Firebase] ✅ พบ ${requests.length} คำขอที่รอการตอบรับ');
      for (final req in requests) {
        Log.d('[Firebase]   - จาก: ${req.fromUserName} (${req.fromUserId})');
      }
      
      return requests;
    } catch (e) {
      Log.d('[Firebase] ❌ Error getting friend requests: $e');
      return [];
    }
  }

  /// ตอบรับ/ปฏิเสธคำขอเป็นเพื่อน
  Future<bool> respondToFriendRequest(String requestId, bool accept) async {
    if (_db == null) return false;
    try {
      Log.d('[Firebase] 🔄 กำลังตอบรับคำขอ: $requestId (accept=$accept)');
      
      // ดึงข้อมูลคำขอก่อน
      final requestDoc = await _db!.collection('friend_requests').doc(requestId).get();
      if (!requestDoc.exists) {
        Log.d('[Firebase] ⚠️ ไม่พบคำขอ: $requestId');
        return false;
      }
      
      final requestData = requestDoc.data()!;
      final fromUserId = requestData['fromUserId'];
      final toUserId = requestData['toUserId'];
      
      if (accept) {
        // ⚠️ Security rules อนุญาตให้เขียนได้แค่ subcollection ของตัวเอง (auth.uid == userId)
        // ผู้ที่กดรับคำขอคือ toUserId เท่านั้น จึงเพิ่มเพื่อนได้แค่ฝั่งตัวเอง
        // ฝั่ง fromUserId จะเพิ่มเพื่อนของตัวเองตอน sync ครั้งถัดไป (ดู FriendService.syncWithFirebase)
        await _addFriendToUserList(toUserId, fromUserId);
        Log.d('[Firebase] ✅ เพิ่มเพื่อนให้ผู้รับ ($toUserId)');

        // mark accepted แทนการลบทันที เพื่อให้ผู้ส่งคำขอ sync แล้วเพิ่มเพื่อนของตัวเองได้
        await _db!.collection('friend_requests').doc(requestId).set(
          {'status': 'accepted'},
          SetOptions(merge: true),
        );
        Log.d('[Firebase] ✅ บันทึกสถานะ accepted (รอผู้ส่ง sync เพื่อเพิ่มเพื่อนฝั่งตัวเอง)');
      } else {
        await _db!.collection('friend_requests').doc(requestId).delete();
        Log.d('[Firebase] 🗑️ ลบคำขอออกจาก Firebase แล้ว (rejected)');
      }

      return true;
    } catch (e) {
      Log.d('[Firebase] ❌ Error responding to friend request: $e');
      return false;
    }
  }

  /// เพิ่มเพื่อนเข้าลิสต์ของผู้ใช้
  Future<void> _addFriendToUserList(String userId, String friendUserId) async {
    if (_db == null) return;
    try {
      Log.d('[Firebase] 🔄 กำลังเพิ่มเพื่อน');
      Log.d('[Firebase]   - ให้ผู้ใช้: $userId');
      Log.d('[Firebase]   - เพิ่มเพื่อน: $friendUserId');
      
      // ดึงข้อมูลของเพื่อน
      final friendDoc = await _db!.collection('users').doc(friendUserId).get();
      if (!friendDoc.exists) {
        Log.d('[Firebase] ⚠️ ไม่พบข้อมูลผู้ใช้: $friendUserId');
        return;
      }
      
      final friendData = friendDoc.data()!;
      Log.d('[Firebase] ✅ พบข้อมูลเพื่อน: ${friendData['name']} (ID: ${friendData['id']})');
      
      final friend = Friend(
        id: 'friend_${userId}_$friendUserId',
        name: friendData['name'],
        userId: friendUserId, // 🔥 สำคัญ: userId ของเพื่อน
        avatar: friendData['avatar'],
        addedAt: DateTime.now(),
        lastSeen: DateTime.parse(friendData['lastActiveAt'] ?? DateTime.now().toIso8601String()),
        isOnline: friendData['isOnline'] ?? false,
      );

      Log.d('[Firebase] 💾 บันทึกเพื่อน: ${friend.name} (userId: ${friend.userId}) -> ลง collection ของ user $userId');
      
      await _db!
          .collection('users')
          .doc(userId)
          .collection('friends')
          .doc(friendUserId)
          .set(friend.toJson());
      
      Log.d('[Firebase] ✅ เพิ่มเพื่อนสำเร็จ');
    } catch (e, stackTrace) {
      Log.d('[Firebase] ❌ Error adding friend to user list: $e');
      Log.d('[Firebase] ❌ Stack trace: $stackTrace');
      rethrow; // throw ต่อเพื่อให้รู้ว่า error จริงๆ
    }
  }

  /// ดึงคำขอที่เราส่งไปแล้วถูกอีกฝั่งกดรับ (status=accepted)
  /// ใช้เพื่อให้ผู้ส่งคำขอเพิ่มเพื่อนของตัวเองได้ (เขียนได้แค่ subcollection ของตัวเองตาม security rules)
  Future<List<Map<String, dynamic>>> getAcceptedSentRequests(String userId) async {
    if (_db == null) return [];
    try {
      final query = await _db!
          .collection('friend_requests')
          .where('fromUserId', isEqualTo: userId)
          .where('status', isEqualTo: 'accepted')
          .get();

      return query.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
    } catch (e) {
      Log.d('[Firebase] ❌ Error getting accepted sent requests: $e');
      return [];
    }
  }

  /// เพิ่มเพื่อนฝั่งผู้ส่งคำขอ (หลังอีกฝั่งกดรับแล้ว) และลบคำขอทิ้ง
  Future<void> completeAcceptedRequest(String requestId, String userId, String friendUserId) async {
    if (_db == null) return;
    try {
      await _addFriendToUserList(userId, friendUserId);
      await _db!.collection('friend_requests').doc(requestId).delete();
      Log.d('[Firebase] ✅ เพิ่มเพื่อนฝั่งผู้ส่งสำเร็จ และลบคำขอแล้ว: $friendUserId');
    } catch (e) {
      Log.d('[Firebase] ❌ Error completing accepted request: $e');
    }
  }

  /// ดึงรายชื่อเพื่อนจาก Firebase
  Future<List<Friend>> getUserFriends(String userId) async {
    if (_db == null) return [];
    try {
      Log.d('[Firebase] 🔍 กำลังดึงเพื่อนของ: $userId');
      final query = await _db!
          .collection('users')
          .doc(userId)
          .collection('friends')
          .get();
      
      final friends = query.docs
          .map((doc) => Friend.fromJson(doc.data()))
          .toList();
      
      Log.d('[Firebase] ✅ พบเพื่อน: ${friends.length} คน');
      for (final friend in friends) {
        Log.d('[Firebase]   - ${friend.name} (${friend.userId})');
      }
      
      return friends;
    } catch (e) {
      Log.d('[Firebase] ❌ Error getting user friends: $e');
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
      Log.d('[Firebase] Error removing friend: $e');
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
      
      Log.d('[Firebase] 💬 บันทึกข้อความ');
      Log.d('[Firebase]   - Chat ID: $chatId');
      Log.d('[Firebase]   - Message ID: $msgId');
      Log.d('[Firebase]   - จาก: $fromUserId');
      Log.d('[Firebase]   - ถึง: $toUserId');
      Log.d('[Firebase]   - ข้อความ: $text');
      
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
      
      Log.d('[Firebase] ✅ บันทึกข้อความสำเร็จ');
    } catch (e) {
      Log.d('[Firebase] ❌ Error saving friend chat message: $e');
    }
  }

  /// ดึงข้อความแชทกับเพื่อน
  Future<List<Map<String, dynamic>>> getFriendChatMessages(String user1Id, String user2Id) async {
    if (_db == null) return [];
    try {
      final chatId = _generateChatId(user1Id, user2Id);
      Log.d('[Firebase] 🔍 ดึงข้อความ Chat ID: $chatId');
      
      final query = await _db!
          .collection('friend_chats')
          .doc(chatId)
          .collection('messages')
          .orderBy('time', descending: false)
          .get();
      
      Log.d('[Firebase] ✅ พบ ${query.docs.length} ข้อความ');
      
      return query.docs.map((doc) {
        final data = doc.data();
        // ใช้ id จาก document ถ้ามี ไม่งั้นใช้ document ID
        data['id'] = data['id'] ?? doc.id;
        return data;
      }).toList();
    } catch (e) {
      Log.d('[Firebase] ❌ Error getting friend chat messages: $e');
      return [];
    }
  }

  /// Real-time stream ข้อความแชทกับเพื่อน — ใช้แทน polling
  Stream<List<Map<String, dynamic>>> streamFriendChatMessages(
      String user1Id, String user2Id) {
    if (_db == null) return const Stream.empty();
    final chatId = _generateChatId(user1Id, user2Id);
    return _db!
        .collection('friend_chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('time', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              data['id'] = data['id'] ?? doc.id;
              return data;
            }).toList());
  }

  /// Stream ข้อความขาเข้าจากเพื่อนคนนึง (fromUserId == friendUserId) ที่มาหลัง since
  /// ใช้โดย global inbox listener เพื่อแจ้งเตือนแม้ไม่ได้อยู่ใน chat screen
  Stream<List<Map<String, dynamic>>> streamIncomingMessagesFromFriend(
      String currentUserId, String friendUserId, Timestamp since) {
    if (_db == null) return const Stream.empty();
    final chatId = _generateChatId(currentUserId, friendUserId);
    return _db!
        .collection('friend_chats')
        .doc(chatId)
        .collection('messages')
        .where('fromUserId', isEqualTo: friendUserId)
        .where('time', isGreaterThan: since)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              data['id'] = data['id'] ?? doc.id;
              return data;
            }).toList());
  }

  /// ลบข้อความแชทกับเพื่อนทั้งหมดออกจาก Firestore
  /// ลบทีละ batch เพื่อไม่เกิน Firestore limit (500 writes/batch)
  Future<void> deleteFriendChatMessages(String user1Id, String user2Id) async {
    if (_db == null) return;
    try {
      final chatId = _generateChatId(user1Id, user2Id);
      final col = _db!
          .collection('friend_chats')
          .doc(chatId)
          .collection('messages');

      QuerySnapshot snapshot;
      do {
        snapshot = await col.limit(400).get();
        if (snapshot.docs.isEmpty) break;
        final batch = _db!.batch();
        for (final doc in snapshot.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      } while (snapshot.docs.length == 400);

      Log.d('[Firebase] 🗑️ ลบข้อความแชทกับ friend สำเร็จ (chatId: $chatId)');
    } catch (e) {
      Log.d('[Firebase] ❌ Error deleting friend chat: $e');
      rethrow;
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
      Log.d('[Firebase] Error getting all chat messages: $e');
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
      Log.d('[Firebase] ✅ Saved chat message: ${message['id']}');
      return true;
    } catch (e) {
      Log.d('[Firebase] ❌ Error saving chat message: $e');
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
      Log.d('[Firebase] 📥 Fetched ${messages.length} chat messages');
      return messages;
    } catch (e) {
      Log.d('[Firebase] ❌ Error fetching user chat messages: $e');
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
    
    Log.d('[Firebase] 🔄 Synced $syncedCount/${pendingMessages.length} messages');
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
      
      Log.d('[Firebase] 🗑️ Deleted message: $messageId');
      return true;
    } catch (e) {
      Log.d('[Firebase] ❌ Error deleting message: $e');
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
      
      Log.d('[Firebase] 🗑️ Cleared all user chat messages');
      return true;
    } catch (e) {
      Log.d('[Firebase] ❌ Error clearing chat messages: $e');
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
