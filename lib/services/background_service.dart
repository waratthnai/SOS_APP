import 'dart:async';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class BackgroundService {
  static final BackgroundService _instance = BackgroundService._internal();
  factory BackgroundService() => _instance;
  BackgroundService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  bool _isRunning = false;

  bool get isRunning => _isRunning;

  /// Initialize background service
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Initialize local notifications
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    await _notificationsPlugin.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
    );

    // Initialize foreground task
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'offgrid_sos_service',
        channelName: 'OffGrid SOS Background Service',
        channelDescription: 'This notification keeps OffGrid SOS running to receive emergency alerts',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000), // Check every 5 seconds
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    _isInitialized = true;
  }

  /// Start background service
  Future<bool> startService() async {
    if (!_isInitialized) {
      await initialize();
    }

    if (_isRunning) {
      return true;
    }

    // Request necessary permissions
    final hasPermission = await _requestPermissions();
    if (!hasPermission) {
      return false;
    }

    // Start foreground service
    try {
      await FlutterForegroundTask.startService(
        serviceId: 256,
        notificationTitle: 'OffGrid SOS กำลังทำงาน',
        notificationText: 'พร้อมรับสัญญาณ SOS จากเพื่อน',
        callback: startCallback,
      );

      _isRunning = true;
      return true;
    } catch (e) {
      print('❌ Error starting service: $e');
      return false;
    }
  }

  /// Stop background service
  Future<bool> stopService() async {
    if (!_isRunning) {
      return true;
    }

    try {
      await FlutterForegroundTask.stopService();
      _isRunning = false;
      return true;
    } catch (e) {
      print('❌ Error stopping service: $e');
      return false;
    }
  }

  /// Request necessary permissions
  Future<bool> _requestPermissions() async {
    // Request notification permission (Android 13+)
    if (await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      return true;
    }

    // Request to ignore battery optimization
    return await FlutterForegroundTask.requestIgnoreBatteryOptimization();
  }

  /// Show SOS notification
  Future<void> showSOSNotification({
    required String senderName,
    String? message,
    double? latitude,
    double? longitude,
  }) async {
    String notificationText = '$senderName ส่งสัญญาณ SOS!';
    if (message != null && message.isNotEmpty) {
      notificationText += '\n💬 $message';
    }
    if (latitude != null && longitude != null) {
      notificationText += '\n📍 ตำแหน่ง: $latitude, $longitude';
    }

    const androidDetails = AndroidNotificationDetails(
      'sos_alerts',
      'SOS Alerts',
      channelDescription: 'Emergency SOS notifications from friends',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
      largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await _notificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      '🆘 SOS ฉุกเฉิน!',
      notificationText,
      const NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
    );
  }

  /// Show chat message notification (ทำงานแม้ไม่เปิด background service)
  Future<void> showMessageNotification({
    required String senderName,
    required String message,
  }) async {
    // Initialize ถ้ายังไม่ได้ init
    if (!_isInitialized) {
      await initialize();
    }

    const androidDetails = AndroidNotificationDetails(
      'chat_messages',
      'Chat Messages',
      channelDescription: 'Notifications for new chat messages',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
      largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await _notificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      '💬 ข้อความใหม่จาก $senderName',
      message,
      const NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
    );
  }

  /// Update foreground notification
  Future<void> updateNotification({
    required String title,
    required String text,
  }) async {
    if (_isRunning) {
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: text,
      );
    }
  }
}

/// Callback function for foreground task
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(BackgroundTaskHandler());
}

/// Background task handler
class BackgroundTaskHandler extends TaskHandler {
  int _checkCount = 0;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    print('🔄 Background service started at $timestamp');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _checkCount++;

    // Update notification every minute
    if (_checkCount % 12 == 0) {
      FlutterForegroundTask.updateService(
        notificationTitle: 'OffGrid SOS กำลังทำงาน',
        notificationText: 'พร้อมรับสัญญาณ SOS • ตรวจสอบครั้งที่ $_checkCount',
      );
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    print('⏹️ Background service stopped at $timestamp');
  }

  @override
  void onNotificationPressed() {
    // Bring app to foreground when notification is tapped
    FlutterForegroundTask.launchApp('/');
  }
}
