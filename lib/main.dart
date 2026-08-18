import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; // เพิ่มสำหรับ FCM
import 'core/app_state.dart';
import 'core/app_theme.dart'; // Import ธีมใหม่
import 'cloud/firebase_service.dart';
import 'core/fcm_service.dart'; // เพิ่ม FCM Service
import 'core/notification_service.dart';
import 'ui/device_name_setup_screen.dart';
// เพิ่ม import หน้า Debug
// เพิ่มสำหรับหน้าประวัติแชท
import 'widgets/floating_notification.dart'; // เพิ่ม floating notification
import 'package:shared_preferences/shared_preferences.dart';
import 'package:offgrid_sos/core/logger.dart';
import 'ui/root_nav.dart';

// Global navigator key สำหรับ navigation จาก notification
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase และ FCM background handler
  await firebaseService.init();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Initialize FCM Service
  await FCMService().initialize();
  
  // Initialize notification service
  NotificationService().init();

  // โหลดชื่อเครื่องจาก SharedPreferences
  final prefs = await SharedPreferences.getInstance();
  final deviceName = prefs.getString('device_name');
  final themeMode = prefs.getString('theme_mode') ?? 'dark'; // ✨ ตั้งค่าเริ่มต้นเป็นโหมดมืด

  // ถ้ามีชื่อแล้ว ให้อัพเดทใน appState
  if (deviceName != null && deviceName.isNotEmpty) {
    appState.setDeviceName(deviceName);
    Log.d('📱 โหลดชื่อเครื่อง: $deviceName');
  }
  
  Log.d('🎨 ธีมเริ่มต้น: $themeMode');

  runApp(
    OffGridApp(
      hasDeviceName: deviceName != null && deviceName.isNotEmpty,
      initialThemeMode: themeMode,
    ),
  );
}

class OffGridApp extends StatefulWidget {
  final bool hasDeviceName;
  final String initialThemeMode;

  const OffGridApp({
    super.key,
    required this.hasDeviceName,
    required this.initialThemeMode,
  });

  @override
  State<OffGridApp> createState() => OffGridAppState();
}

class OffGridAppState extends State<OffGridApp> {
  late ThemeMode _themeMode;
  ThemeMode get themeMode => _themeMode;

  @override
  void initState() {
    super.initState();
    _themeMode = _themeModeFromString(widget.initialThemeMode);
  }

  ThemeMode _themeModeFromString(String mode) {
    switch (mode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      default:
        return 'system';
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    HapticFeedback.lightImpact();
    setState(() => _themeMode = mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', _themeModeToString(mode));
  }

  @override
  Widget build(BuildContext context) {
    return FloatingNotificationOverlay(
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Off-Grid SOS',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: _themeMode,
        themeAnimationDuration: Duration.zero,
        routes: {'/home': (context) => const RootNav()},
        home: widget.hasDeviceName
            ? AnimatedBuilder(
                animation: appState,
                builder: (context, _) => const RootNav(),
              )
            : const DeviceNameSetupScreen(),
      ),
    );
  }
}

