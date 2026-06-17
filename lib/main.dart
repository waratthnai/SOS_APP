import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // เพิ่ม import สำหรับ Clipboard
import 'package:geolocator/geolocator.dart'; // เพิ่ม import สำหรับ GPS
import 'package:firebase_messaging/firebase_messaging.dart'; // เพิ่มสำหรับ FCM
import 'package:offgrid_sos/core/transport.dart';
import 'core/app_state.dart';
import 'core/app_theme.dart'; // Import ธีมใหม่
import 'cloud/firebase_service.dart';
import 'core/fcm_service.dart'; // เพิ่ม FCM Service
import 'ui/notification_panel.dart';
import 'core/notification_service.dart';
import 'ui/friends_screen.dart';
import 'ui/profile_screen.dart';
import 'ui/emergency_chat_screen.dart';
import 'ui/device_name_setup_screen.dart';
import 'ui/debug_screen.dart'; // เพิ่ม import หน้า Debug
import 'ui/chat_history_screen.dart'; // เพิ่มสำหรับหน้าประวัติแชท
import 'widgets/floating_notification.dart'; // เพิ่ม floating notification
import 'package:shared_preferences/shared_preferences.dart';
import 'package:offgrid_sos/core/logger.dart';

bool dummySwitch1 = false;
bool dummySwitch2 = false;

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
  State<OffGridApp> createState() => _OffGridAppState();
}

class _OffGridAppState extends State<OffGridApp> {
  late ThemeMode _themeMode;

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
    // เพิ่ม haptic feedback เมื่อเปลี่ยนธีม
    HapticFeedback.mediumImpact();

    setState(() {
      _themeMode = mode;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', _themeModeToString(mode));
  }

  @override
  Widget build(BuildContext context) {
    return FloatingNotificationOverlay(
      child: MaterialApp(
        navigatorKey: navigatorKey, // เพิ่ม global navigator key
        title: 'Off-Grid SOS',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: _themeMode,
        // เพิ่ม smooth theme transition
        themeAnimationDuration: const Duration(milliseconds: 500),
        themeAnimationCurve: Curves.easeInOutCubic,
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

class RootNav extends StatefulWidget {
  const RootNav({super.key});

  @override
  State<RootNav> createState() => _RootNavState();
}

class _RootNavState extends State<RootNav> {
  int _index = 0;

  final _pages = [
    const HomeScreen(),
    const ChatHistoryScreen(),
    const FriendsScreen(),
    const ProfileScreen(),
    const SettingsScreen(),
  ];

  final _items = const [
    _NavItem(icon: Icons.home_rounded, label: 'Home'),
    _NavItem(icon: Icons.chat_bubble_outline_rounded, label: 'Chat'),
    _NavItem(icon: Icons.people_outline_rounded, label: 'Friends'),
    _NavItem(icon: Icons.person_outline_rounded, label: 'Profile'),
    _NavItem(icon: Icons.settings_outlined, label: 'Settings'),
  ];

  void _onNavTap(int i) {
    setState(() => _index = i);
  }

  void _onHorizontalDrag(DragUpdateDetails details) {
    if (details.primaryDelta != null && details.primaryDelta!.abs() > 10) {
      if (details.primaryDelta! < 0 && _index < _pages.length - 1) {
        setState(() => _index += 1);
      } else if (details.primaryDelta! > 0 && _index > 0) {
        setState(() => _index -= 1);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onHorizontalDragUpdate: _onHorizontalDrag,
        child: _pages[_index],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200, width: 0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 56,
            child: Row(
              children: List.generate(_items.length, (i) {
                final item = _items[i];
                final selected = i == _index;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _onNavTap(i);
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          item.icon,
                          color: selected ? const Color(0xFFD32F2F) : const Color(0xFF8E8E93),
                          size: 24,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.label,
                          style: TextStyle(
                            color: selected ? const Color(0xFFD32F2F) : const Color(0xFF8E8E93),
                            fontSize: 10,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late AnimationController _blinkController;

  // Hold-to-emergency state
  Timer? _holdTimer;
  double _holdProgress = 0.0;
  bool _isHolding = false;
  bool _isEmergencyActive = false;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _warningSnackBar;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..repeat(reverse: true);
    // TODO: remove mock — for UI preview only
    WidgetsBinding.instance.addPostFrameCallback((_) {
      appState.DEBUG_addMockPeer();
    });
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _blinkController.dispose();
    super.dispose();
  }

  // Unified SOS handler: tap = normal help, hold 5s = emergency
  Future<void> _handleSOSTap(BuildContext context, {bool emergency = false}) async {
    final wasActive = appState.isSOSActive;

    // กด normal tap ขณะ SOS active → ปิด SOS
    // กด emergency hold ขณะ SOS active → อัพเกรดเป็น emergency (ไม่ปิด)
    if (wasActive && !emergency) {
      HapticFeedback.mediumImpact();
      await appState.toggleSOSMode();
      setState(() { _isEmergencyActive = false; });
      if (appState.peers.isNotEmpty) {
        appState.broadcastSOSStatus(isActive: false);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ปิดการขอความช่วยเหลือ'), duration: Duration(seconds: 2)),
        );
      }
      return;
    }

    // emergency hold ขณะ SOS active → อัพเกรดเป็น emergency โดยไม่ toggle
    if (!wasActive) {
      await appState.toggleSOSMode();
    }

    if (emergency) {
      HapticFeedback.heavyImpact();
      setState(() { _isEmergencyActive = true; });
    } else {
      HapticFeedback.mediumImpact();
      setState(() { _isEmergencyActive = false; });
    }

    String? latitude;
    String? longitude;
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );
      latitude = position.latitude.toStringAsFixed(6);
      longitude = position.longitude.toStringAsFixed(6);
    } catch (e) {
      Log.d('⚠️ Cannot get GPS location: $e');
    }

    if (appState.peers.isNotEmpty) {
      final now = DateTime.now();
      final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      final String message;
      if (emergency) {
        message = '🚨 SOS ฉุกเฉิน! ต้องการความช่วยเหลือด่วน!\n⏰ เวลา: $timeStr'
            + (latitude != null && longitude != null ? '\n📍 ตำแหน่ง: https://www.google.com/maps?q=$latitude,$longitude' : '');
      } else {
        message = '🆘 ขอความช่วยเหลือ\n⏰ เวลา: $timeStr'
            + (latitude != null && longitude != null ? '\n📍 ตำแหน่ง: https://www.google.com/maps?q=$latitude,$longitude' : '');
      }
      appState.send(message);
      appState.broadcastSOSStatus(
        isActive: true,
        isEmergency: emergency,
        latitude: latitude != null ? double.parse(latitude) : null,
        longitude: longitude != null ? double.parse(longitude) : null,
      );
    }

    if (context.mounted && !emergency) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ส่งคำขอความช่วยเหลือแล้ว'), duration: Duration(seconds: 2)),
      );
    }
  }

  void _startHold(BuildContext context) {
    if (_isHolding) return;
    _isHolding = true;
    _holdProgress = 0.0;

    _warningSnackBar = ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.gavel, color: Colors.white, size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'หากกดขอความช่วยเหลือโดยไม่ได้มีเหตุจำเป็น มีโทษทางกฎหมาย',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFE65100),
        duration: const Duration(seconds: 10),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    const totalMs = 5000;
    const intervalMs = 80;
    _holdTimer = Timer.periodic(const Duration(milliseconds: intervalMs), (timer) {
      if (!_isHolding || !mounted) {
        timer.cancel();
        if (mounted) setState(() { _holdProgress = 0.0; });
        return;
      }
      setState(() { _holdProgress = (_holdProgress + intervalMs / totalMs).clamp(0.0, 1.0); });
      if (_holdProgress >= 1.0) {
        timer.cancel();
        _isHolding = false;
        setState(() { _holdProgress = 0.0; });
        _warningSnackBar?.close();
        _warningSnackBar = null;
        _handleSOSTap(context, emergency: true);
      }
    });
  }

  void _cancelHold() {
    if (!_isHolding) return;
    _isHolding = false;
    _holdTimer?.cancel();
    _warningSnackBar?.close();
    _warningSnackBar = null;
    if (mounted) setState(() { _holdProgress = 0.0; });
  }

  Widget _buildStatusBadge(bool isSOSActive) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isSOSActive ? const Color(0xFFFFEBEE) : const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _blinkController,
            builder: (context, _) => Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isSOSActive
                    ? Color.lerp(Colors.red, Colors.redAccent, _blinkController.value)!
                    : const Color(0xFF4CAF50),
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            isSOSActive ? 'SOS Active' : "You're Safe",
            style: TextStyle(
              color: isSOSActive ? Colors.red.shade700 : const Color(0xFF2E7D32),
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSOSCircleButton(BuildContext context, bool isSOSActive) {
    return GestureDetector(
      onTap: () {
        if (_isHolding) return;
        _handleSOSTap(context, emergency: false);
      },
      onLongPressStart: (_) {
        if (_isEmergencyActive) return; // ถ้าเป็น emergency อยู่แล้ว ไม่ต้อง hold ซ้ำ
        _startHold(context);
      },
      onLongPressEnd: (_) => _cancelHold(),
      onLongPressCancel: () => _cancelHold(),
      child: AnimatedBuilder(
        animation: _blinkController,
        builder: (context, _) {
          final pulse = _blinkController.value;
          final isEmergency = isSOSActive && _isEmergencyActive;
          final buttonColor = isEmergency
              ? Color.lerp(const Color(0xFFB71C1C), const Color(0xFFD32F2F), pulse)!
              : const Color(0xFFD32F2F);
          return SizedBox(
            width: 260,
            height: 260,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (isSOSActive) ...[
                  Container(
                    width: 210 + (pulse * (isEmergency ? 50 : 40)),
                    height: 210 + (pulse * (isEmergency ? 50 : 40)),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.red.withOpacity((1 - pulse) * (isEmergency ? 0.14 : 0.08)),
                    ),
                  ),
                  Container(
                    width: 188 + (pulse * (isEmergency ? 30 : 24)),
                    height: 188 + (pulse * (isEmergency ? 30 : 24)),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.red.withOpacity((1 - pulse) * (isEmergency ? 0.18 : 0.12)),
                    ),
                  ),
                ] else ...[
                  Container(
                    width: 200,
                    height: 200,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0x14D32F2F),
                    ),
                  ),
                ],
                // Hold progress ring
                if (_holdProgress > 0)
                  SizedBox(
                    width: 186,
                    height: 186,
                    child: CircularProgressIndicator(
                      value: _holdProgress,
                      strokeWidth: 7,
                      color: Colors.orangeAccent,
                      backgroundColor: Colors.red.withOpacity(0.2),
                    ),
                  ),
                Container(
                  width: 170,
                  height: 170,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: buttonColor,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(isSOSActive ? (isEmergency ? 0.6 : 0.45) : 0.25),
                        blurRadius: isSOSActive ? (isEmergency ? 50 : 40) : 20,
                        spreadRadius: isSOSActive ? (isEmergency ? 12 : 8) : 2,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isEmergency ? Icons.crisis_alert : Icons.warning_amber_rounded,
                        size: 54,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'SOS',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _holdProgress > 0
                            ? 'Emergency in ${((1.0 - _holdProgress) * 5).ceil()}s...'
                            : isSOSActive
                                ? (isEmergency ? 'EMERGENCY ACTIVE' : 'HELP ACTIVE')
                                : 'Tap / Hold 5s',
                        style: TextStyle(
                          fontSize: _holdProgress > 0 ? 10 : 12,
                          fontWeight: FontWeight.w400,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 📡 รายการโปรโตคอลการเชื่อมต่อที่เลือกได้
  static const _protocolOptions = [
    (key: 'nearby', label: 'Nearby Connections', subtitle: 'BLE + WiFi รวมกัน (แนะนำ)', icon: Icons.share_outlined),
    (key: 'ble', label: 'Bluetooth LE', subtitle: 'เชื่อมต่อผ่าน BLE โดยตรง', icon: Icons.bluetooth),
    (key: 'wifi_direct', label: 'WiFi Direct', subtitle: 'ต้องเปิด WiFi Direct ทั้ง 2 เครื่อง', icon: Icons.wifi_tethering),
    (key: 'mesh', label: 'Radio Mesh', subtitle: 'ส่งต่อข้อความหลาย hop ผ่านอุปกรณ์ตัวกลาง', icon: Icons.hub_outlined),
  ];

  void _showProtocolPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        // 🔒 อยู่นอก StatefulBuilder.builder เพื่อให้ค่าคงอยู่ข้าม rebuild ของ setSheetState
        var isSwitching = false;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'เลือกโปรโตคอลการเชื่อมต่อ',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final option in _protocolOptions)
                      ListTile(
                        leading: Icon(
                          option.icon,
                          color: appState.selectedProtocol == option.key ? const Color(0xFF1976D2) : Colors.grey[600],
                        ),
                        title: Text(
                          option.label,
                          style: TextStyle(
                            fontWeight: appState.selectedProtocol == option.key ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(option.subtitle, style: const TextStyle(fontSize: 12)),
                        trailing: appState.selectedProtocol == option.key
                            ? const Icon(Icons.check_circle, color: Color(0xFF1976D2))
                            : null,
                        enabled: !isSwitching,
                        onTap: appState.selectedProtocol == option.key
                            ? null
                            : () async {
                                setSheetState(() => isSwitching = true);
                                try {
                                  await appState.switchTransport(option.key);
                                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                                  if (mounted) {
                                    ScaffoldMessenger.of(this.context).showSnackBar(
                                      SnackBar(
                                        content: Text('✅ สลับไปใช้ ${option.label} แล้ว'),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  setSheetState(() => isSwitching = false);
                                  if (mounted) {
                                    ScaffoldMessenger.of(this.context).showSnackBar(
                                      SnackBar(
                                        content: Text('❌ สลับโปรโตคอลไม่สำเร็จ: $e'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                }
                              },
                      ),
                    if (isSwitching)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRescueOthersButton(BuildContext context, bool isRescueMode) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        appState.toggleRescueMode().then((_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(!isRescueMode ? 'เปิดโหมดหน่วยกู้ภัย' : 'ปิดโหมดหน่วยกู้ภัย'),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: isRescueMode ? const Color(0x141565C0) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF1976D2), width: 2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isRescueMode ? Icons.shield : Icons.shield_outlined,
              color: const Color(0xFF1976D2),
              size: 22,
            ),
            const SizedBox(width: 10),
            Text(
              isRescueMode ? 'Rescue Mode: ON' : 'Rescue Others',
              style: const TextStyle(
                color: Color(0xFF1976D2),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) {
        final isSOSActive = appState.isSOSActive;
        final isRescueMode = appState.isRescueMode;
        final peers = appState.peers;

        return Scaffold(
          backgroundColor: const Color(0xFFF2F2F7),
          appBar: AppBar(
            title: const Text(
              'SOS Rescue',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
            ),
            leading: IconButton(
              icon: const Icon(Icons.settings_input_antenna, color: Colors.black87),
              tooltip: 'เลือกโปรโตคอลการเชื่อมต่อ',
              onPressed: () => _showProtocolPicker(context),
            ),
            backgroundColor: Colors.white,
            elevation: 0,
            centerTitle: true,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(0.5),
              child: Container(height: 0.5, color: const Color(0xFFE0E0E0)),
            ),
            actions: [
              AnimatedBuilder(
                animation: NotificationService(),
                builder: (context, child) {
                  final notificationCount = NotificationService().inAppNotifications.length;
                  return Stack(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.notifications_outlined, color: Colors.black87),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (context) => const NotificationsScreen()),
                          );
                        },
                      ),
                      if (notificationCount > 0)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                            child: Text(
                              notificationCount > 9 ? '9+' : '$notificationCount',
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  const SizedBox(height: 32),
                  _buildStatusBadge(isSOSActive),
                  const SizedBox(height: 40),
                  _buildSOSCircleButton(context, isSOSActive),
                  const SizedBox(height: 32),
                  _buildRescueOthersButton(context, isRescueMode),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.devices, color: Colors.blue, size: 20),
                            const SizedBox(width: 8),
                            const Text(
                              'Nearby Devices',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
                            ),
                            const Spacer(),
                            if (peers.isNotEmpty)
                              Text('${peers.length} device${peers.length > 1 ? 's' : ''}', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (peers.isEmpty)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                'No nearby devices found',
                                style: TextStyle(fontSize: 13, color: Colors.black26, fontStyle: FontStyle.italic),
                              ),
                            ),
                          )
                        else
                          ...peers.take(5).map((p) {
                            final isRescue = appState.isPeerRescue(p.name);
                            final isEmergencySOS = appState.isEmergencySOSPeer(p.name);
                            final isSOS = isEmergencySOS || appState.isSOSModePeer(p.name) || appState.isSOSPeer(p.name);
                            if (isEmergencySOS) {
                              // Emergency SOS — blinking red card
                              return AnimatedBuilder(
                                animation: _blinkController,
                                builder: (ctx, _) {
                                  final blink = _blinkController.value;
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withOpacity(0.06 + blink * 0.18),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Colors.red.withOpacity(0.4 + blink * 0.6),
                                        width: 1.5 + blink * 1.5,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.red.withOpacity(blink * 0.3),
                                          blurRadius: 8 + blink * 8,
                                          spreadRadius: blink * 2,
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.crisis_alert, color: Color.lerp(Colors.red.shade700, Colors.red.shade300, blink)!, size: 18),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text.rich(
                                                TextSpan(
                                                  children: [
                                                    TextSpan(
                                                      text: p.name.isNotEmpty ? p.name : 'Unknown Device',
                                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color.lerp(Colors.red.shade800, Colors.red.shade500, blink)!),
                                                    ),
                                                    TextSpan(
                                                      text: '  🚨 ฉุกเฉิน!',
                                                      style: TextStyle(fontSize: 11, color: Colors.red.shade700, fontWeight: FontWeight.w600),
                                                    ),
                                                  ],
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              if (p.distance != null) ...[
                                                const SizedBox(height: 2),
                                                Text(
                                                  p.distance! < 1000
                                                      ? '${p.distance!.toStringAsFixed(0)} m away'
                                                      : '${(p.distance! / 1000).toStringAsFixed(1)} km away',
                                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        GestureDetector(
                                          onTap: () => Navigator.of(context).push(
                                            MaterialPageRoute(builder: (_) => EmergencyChatScreen(peer: p)),
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.red,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Text('Chat', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            }
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isSOS
                                    ? Colors.red.withOpacity(0.08)
                                    : isRescue
                                        ? Colors.blue.withOpacity(0.08)
                                        : const Color(0xFFF5F5F5),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSOS
                                      ? Colors.red.withOpacity(0.3)
                                      : isRescue
                                          ? Colors.blue.withOpacity(0.3)
                                          : Colors.transparent,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isSOS ? Icons.warning_amber_rounded : isRescue ? Icons.local_hospital : Icons.device_hub,
                                    color: isSOS ? Colors.red : isRescue ? Colors.blue : Colors.grey,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          p.name.isNotEmpty ? p.name : 'Unknown Device',
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.black87),
                                        ),
                                        if (p.distance != null) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            p.distance! < 1000
                                                ? '${p.distance!.toStringAsFixed(0)} m away'
                                                : '${(p.distance! / 1000).toStringAsFixed(1)} km away',
                                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () => Navigator.of(context).push(
                                      MaterialPageRoute(builder: (_) => EmergencyChatScreen(peer: p)),
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isRescue ? Colors.blue : isSOS ? Colors.red : Colors.green,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text('Chat', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
class NearbyShareScreen extends StatefulWidget {
  const NearbyShareScreen({super.key});

  @override
  State<NearbyShareScreen> createState() => _NearbyShareScreenState();
}

class _NearbyShareScreenState extends State<NearbyShareScreen> {
  final _msgCtrl = TextEditingController();
  Peer? _selected;

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final peers = appState.peers;
    final msgs = appState.messages;
    final currentProtocol = appState.selectedProtocol; // 🔧 เพิ่มตัวแปร

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Share (Demo)'),
        actions: [
          IconButton(
            tooltip:
                appState.transport.discoveryState == DiscoveryState.scanning
                ? 'Stop Scan'
                : 'Scan',
            onPressed: () {
              // ⚡ Real-time: แสดงผลทันทีและทำงาน background
              final isScanning = appState.transport.discoveryState == DiscoveryState.scanning;
              
              if (isScanning) {
                // แสดงผลทันที
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('⏸️ หยุดการสแกน...'),
                    duration: Duration(milliseconds: 800),
                  ),
                );
                setState(() {}); // refresh UI ทันที
                
                // ทำงานใน background
                appState.stopScan().then((_) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('✅ หยุดการสแกนแล้ว'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  }
                });
              } else {
                // แสดงผลทันที
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('🔍 กำลังค้นหาอุปกรณ์...'),
                    duration: Duration(milliseconds: 800),
                  ),
                );
                setState(() {}); // refresh UI ทันที
                
                // ทำงานใน background
                appState.startScan().then((_) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('✅ กำลังค้นหาอุปกรณ์รอบข้าง'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  }
                });
              }
            },
            icon: Icon(
              appState.transport.discoveryState == DiscoveryState.scanning
                  ? Icons.stop_circle_outlined
                  : Icons.sensors,
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // กล่องพิมพ์ข้อความ
            TextField(
              controller: _msgCtrl,
              decoration: const InputDecoration(
                labelText: 'Message / Coordinates',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 12),

            // ปุ่มส่ง
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: peers.isEmpty
                        ? null
                        : () {
                            if (_msgCtrl.text.isNotEmpty) {
                              appState.send(_msgCtrl.text); // ⚡ ไม่ await
                              _msgCtrl.clear();
                            }
                          },
                    icon: const Icon(Icons.wifi_tethering),
                    label: const Text('Broadcast'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (_selected != null && _msgCtrl.text.isNotEmpty)
                        ? () {
                            appState.send(_msgCtrl.text, to: _selected); // ⚡ ไม่ await
                            _msgCtrl.clear();
                          }
                        : null,
                    icon: const Icon(Icons.send),
                    label: const Text('Send to Selected'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // รายชื่อเพื่อนที่ค้นพบ
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Discovered devices',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              flex: 1,
              child: peers.isEmpty
                  ? Card(
                      child: ListTile(
                        leading: Icon(Icons.info, color: cs.primary),
                        title: Text(
                          // 🔧 แสดงสถานะเฉพาะสำหรับ WiFi Direct
                          currentProtocol == 'wifi_direct'
                              ? '⚠️ WiFi Direct ต้องมี 2 เครื่องเปิดพร้อมกัน'
                              : 'No devices yet'
                        ),
                        subtitle: Text(
                          currentProtocol == 'wifi_direct'
                              ? 'เปิด WiFi Direct บนอุปกรณ์อีกเครื่อง แล้วกด Scan'
                              : 'Tap the sensor icon to Scan'
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: peers.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final p = peers[i];
                        final selected = _selected?.id == p.id;
                        return ListTile(
                          leading: Icon(
                            Icons.device_hub,
                            color: selected ? cs.primary : null,
                          ),
                          title: Text(
                            p.name.isNotEmpty ? p.name : 'อุปกรณ์ไม่ระบุชื่อ',
                          ),
                          subtitle: Text('ID: ${p.id}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.chat, color: Colors.green),
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          EmergencyChatScreen(peer: p),
                                    ),
                                  );
                                },
                                tooltip: 'แชทกับอุปกรณ์นี้',
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                selected
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                color: selected ? cs.primary : null,
                              ),
                            ],
                          ),
                          selected: selected,
                          onTap: () => setState(() => _selected = p),
                        );
                      },
                    ),
            ),

            const SizedBox(height: 12),

            // ประวัติข้อความ
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Messages',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              flex: 1,
              child: Card(
                child: ListView.separated(
                  padding: const EdgeInsets.all(8),
                  itemCount: msgs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final m = msgs[i];
                    final incoming = m.fromPeerId != 'me';
                    return ListTile(
                      leading: Icon(incoming ? Icons.device_hub : Icons.person),
                      title: Text(m.body),
                      subtitle: Text(
                        'From: ${m.fromPeerId}${m.toPeerId != null ? ' → ${m.toPeerId}' : ''}',
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<void> handleForgotPassword() async {
    String targetEmail = email.trim();
    if (targetEmail.isEmpty) {
      // Show dialog to input email
      final ctrl = TextEditingController();
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Forgot Password'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(labelText: 'Enter your email'),
            keyboardType: TextInputType.emailAddress,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Send'),
            ),
          ],
        ),
      );
      if (result == null || result.isEmpty) return;
      targetEmail = result;
    }
    setState(() {
      _busy = true;
    });
    try {
      await firebaseService.sendPasswordResetEmail(targetEmail);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Password reset email sent to $targetEmail'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send reset email: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    setState(() {
      _busy = false;
    });
  }

  @override
  void initState() {
    super.initState();
    firebaseService.addListener(_onFirebaseUserChanged);
  }

  @override
  void dispose() {
    firebaseService.removeListener(_onFirebaseUserChanged);
    super.dispose();
  }

  void _onFirebaseUserChanged() {
    if (mounted) setState(() {});
  }

  String email = '';
  String password = '';
  String displayName = '';
  String deviceName = ''; // เพิ่มชื่อเครื่อง
  bool isSignUp = false;
  
  // 🔄 แปลง protocols เป็น getter ที่อ่านค่าจาก appState
  Map<String, bool> get protocols {
    final selected = appState.selectedProtocol;
    return {
      'wifi': selected == 'wifi' || selected == 'wifi_direct',
      'bluetooth': selected == 'bluetooth' || selected == 'nearby',
      'radio': selected == 'radio' || selected == 'mesh',
    };
  }

  bool _busy = false;
  String? _error;

  Future<void> handleLogin() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter email and password'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    String? err;
    if (isSignUp) {
      if (displayName.isEmpty) {
        setState(() {
          _busy = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter display name'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      err = await firebaseService.signUpWithEmail(
        email.trim(),
        password,
        displayName: displayName.trim(),
      );
    } else {
      err = await firebaseService.signInWithEmail(email.trim(), password);
    }
    setState(() {
      _busy = false;
      _error = err;
    });
    if (err == null) {
      Log.d('[Main] 🔑 Login สำเร็จ - เรียก onUserLogin()...');
      // เรียกใช้ onUserLogin เพื่อโหลดข้อมูลของ user
      await appState.onUserLogin();
      Log.d('[Main] ✅ onUserLogin() เสร็จสิ้น');

      // ⚠️ ลบบรรทัดนี้ออก เพราะ onUserLogin() ได้ sync แล้ว
      // await friendService.syncWithFirebase();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isSignUp ? 'Signed up successfully' : 'Logged in successfully',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> handleLogout() async {
    setState(() {
      _busy = true;
    });

    // เรียกใช้ logout ของ appState เพื่อล้างข้อมูลแชท
    await appState.logout();

    // Logout จาก Firebase
    await firebaseService.signOut();

    setState(() {
      _busy = false;
      email = '';
      password = '';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Logged out'),
        backgroundColor: Colors.blueGrey,
      ),
    );
  }

  void toggleProtocol(String protocol) {
    // ป้องกันการ toggle protocol เดียวกันซ้ำ
    if ((protocol == 'wifi' && appState.selectedProtocol == 'wifi_direct') ||
        (protocol == 'bluetooth' && appState.selectedProtocol == 'nearby') ||
        (protocol == 'radio' && appState.selectedProtocol == 'mesh')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${protocol.toUpperCase()} protocol กำลังทำงานอยู่แล้ว'),
          backgroundColor: Colors.blue,
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }
    
    // ⚡ Real-time: แสดงผลทันทีและทำงาน background
    String displayName = protocol == 'wifi' ? 'WiFi Direct' 
                       : protocol == 'bluetooth' ? 'Bluetooth'
                       : 'Radio Mesh';
    
    // แสดงข้อความกำลังสลับทันที
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🔄 กำลังสลับไปยัง $displayName...'),
        backgroundColor: Colors.orange,
        duration: const Duration(milliseconds: 800),
      ),
    );
    
    // อัปเดต UI ทันที
    setState(() {});
    
    // กำหนด transport name
    String transportName;
    if (protocol == 'wifi') {
      transportName = 'wifi_direct';
    } else if (protocol == 'bluetooth') {
      transportName = 'nearby';
    } else if (protocol == 'radio') {
      transportName = 'mesh';
    } else {
      transportName = protocol;
    }
    
    // ทำงานใน background
    appState.switchTransport(transportName).then((_) async {
      // บันทึกค่า
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('active_protocol', protocol);
      
      if (mounted) {
        // อัพเดท UI
        setState(() {});
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ สลับไปยัง $displayName สำเร็จ',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }).catchError((e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ไม่สามารถสลับโปรโตคอลได้: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = firebaseService.currentUser;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final offGridState = context.findAncestorStateOfType<_OffGridAppState>();
    final currentMode = offGridState?._themeMode ?? ThemeMode.system;
    final isDark = currentMode == ThemeMode.dark ||
        (currentMode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ตั้งค่า', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: cs.surface,
        actions: [
          IconButton(
            icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
            tooltip: isDark ? 'สลับเป็นโหมดสว่าง' : 'สลับเป็นโหมดมืด',
            onPressed: () => offGridState?.setThemeMode(
              isDark ? ThemeMode.light : ThemeMode.dark,
            ),
          ),
          IconButton(
            icon: Icon(Icons.bug_report, color: cs.secondary),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DebugScreen(),
                ),
              );
            },
            tooltip: 'Debug Info',
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Account Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.person, color: cs.primary, size: 28),
                            const SizedBox(width: 8),
                            Text('บัญชี', style: theme.textTheme.titleLarge),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (user == null) ...[
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  isSignUp ? 'สมัครสมาชิก' : 'เข้าสู่ระบบ',
                                  style: theme.textTheme.titleMedium,
                                ),
                              ),
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () {
                                        setState(() {
                                          isSignUp = !isSignUp;
                                          _error = null;
                                        });
                                      },
                                child: Text(
                                  isSignUp ? 'Go to Login' : 'Create Account',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (isSignUp) ...[
                            TextField(
                              decoration: const InputDecoration(
                                labelText: 'ชื่อที่แสดง',
                              ),
                              onChanged: (v) => setState(() => displayName = v),
                            ),
                            const SizedBox(height: 12),
                          ],
                          TextField(
                            decoration: const InputDecoration(
                              labelText: 'อีเมล',
                            ),
                            keyboardType: TextInputType.emailAddress,
                            onChanged: (v) => setState(() => email = v),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            decoration: const InputDecoration(
                              labelText: 'รหัสผ่าน',
                            ),
                            obscureText: true,
                            onChanged: (v) => setState(() => password = v),
                          ),
                          const SizedBox(height: 16),
                          if (_error != null) ...[
                            Text(_error!, style: TextStyle(color: cs.error)),
                            const SizedBox(height: 8),
                          ],
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _busy ? null : handleLogin,
                                  icon: _busy
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Icon(
                                          isSignUp
                                              ? Icons.person_add
                                              : Icons.login,
                                        ),
                                  label: Text(
                                    isSignUp ? 'สมัครสมาชิก' : 'เข้าสู่ระบบ',
                                  ),
                                ),
                              ),
                              if (!isSignUp)
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : handleForgotPassword,
                                  child: const Text('ลืมรหัสผ่าน?'),
                                ),
                            ],
                          ),
                        ] else ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'เข้าสู่ระบบแล้ว',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                Text(
                                  user.email ?? '',
                                  style: theme.textTheme.titleMedium,
                                ),
                                if (user.displayName != null &&
                                    user.displayName!.isNotEmpty)
                                  Text(
                                    user.displayName!,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _busy ? null : handleLogout,
                              icon: _busy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.logout),
                              label: const Text('ออกจากระบบ'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Device Name Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.phone_android,
                              color: cs.primary,
                              size: 28,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'ชื่อเครื่อง',
                              style: theme.textTheme.titleLarge,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'ชื่อที่จะแสดงให้ผู้อื่นเห็นเมื่อสแกนหา',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 16),
                        AnimatedBuilder(
                          animation: appState,
                          builder: (context, _) {
                            final currentName = appState.deviceName;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: cs.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.badge,
                                        color: cs.primary,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          currentName,
                                          style: theme.textTheme.titleMedium,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  onPressed: () async {
                                    final controller = TextEditingController(
                                      text: currentName,
                                    );
                                    final newName = await showDialog<String>(
                                      context: context,
                                      builder: (ctx) {
                                        return AlertDialog(
                                          title: const Text(
                                            'เปลี่ยนชื่อเครื่อง',
                                          ),
                                          content: TextField(
                                            controller: controller,
                                            autofocus: true,
                                            decoration: const InputDecoration(
                                              labelText: 'ชื่อเครื่องใหม่',
                                              hintText:
                                                  'เช่น มือถือของแม่, แทบเล็ตของพ่อ',
                                            ),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx),
                                              child: const Text('ยกเลิก'),
                                            ),
                                            FilledButton(
                                              onPressed: () {
                                                final name = controller.text
                                                    .trim();
                                                if (name.isNotEmpty &&
                                                    name.length >= 2 &&
                                                    name.length <= 20) {
                                                  Navigator.pop(ctx, name);
                                                } else {
                                                  ScaffoldMessenger.of(
                                                    ctx,
                                                  ).showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        'ชื่อต้องมี 2-20 ตัวอักษร',
                                                      ),
                                                    ),
                                                  );
                                                }
                                              },
                                              child: const Text('บันทึก'),
                                            ),
                                          ],
                                        );
                                      },
                                    );

                                    if (newName != null && newName.isNotEmpty) {
                                      final prefs =
                                          await SharedPreferences.getInstance();
                                      await prefs.setString(
                                        'device_name',
                                        newName,
                                      );
                                      appState.setDeviceName(newName);

                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              '✅ เปลี่ยนชื่อเครื่องเป็น "$newName" แล้ว',
                                            ),
                                          ),
                                        );
                                      }
                                    }
                                  },
                                  icon: const Icon(Icons.edit),
                                  label: const Text('เปลี่ยนชื่อเครื่อง'),
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('ยืนยันการรีเซ็ต'),
                                        content: const Text(
                                          'คุณต้องการรีเซ็ตชื่อเครื่องและตั้งใหม่หรือไม่?\n\n'
                                          'แอปจะรีสตาร์ทเพื่อให้คุณตั้งชื่อใหม่',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, false),
                                            child: const Text('ยกเลิก'),
                                          ),
                                          FilledButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, true),
                                            child: const Text('รีเซ็ต'),
                                          ),
                                        ],
                                      ),
                                    );

                                    if (confirm == true) {
                                      final prefs =
                                          await SharedPreferences.getInstance();
                                      await prefs.remove('device_name');
                                      appState.setDeviceName('ผู้ใช้ฉุกเฉิน');

                                      if (context.mounted) {
                                        showDialog(
                                          context: context,
                                          barrierDismissible: false,
                                          builder: (ctx) => const Center(
                                            child: CircularProgressIndicator(),
                                          ),
                                        );

                                        await Future.delayed(
                                          const Duration(milliseconds: 500),
                                        );

                                        if (context.mounted) {
                                          Navigator.of(
                                            context,
                                          ).pushAndRemoveUntil(
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  const DeviceNameSetupScreen(),
                                            ),
                                            (route) => false,
                                          );
                                        }
                                      }
                                    }
                                  },
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('รีเซ็ตชื่อเครื่อง'),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),


              ],
            ),
          ),
        ),
    );
  }
}

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 120,
            flexibleSpace: FlexibleSpaceBar(
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cs.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.notifications_active,
                      color: cs.error,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('การแจ้งเตือน', style: theme.textTheme.headlineSmall),
                ],
              ),
              titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
            ),
            actions: [
              ListenableBuilder(
                listenable: NotificationService(),
                builder: (context, child) {
                  final hasNotifications =
                      NotificationService().inAppNotifications.isNotEmpty;
                  return hasNotifications
                      ? IconButton(
                          icon: const Icon(Icons.clear_all),
                          onPressed: () {
                            NotificationService().clearAllNotifications();
                          },
                        )
                      : const SizedBox.shrink();
                },
              ),
            ],
          ),
          const NotificationPanel(),
        ],
      ),
    );
  }
}
