// lib/core/friend_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'friend_models.dart';
import 'friend_db.dart';
import '../cloud/firebase_service.dart';

class FriendService extends ChangeNotifier {
  final List<Friend> _friends = [];
  final List<FriendRequest> _friendRequests = [];
  UserProfile? _currentUser;
  bool _isLoading = false;
  Timer? _syncTimer; // เพิ่ม timer สำหรับ auto sync

  // Getters
  List<Friend> get friends => List.unmodifiable(_friends);
  List<FriendRequest> get friendRequests => List.unmodifiable(_friendRequests);
  UserProfile? get currentUser => _currentUser;
  bool get isLoading => _isLoading;

  // Online friends
  List<Friend> get onlineFriends => _friends.where((f) => f.isOnline).toList();
  
  // Friends with unread messages
  List<Friend> get friendsWithUnreadMessages => _friends.where((f) => f.unreadCount > 0).toList();

  // Total unread count
  int get totalUnreadCount => _friends.fold(0, (sum, f) => sum + f.unreadCount);

  /// Initialize the service
  Future<void> init() async {
    _setLoading(true);
    
    // โหลดข้อมูลผู้ใช้
    await _loadCurrentUser();
    
    // 🔥 ตั้งสถานะออนไลน์ทันทีหลังโหลดโปรไฟล์ (ก่อน sync)
    if (_currentUser != null && firebaseService.isOnline && firebaseService.isSignedIn) {
      debugPrint('[FriendService] ✅ ตั้งสถานะออนไลน์หลัง login สำหรับ: ${_currentUser!.name} (${_currentUser!.id})');
      
      try {
        await firebaseService.updateOnlineStatus(_currentUser!.id, true);
        debugPrint('[FriendService] ✅ ตั้งสถานะออนไลน์สำเร็จ');
        
        // ⏱️ รอให้ Firebase propagate ข้อมูล (1 วินาที)
        debugPrint('[FriendService] ⏱️ รอให้ Firebase อัปเดตข้อมูล (1 วินาที)...');
        await Future.delayed(const Duration(milliseconds: 1000));
        debugPrint('[FriendService] ✅ พร้อม sync แล้ว');
      } catch (e) {
        debugPrint('[FriendService] ❌ Error ตั้งสถานะออนไลน์: $e');
      }
    }
    
    // โหลดเพื่อนจากฐานข้อมูลท้องถิ่น
    await _loadLocalFriends();
    debugPrint('[FriendService] 📱 โหลดเพื่อนจาก Local: ${_friends.length} คน');
    
    // โหลดคำขอเป็นเพื่อนจากฐานข้อมูลท้องถิ่น
    await _loadLocalFriendRequests();
    debugPrint('[FriendService] 📱 โหลดคำขอจาก Local: ${_friendRequests.length} รายการ');
    
    // Sync กับ Firebase หากออนไลน์ (บังคับทุกครั้งเพื่อให้ข้อมูลถูกต้อง)
    if (firebaseService.isOnline && firebaseService.isSignedIn) {
      debugPrint('[FriendService] 🔄 เริ่ม sync กับ Firebase...');
      await syncWithFirebase();
      debugPrint('[FriendService] ✅ sync เสร็จสิ้น: เพื่อน=${_friends.length} คน, คำขอ=${_friendRequests.length} รายการ');
      
      // ✨ เพิ่ม: เปิด auto sync ทุก 30 วินาที
      _startAutoSync();
    } else {
      debugPrint('[FriendService] ⚠️ ไม่สามารถ sync: Online=${firebaseService.isOnline}, SignedIn=${firebaseService.isSignedIn}');
    }
    
    _setLoading(false);
  }

  /// เริ่ม auto sync ทุก 10 วินาที
  void _startAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (firebaseService.isOnline && firebaseService.isSignedIn) {
        debugPrint('[FriendService] 🔄 Auto sync...');
        await syncWithFirebase();
      }
    });
  }

  /// หยุด auto sync
  void stopAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  @override
  void dispose() {
    stopAutoSync();
    super.dispose();
  }

  /// โหลดข้อมูลผู้ใช้ปัจจุบัน
  Future<void> _loadCurrentUser() async {
    try {
      // ตรวจสอบว่า login Firebase หรือไม่
      final firebaseUser = firebaseService.currentUser;
      
      if (firebaseUser != null && firebaseUser.email != null && firebaseService.isOnline) {
        // ✅ ใช้ Firebase UID เป็น User ID (ไม่เปลี่ยนแปลง!)
        final userId = firebaseUser.uid;
        debugPrint('[FriendService] 🔑 Firebase UID: $userId');
        
        // ลองดึงโปรไฟล์จาก Firebase ด้วย UID
        try {
          final existingProfile = await firebaseService.findUserByUserId(userId);
          
          if (existingProfile != null) {
            // พบโปรไฟล์เดิมใน Firebase แล้ว
            _currentUser = existingProfile;
            await FriendDB.saveUserProfile(_currentUser!);
            debugPrint('[FriendService] ✅ โหลดโปรไฟล์เดิมจาก Firebase: ${_currentUser!.id}');
            return;
          } else {
            debugPrint('[FriendService] ⚠️ ไม่พบโปรไฟล์ใน Firebase กำลังสร้างใหม่');
          }
        } catch (e) {
          debugPrint('[FriendService] ⚠️ Error loading user from Firebase: $e');
        }
        
        // ถ้าไม่พบใน Firebase ให้สร้างใหม่ด้วย Firebase UID
        final displayName = firebaseUser.displayName ?? 'ผู้ใช้ ${DateTime.now().millisecondsSinceEpoch % 1000}';
        _currentUser = UserProfile(
          id: userId, // ✅ ใช้ Firebase UID ตรงๆ
          name: displayName,
          email: firebaseUser.email,
          createdAt: DateTime.now(),
          lastActiveAt: DateTime.now(),
        );
        await FriendDB.saveUserProfile(_currentUser!);
        debugPrint('[FriendService] ✨ สร้างโปรไฟล์ใหม่ด้วย Firebase UID: ${_currentUser!.id}');
        
        // บันทึกขึ้น Firebase ทันทีถ้า login แล้ว
        try {
          await firebaseService.saveFullUserProfile(_currentUser!);
          debugPrint('[FriendService] ☁️ บันทึกโปรไฟล์ขึ้น Firebase แล้ว');
        } catch (e) {
          debugPrint('[FriendService] ⚠️ Error saving to Firebase: $e');
        }
        return;
      }
      
      // ถ้าไม่ได้ login ให้ดึงจาก local
      _currentUser = await FriendDB.getUserProfile();
      
      if (_currentUser == null) {
        // สร้างโปรไฟล์แบบออฟไลน์ (ใช้ ID สุ่ม)
        _currentUser = UserProfile(
          id: FriendDB.generateUserId(),
          name: 'ผู้ใช้ ${DateTime.now().millisecondsSinceEpoch % 1000}',
          createdAt: DateTime.now(),
          lastActiveAt: DateTime.now(),
        );
        await FriendDB.saveUserProfile(_currentUser!);
        debugPrint('[FriendService] 📱 สร้างโปรไฟล์แบบออฟไลน์: ${_currentUser!.id}');
      } else {
        debugPrint('[FriendService] 📱 ใช้โปรไฟล์จาก Local: ${_currentUser!.id}');
      }
    } catch (e) {
      debugPrint('[FriendService] ❌ Fatal error in _loadCurrentUser: $e');
      // สร้าง fallback profile
      _currentUser = UserProfile(
        id: FriendDB.generateUserId(),
        name: 'ผู้ใช้ ${DateTime.now().millisecondsSinceEpoch % 1000}',
        createdAt: DateTime.now(),
        lastActiveAt: DateTime.now(),
      );
      await FriendDB.saveUserProfile(_currentUser!);
    }
  }

  /// โหลดเพื่อนจากฐานข้อมูลท้องถิ่น
  Future<void> _loadLocalFriends() async {
    final localFriends = await FriendDB.getFriends();
    _friends.clear();
    _friends.addAll(localFriends);
  }

  /// โหลดคำขอเป็นเพื่อนจากฐานข้อมูลท้องถิ่น
  Future<void> _loadLocalFriendRequests() async {
    final localRequests = await FriendDB.getFriendRequests();
    _friendRequests.clear();
    _friendRequests.addAll(localRequests);
  }

  /// Sync ข้อมูลกับ Firebase
  Future<void> syncWithFirebase() async {
    if (!firebaseService.isOnline || !firebaseService.isSignedIn || _currentUser == null) {
      debugPrint('[FriendService] ⚠️ ไม่สามารถ sync: Online=${firebaseService.isOnline}, SignedIn=${firebaseService.isSignedIn}, User=${_currentUser != null}');
      return;
    }

    try {
      // อัพเดทโปรไฟล์บน Firebase (บังคับทุกครั้ง)
      debugPrint('[FriendService] 🔄 กำลัง sync โปรไฟล์: ID=${_currentUser!.id}, Name=${_currentUser!.name}');
      await firebaseService.saveFullUserProfile(_currentUser!);
      debugPrint('[FriendService] ✅ sync โปรไฟล์สำเร็จ');
      
      // ดึงเพื่อนจาก Firebase
      final firebaseFriends = await firebaseService.getUserFriends(_currentUser!.id);
      
      // ผสานข้อมูลเพื่อนจาก Firebase กับท้องถิ่น
      for (final friend in firebaseFriends) {
        final existingIndex = _friends.indexWhere((f) => f.userId == friend.userId);
        if (existingIndex >= 0) {
          // อัพเดทข้อมูลเพื่อนที่มีอยู่
          _friends[existingIndex] = friend;
        } else {
          // เพิ่มเพื่อนใหม่
          _friends.add(friend);
        }
      }
      
      // 🔥 อัปเดตสถานะออนไลน์ของเพื่อนทุกคน
      await _updateFriendsOnlineStatus();
      
      // บันทึกเพื่อนลงฐานข้อมูลท้องถิ่น
      await FriendDB.saveFriends(_friends);
      
      // ดึงคำขอเป็นเพื่อนจาก Firebase (แค่ที่ส่งมาหาเราเท่านั้น)
      debugPrint('[FriendService] 📥 กำลังดึงคำขอที่ส่งมาหา: ${_currentUser!.id}');
      final firebaseRequests = await firebaseService.getReceivedFriendRequests(_currentUser!.id);
      debugPrint('[FriendService] ✅ ได้รับ ${firebaseRequests.length} คำขอจาก Firebase');
      
      // 🔥 สำคัญ: ล้างคำขอเก่าทั้ง local และ memory
      _friendRequests.clear();
      await FriendDB.clearFriendRequests(); // ล้างใน local storage ด้วย
      debugPrint('[FriendService] 🗑️ ล้างคำขอเก่าออกจาก local');
      
      // ผสานข้อมูลคำขอจาก Firebase
      for (final request in firebaseRequests) {
        // ตรวจสอบอีกครั้งว่าคำขอนี้ส่งมาหาเราจริงๆ และเป็น pending
        // ⭐ และไม่ใช่คนที่เป็นเพื่อนอยู่แล้ว (ป้องกันคำขอซ้ำ)
        final isAlreadyFriend = _friends.any((f) => f.userId == request.fromUserId);
        if (request.toUserId == _currentUser!.id && 
            request.status == FriendRequestStatus.pending &&
            !isAlreadyFriend) {
          _friendRequests.add(request);
          debugPrint('[FriendService] ➕ เพิ่มคำขอจาก: ${request.fromUserName} (ID: ${request.id})');
        } else if (isAlreadyFriend) {
          debugPrint('[FriendService] ⏭️ ข้าม: ${request.fromUserName} (เป็นเพื่อนอยู่แล้ว)');
        }
      }
      
      // บันทึกคำขอลงฐานข้อมูลท้องถิ่น
      await FriendDB.saveFriendRequests(_friendRequests);
      debugPrint('[FriendService] 💾 บันทึก ${_friendRequests.length} คำขอลง Local');
      
      // 🔍 Debug: แสดงจำนวนเพื่อนออนไลน์
      final onlineCount = _friends.where((f) => f.isOnline).length;
      debugPrint('[FriendService] 📊 สรุป: เพื่อนทั้งหมด ${_friends.length} คน, ออนไลน์ $onlineCount คน');
      for (final friend in _friends) {
        debugPrint('[FriendService]   - ${friend.name}: ${friend.isOnline ? "🟢 ออนไลน์" : "⚪ ออฟไลน์"}');
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('[FriendService] Error syncing with Firebase: $e');
    }
  }

  /// อัปเดตสถานะออนไลน์ของเพื่อนทุกคน
  Future<void> _updateFriendsOnlineStatus() async {
    debugPrint('[FriendService] 🔄 กำลังอัปเดตสถานะออนไลน์ของเพื่อน ${_friends.length} คน...');
    
    for (int i = 0; i < _friends.length; i++) {
      try {
        // ดึงโปรไฟล์เพื่อนจาก Firebase เพื่อเช็คสถานะออนไลน์ (force reload จาก server)
        final friendProfile = await firebaseService.findUserByUserId(_friends[i].userId, forceRefresh: true);
        if (friendProfile != null) {
          // อัปเดตสถานะออนไลน์
          final oldStatus = _friends[i].isOnline;
          _friends[i] = _friends[i].copyWith(isOnline: friendProfile.isOnline);
          
          if (oldStatus != friendProfile.isOnline) {
            debugPrint('[FriendService] 🔄 ${_friends[i].name}: ${oldStatus ? "ออนไลน์" : "ออฟไลน์"} → ${friendProfile.isOnline ? "ออนไลน์" : "ออฟไลน์"}');
          }
        }
      } catch (e) {
        debugPrint('[FriendService] ⚠️ Error updating status for ${_friends[i].name}: $e');
      }
    }
    
    debugPrint('[FriendService] ✅ อัปเดตสถานะออนไลน์เสร็จสิ้น');
    // แจ้ง UI ให้อัปเดต
    notifyListeners();
  }

  /// ค้นหาผู้ใช้เพื่อเพิ่มเป็นเพื่อน (ค้นหาจาก User ID หรือชื่อ)
  Future<List<UserProfile>> searchUsers(String query) async {
    debugPrint('[FriendService] 🔍 เริ่มค้นหา: "$query"');
    
    if (!firebaseService.isOnline) {
      debugPrint('[FriendService] ❌ ไม่มีอินเทอร์เน็ต');
      return [];
    }
    
    if (!firebaseService.isSignedIn) {
      debugPrint('[FriendService] ❌ ยังไม่ได้ login');
      return [];
    }

    try {
      List<UserProfile> users = [];
      
      // ถ้า query เป็นตัวอักษรใหญ่และตัวเลข (เช่น A7X2M9) → ค้นหาจาก User ID
      final isUserId = RegExp(r'^[A-Z0-9]{4,8}$').hasMatch(query);
      debugPrint('[FriendService] รูปแบบการค้นหา: ${isUserId ? "User ID" : "ชื่อ"}');
      
      if (isUserId) {
        // ค้นหาจาก User ID โดยตรง
        final user = await firebaseService.findUserByUserId(query);
        if (user != null) {
          users = [user];
          debugPrint('[FriendService] ✅ พบ 1 ผู้ใช้');
        } else {
          debugPrint('[FriendService] ❌ ไม่พบผู้ใช้ด้วย ID นี้');
        }
      } else {
        // ค้นหาจากชื่อ
        users = await firebaseService.searchUsersByName(query);
        debugPrint('[FriendService] ✅ พบ ${users.length} ผู้ใช้จากชื่อ');
      }
      
      // กรองผู้ใช้ที่เป็นตัวเองและเพื่อนที่มีอยู่แล้วออก
      final filtered = users.where((user) {
        return user.id != _currentUser?.id && !_friends.any((f) => f.userId == user.id);
      }).toList();
      
      debugPrint('[FriendService] ✅ ผลลัพธ์หลังกรอง: ${filtered.length} ผู้ใช้');
      return filtered;
    } catch (e) {
      debugPrint('[FriendService] Error searching users: $e');
      return [];
    }
  }

  /// ส่งคำขอเป็นเพื่อน
  Future<bool> sendFriendRequest(UserProfile targetUser, {String? message}) async {
    if (_currentUser == null) return false;

    final request = FriendRequest(
      id: 'req_${_currentUser!.id}_${targetUser.id}_${DateTime.now().millisecondsSinceEpoch}',
      fromUserId: _currentUser!.id,
      toUserId: targetUser.id,
      fromUserName: _currentUser!.name,
      fromUserAvatar: _currentUser!.avatar,
      message: message,
      sentAt: DateTime.now(),
    );

    // ✅ ส่งไปยัง Firebase โดยตรง (ไม่บันทึก local ของผู้ส่ง)
    if (firebaseService.isOnline && firebaseService.isSignedIn) {
      debugPrint('[FriendService] 📤 กำลังส่งคำขอไปหา: ${targetUser.name} (${targetUser.id})');
      final success = await firebaseService.sendFriendRequest(request);
      if (!success) {
        debugPrint('[FriendService] ❌ ส่งคำขอไม่สำเร็จ');
        return false;
      }
      debugPrint('[FriendService] ✅ ส่งคำขอสำเร็จ');
      return true;
    }

    // ถ้าออฟไลน์ ให้บันทึก local ไว้ส่งภายหลัง
    await FriendDB.addFriendRequest(request);
    _friendRequests.add(request);
    notifyListeners();
    debugPrint('[FriendService] 💾 บันทึกคำขอไว้ใน Local (ออฟไลน์)');
    return true;
  }

  /// ตอบรับคำขอเป็นเพื่อน
  Future<bool> acceptFriendRequest(FriendRequest request) async {
    if (_currentUser == null) return false;

    try {
      debugPrint('[FriendService] ✅ เริ่มรับคำขอจาก: ${request.fromUserName}');
      
      // ⭐ ตรวจสอบว่าเป็นเพื่อนอยู่แล้วหรือไม่
      final isAlreadyFriend = _friends.any((f) => f.userId == request.fromUserId);
      if (isAlreadyFriend) {
        debugPrint('[FriendService] ⚠️ ${request.fromUserName} เป็นเพื่อนอยู่แล้ว - ลบคำขอ');
        _friendRequests.removeWhere((r) => r.id == request.id);
        await FriendDB.updateFriendRequestStatus(request.id, FriendRequestStatus.accepted);
        
        // ลบคำขอออกจาก Firebase ด้วย
        if (firebaseService.isOnline && firebaseService.isSignedIn) {
          try {
            await firebaseService.db?.collection('friend_requests').doc(request.id).delete();
          } catch (e) {
            debugPrint('[FriendService] ⚠️ ไม่สามารถลบคำขอจาก Firebase: $e');
          }
        }
        
        notifyListeners();
        return true;
      }
      
      // ส่งไปยัง Firebase ก่อน (จะลบคำขอและเพิ่มเพื่อน 2 ทางใน Firebase)
      if (firebaseService.isOnline && firebaseService.isSignedIn) {
        final success = await firebaseService.respondToFriendRequest(request.id, true);
        if (!success) {
          debugPrint('[FriendService] ❌ ส่งการตอบรับไป Firebase ไม่สำเร็จ');
          return false;
        }
        debugPrint('[FriendService] ✅ ส่งการตอบรับไป Firebase สำเร็จ');
      }
      
      // ลบคำขอออกจาก local
      await FriendDB.updateFriendRequestStatus(request.id, FriendRequestStatus.accepted);
      _friendRequests.removeWhere((r) => r.id == request.id);
      
      // สร้างเพื่อนใหม่ใน local
      final newFriend = Friend(
        id: 'friend_${_currentUser!.id}_${request.fromUserId}',
        name: request.fromUserName,
        userId: request.fromUserId,
        avatar: request.fromUserAvatar,
        addedAt: DateTime.now(),
        lastSeen: DateTime.now(),
      );

      // เพิ่มเพื่อนลงท้องถิ่น
      await FriendDB.addFriend(newFriend);
      _friends.add(newFriend);
      debugPrint('[FriendService] ✅ เพิ่มเพื่อนใน Local แล้ว');

      // 🔥 สำคัญ: Sync กับ Firebase อีกครั้งเพื่อดึงข้อมูลเพื่อนที่ครบถ้วน
      if (firebaseService.isOnline && firebaseService.isSignedIn) {
        debugPrint('[FriendService] 🔄 กำลัง sync ข้อมูลเพื่อนจาก Firebase...');
        await syncWithFirebase();
        debugPrint('[FriendService] ✅ sync เสร็จสมบูรณ์');
      }

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[FriendService] ❌ Error accepting friend request: $e');
      return false;
    }
  }

  /// ปฏิเสธคำขอเป็นเพื่อน
  Future<bool> rejectFriendRequest(FriendRequest request) async {
    try {
      // อัพเดทสถานะคำขอ
      await FriendDB.updateFriendRequestStatus(request.id, FriendRequestStatus.rejected);
      _friendRequests.removeWhere((r) => r.id == request.id);

      // ส่งไปยัง Firebase หากออนไลน์
      if (firebaseService.isOnline && firebaseService.isSignedIn) {
        await firebaseService.respondToFriendRequest(request.id, false);
      }

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[FriendService] Error rejecting friend request: $e');
      return false;
    }
  }

  /// ลบเพื่อน
  Future<bool> removeFriend(Friend friend) async {
    if (_currentUser == null) return false;

    try {
      // ลบจากท้องถิ่น
      await FriendDB.removeFriend(friend.userId);
      _friends.removeWhere((f) => f.userId == friend.userId);

      // ลบจาก Firebase หากออนไลน์
      if (firebaseService.isOnline && firebaseService.isSignedIn) {
        await firebaseService.removeFriend(_currentUser!.id, friend.userId);
      }

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[FriendService] Error removing friend: $e');
      return false;
    }
  }

  /// อัพเดทข้อความสุดท้ายของเพื่อน
  Future<void> updateFriendLastMessage(String friendUserId, String message, DateTime time, {bool incrementUnread = false}) async {
    await FriendDB.updateFriendLastMessage(friendUserId, message, time, incrementUnread: incrementUnread);
    
    final index = _friends.indexWhere((f) => f.userId == friendUserId);
    if (index >= 0) {
      final currentUnread = _friends[index].unreadCount;
      _friends[index] = _friends[index].copyWith(
        lastMessage: message,
        lastMessageTime: time,
        unreadCount: incrementUnread ? currentUnread + 1 : currentUnread,
      );
      notifyListeners();
    }
  }

  /// รีเซ็ตจำนวนข้อความที่ยังไม่อ่าน
  Future<void> markFriendMessagesAsRead(String friendUserId) async {
    await FriendDB.markFriendMessagesAsRead(friendUserId);
    
    final index = _friends.indexWhere((f) => f.userId == friendUserId);
    if (index >= 0) {
      _friends[index] = _friends[index].copyWith(unreadCount: 0);
      notifyListeners();
    }
  }

  /// อัพเดทสถานะออนไลน์ของเพื่อน
  Future<void> updateFriendOnlineStatus(String friendUserId, bool isOnline) async {
    await FriendDB.updateFriendOnlineStatus(friendUserId, isOnline);
    
    final index = _friends.indexWhere((f) => f.userId == friendUserId);
    if (index >= 0) {
      _friends[index] = _friends[index].copyWith(
        isOnline: isOnline,
        lastSeen: DateTime.now(),
      );
      notifyListeners();
    }
  }

  /// อัพเดทโปรไฟล์ผู้ใช้
  Future<void> updateUserProfile(UserProfile updatedProfile) async {
    _currentUser = updatedProfile;
    await FriendDB.saveUserProfile(_currentUser!);
    
    // อัพเดทบน Firebase หากออนไลน์
    if (firebaseService.isOnline && firebaseService.isSignedIn) {
      await firebaseService.saveFullUserProfile(_currentUser!);
    }
    
    notifyListeners();
  }

  /// ตั้งค่าสถานะโหลด
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  /// ค้นหาเพื่อนจาก User ID
  Friend? findFriendByUserId(String userId) {
    try {
      return _friends.firstWhere((f) => f.userId == userId);
    } catch (e) {
      return null;
    }
  }

  /// ตรวจสอบว่าเป็นเพื่อนกันแล้วหรือไม่
  bool isFriend(String userId) {
    return _friends.any((f) => f.userId == userId);
  }

  /// ล้างข้อมูลทั้งหมด (สำหรับออกจากระบบ)
  Future<void> clearAllData() async {
    _friends.clear();
    _friendRequests.clear();
    _currentUser = null;
    await FriendDB.clearAllData();
    notifyListeners();
  }
}

// Singleton instance
final friendService = FriendService();