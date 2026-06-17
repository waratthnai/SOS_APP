import 'package:flutter/material.dart';
import 'package:offgrid_sos/core/logger.dart';

class NotificationService extends ChangeNotifier {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final List<InAppNotification> _inAppNotifications = [];

  List<InAppNotification> get inAppNotifications => List.unmodifiable(_inAppNotifications);

  Future<void> init() async {
    // Initialize notification service
  }

  void showInAppNotification({
    required String title,
    required String message,
    NotificationType type = NotificationType.info,
    String? senderId,
    VoidCallback? onReply,
  }) {
    Log.d('🔔 showInAppNotification เรียก: title=$title, type=$type');
    final notification = InAppNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      message: message,
      type: type,
      timestamp: DateTime.now(),
      senderId: senderId,
      onReply: onReply,
    );

    _inAppNotifications.insert(0, notification);
    Log.d('🔔 เพิ่มการแจ้งเตือนแล้ว ID: ${notification.id}');
    
    if (_inAppNotifications.length > 20) {
      _inAppNotifications.removeLast();
    }

    notifyListeners();
    Log.d('🔔 notifyListeners() เรียกแล้ว, จำนวนการแจ้งเตือน: ${_inAppNotifications.length}');
  }

  void clearNotification(String id) {
    _inAppNotifications.removeWhere((n) => n.id == id);
    notifyListeners();
  }

  void clearAllNotifications() {
    _inAppNotifications.clear();
    notifyListeners();
  }

  void showSOSNotification(String message) {
    showInAppNotification(
      title: '🆘 EMERGENCY',
      message: message,
      type: NotificationType.emergency,
    );
  }

  void showDeviceNotification(String deviceName, bool connected) {
    showInAppNotification(
      title: connected ? '📡 Device Connected' : '📡 Device Disconnected',
      message: '${connected ? 'Connected to' : 'Disconnected from'} $deviceName',
      type: connected ? NotificationType.success : NotificationType.warning,
    );
  }

  void showMessageNotification(String senderName, String message, {String? senderId, VoidCallback? onReply}) {
    Log.d('🔔 showMessageNotification เรียก: senderName=$senderName, message=$message, senderId=$senderId, onReply=${onReply != null}');
    showInAppNotification(
      title: '💬 New Message',
      message: '$senderName: $message',
      type: NotificationType.info,
      senderId: senderId,
      onReply: onReply,
    );
    Log.d('🔔 จำนวนการแจ้งเตือนปัจจุบัน: ${_inAppNotifications.length}');
  }
}

class InAppNotification {
  final String id;
  final String title;
  final String message;
  final NotificationType type;
  final DateTime timestamp;
  final String? senderId; // เพิ่ม: Peer ID ของคนส่งข้อความ (สำหรับปุ่มตอบกลับ)
  final VoidCallback? onReply; // เพิ่ม: Callback สำหรับปุ่มตอบกลับ

  InAppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.timestamp,
    this.senderId,
    this.onReply,
  });
}

enum NotificationType {
  info,
  success,
  warning,
  error,
  emergency,
}

extension NotificationTypeExtension on NotificationType {
  Color get color {
    switch (this) {
      case NotificationType.info:
        return Colors.blue;
      case NotificationType.success:
        return Colors.green;
      case NotificationType.warning:
        return Colors.orange;
      case NotificationType.error:
        return Colors.red;
      case NotificationType.emergency:
        return Colors.red.shade800;
    }
  }

  IconData get icon {
    switch (this) {
      case NotificationType.info:
        return Icons.info;
      case NotificationType.success:
        return Icons.check_circle;
      case NotificationType.warning:
        return Icons.warning;
      case NotificationType.error:
        return Icons.error;
      case NotificationType.emergency:
        return Icons.emergency;
    }
  }
}