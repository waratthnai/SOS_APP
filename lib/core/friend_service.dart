// lib/core/friend_service.dart
import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'friend_models.dart';
import 'friend_db.dart';
import '../cloud/firebase_service.dart';
import 'fcm_service.dart';
import 'package:offgrid_sos/core/logger.dart';

class FriendService extends ChangeNotifier with WidgetsBindingObserver {
  final List<Friend> _friends = [];
  final List<FriendRequest> _friendRequests = [];
  UserProfile? _currentUser;
  bool _isLoading = false;
  Timer? _syncTimer;
  StreamSubscription<QuerySnapshot>? _requestsListener;
  StreamSubscription<QuerySnapshot>? _acceptedSentListener;

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
  int get totalUnreadCount => _friends.fold(0, (acc, f) => acc + f.unreadCount);

  /// Initialize the service
  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    _setLoading(true);

    // โหลดข้อมูลผู้ใช้
    await _loadCurrentUser();

    // 🔔 บันทึก FCM token ลง Firestore ตอนนี้ที่รู้ currentUser แล้ว
    // (ตอน FCMService().initialize() ใน main.dart รันก่อนหน้านี้ currentUser ยังเป็น null อยู่)
    if (_currentUser != null && firebaseService.isOnline && firebaseService.isSignedIn) {
      FCMService().syncTokenForCurrentUser().catchError((e) {
        Log.d('[FriendService] ⚠️ Error syncing FCM token: $e');
      });
    }

    // ตั้งสถานะออนไลน์หลังโหลดโปรไฟล์
    if (_currentUser != null && firebaseService.isOnline && firebaseService.isSignedIn) {
      try {
        await firebaseService.updateOnlineStatus(_currentUser!.id, true);
        Log.d('[FriendService] ✅ ตั้งสถานะออนไลน์: ${_currentUser!.name}');
      } catch (e) {
        Log.d('[FriendService] ⚠️ Error ตั้งสถานะออนไลน์: $e');
      }
    }

    // โหลดเพื่อนจากฐานข้อมูลท้องถิ่น
    await _loadLocalFriends();
    Log.d('[FriendService] 📱 โหลดเพื่อนจาก Local: ${_friends.length} คน');

    // โหลดคำขอเป็นเพื่อนจากฐานข้อมูลท้องถิ่น
    await _loadLocalFriendRequests();
    Log.d('[FriendService] 📱 โหลดคำขอจาก Local: ${_friendRequests.length} รายการ');

    // Sync กับ Firebase หากออนไลน์
    if (firebaseService.isOnline && firebaseService.isSignedIn) {
      Log.d('[FriendService] 🔄 เริ่ม sync กับ Firebase...');
      await syncWithFirebase();
      Log.d('[FriendService] ✅ sync เสร็จสิ้น: เพื่อน=${_friends.length} คน, คำขอ=${_friendRequests.length} รายการ');

      _startAutoSync();
      _startRequestsListener(); // [Fix 4] เปิด real-time listener
      _startAcceptedSentListener(); // เปิด real-time listener สำหรับคำขอที่เราส่งไปแล้วถูกรับ
    } else {
      Log.d('[FriendService] ⚠️ ไม่สามารถ sync: Online=${firebaseService.isOnline}, SignedIn=${firebaseService.isSignedIn}');
    }

    _setLoading(false);
  }

  // [Fix 2] ติดตาม app lifecycle เพื่ออัปเดตสถานะออนไลน์
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (_currentUser == null) return;
    if (!firebaseService.isOnline || !firebaseService.isSignedIn) return;

    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      firebaseService.updateOnlineStatus(_currentUser!.id, false).catchError((e) {
        Log.d('[FriendService] ⚠️ Error set offline: $e');
      });
    } else if (state == AppLifecycleState.resumed) {
      firebaseService.updateOnlineStatus(_currentUser!.id, true).catchError((e) {
        Log.d('[FriendService] ⚠️ Error set online: $e');
      });
    }
  }

  /// auto sync ทุก 60 วินาที — ประหยัดแบตเตอรี่สำหรับสถานการณ์ภัยพิบัติ
  void _startAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 60), (timer) async {
      if (firebaseService.isOnline && firebaseService.isSignedIn) {
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
    WidgetsBinding.instance.removeObserver(this);
    stopAutoSync();
    _requestsListener?.cancel();
    _requestsListener = null;
    _acceptedSentListener?.cancel();
    _acceptedSentListener = null;
    super.dispose();
  }

  /// โหลดข้อมูลผู้ใช้ปัจจุบัน — offline-first: ถ้า login อยู่จะใช้ Firebase UID เสมอ
  /// ไม่ว่าจะมีเน็ตหรือไม่ เพื่อรองรับสถานการณ์ภัยพิบัติที่ไม่มีสัญญาณ
  Future<void> _loadCurrentUser() async {
    try {
      final firebaseUser = firebaseService.currentUser;

      if (firebaseUser != null) {
        // ✅ login อยู่ → ใช้ Firebase UID เสมอ ไม่ว่าจะออนไลน์หรือไม่
        final userId = firebaseUser.uid;
        Log.d('[FriendService] 🔑 Firebase UID: $userId');

        // 1️⃣ Local cache ก่อนเสมอ (เร็ว ทำงานได้แม้ไม่มีเน็ต)
        final localProfile = await FriendDB.getUserProfile();
        if (localProfile != null && localProfile.id == userId) {
          _currentUser = localProfile;
          Log.d('[FriendService] ✅ ใช้โปรไฟล์จาก Local Cache (ID ตรง): ${_currentUser!.id}');
          // sync กับ Firebase ใน background ไม่ blocking
          if (firebaseService.isOnline) {
            _syncProfileInBackground();
          }
          return;
        }

        // 2️⃣ local ไม่มีหรือ ID ไม่ตรง (เปลี่ยน account) → ดึงจาก Firebase ถ้าออนไลน์
        if (firebaseService.isOnline) {
          try {
            final remoteProfile = await firebaseService.findUserByUserId(userId);
            if (remoteProfile != null) {
              _currentUser = remoteProfile;
              await FriendDB.saveUserProfile(_currentUser!);
              Log.d('[FriendService] ✅ โหลดโปรไฟล์จาก Firebase: ${_currentUser!.id}');
              return;
            }
          } catch (e) {
            Log.d('[FriendService] ⚠️ Error loading from Firebase: $e');
          }
        }

        // 3️⃣ ออฟไลน์ + ไม่มี local cache → สร้างด้วย Firebase UID (sync ตอนมีเน็ต)
        final displayName = firebaseUser.displayName?.isNotEmpty == true
            ? firebaseUser.displayName!
            : 'ผู้ใช้';
        _currentUser = UserProfile(
          id: userId,
          name: displayName,
          email: firebaseUser.email,
          createdAt: DateTime.now(),
          lastActiveAt: DateTime.now(),
        );
        await FriendDB.saveUserProfile(_currentUser!);
        Log.d('[FriendService] 📱 สร้างโปรไฟล์ด้วย Firebase UID (ออฟไลน์): $userId');

        if (firebaseService.isOnline) {
          try {
            await firebaseService.saveFullUserProfile(_currentUser!);
            Log.d('[FriendService] ☁️ บันทึกโปรไฟล์ใหม่ขึ้น Firebase แล้ว');
          } catch (e) {
            Log.d('[FriendService] ⚠️ Error saving to Firebase: $e');
          }
        }
        return;
      }

      // ไม่ได้ login Firebase → ดึงจาก local (offline mode)
      _currentUser = await FriendDB.getUserProfile();
      if (_currentUser == null) {
        _currentUser = UserProfile(
          id: FriendDB.generateUserId(),
          name: 'ผู้ใช้ ${DateTime.now().millisecondsSinceEpoch % 1000}',
          createdAt: DateTime.now(),
          lastActiveAt: DateTime.now(),
        );
        await FriendDB.saveUserProfile(_currentUser!);
        Log.d('[FriendService] 📱 สร้างโปรไฟล์ออฟไลน์: ${_currentUser!.id}');
      } else {
        Log.d('[FriendService] 📱 ใช้โปรไฟล์จาก Local: ${_currentUser!.id}');
      }
    } catch (e) {
      Log.d('[FriendService] ❌ Fatal error in _loadCurrentUser: $e');
      _currentUser = UserProfile(
        id: FriendDB.generateUserId(),
        name: 'ผู้ใช้',
        createdAt: DateTime.now(),
        lastActiveAt: DateTime.now(),
      );
      await FriendDB.saveUserProfile(_currentUser!);
    }
  }

  /// Sync โปรไฟล์กับ Firebase ใน background ไม่ blocking
  void _syncProfileInBackground() {
    if (_currentUser == null) return;
    firebaseService.findUserByUserId(_currentUser!.id).then((remote) {
      if (remote == null) {
        firebaseService.saveFullUserProfile(_currentUser!).catchError((e) {
          Log.d('[FriendService] ⚠️ Background profile upload error: $e');
        });
      }
    }).catchError((e) {
      Log.d('[FriendService] ⚠️ Background profile sync error: $e');
    });
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
      Log.d('[FriendService] ⚠️ ไม่สามารถ sync: Online=${firebaseService.isOnline}, SignedIn=${firebaseService.isSignedIn}, User=${_currentUser != null}');
      return;
    }

    try {
      // อัพเดทโปรไฟล์บน Firebase (บังคับทุกครั้ง)
      Log.d('[FriendService] 🔄 กำลัง sync โปรไฟล์: ID=${_currentUser!.id}, Name=${_currentUser!.name}');
      await firebaseService.saveFullUserProfile(_currentUser!);
      Log.d('[FriendService] ✅ sync โปรไฟล์สำเร็จ');

      // ⭐ ตรวจสอบคำขอที่เราส่งไปแล้วถูกอีกฝั่งกดรับ → เพิ่มเพื่อนฝั่งเราเอง
      // (อีกฝั่งเขียนได้แค่ subcollection ของตัวเองตาม security rules ตอนกดรับ)
      final acceptedSent = await firebaseService.getAcceptedSentRequests(_currentUser!.id);
      for (final reqData in acceptedSent) {
        final friendUserId = reqData['toUserId'] as String;
        final requestId = reqData['id'] as String;
        await firebaseService.completeAcceptedRequest(requestId, _currentUser!.id, friendUserId);
        Log.d('[FriendService] ✅ คำขอที่ส่งไปถูกรับแล้ว เพิ่มเพื่อน: $friendUserId');
      }

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
      Log.d('[FriendService] 📥 กำลังดึงคำขอที่ส่งมาหา: ${_currentUser!.id}');
      final firebaseRequests = await firebaseService.getReceivedFriendRequests(_currentUser!.id);
      Log.d('[FriendService] ✅ ได้รับ ${firebaseRequests.length} คำขอจาก Firebase');
      
      // 🔥 สำคัญ: ล้างคำขอเก่าทั้ง local และ memory
      _friendRequests.clear();
      await FriendDB.clearFriendRequests(); // ล้างใน local storage ด้วย
      Log.d('[FriendService] 🗑️ ล้างคำขอเก่าออกจาก local');
      
      // ผสานข้อมูลคำขอจาก Firebase
      for (final request in firebaseRequests) {
        // ตรวจสอบอีกครั้งว่าคำขอนี้ส่งมาหาเราจริงๆ และเป็น pending
        // ⭐ และไม่ใช่คนที่เป็นเพื่อนอยู่แล้ว (ป้องกันคำขอซ้ำ)
        final isAlreadyFriend = _friends.any((f) => f.userId == request.fromUserId);
        if (request.toUserId == _currentUser!.id && 
            request.status == FriendRequestStatus.pending &&
            !isAlreadyFriend) {
          _friendRequests.add(request);
          Log.d('[FriendService] ➕ เพิ่มคำขอจาก: ${request.fromUserName} (ID: ${request.id})');
        } else if (isAlreadyFriend) {
          Log.d('[FriendService] ⏭️ ข้าม: ${request.fromUserName} (เป็นเพื่อนอยู่แล้ว)');
        }
      }
      
      // บันทึกคำขอลงฐานข้อมูลท้องถิ่น
      await FriendDB.saveFriendRequests(_friendRequests);
      Log.d('[FriendService] 💾 บันทึก ${_friendRequests.length} คำขอลง Local');
      
      // 🔍 Debug: แสดงจำนวนเพื่อนออนไลน์
      final onlineCount = _friends.where((f) => f.isOnline).length;
      Log.d('[FriendService] 📊 สรุป: เพื่อนทั้งหมด ${_friends.length} คน, ออนไลน์ $onlineCount คน');
      for (final friend in _friends) {
        Log.d('[FriendService]   - ${friend.name}: ${friend.isOnline ? "🟢 ออนไลน์" : "⚪ ออฟไลน์"}');
      }
      
      notifyListeners();
    } catch (e) {
      Log.d('[FriendService] Error syncing with Firebase: $e');
    }
  }

  // เพื่อนจะถือว่าออนไลน์ได้ก็ต่อเมื่อ heartbeat ล่าสุด (lastActiveAt) ไม่เก่ากว่านี้
  // กันกรณีแอพเพื่อนถูกปิดแบบไม่ทันเขียนสถานะ offline (force-kill, แบตหมด, ฯลฯ)
  // ที่จะทำให้ isOnline ค้างเป็น true บน Firebase ตลอดไป
  static const Duration _onlineStatusTimeout = Duration(seconds: 30);

  // [Fix 3] ดึงสถานะออนไลน์แบบ parallel แทนการดึงทีละคน
  Future<void> _updateFriendsOnlineStatus() async {
    if (_friends.isEmpty) return;
    Log.d('[FriendService] 🔄 อัปเดตสถานะออนไลน์ ${_friends.length} คน (parallel)...');

    await Future.wait(
      List.generate(_friends.length, (i) async {
        try {
          final profile = await firebaseService.findPublicProfileByUserId(
            _friends[i].userId, forceRefresh: true);
          if (profile == null) return;

          final isStale = DateTime.now().difference(profile.lastActiveAt) > _onlineStatusTimeout;
          final effectiveOnline = profile.isOnline && !isStale;

          if (_friends[i].isOnline != effectiveOnline) {
            Log.d('[FriendService] 🔄 ${_friends[i].name}: → ${effectiveOnline ? "ออนไลน์" : "ออฟไลน์"}'
                '${isStale ? " (stale heartbeat)" : ""}');
            _friends[i] = _friends[i].copyWith(isOnline: effectiveOnline);
          }
        } catch (e) {
          Log.d('[FriendService] ⚠️ Error status ${_friends[i].name}: $e');
        }
      }),
    );

    Log.d('[FriendService] ✅ อัปเดตสถานะออนไลน์เสร็จสิ้น');
    notifyListeners();
  }

  /// ค้นหาผู้ใช้เพื่อเพิ่มเป็นเพื่อน (ค้นหาจาก User ID หรือชื่อ)
  Future<List<UserProfile>> searchUsers(String query) async {
    Log.d('[FriendService] 🔍 เริ่มค้นหา: "$query"');
    
    if (!firebaseService.isOnline) {
      Log.d('[FriendService] ❌ ไม่มีอินเทอร์เน็ต');
      return [];
    }
    
    if (!firebaseService.isSignedIn) {
      Log.d('[FriendService] ❌ ยังไม่ได้ login');
      return [];
    }

    try {
      List<UserProfile> users = [];
      
      // [Fix 1] รองรับทั้ง short ID (A7X2M9) และ Firebase UID (lowercase 20+ chars)
      final isUserId = RegExp(r'^[A-Z0-9]{4,8}$').hasMatch(query) ||
          RegExp(r'^[a-zA-Z0-9]{20,}$').hasMatch(query);
      Log.d('[FriendService] รูปแบบการค้นหา: ${isUserId ? "User ID" : "ชื่อ"}');
      
      if (isUserId) {
        // ค้นหาจาก User ID โดยตรง
        final user = await firebaseService.findPublicProfileByUserId(query);
        if (user != null) {
          users = [user];
          Log.d('[FriendService] ✅ พบ 1 ผู้ใช้');
        } else {
          Log.d('[FriendService] ❌ ไม่พบผู้ใช้ด้วย ID นี้');
        }
      } else {
        // ค้นหาจากชื่อ
        users = await firebaseService.searchUsersByName(query);
        Log.d('[FriendService] ✅ พบ ${users.length} ผู้ใช้จากชื่อ');
      }
      
      // กรองผู้ใช้ที่เป็นตัวเองและเพื่อนที่มีอยู่แล้วออก
      final filtered = users.where((user) {
        return user.id != _currentUser?.id && !_friends.any((f) => f.userId == user.id);
      }).toList();
      
      Log.d('[FriendService] ✅ ผลลัพธ์หลังกรอง: ${filtered.length} ผู้ใช้');
      return filtered;
    } catch (e) {
      Log.d('[FriendService] Error searching users: $e');
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
      Log.d('[FriendService] 📤 กำลังส่งคำขอไปหา: ${targetUser.name} (${targetUser.id})');
      final success = await firebaseService.sendFriendRequest(request);
      if (!success) {
        Log.d('[FriendService] ❌ ส่งคำขอไม่สำเร็จ');
        return false;
      }
      Log.d('[FriendService] ✅ ส่งคำขอสำเร็จ');
      return true;
    }

    // ถ้าออฟไลน์ ให้บันทึก local ไว้ส่งภายหลัง
    await FriendDB.addFriendRequest(request);
    _friendRequests.add(request);
    notifyListeners();
    Log.d('[FriendService] 💾 บันทึกคำขอไว้ใน Local (ออฟไลน์)');
    return true;
  }

  /// ตอบรับคำขอเป็นเพื่อน
  Future<bool> acceptFriendRequest(FriendRequest request) async {
    if (_currentUser == null) return false;

    try {
      Log.d('[FriendService] ✅ เริ่มรับคำขอจาก: ${request.fromUserName}');
      
      // ⭐ ตรวจสอบว่าเป็นเพื่อนอยู่แล้วหรือไม่
      final isAlreadyFriend = _friends.any((f) => f.userId == request.fromUserId);
      if (isAlreadyFriend) {
        Log.d('[FriendService] ⚠️ ${request.fromUserName} เป็นเพื่อนอยู่แล้ว - ลบคำขอ');
        _friendRequests.removeWhere((r) => r.id == request.id);
        await FriendDB.updateFriendRequestStatus(request.id, FriendRequestStatus.accepted);
        
        // ลบคำขอออกจาก Firebase ด้วย
        if (firebaseService.isOnline && firebaseService.isSignedIn) {
          try {
            await firebaseService.db?.collection('friend_requests').doc(request.id).delete();
          } catch (e) {
            Log.d('[FriendService] ⚠️ ไม่สามารถลบคำขอจาก Firebase: $e');
          }
        }
        
        notifyListeners();
        return true;
      }
      
      // ส่งไปยัง Firebase ก่อน (จะลบคำขอและเพิ่มเพื่อน 2 ทางใน Firebase)
      if (firebaseService.isOnline && firebaseService.isSignedIn) {
        final success = await firebaseService.respondToFriendRequest(request.id, true);
        if (!success) {
          Log.d('[FriendService] ❌ ส่งการตอบรับไป Firebase ไม่สำเร็จ');
          return false;
        }
        Log.d('[FriendService] ✅ ส่งการตอบรับไป Firebase สำเร็จ');
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
      Log.d('[FriendService] ✅ เพิ่มเพื่อนใน Local แล้ว');

      // 🔥 สำคัญ: Sync กับ Firebase อีกครั้งเพื่อดึงข้อมูลเพื่อนที่ครบถ้วน
      if (firebaseService.isOnline && firebaseService.isSignedIn) {
        Log.d('[FriendService] 🔄 กำลัง sync ข้อมูลเพื่อนจาก Firebase...');
        await syncWithFirebase();
        Log.d('[FriendService] ✅ sync เสร็จสมบูรณ์');
      }

      notifyListeners();
      return true;
    } catch (e) {
      Log.d('[FriendService] ❌ Error accepting friend request: $e');
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
      Log.d('[FriendService] Error rejecting friend request: $e');
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
      Log.d('[FriendService] Error removing friend: $e');
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

  // [Fix 4] เปิด real-time listener สำหรับคำขอเป็นเพื่อน
  void _startRequestsListener() {
    if (_currentUser == null) return;
    if (firebaseService.db == null) return;

    _requestsListener?.cancel();
    _requestsListener = firebaseService.db!
        .collection('friend_requests')
        .where('toUserId', isEqualTo: _currentUser!.id)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen(
      (snapshot) => _handleRequestsSnapshot(snapshot),
      onError: (e) {
        Log.d('[FriendService] ⚠️ Requests listener error: $e');
      },
    );

    Log.d('[FriendService] 🔔 เปิด real-time listener คำขอเป็นเพื่อน');
  }

  // เปิด real-time listener สำหรับคำขอที่เราส่งไปแล้วถูกอีกฝั่งกดรับ (status=accepted)
  // เพื่อให้ฝั่งผู้ส่งเพิ่มเพื่อนของตัวเองได้ทันที ไม่ต้องรอ auto sync รอบ 60 วินาที
  void _startAcceptedSentListener() {
    if (_currentUser == null) return;
    if (firebaseService.db == null) return;

    _acceptedSentListener?.cancel();
    _acceptedSentListener = firebaseService.db!
        .collection('friend_requests')
        .where('fromUserId', isEqualTo: _currentUser!.id)
        .where('status', isEqualTo: 'accepted')
        .snapshots()
        .listen(
      (snapshot) => _handleAcceptedSentSnapshot(snapshot),
      onError: (e) {
        Log.d('[FriendService] ⚠️ Accepted-sent listener error: $e');
      },
    );

    Log.d('[FriendService] 🔔 เปิด real-time listener คำขอที่ถูกรับ (ฝั่งผู้ส่ง)');
  }

  void _handleAcceptedSentSnapshot(QuerySnapshot snapshot) {
    if (snapshot.docs.isEmpty) return;
    Log.d('[FriendService] 🔔 Real-time: คำขอที่ส่งไปถูกรับแล้ว ${snapshot.docs.length} รายการ');
    syncWithFirebase();
  }

  void _handleRequestsSnapshot(QuerySnapshot snapshot) {
    final updated = <FriendRequest>[];

    for (final doc in snapshot.docs) {
      try {
        final request = FriendRequest.fromJson(doc.data() as Map<String, dynamic>);
        final isAlreadyFriend = _friends.any((f) => f.userId == request.fromUserId);
        if (!isAlreadyFriend) {
          updated.add(request);
        }
      } catch (e) {
        Log.d('[FriendService] ⚠️ Error parsing request: $e');
      }
    }

    _friendRequests
      ..clear()
      ..addAll(updated);
    FriendDB.saveFriendRequests(_friendRequests);
    Log.d('[FriendService] 🔔 Real-time: ${_friendRequests.length} คำขอ');
    notifyListeners();
  }

  /// ล้างข้อมูลทั้งหมด (สำหรับออกจากระบบ)
  Future<void> clearAllData() async {
    _requestsListener?.cancel();
    _requestsListener = null;
    _acceptedSentListener?.cancel();
    _acceptedSentListener = null;
    _friends.clear();
    _friendRequests.clear();
    _currentUser = null;
    await FriendDB.clearAllData();
    notifyListeners();
  }
}

// Singleton instance
final friendService = FriendService();