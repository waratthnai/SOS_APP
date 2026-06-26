// lib/core/fcm_service.dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'notification_service.dart';
import 'friend_service.dart';
import 'app_state.dart';
import '../services/background_service.dart';
import 'package:offgrid_sos/core/logger.dart';

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

      Log.d('🔔 [FCM] Permission status: ${settings.authorizationStatus}');

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        // รับ FCM token
        _fcmToken = await _messaging.getToken();
        Log.d('🔔 [FCM] Token: $_fcmToken');

        // ฟังการเปลี่ยนแปลง token
        _messaging.onTokenRefresh.listen((newToken) {
          _fcmToken = newToken;
          Log.d('🔔 [FCM] Token refreshed: $newToken');
          _updateTokenInFirestore(newToken);
        });

        // Update token ครั้งแรก
        if (_fcmToken != null) {
          await _updateTokenInFirestore(_fcmToken!);
        }

        // ตั้งค่า handlers
        _setupMessageHandlers();
      } else {
        Log.d('🔔 [FCM] Permission denied');
      }
    } catch (e) {
      Log.d('🔔 [FCM] Error initializing: $e');
    }
  }

  /// บันทึก FCM token ลง Firestore ของผู้ใช้ปัจจุบัน
  /// เรียกซ้ำได้เมื่อ friendService.currentUser พร้อมแล้ว เพราะตอน initialize()
  /// ตอน app เริ่มต้น currentUser มักยังเป็น null (ยังโหลดโปรไฟล์ไม่เสร็จ)
  /// ทำให้ token ไม่ถูกบันทึกไปตลอดกาล (รอ onTokenRefresh ซึ่งนานๆเกิดครั้ง)
  Future<void> syncTokenForCurrentUser() async {
    _fcmToken ??= await _messaging.getToken();
    if (_fcmToken != null) {
      await _updateTokenInFirestore(_fcmToken!);
    }
  }

  /// อัพเดท FCM token ใน Firestore
  Future<void> _updateTokenInFirestore(String token) async {
    try {
      final userId = friendService.currentUser?.id;
      if (userId == null) {
        Log.d('🔔 [FCM] No user ID, skipping token update');
        return;
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .set({'fcmToken': token, 'lastActive': FieldValue.serverTimestamp()}, SetOptions(merge: true));

      Log.d('🔔 [FCM] Token updated in Firestore for user: $userId');
    } catch (e) {
      Log.d('🔔 [FCM] Error updating token: $e');
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
        Log.d('🔔 [FCM] App opened from terminated state with message');
        _handleBackgroundMessage(message);
      }
    });

    // บันทึก token ทันทีที่ user sign in (กรณี initialize() รันก่อน user profile โหลด)
    fa.FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null && _fcmToken != null) {
        _updateTokenInFirestore(_fcmToken!);
      }
    });
  }

  /// จัดการข้อความเมื่อแอพเปิดอยู่ (Foreground)
  void _handleForegroundMessage(RemoteMessage message) {
    Log.d('🔔 [FCM] Foreground message received');
    Log.d('🔔 [FCM] Title: ${message.notification?.title}');
    Log.d('🔔 [FCM] Body: ${message.notification?.body}');
    Log.d('🔔 [FCM] Data: ${message.data}');

    // แสดงการแจ้งเตือนในแอพ
    final data = message.data;
    final type = data['type'] ?? 'message';

    if (type == 'friend_message') {
      final fromUserId = data['fromUserId'] ?? '';
      final messageText = data['message'] ?? message.notification?.body ?? '';
      final senderName = data['senderName'] ?? fromUserId;

      // โหลดข้อความใหม่เข้า _friendChats ทันที ไม่รอ auto-refresh 5 วินาที
      if (fromUserId.isNotEmpty) {
        appState.loadFriendChatMessages(fromUserId, forceRefresh: true);
      }

      // ข้าม notification ถ้าผู้ใช้เปิดห้องแชทกับคนนี้อยู่แล้ว
      final userAlreadyInChat = appState.isActiveFriendChat(fromUserId);
      if (!userAlreadyInChat) {
        // แสดง in-app notification
        NotificationService().showMessageNotification(
          senderName,
          messageText,
          senderId: fromUserId,
          onReply: () => _openFriendChat(fromUserId),
        );
        // 🔔 แสดง system notification จริง (FCM ไม่ auto-show ตอนแอป foreground)
        BackgroundService().showMessageNotification(
          senderName: senderName,
          message: messageText,
        );
      } else {
        Log.d('⏭️ [FCM] ข้าม notification — ผู้ใช้อยู่ในห้องแชทกับ $senderName อยู่แล้ว');
      }
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
    Log.d('🔔 [FCM] Background message opened');
    Log.d('🔔 [FCM] Data: ${message.data}');

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
      final friend = friendService.friends.firstWhere((f) => f.userId == friendUserId);
      appState.openFriendChatScreenPublic(friend);
    } catch (e) {
      Log.d('🔔 [FCM] Error opening friend chat: $e');
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
        Log.d('🔔 [FCM] No current user');
        return;
      }

      // ดึง FCM token ของเพื่อน
      final friendDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(friendUserId)
          .get();

      final friendToken = friendDoc.data()?['fcmToken'] as String?;
      if (friendToken == null) {
        Log.d('🔔 [FCM] Friend has no FCM token, skipping notification');
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

      Log.d('🔔 [FCM] Notification queued for friend: $friendUserId');
    } catch (e) {
      Log.d('🔔 [FCM] Error sending notification: $e');
    }
  }
}

/// Background message handler (ต้องเป็น top-level function)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  Log.d('🔔 [FCM] Background handler: ${message.messageId}');
  // ไม่ต้องทำอะไร - จะจัดการใน onMessageOpenedApp
}
