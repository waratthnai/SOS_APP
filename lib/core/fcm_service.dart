// lib/core/fcm_service.dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'notification_service.dart';
import 'friend_service.dart';
import 'app_state.dart';

/// 🔔 Firebase Cloud Messaging Service
/// จัดการ Push Notifications ผ่านอินเทอร์เน็ต
class FCMService extends ChangeNotifier {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  String? _fcmToken;
  String? get fcmToken => _fcmToken;

  /// เริ่มต้น FCM
  Future<void> initialize() async {
    try {
      // ขออนุญาต notification
      NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      debugPrint('🔔 [FCM] Permission status: ${settings.authorizationStatus}');

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        // รับ FCM token
        _fcmToken = await _messaging.getToken();
        debugPrint('🔔 [FCM] Token: $_fcmToken');

        // ฟังการเปลี่ยนแปลง token
        _messaging.onTokenRefresh.listen((newToken) {
          _fcmToken = newToken;
          debugPrint('🔔 [FCM] Token refreshed: $newToken');
          _updateTokenInFirestore(newToken);
        });

        // Update token ครั้งแรก
        if (_fcmToken != null) {
          await _updateTokenInFirestore(_fcmToken!);
        }

        // ตั้งค่า handlers
        _setupMessageHandlers();
      } else {
        debugPrint('🔔 [FCM] Permission denied');
      }
    } catch (e) {
      debugPrint('🔔 [FCM] Error initializing: $e');
    }
  }

  /// อัพเดท FCM token ใน Firestore
  Future<void> _updateTokenInFirestore(String token) async {
    try {
      final userId = friendService.currentUser?.id;
      if (userId == null) {
        debugPrint('🔔 [FCM] No user ID, skipping token update');
        return;
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .set({'fcmToken': token, 'lastActive': FieldValue.serverTimestamp()}, SetOptions(merge: true));

      debugPrint('🔔 [FCM] Token updated in Firestore for user: $userId');
    } catch (e) {
      debugPrint('🔔 [FCM] Error updating token: $e');
    }
  }

  /// ตั้งค่า message handlers
  void _setupMessageHandlers() {
    // Foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Background/terminated messages
    FirebaseMessaging.onMessageOpenedApp.listen(_handleBackgroundMessage);

    // Check for initial message (app opened from terminated state)
    _messaging.getInitialMessage().then((message) {
      if (message != null) {
        debugPrint('🔔 [FCM] App opened from terminated state with message');
        _handleBackgroundMessage(message);
      }
    });
  }

  /// จัดการข้อความเมื่อแอพเปิดอยู่ (Foreground)
  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('🔔 [FCM] Foreground message received');
    debugPrint('🔔 [FCM] Title: ${message.notification?.title}');
    debugPrint('🔔 [FCM] Body: ${message.notification?.body}');
    debugPrint('🔔 [FCM] Data: ${message.data}');

    // แสดงการแจ้งเตือนในแอพ
    final data = message.data;
    final type = data['type'] ?? 'message';

    if (type == 'friend_message') {
      final fromUserId = data['fromUserId'] ?? '';
      final messageText = data['message'] ?? message.notification?.body ?? '';
      final senderName = data['senderName'] ?? fromUserId;

      // แสดง in-app notification
      NotificationService().showMessageNotification(
        senderName,
        messageText,
        senderId: fromUserId,
        onReply: () => _openFriendChat(fromUserId),
      );
    } else if (type == 'sos') {
      NotificationService().showInAppNotification(
        title: '🆘 ${message.notification?.title ?? "SOS Alert"}',
        message: message.notification?.body ?? 'Emergency nearby!',
        type: NotificationType.emergency,
      );
    }
  }

  /// จัดการข้อความเมื่อแอพอยู่ background หรือ terminated
  void _handleBackgroundMessage(RemoteMessage message) {
    debugPrint('🔔 [FCM] Background message opened');
    debugPrint('🔔 [FCM] Data: ${message.data}');

    final data = message.data;
    final type = data['type'] ?? 'message';

    if (type == 'friend_message') {
      final fromUserId = data['fromUserId'] ?? '';
      _openFriendChat(fromUserId);
    }
  }

  /// เปิดหน้าแชทเพื่อน
  void _openFriendChat(String friendUserId) {
    try {
      final friend = friendService.friends.firstWhere((f) => f.id == friendUserId);
      appState.openFriendChatScreenPublic(friend);
    } catch (e) {
      debugPrint('🔔 [FCM] Error opening friend chat: $e');
    }
  }

  /// ส่ง notification ไปยังเพื่อน (ผ่าน Cloud Function)
  Future<void> sendNotificationToFriend({
    required String friendUserId,
    required String message,
    String type = 'friend_message',
  }) async {
    try {
      final currentUser = friendService.currentUser;
      if (currentUser == null) {
        debugPrint('🔔 [FCM] No current user');
        return;
      }

      // ดึง FCM token ของเพื่อน
      final friendDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(friendUserId)
          .get();

      final friendToken = friendDoc.data()?['fcmToken'] as String?;
      if (friendToken == null) {
        debugPrint('🔔 [FCM] Friend has no FCM token, skipping notification');
        return;
      }

      // บันทึก notification request ใน Firestore
      // Cloud Function จะดึงไปส่ง FCM
      await FirebaseFirestore.instance.collection('notifications').add({
        'to': friendUserId,
        'toToken': friendToken,
        'fromUserId': currentUser.id,
        'senderName': currentUser.name,
        'message': message,
        'type': type,
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
      });

      debugPrint('🔔 [FCM] Notification queued for friend: $friendUserId');
    } catch (e) {
      debugPrint('🔔 [FCM] Error sending notification: $e');
    }
  }
}

/// Background message handler (ต้องเป็น top-level function)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('🔔 [FCM] Background handler: ${message.messageId}');
  // ไม่ต้องทำอะไร - จะจัดการใน onMessageOpenedApp
}
