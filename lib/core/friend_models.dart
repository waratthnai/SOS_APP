// lib/core/friend_models.dart
class Friend {
  final String id; // Unique Friend ID
  final String name; // ชื่อเพื่อน
  final String userId; // User ID ของเพื่อน (สำหรับค้นหาและเพิ่มเพื่อน)
  final String? avatar; // รูปโปรไฟล์ (optional)
  final DateTime addedAt; // วันที่เพิ่มเพื่อน
  final DateTime lastSeen; // ครั้งสุดท้ายที่เจอออนไลน์
  final bool isOnline; // สถานะออนไลน์ปัจจุบัน
  final String? lastMessage; // ข้อความสุดท้าย
  final DateTime? lastMessageTime; // เวลาข้อความสุดท้าย
  final int unreadCount; // จำนวนข้อความที่ยังไม่อ่าน

  Friend({
    required this.id,
    required this.name,
    required this.userId,
    this.avatar,
    required this.addedAt,
    required this.lastSeen,
    this.isOnline = false,
    this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
  });

  // Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'userId': userId,
      'avatar': avatar,
      'addedAt': addedAt.toIso8601String(),
      'lastSeen': lastSeen.toIso8601String(),
      'isOnline': isOnline,
      'lastMessage': lastMessage,
      'lastMessageTime': lastMessageTime?.toIso8601String(),
      'unreadCount': unreadCount,
    };
  }

  // Create from JSON
  factory Friend.fromJson(Map<String, dynamic> json) {
    return Friend(
      id: json['id'] as String,
      name: json['name'] as String,
      userId: json['userId'] as String,
      avatar: json['avatar'] as String?,
      addedAt: DateTime.parse(json['addedAt'] as String),
      lastSeen: DateTime.parse(json['lastSeen'] as String),
      isOnline: json['isOnline'] as bool? ?? false,
      lastMessage: json['lastMessage'] as String?,
      lastMessageTime: json['lastMessageTime'] != null 
        ? DateTime.parse(json['lastMessageTime'] as String) 
        : null,
      unreadCount: json['unreadCount'] as int? ?? 0,
    );
  }

  // Copy with new values
  Friend copyWith({
    String? id,
    String? name,
    String? userId,
    String? avatar,
    DateTime? addedAt,
    DateTime? lastSeen,
    bool? isOnline,
    String? lastMessage,
    DateTime? lastMessageTime,
    int? unreadCount,
  }) {
    return Friend(
      id: id ?? this.id,
      name: name ?? this.name,
      userId: userId ?? this.userId,
      avatar: avatar ?? this.avatar,
      addedAt: addedAt ?? this.addedAt,
      lastSeen: lastSeen ?? this.lastSeen,
      isOnline: isOnline ?? this.isOnline,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}

// Model สำหรับ User Profile
class UserProfile {
  final String id; // Unique User ID (ใช้สำหรับค้นหาและเพิ่มเพื่อน)
  final String name; // ชื่อผู้ใช้
  final String? email; // อีเมล (optional)
  final String? avatar; // รูปโปรไฟล์ (optional)
  final String? bio; // คำอธิบาย (optional)
  final DateTime createdAt; // วันที่สร้างบัญชี
  final DateTime lastActiveAt; // ครั้งสุดท้ายที่ใช้งาน
  final bool isOnline; // สถานะออนไลน์

  UserProfile({
    required this.id,
    required this.name,
    this.email,
    this.avatar,
    this.bio,
    required this.createdAt,
    required this.lastActiveAt,
    this.isOnline = false,
  });

  // Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'avatar': avatar,
      'bio': bio,
      'createdAt': createdAt.toIso8601String(),
      'lastActiveAt': lastActiveAt.toIso8601String(),
      'isOnline': isOnline,
    };
  }

  // Create from JSON
  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String?,
      avatar: json['avatar'] as String?,
      bio: json['bio'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastActiveAt: DateTime.parse(json['lastActiveAt'] as String),
      isOnline: json['isOnline'] as bool? ?? false,
    );
  }

  // Copy with new values
  UserProfile copyWith({
    String? id,
    String? name,
    String? email,
    String? avatar,
    String? bio,
    DateTime? createdAt,
    DateTime? lastActiveAt,
    bool? isOnline,
  }) {
    return UserProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      avatar: avatar ?? this.avatar,
      bio: bio ?? this.bio,
      createdAt: createdAt ?? this.createdAt,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      isOnline: isOnline ?? this.isOnline,
    );
  }
}

// Model สำหรับ Friend Request
class FriendRequest {
  final String id;
  final String fromUserId; // ผู้ส่งคำขอ
  final String toUserId; // ผู้รับคำขอ
  final String fromUserName; // ชื่อผู้ส่งคำขอ
  final String? fromUserAvatar; // รูปโปรไฟล์ผู้ส่งคำขอ
  final String? message; // ข้อความแนะนำตัว (optional)
  final DateTime sentAt; // วันที่ส่งคำขอ
  final FriendRequestStatus status; // สถานะคำขอ

  FriendRequest({
    required this.id,
    required this.fromUserId,
    required this.toUserId,
    required this.fromUserName,
    this.fromUserAvatar,
    this.message,
    required this.sentAt,
    this.status = FriendRequestStatus.pending,
  });

  // Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fromUserId': fromUserId,
      'toUserId': toUserId,
      'fromUserName': fromUserName,
      'fromUserAvatar': fromUserAvatar,
      'message': message,
      'sentAt': sentAt.toIso8601String(),
      'status': status.name,
    };
  }

  // Create from JSON
  factory FriendRequest.fromJson(Map<String, dynamic> json) {
    return FriendRequest(
      id: json['id'] as String,
      fromUserId: json['fromUserId'] as String,
      toUserId: json['toUserId'] as String,
      fromUserName: json['fromUserName'] as String,
      fromUserAvatar: json['fromUserAvatar'] as String?,
      message: json['message'] as String?,
      sentAt: DateTime.parse(json['sentAt'] as String),
      status: FriendRequestStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => FriendRequestStatus.pending,
      ),
    );
  }
}

enum FriendRequestStatus {
  pending,   // รอการตอบรับ
  accepted,  // ยอมรับแล้ว
  rejected,  // ปฏิเสธแล้ว
  cancelled, // ยกเลิกแล้ว
}