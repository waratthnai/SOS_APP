// lib/core/friend_db.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'friend_models.dart';

class FriendDB {
  static const String _friendsKey = 'stored_friends';
  static const String _userProfileKey = 'user_profile';
  static const String _friendRequestsKey = 'friend_requests';
  static const String _friendChatsKey = 'friend_chats';

  // ========== User Profile Management ==========

  /// บันทึกโปรไฟล์ของผู้ใช้
  static Future<void> saveUserProfile(UserProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userProfileKey, jsonEncode(profile.toJson()));
  }

  /// ดึงโปรไฟล์ของผู้ใช้
  static Future<UserProfile?> getUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_userProfileKey);
    if (data != null) {
      return UserProfile.fromJson(jsonDecode(data));
    }
    return null;
  }

  /// สร้าง User ID ใหม่ (ใช้เมื่อยังไม่มีโปรไฟล์)
  /// สร้าง ID แบบสุ่ม สั้น ง่ายต่อการพิมพ์ เช่น A7X2M9, K4P3R8
  static String generateUserId() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // ตัดตัวที่สับสนออก (I, O, 0, 1)
    final random = DateTime.now().millisecondsSinceEpoch;
    final uuid = Uuid();
    final randomBytes = uuid.v4().replaceAll('-', '');
    
    String id = '';
    for (int i = 0; i < 6; i++) {
      final index = (randomBytes.codeUnitAt(i) + random + i) % chars.length;
      id += chars[index];
    }
    
    return id; // เช่น A7X2M9, K4P3R8, 9TZ5B2
  }

  // ========== Friends Management ==========

  /// บันทึกเพื่อนทั้งหมด
  static Future<void> saveFriends(List<Friend> friends) async {
    final prefs = await SharedPreferences.getInstance();
    final friendsJson = friends.map((f) => f.toJson()).toList();
    await prefs.setString(_friendsKey, jsonEncode(friendsJson));
  }

  /// ดึงเพื่อนทั้งหมด
  static Future<List<Friend>> getFriends() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_friendsKey);
    if (data != null) {
      final List<dynamic> friendsJson = jsonDecode(data);
      return friendsJson.map((json) => Friend.fromJson(json)).toList();
    }
    return [];
  }

  /// เพิ่มเพื่อนใหม่
  static Future<void> addFriend(Friend friend) async {
    final friends = await getFriends();
    // ตรวจสอบว่ามีเพื่อนคนนี้แล้วหรือไม่
    final existingIndex = friends.indexWhere((f) => f.userId == friend.userId);
    if (existingIndex >= 0) {
      // อัพเดทข้อมูลเพื่อนที่มีอยู่
      friends[existingIndex] = friend;
    } else {
      // เพิ่มเพื่อนใหม่
      friends.add(friend);
    }
    await saveFriends(friends);
  }

  /// ลบเพื่อน
  static Future<void> removeFriend(String userId) async {
    final friends = await getFriends();
    friends.removeWhere((f) => f.userId == userId);
    await saveFriends(friends);
  }

  /// อัพเดทสถานะออนไลน์ของเพื่อน
  static Future<void> updateFriendOnlineStatus(String userId, bool isOnline) async {
    final friends = await getFriends();
    final index = friends.indexWhere((f) => f.userId == userId);
    if (index >= 0) {
      friends[index] = friends[index].copyWith(
        isOnline: isOnline,
        lastSeen: DateTime.now(),
      );
      await saveFriends(friends);
    }
  }

  /// อัพเดทข้อความสุดท้าย
  static Future<void> updateFriendLastMessage(
    String userId, 
    String message, 
    DateTime time,
    {bool incrementUnread = false}
  ) async {
    final friends = await getFriends();
    final index = friends.indexWhere((f) => f.userId == userId);
    if (index >= 0) {
      final currentUnread = friends[index].unreadCount;
      friends[index] = friends[index].copyWith(
        lastMessage: message,
        lastMessageTime: time,
        unreadCount: incrementUnread ? currentUnread + 1 : currentUnread,
      );
      await saveFriends(friends);
    }
  }

  /// รีเซ็ตจำนวนข้อความที่ยังไม่อ่าน
  static Future<void> markFriendMessagesAsRead(String userId) async {
    final friends = await getFriends();
    final index = friends.indexWhere((f) => f.userId == userId);
    if (index >= 0) {
      friends[index] = friends[index].copyWith(unreadCount: 0);
      await saveFriends(friends);
    }
  }

  // ========== Friend Requests Management ==========

  /// บันทึกคำขอเป็นเพื่อนทั้งหมด
  static Future<void> saveFriendRequests(List<FriendRequest> requests) async {
    final prefs = await SharedPreferences.getInstance();
    final requestsJson = requests.map((r) => r.toJson()).toList();
    await prefs.setString(_friendRequestsKey, jsonEncode(requestsJson));
  }

  /// ดึงคำขอเป็นเพื่อนทั้งหมด
  static Future<List<FriendRequest>> getFriendRequests() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_friendRequestsKey);
    if (data != null) {
      final List<dynamic> requestsJson = jsonDecode(data);
      return requestsJson.map((json) => FriendRequest.fromJson(json)).toList();
    }
    return [];
  }

  /// เพิ่มคำขอเป็นเพื่อน
  static Future<void> addFriendRequest(FriendRequest request) async {
    final requests = await getFriendRequests();
    // ตรวจสอบว่ามีคำขอนี้แล้วหรือไม่
    final existingIndex = requests.indexWhere(
      (r) => r.fromUserId == request.fromUserId && r.toUserId == request.toUserId
    );
    if (existingIndex >= 0) {
      // อัพเดทคำขอที่มีอยู่
      requests[existingIndex] = request;
    } else {
      // เพิ่มคำขอใหม่
      requests.add(request);
    }
    await saveFriendRequests(requests);
  }

  /// อัพเดทสถานะคำขอเป็นเพื่อน
  static Future<void> updateFriendRequestStatus(String requestId, FriendRequestStatus status) async {
    final requests = await getFriendRequests();
    final index = requests.indexWhere((r) => r.id == requestId);
    if (index >= 0) {
      requests[index] = FriendRequest(
        id: requests[index].id,
        fromUserId: requests[index].fromUserId,
        toUserId: requests[index].toUserId,
        fromUserName: requests[index].fromUserName,
        fromUserAvatar: requests[index].fromUserAvatar,
        message: requests[index].message,
        sentAt: requests[index].sentAt,
        status: status,
      );
      await saveFriendRequests(requests);
    }
  }

  /// ลบคำขอเป็นเพื่อน
  static Future<void> removeFriendRequest(String requestId) async {
    final requests = await getFriendRequests();
    requests.removeWhere((r) => r.id == requestId);
    await saveFriendRequests(requests);
  }

  /// ล้างคำขอเป็นเพื่อนทั้งหมด
  static Future<void> clearFriendRequests() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_friendRequestsKey);
  }

  // ========== Friend Chat Messages ==========

  /// บันทึกข้อความแชทกับเพื่อน
  static Future<void> saveFriendChatMessage(String friendUserId, Map<String, dynamic> message) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '${_friendChatsKey}_$friendUserId';
    
    // ดึงข้อความเดิม
    final existingData = prefs.getString(key);
    List<dynamic> messages = [];
    if (existingData != null) {
      messages = jsonDecode(existingData);
    }
    
    // เพิ่มข้อความใหม่
    messages.add(message);
    
    // บันทึกกลับ
    await prefs.setString(key, jsonEncode(messages));
  }

  /// ดึงข้อความแชทกับเพื่อน
  static Future<List<Map<String, dynamic>>> getFriendChatMessages(String friendUserId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '${_friendChatsKey}_$friendUserId';
    final data = prefs.getString(key);
    if (data != null) {
      final List<dynamic> messages = jsonDecode(data);
      return messages.cast<Map<String, dynamic>>();
    }
    return [];
  }

  /// ลบข้อความแชททั้งหมดกับเพื่อน
  static Future<void> clearFriendChatMessages(String friendUserId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '${_friendChatsKey}_$friendUserId';
    await prefs.remove(key);
  }

  // ========== Utility Functions ==========

  /// ลบข้อมูลทั้งหมด (สำหรับ reset)
  static Future<void> clearAllData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_friendsKey);
    await prefs.remove(_userProfileKey);
    await prefs.remove(_friendRequestsKey);
    
    // ลบข้อความแชทเพื่อนทั้งหมด
    final keys = prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith(_friendChatsKey)) {
        await prefs.remove(key);
      }
    }
  }

  /// ตรวจสอบว่าเป็นเพื่อนกันแล้วหรือไม่
  static Future<bool> isFriend(String userId) async {
    final friends = await getFriends();
    return friends.any((f) => f.userId == userId);
  }

  /// ค้นหาเพื่อนจาก User ID
  static Future<Friend?> findFriendByUserId(String userId) async {
    final friends = await getFriends();
    try {
      return friends.firstWhere((f) => f.userId == userId);
    } catch (e) {
      return null;
    }
  }

  /// สร้าง User ID ใหม่สำหรับผู้ใช้ปัจจุบัน (ใช้เมื่อต้องการเปลี่ยน ID)
  static Future<void> regenerateUserId() async {
    final currentProfile = await getUserProfile();
    if (currentProfile != null) {
      final newId = generateUserId();
      final newProfile = UserProfile(
        id: newId,
        name: currentProfile.name,
        email: currentProfile.email,
        avatar: currentProfile.avatar,
        bio: currentProfile.bio,
        createdAt: currentProfile.createdAt,
        lastActiveAt: DateTime.now(),
        isOnline: currentProfile.isOnline,
      );
      await saveUserProfile(newProfile);
    }
  }
}