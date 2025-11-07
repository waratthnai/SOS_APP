// lib/core/chat_models.dart
import 'package:cloud_firestore/cloud_firestore.dart';

enum ChatType { text, image, video }

// สถานะการส่งข้อความ
enum MessageStatus {
  pending,   // ⏳ ค้างส่ง (ยังไม่ได้ส่ง หรือ offline)
  sent,      // ✓ ส่งผ่าน P2P แล้ว (Bluetooth/WiFi)
  delivered, // ✓✓ ส่งถึงผู้รับแล้ว
  synced,    // ✓✓✓ ซิงก์ขึ้น Cloud แล้ว
}

// TODO: เพิ่มระบบคิวข้อความในเครื่อง (Local Queue)
// - เก็บข้อความที่ส่งไม่สำเร็จไว้ในคิว
// - ส่งใหม่อัตโนมัติเมื่อเชื่อมต่อได้
// - บันทึกลง SharedPreferences/SQLite
//
// TODO: เพิ่มระบบซิงก์ข้อความขึ้น Firebase Cloud
// - เมื่อออนไลน์ ให้ซิงก์ข้อความจากคิวขึ้น Cloud
// - อัพเดทสถานะเป็น 'synced' เมื่อซิงก์สำเร็จ
//
// TODO: เพิ่ม UI แสดงสถานะข้อความในช่องแชท
// - แสดงไอคอน: ⏳ (pending), ✓ (sent), ✓✓ (delivered), ☁️ (synced)
// - แสดงข้อความ retry สำหรับข้อความที่ส่งไม่สำเร็จ

class ChatMessage {
  final String id;
  final String from; // 'me' หรือ peerId
  final String? receiver; // ผู้รับ (peer ID) - สำหรับกรองแชทแยกห้อง
  final ChatType type;
  final String? text;
  final String? filePath; // path ของรูป/วิดีโอในเครื่อง
  final DateTime time;
  final bool isEmergency;
  final MessageStatus status; // เพิ่มสถานะข้อความ

  ChatMessage({
    required this.id,
    required this.from,
    this.receiver, // ทำเป็น optional
    required this.type,
    this.text,
    this.filePath,
    required this.time,
    this.isEmergency = false,
    this.status = MessageStatus.sent, // default เป็น sent
  });

  // Convert to JSON for storage/transmission
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'from': from,
      'receiver': receiver,
      'type': type.toString().split('.').last,
      'text': text,
      'filePath': filePath,
      'time': time.toIso8601String(),
      'isEmergency': isEmergency,
      'status': status.toString().split('.').last,
    };
  }

  // Create from JSON
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    // แปลง time จาก String หรือ Timestamp
    DateTime parseTime(dynamic timeValue) {
      if (timeValue is String) {
        return DateTime.parse(timeValue);
      } else if (timeValue is Timestamp) {
        return timeValue.toDate();
      } else if (timeValue is DateTime) {
        return timeValue;
      } else {
        return DateTime.now();
      }
    }
    
    // แปลง status
    MessageStatus parseStatus(dynamic statusValue) {
      if (statusValue == null) return MessageStatus.sent;
      if (statusValue is String) {
        return MessageStatus.values.firstWhere(
          (e) => e.toString().split('.').last == statusValue,
          orElse: () => MessageStatus.sent,
        );
      }
      return MessageStatus.sent;
    }
    
    return ChatMessage(
      id: json['id'] as String,
      from: json['from'] as String,
      receiver: json['receiver'] as String?,
      type: ChatType.values.firstWhere(
        (e) => e.toString().split('.').last == json['type'],
      ),
      text: json['text'] as String?,
      filePath: json['filePath'] as String?,
      time: parseTime(json['time']),
      isEmergency: json['isEmergency'] as bool? ?? false,
      status: parseStatus(json['status']),
    );
  }

  // Helper getters for convenience
  bool get hasImage => type == ChatType.image && filePath != null;
  bool get hasVideo => type == ChatType.video && filePath != null;
  bool get hasText => type == ChatType.text && text != null;
  
  // copyWith สำหรับอัปเดตสถานะ
  ChatMessage copyWith({
    String? id,
    String? from,
    String? receiver,
    ChatType? type,
    String? text,
    String? filePath,
    DateTime? time,
    bool? isEmergency,
    MessageStatus? status,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      from: from ?? this.from,
      receiver: receiver ?? this.receiver,
      type: type ?? this.type,
      text: text ?? this.text,
      filePath: filePath ?? this.filePath,
      time: time ?? this.time,
      isEmergency: isEmergency ?? this.isEmergency,
      status: status ?? this.status,
    );
  }
}

// Friend Chat Message Model
class FriendChatMessage {
  final String id;
  final String fromUserId; // User ID ของผู้ส่ง
  final String toUserId; // User ID ของผู้รับ
  final ChatType type;
  final String? text;
  final String? filePath; // path ของรูป/วิดีโอในเครื่อง
  final String? fileUrl; // URL ของไฟล์บน Firebase
  final DateTime time;
  final bool isRead; // อ่านแล้วหรือยัง
  final bool isDelivered; // ส่งถึงแล้วหรือยัง
  final bool isEmergency;

  FriendChatMessage({
    required this.id,
    required this.fromUserId,
    required this.toUserId,
    required this.type,
    this.text,
    this.filePath,
    this.fileUrl,
    required this.time,
    this.isRead = false,
    this.isDelivered = false,
    this.isEmergency = false,
  });

  // Convert to JSON for storage/transmission
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fromUserId': fromUserId,
      'toUserId': toUserId,
      'type': type.toString().split('.').last,
      'text': text,
      'filePath': filePath,
      'fileUrl': fileUrl,
      'time': time.toIso8601String(),
      'isRead': isRead,
      'isDelivered': isDelivered,
      'isEmergency': isEmergency,
    };
  }

  // Create from JSON
  factory FriendChatMessage.fromJson(Map<String, dynamic> json) {
    // แปลง time จาก String หรือ Timestamp (จาก Firebase)
    DateTime parseTime(dynamic timeValue) {
      if (timeValue is String) {
        return DateTime.parse(timeValue);
      } else if (timeValue is Timestamp) {
        return timeValue.toDate();
      } else if (timeValue is DateTime) {
        return timeValue;
      } else {
        return DateTime.now();
      }
    }
    
    return FriendChatMessage(
      id: json['id'] as String,
      fromUserId: json['fromUserId'] as String,
      toUserId: json['toUserId'] as String,
      type: ChatType.values.firstWhere(
        (e) => e.toString().split('.').last == json['type'],
      ),
      text: json['text'] as String?,
      filePath: json['filePath'] as String?,
      fileUrl: json['fileUrl'] as String?,
      time: parseTime(json['time']),
      isRead: json['isRead'] as bool? ?? false,
      isDelivered: json['isDelivered'] as bool? ?? false,
      isEmergency: json['isEmergency'] as bool? ?? false,
    );
  }

  // Copy with new values
  FriendChatMessage copyWith({
    String? id,
    String? fromUserId,
    String? toUserId,
    ChatType? type,
    String? text,
    String? filePath,
    String? fileUrl,
    DateTime? time,
    bool? isRead,
    bool? isDelivered,
    bool? isEmergency,
  }) {
    return FriendChatMessage(
      id: id ?? this.id,
      fromUserId: fromUserId ?? this.fromUserId,
      toUserId: toUserId ?? this.toUserId,
      type: type ?? this.type,
      text: text ?? this.text,
      filePath: filePath ?? this.filePath,
      fileUrl: fileUrl ?? this.fileUrl,
      time: time ?? this.time,
      isRead: isRead ?? this.isRead,
      isDelivered: isDelivered ?? this.isDelivered,
      isEmergency: isEmergency ?? this.isEmergency,
    );
  }

  // Helper getters for convenience
  bool get hasImage => type == ChatType.image && (filePath != null || fileUrl != null);
  bool get hasVideo => type == ChatType.video && (filePath != null || fileUrl != null);
  bool get hasText => type == ChatType.text && text != null;
  bool get isFromMe => fromUserId == 'me'; // ต้องเปรียบเทียบกับ current user ID
}
