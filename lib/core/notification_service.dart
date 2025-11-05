import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:typed_data';

class NotificationService extends ChangeNotifier {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final List<InAppNotification> _inAppNotifications = [];
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  List<InAppNotification> get inAppNotifications => List.unmodifiable(_inAppNotifications);

  Future<void> init() async {
    // Initialize notification service
    debugPrint('🔔 Initializing NotificationService...');
    
    // Android initialization
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    
    // iOS initialization
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );
    
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );
    
    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        debugPrint('🔔 Notification tapped: ${response.payload}');
      },
    );
    
    // Request permissions for Android 13+
    await _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    
    debugPrint('🔔 NotificationService initialized');
  }

  // แสดง Head-up notification พร้อมเสียงและสั่น
  Future<void> _showSystemNotification({
    required String title,
    required String body,
    NotificationType type = NotificationType.info,
  }) async {
    try {
      // กำหนดความสำคัญและเสียงตามประเภท
      final Priority priority = type == NotificationType.emergency
          ? Priority.max
          : type == NotificationType.info
              ? Priority.high
              : Priority.defaultPriority;
      
      final Importance importance = type == NotificationType.emergency
          ? Importance.max
          : type == NotificationType.info
              ? Importance.high
              : Importance.defaultImportance;
      
      final androidPlatformChannelSpecifics = AndroidNotificationDetails(
        'emergency_channel', // channel ID
        'Emergency Messages', // channel name
        channelDescription: 'Notifications for emergency messages',
        importance: importance,
        priority: priority,
        showWhen: true,
        // ✨ เสียงและการสั่น
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 500, 200, 500]), // รูปแบบการสั่น: เงียบ 0ms → สั่น 500ms → พัก 200ms → สั่น 500ms
        playSound: true,
        // ไฟ LED
        enableLights: true,
        color: type == NotificationType.emergency 
            ? const Color(0xFFD32F2F) // สีแดง for SOS
            : type == NotificationType.info 
                ? const Color(0xFF2196F3) // สีน้ำเงิน for chat
                : const Color(0xFF4CAF50), // สีเขียว for others
        ledColor: type == NotificationType.emergency
            ? const Color(0xFFD32F2F)
            : const Color(0xFF2196F3),
        ledOnMs: 1000,
        ledOffMs: 500,
        // ✨ Head-up notification settings (เด้งขึ้นมาเหมือน Facebook Messenger)
        fullScreenIntent: type == NotificationType.emergency,
        category: AndroidNotificationCategory.message,
        ticker: 'Emergency Alert', // แสดงใน status bar
      );
      
      const iOSPlatformChannelSpecifics = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'default',
      );
      
      final platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: iOSPlatformChannelSpecifics,
      );
      
      await _flutterLocalNotificationsPlugin.show(
        DateTime.now().millisecond, // notification ID
        title,
        body,
        platformChannelSpecifics,
        payload: 'emergency_message',
      );
      
      debugPrint('🔔 System notification shown: $title');
    } catch (e) {
      debugPrint('❌ Error showing system notification: $e');
    }
  }

  void showInAppNotification({
    required String title,
    required String message,
    NotificationType type = NotificationType.info,
    String? senderId,
    VoidCallback? onReply,
  }) {
    debugPrint('🔔 showInAppNotification เรียก: title=$title, type=$type');
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
    debugPrint('🔔 เพิ่มการแจ้งเตือนแล้ว ID: ${notification.id}');
    
    if (_inAppNotifications.length > 20) {
      _inAppNotifications.removeLast();
    }

    // ✨ แสดง System Notification (Head-up) พร้อมเสียงและสั่น
    _showSystemNotification(
      title: title,
      body: message,
      type: type,
    );

    notifyListeners();
    debugPrint('🔔 notifyListeners() เรียกแล้ว, จำนวนการแจ้งเตือน: ${_inAppNotifications.length}');
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
    debugPrint('🔔 showMessageNotification เรียก: senderName=$senderName, message=$message, senderId=$senderId, onReply=${onReply != null}');
    showInAppNotification(
      title: '💬 New Message',
      message: '$senderName: $message',
      type: NotificationType.info,
      senderId: senderId,
      onReply: onReply,
    );
    debugPrint('🔔 จำนวนการแจ้งเตือนปัจจุบัน: ${_inAppNotifications.length}');
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