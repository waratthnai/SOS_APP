import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // เพิ่ม import สำหรับ Clipboard
import 'package:geolocator/geolocator.dart'; // เพิ่ม import สำหรับ GPS
import 'package:firebase_messaging/firebase_messaging.dart'; // เพิ่มสำหรับ FCM
import 'package:offgrid_sos/core/transport.dart';
import 'core/app_state.dart';
import 'core/app_theme.dart'; // Import ธีมใหม่
import 'cloud/firebase_service.dart';
import 'core/fcm_service.dart'; // เพิ่ม FCM Service
import 'ui/MapScreen.dart';
import 'ui/notification_panel.dart';
import 'core/notification_service.dart';
import 'ui/friends_screen.dart';
import 'ui/profile_screen.dart';
import 'core/friend_service.dart';
import 'ui/emergency_chat_screen.dart';
import 'ui/device_name_setup_screen.dart';
import 'ui/debug_screen.dart'; // เพิ่ม import หน้า Debug
import 'ui/chat_history_screen.dart'; // เพิ่มสำหรับหน้าประวัติแชท
import 'package:shared_preferences/shared_preferences.dart';

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
    debugPrint('📱 โหลดชื่อเครื่อง: $deviceName');
  }
  
  debugPrint('🎨 ธีมเริ่มต้น: $themeMode');

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
    return MaterialApp(
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
    const MapScreen(),
    const ChatHistoryScreen(), // เปลี่ยนจาก NotificationsScreen เป็น ChatHistoryScreen
    const SettingsScreen(),
  ];

  final _items = const [
    _NavItem(icon: Icons.home, label: 'หน้าหลัก'),
    _NavItem(icon: Icons.map, label: 'แผนที่'),
    _NavItem(icon: Icons.warning_amber_rounded, label: 'SOS', isSOS: true),
    _NavItem(icon: Icons.chat, label: 'แชท'), // เปลี่ยนจากการแจ้งเตือนเป็นแชท
    _NavItem(icon: Icons.settings, label: 'การตั้งค่า'),
  ];

  void _onNavTap(int i) {
    // Handle SOS button tap
    if (_items[i].isSOS) {
      _handleSOSTap();
      return;
    }

    // Adjust index for other items since SOS is in the middle
    int pageIndex = i;
    if (i > 2) pageIndex = i - 1; // Skip SOS for page navigation

    setState(() => _index = pageIndex);
  }

  void _handleSOSTap() async {
    // สั่นเตือนทันที
    HapticFeedback.heavyImpact();

    // ตรวจสอบจำนวนอุปกรณ์ที่เชื่อมต่อ (ดูจาก peers ที่ scan พบ)
    final connectedCount = appState.peers.length;

    // ถ้าไม่มีอุปกรณ์ในรายการ → แจ้งเตือนและเสนอให้สแกน
    if (connectedCount == 0) {
      if (!mounted) return;

      final shouldScan = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final theme = Theme.of(ctx);
          return AlertDialog(
            icon: Icon(
              Icons.warning_amber_rounded,
              color: theme.colorScheme.secondary,
              size: 28,
            ),
            title: Text(
              'ไม่มีอุปกรณ์ใกล้เคียง',
              style: theme.textTheme.titleLarge,
            ),
            content: Text(
              'ยังไม่พบอุปกรณ์ใกล้เคียง\nต้องการสแกนหาอุปกรณ์ก่อนส่ง SOS หรือไม่?',
              style: theme.textTheme.bodyMedium,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('ยกเลิก'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('สแกนเลย'),
              ),
            ],
          );
        },
      );

      if (shouldScan == true) {
        // เปลี่ยนไปหน้าหลักและเปิด scan dialog
        setState(() => _index = 0);
      }
      return;
    }

    // มีอุปกรณ์ในรายการ → แสดง Dialog ยืนยัน
    if (!mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        return AlertDialog(
          icon: Icon(Icons.warning_amber_rounded, color: cs.primary, size: 32),
          title: Text('ส่งสัญญาณ SOS?', style: theme.textTheme.headlineSmall),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'จะส่งสัญญาณฉุกเฉินแบบ Broadcast ไปยังอุปกรณ์ใกล้เคียงทั้งหมด',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.radar, color: cs.secondary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'อุปกรณ์ใกล้เคียง: $connectedCount เครื่อง',
                      style: theme.textTheme.titleSmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ยกเลิก'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.warning_amber_rounded, size: 20),
              label: const Text('ส่ง SOS'),
            ),
          ],
        );
      },
    );

    // ถ้ายกเลิก → ไม่ทำอะไร
    if (confirm != true) return;

    // สั่นอีกครั้งก่อนส่ง
    HapticFeedback.heavyImpact();

    // 📍 ดึงพิกัด GPS ปัจจุบัน
    String? latitude;
    String? longitude;
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );
      latitude = position.latitude.toStringAsFixed(6);
      longitude = position.longitude.toStringAsFixed(6);
      debugPrint('📍 GPS Location: $latitude, $longitude');
    } catch (e) {
      debugPrint('⚠️ Cannot get GPS location: $e');
    }

    // ส่ง SOS พร้อมข้อมูลเวลาและพิกัด
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    
    // สร้างข้อความ SOS
    String message = '🚨 SOS: ช่วยด้วย! ฉันอยู่ในสถานการณ์ฉุกเฉิน\n⏰ เวลา: $timeStr';
    if (latitude != null && longitude != null) {
      final googleMapsUrl = 'https://www.google.com/maps?q=$latitude,$longitude';
      message += '\n📍 ตำแหน่ง: $googleMapsUrl';
    }

    // ส่งข้อความ SOS ไปยังอุปกรณ์ใกล้เคียง
    await appState.send(message);
    
    // 🚨 เปิดโหมด SOS และ Broadcast สถานะพร้อมพิกัด
    await appState.broadcastSOSStatus(
      isActive: true,
      latitude: latitude != null ? double.parse(latitude) : null,
      longitude: longitude != null ? double.parse(longitude) : null,
    );

    // บันทึก Log
    debugPrint('🚨 SOS SENT (broadcast) to $connectedCount devices at $now');

    // แสดงการยืนยัน
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '✅ ส่ง SOS สำเร็จ!\nกำลังส่งแบบ Broadcast ไปยังอุปกรณ์ใกล้เคียง',
                  style: const TextStyle(fontSize: 15),
                ),
              ),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );

      // สั่นเบา ๆ เป็นยืนยัน
      Future.delayed(const Duration(milliseconds: 200), () {
        HapticFeedback.mediumImpact();
      });
    }
  }

  void _onHorizontalDrag(DragUpdateDetails details) {
    if (details.primaryDelta != null && details.primaryDelta!.abs() > 10) {
      if (details.primaryDelta! < 0 && _index < _items.length - 1) {
        setState(() => _index += 1);
      } else if (details.primaryDelta! > 0 && _index > 0) {
        setState(() => _index -= 1);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      body: _pages[_index],
      // Custom floating nav bar
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 12, right: 12),
        child: GestureDetector(
          onHorizontalDragUpdate: _onHorizontalDrag,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [cs.surfaceContainer, cs.surfaceContainerHigh],
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: cs.outlineVariant.withOpacity(0.3),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: cs.shadow.withOpacity(0.2),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            height: 60,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(_items.length, (i) {
                final item = _items[i];
                final selected =
                    !item.isSOS &&
                    i == _index + (i > 2 ? 1 : 0); // Adjust selection for SOS

                if (item.isSOS) {
                  // Special SOS button in the center with scale animation
                  return Expanded(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 1.0, end: 1.0),
                      duration: const Duration(milliseconds: 200),
                      builder: (context, scale, child) {
                        return Transform.scale(
                          scale: scale,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () {
                              // Trigger haptic feedback
                              HapticFeedback.heavyImpact();
                              _onNavTap(i);
                            },
                            onTapDown: (_) {
                              // Scale down animation
                              (context as Element).markNeedsBuild();
                            },
                            child: Container(
                              margin: const EdgeInsets.symmetric(
                                vertical: 6,
                                horizontal: 6,
                              ),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFE53E3E),
                                    Color(0xFFFF0000),
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.red.withOpacity(0.5),
                                    blurRadius: 12,
                                    spreadRadius: 2,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    item.icon,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    item.label,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                }

                // Regular navigation items - with smooth animation
                return Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _onNavTap(i);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 0,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? cs.primaryContainer.withOpacity(0.5)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            child: Icon(
                              item.icon,
                              color: selected
                                  ? cs.primary
                                  : cs.onSurfaceVariant,
                              size: selected ? 24 : 22,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.label,
                            style: TextStyle(
                              color: selected
                                  ? cs.primary
                                  : cs.onSurfaceVariant,
                              fontSize: selected ? 11 : 10,
                              fontWeight: selected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
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
  final bool isSOS;
  const _NavItem({required this.icon, required this.label, this.isSOS = false});
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late AnimationController _blinkController;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }

  // Helper method สำหรับสร้าง content ของ peer card
  Widget _buildPeerCardContent(
    Peer p,
    bool isSOS,
    bool isSOSActive,
    bool isRescue,
    AppState appState,
  ) {
    return Row(
      children: [
        // 🚨 Icon SOS / 🚑 Icon หน่วยกู้ภัย / icon ปกติ
        Icon(
          isSOS
              ? Icons.warning_amber_rounded
              : isRescue
                  ? Icons.local_hospital
                  : Icons.device_hub,
          color: isSOS
              ? Colors.red
              : isRescue
                  ? Colors.blue
                  : Colors.blue,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      p.name.isNotEmpty ? p.name : 'อุปกรณ์ไม่ระบุชื่อ',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isSOS
                            ? Colors.red
                            : isRescue
                                ? Colors.blue
                                : Colors.black,
                      ),
                    ),
                  ),
                  // 🚨 Badge SOS สีแดง
                  if (isSOS) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        '🚨 SOS',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                  // 🚑 Badge หน่วยกู้ภัย
                  if (isRescue && !isSOS) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        '🚑 กู้ภัย',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              Text(
                'ID: ${p.id}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              // 📍 แสดงระยะห่าง (อัพเดททุก 5 วินาที)
              StreamBuilder<Position>(
                stream: Geolocator.getPositionStream(
                  locationSettings: const LocationSettings(
                    accuracy: LocationAccuracy.best,
                    distanceFilter: 1, // อัพเดทเมื่อเคลื่อนที่ 1 เมตร
                  ),
                ),
                builder: (context, snapshot) {
                  Position? myPosition;

                  if (snapshot.hasData) {
                    myPosition = snapshot.data;
                  } else {
                    // Fallback: ถ้าไม่มี stream ให้แสดงข้อความรอ
                    return Row(
                      children: [
                        const SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'กำลังหา GPS...',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    );
                  }

                  final distance = appState.getDistanceToPeerSync(p.id, myPosition);

                  if (distance == null) {
                    // แสดงว่ายังไม่ได้รับตำแหน่ง GPS ของ peer
                    return Row(
                      children: [
                        Icon(
                          Icons.location_off,
                          size: 12,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'ไม่มีตำแหน่ง',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    );
                  }

                  // แปลงหน่วย: < 1 km แสดงเป็นเมตร, >= 1 km แสดงเป็น km
                  String distanceText;
                  Color distanceColor;

                  if (distance < 1000) {
                    distanceText = '${distance.toStringAsFixed(0)} m';
                    // สีเขียวถ้าใกล้มาก (< 10m), เหลืองถ้าปานกลาง, ส้มถ้าไกล
                    if (distance < 10) {
                      distanceColor = Colors.green.shade700;
                    } else if (distance < 50) {
                      distanceColor = Colors.orange.shade700;
                    } else {
                      distanceColor = Colors.grey.shade700;
                    }
                  } else {
                    distanceText = '${(distance / 1000).toStringAsFixed(2)} km';
                    distanceColor = Colors.grey.shade700;
                  }

                  return Row(
                    children: [
                      Icon(
                        Icons.my_location,
                        size: 12,
                        color: distanceColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        distanceText,
                        style: TextStyle(
                          fontSize: 11,
                          color: distanceColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => EmergencyChatScreen(peer: p),
              ),
            );
          },
          icon: const Icon(Icons.chat, size: 14),
          label: const Text(
            'แชท',
            style: TextStyle(fontSize: 12),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: isRescue ? Colors.blue : Colors.green,
            foregroundColor: Colors.white,
            minimumSize: const Size(70, 32),
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 4,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) {
        final peers = appState.peers;
        final theme = Theme.of(context);
        final cs = theme.colorScheme;

        return Scaffold(
          appBar: AppBar(
            title: const Text('หน้าหลัก'),
            backgroundColor: cs.surface,
            elevation: 0,
            actions: [
              // ปุ่มการแจ้งเตือน (ย้ายมาจากแท็บล่าง)
              IconButton(
                icon: const Icon(Icons.notifications),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const NotificationsScreen(),
                    ),
                  );
                },
                tooltip: 'การแจ้งเตือน',
              ),
            ],
          ),
          body: Stack(
            children: [
              // Main content
              SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 60),

                      // Discovered Devices (แสดงเป็น simple card) - ย้ายขึ้นมาบนสุด
                      if (peers.isNotEmpty) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.devices,
                                    color: Colors.blue,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'อุปกรณ์ที่พบ',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const Spacer(),
                                  // 🚑 จำนวนหน่วยกู้ภัย
                                  if (peers.where((p) => appState.isPeerRescue(p.id)).isNotEmpty) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.blue,
                                          width: 1,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.local_hospital,
                                            color: Colors.blue,
                                            size: 12,
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            '${peers.where((p) => appState.isPeerRescue(p.id)).length}',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.blue,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                  ],
                                  // ⚠️ จำนวนโหมด SOS (ยังไม่กดปุ่ม)
                                  if (peers.where((p) => appState.isSOSModePeer(p.id) && !appState.isSOSPeer(p.id)).isNotEmpty) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.orange,
                                          width: 1,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.emergency,
                                            color: Colors.orange,
                                            size: 12,
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            '${peers.where((p) => appState.isSOSModePeer(p.id) && !appState.isSOSPeer(p.id)).length}',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.orange,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                  ],
                                  // 🚨 จำนวนผู้ขอความช่วยเหลือด่วน (กดปุ่ม SOS)
                                  if (peers.where((p) => appState.isSOSPeer(p.id)).isNotEmpty) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.red.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.red,
                                          width: 1,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.warning_amber_rounded,
                                            color: Colors.red,
                                            size: 12,
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            '${peers.where((p) => appState.isSOSPeer(p.id)).length}',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.red,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 12),
                              ...peers.take(3).map((p) {
                                // 🚑 เช็คว่าเป็นหน่วยกู้ภัยหรือไม่
                                final isRescue = appState.isPeerRescue(p.id);
                                // 🚨 เช็คว่าอยู่ในโหมด SOS หรือไม่
                                final isSOSMode = appState.isSOSModePeer(p.id);
                                // 🚨 เช็คว่ากดปุ่ม SOS (ขอความช่วยเหลือด่วน) หรือไม่
                                final isSOSActive = appState.isSOSPeer(p.id);
                                // รวม: แสดงสีแดงถ้าอยู่ในโหมด SOS หรือกดปุ่ม SOS
                                final isSOS = isSOSMode || isSOSActive;

                                // 🚨 ถ้ากด SOS ฉุกเฉินด่วน ให้กระพริบ
                                if (isSOSActive) {
                                  return AnimatedBuilder(
                                    animation: _blinkController,
                                    builder: (context, child) {
                                      final opacity = _blinkController.value;
                                      return Container(
                                        margin: const EdgeInsets.only(bottom: 6),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.red.withOpacity(0.15 + (opacity * 0.2)),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: Colors.red.withOpacity(0.5 + (opacity * 0.5)),
                                            width: 2,
                                          ),
                                        ),
                                        child: child,
                                      );
                                    },
                                    child: _buildPeerCardContent(p, isSOS, isSOSActive, isRescue, appState),
                                  );
                                }

                                // ไม่กระพริบสำหรับโหมด SOS หรือหน่วยกู้ภัย
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSOS
                                        ? Colors.red.withOpacity(0.15)
                                        : isRescue
                                            ? Colors.blue.withOpacity(0.15)
                                            : Colors.blue.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: isSOS
                                        ? Border.all(
                                            color: Colors.red,
                                            width: 2,
                                          )
                                        : isRescue
                                            ? Border.all(
                                                color: Colors.blue,
                                                width: 2,
                                              )
                                            : null,
                                  ),
                                  child: _buildPeerCardContent(p, isSOS, isSOSActive, isRescue, appState),
                                );
                              }),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],

                      // 🚨 โหมดฉุกเฉิน SOS Card
                      AnimatedBuilder(
                        animation: appState,
                        builder: (context, _) {
                          final isSOSActive = appState.isSOSActive;
                          return GestureDetector(
                            onTap: () async {
                              await appState.toggleSOSMode();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      isSOSActive
                                          ? '🚨 ปิดโหมด SOS แล้ว'
                                          : '🚨 เปิดโหมด SOS - กำลังค้นหาอุปกรณ์ใกล้เคียง...',
                                    ),
                                    backgroundColor: isSOSActive
                                        ? cs.surfaceContainerHighest
                                        : Colors.red,
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              }
                            },
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: isSOSActive
                                      ? [
                                          const Color(0xFFE53E3E),
                                          const Color(0xFFFF0000),
                                        ]
                                      : [
                                          cs.surfaceContainer,
                                          cs.surfaceContainerHigh,
                                        ],
                                ),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isSOSActive
                                      ? Colors.red.shade700
                                      : cs.outline.withOpacity(0.3),
                                  width: isSOSActive ? 3 : 1,
                                ),
                                boxShadow: isSOSActive
                                    ? [
                                        BoxShadow(
                                          color: Colors.red.withOpacity(0.5),
                                          blurRadius: 20,
                                          spreadRadius: 5,
                                        ),
                                      ]
                                    : [
                                        BoxShadow(
                                          color: cs.shadow.withOpacity(0.1),
                                          blurRadius: 8,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: isSOSActive
                                          ? Colors.white.withOpacity(0.2)
                                          : cs.errorContainer,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Icon(
                                      Icons.warning_amber_rounded,
                                      size: 40,
                                      color: isSOSActive
                                          ? Colors.white
                                          : cs.error,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'โหมดฉุกเฉิน SOS',
                                          style: theme.textTheme.titleLarge
                                              ?.copyWith(
                                                color: isSOSActive
                                                    ? Colors.white
                                                    : cs.onSurface,
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          isSOSActive
                                              ? 'กำลังค้นหาและส่งสัญญาณ SOS...'
                                              : 'เปิดเพื่อแจ้งสัญญาณฉุกเฉิน',
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                color: isSOSActive
                                                    ? Colors.white.withOpacity(0.9)
                                                    : cs.onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    value: isSOSActive,
                                    onChanged: (value) async {
                                      await appState.toggleSOSMode();
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              value
                                                  ? '🚨 เปิดโหมด SOS - กำลังค้นหาอุปกรณ์ใกล้เคียง...'
                                                  : '🚨 ปิดโหมด SOS แล้ว',
                                            ),
                                            backgroundColor: value
                                                ? Colors.red
                                                : cs.surfaceContainerHighest,
                                            duration: const Duration(
                                              seconds: 2,
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                    activeColor: Colors.white,
                                    activeTrackColor: Colors.red.shade700,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 16),

                      // 🚑 โหมดหน่วยกู้ภัย Card
                      AnimatedBuilder(
                        animation: appState,
                        builder: (context, _) {
                          final isRescueMode = appState.isRescueMode;
                          return GestureDetector(
                            onTap: () async {
                              await appState.toggleRescueMode();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      isRescueMode
                                          ? '🚑 ปิดโหมดหน่วยกู้ภัยแล้ว'
                                          : '🚑 เปิดโหมดหน่วยกู้ภัย - กำลังค้นหาผู้ต้องการความช่วยเหลือ...',
                                    ),
                                    backgroundColor: isRescueMode
                                        ? cs.surfaceContainerHighest
                                        : Colors.blue,
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              }
                            },
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: isRescueMode
                                      ? [
                                          Colors.blue.shade600,
                                          Colors.blue.shade400,
                                        ]
                                      : [
                                          cs.surfaceContainer,
                                          cs.surfaceContainerHigh,
                                        ],
                                ),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isRescueMode
                                      ? Colors.blue.shade700
                                      : cs.outline.withOpacity(0.3),
                                  width: isRescueMode ? 3 : 1,
                                ),
                                boxShadow: isRescueMode
                                    ? [
                                        BoxShadow(
                                          color: Colors.blue.withOpacity(0.5),
                                          blurRadius: 20,
                                          spreadRadius: 5,
                                        ),
                                      ]
                                    : [
                                        BoxShadow(
                                          color: cs.shadow.withOpacity(0.1),
                                          blurRadius: 8,
                                          offset: const Offset(0, 4),
                                          ),
                                      ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: isRescueMode
                                          ? Colors.white.withOpacity(0.2)
                                          : cs.tertiaryContainer,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Icon(
                                      Icons.local_hospital,
                                      size: 40,
                                      color: isRescueMode
                                          ? Colors.white
                                          : cs.tertiary,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'โหมดหน่วยกู้ภัย',
                                          style: theme.textTheme.titleLarge
                                              ?.copyWith(
                                                color: isRescueMode
                                                    ? Colors.white
                                                    : cs.onSurface,
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          isRescueMode
                                              ? 'กำลังค้นหาผู้ต้องการความช่วยเหลือ...'
                                              : 'เปิดเพื่อให้ความช่วยเหลือผู้อื่น',
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                color: isRescueMode
                                                    ? Colors.white.withOpacity(0.9)
                                                    : cs.onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    value: isRescueMode,
                                    onChanged: (value) async {
                                      await appState.toggleRescueMode();
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              value
                                                  ? '🚑 เปิดโหมดหน่วยกู้ภัย - กำลังค้นหาผู้ต้องการความช่วยเหลือ...'
                                                  : '🚑 ปิดโหมดหน่วยกู้ภัยแล้ว',
                                            ),
                                            backgroundColor: value
                                                ? Colors.blue
                                                : cs.surfaceContainerHighest,
                                            duration: const Duration(
                                              seconds: 2,
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                    activeColor: Colors.white,
                                    activeTrackColor: Colors.blue.shade700,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 16),

                      // Menu Grid - เหลือ 2 ปุ่ม
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 1.1,
                        children: [
                          _MenuCard(
                            title: 'เพื่อน',
                            subtitle: 'จัดการรายชื่อเพื่อน',
                            icon: Icons.people,
                            gradient: const LinearGradient(
                              colors: [Colors.green, Colors.greenAccent],
                            ),
                            badge: friendService.totalUnreadCount > 0
                                ? '${friendService.totalUnreadCount}'
                                : null,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const FriendsScreen(),
                                ),
                              );
                            },
                          ),
                          _MenuCard(
                            title: 'โปรไฟล์',
                            subtitle: 'ข้อมูลส่วนตัว',
                            icon: Icons.person,
                            gradient: const LinearGradient(
                              colors: [Colors.green, Colors.greenAccent],
                            ),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const ProfileScreen(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// Menu Card Widget
class _MenuCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Gradient gradient;
  final VoidCallback onTap;
  final String? badge;

  const _MenuCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 32, color: Colors.white),
                  const Spacer(),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                ],
              ),
            ),
            if (badge != null)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    badge!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Share (Demo)'),
        actions: [
          IconButton(
            tooltip:
                appState.transport.discoveryState == DiscoveryState.scanning
                ? 'Stop Scan'
                : 'Scan',
            onPressed: () async {
              if (appState.transport.discoveryState ==
                  DiscoveryState.scanning) {
                await appState.stopScan();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Stopped scanning')),
                  );
                }
              } else {
                await appState.startScan();
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('Scanning…')));
                }
              }
              setState(() {}); // refresh icon tooltip
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
                        : () async {
                            if (_msgCtrl.text.isNotEmpty) {
                              await appState.send(_msgCtrl.text);
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
                        ? () async {
                            await appState.send(_msgCtrl.text, to: _selected);
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
                        title: const Text('No devices yet'),
                        subtitle: const Text('Tap the sensor icon to Scan'),
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
  Map<String, bool> protocols = {
    'wifi': true,
    'bluetooth': true,
    'radio': false,
  };

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
      debugPrint('[Main] 🔑 Login สำเร็จ - เรียก onUserLogin()...');
      // เรียกใช้ onUserLogin เพื่อโหลดข้อมูลของ user
      await appState.onUserLogin();
      debugPrint('[Main] ✅ onUserLogin() เสร็จสิ้น');

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
    setState(() => protocols[protocol] = !(protocols[protocol] ?? false));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${protocol.toUpperCase()} ${protocols[protocol]! ? "enabled" : "disabled"}',
        ),
        backgroundColor: protocols[protocol]! ? Colors.green : Colors.grey,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = firebaseService.currentUser;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 32),
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'ตั้งค่า',
                      style: theme.textTheme.displaySmall,
                      textAlign: TextAlign.center,
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
                const SizedBox(height: 8),
                Text(
                  'ปรับแต่งการสื่อสารฉุกเฉิน',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
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

                const SizedBox(height: 24),

                // Theme Selection Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: cs.primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.palette,
                                color: cs.primary,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'ธีมสี',
                                    style: theme.textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'เลือกธีมแสดงผลสำหรับแอป',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        // Get current theme mode from ancestor
                        Builder(
                          builder: (context) {
                            // Find the OffGridApp state in the widget tree
                            final offGridState = context
                                .findAncestorStateOfType<_OffGridAppState>();
                            final currentMode =
                                offGridState?._themeMode ?? ThemeMode.system;

                            return Column(
                              children: [
                                // Theme Preview Cards
                                Row(
                                  children: [
                                    // Light Theme Preview
                                    Expanded(
                                      child: _ThemePreviewCard(
                                        label: 'สว่าง',
                                        icon: Icons.light_mode,
                                        isSelected:
                                            currentMode == ThemeMode.light,
                                        onTap: () => offGridState?.setThemeMode(
                                          ThemeMode.light,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    // Dark Theme Preview
                                    Expanded(
                                      child: _ThemePreviewCard(
                                        label: 'มืด',
                                        icon: Icons.dark_mode,
                                        isSelected:
                                            currentMode == ThemeMode.dark,
                                        onTap: () => offGridState?.setThemeMode(
                                          ThemeMode.dark,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    // System Theme Preview
                                    Expanded(
                                      child: _ThemePreviewCard(
                                        label: 'ระบบ',
                                        icon: Icons.brightness_auto,
                                        isSelected:
                                            currentMode == ThemeMode.system,
                                        onTap: () => offGridState?.setThemeMode(
                                          ThemeMode.system,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Profile Card - แสดงเฉพาะตอน login
                if (user != null)
                  Card(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            cs.secondaryContainer,
                            cs.secondaryContainer.withOpacity(0.7),
                          ],
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: cs.secondary,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    Icons.account_circle,
                                    color: cs.onSecondary,
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'โปรไฟล์ผู้ใช้',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    color: cs.onSecondaryContainer,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            AnimatedBuilder(
                              animation: friendService,
                              builder: (context, _) {
                                final currentUser = friendService.currentUser;
                                if (currentUser == null) {
                                  return Center(
                                    child: CircularProgressIndicator(
                                      color: cs.secondary,
                                    ),
                                  );
                                }

                                return Column(
                                  children: [
                                    // Device Name Setting
                                    Text(
                                      'ชื่อเครื่องที่จะแสดงให้คนอื่นเห็น',
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: cs.onSecondaryContainer
                                                .withOpacity(0.8),
                                          ),
                                    ),
                                    const SizedBox(height: 8),
                                    TextField(
                                      controller: TextEditingController(
                                        text: appState.deviceName,
                                      ),
                                      style: TextStyle(
                                        color: cs.onSecondaryContainer,
                                      ),
                                      decoration: InputDecoration(
                                        labelText: 'ชื่อเครื่อง',
                                        hintText: 'เช่น iPhone ของ John',
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                      onChanged: (v) =>
                                          setState(() => deviceName = v),
                                      onSubmitted: (v) {
                                        if (v.isNotEmpty) {
                                          // บันทึกชื่อเครื่องใน appState
                                          appState.setDeviceName(v);
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'บันทึกชื่อเครื่อง: $v',
                                              ),
                                              backgroundColor: cs.secondary,
                                            ),
                                          );
                                        }
                                      },
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 30,
                                          backgroundColor: cs.secondary,
                                          backgroundImage:
                                              currentUser.avatar != null
                                              ? NetworkImage(
                                                  currentUser.avatar!,
                                                )
                                              : null,
                                          child: currentUser.avatar == null
                                              ? Text(
                                                  currentUser.name.isNotEmpty
                                                      ? currentUser.name[0]
                                                            .toUpperCase()
                                                      : '?',
                                                  style: TextStyle(
                                                    fontSize: 24,
                                                    fontWeight: FontWeight.bold,
                                                    color: cs.onSecondary,
                                                  ),
                                                )
                                              : null,
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                currentUser.name,
                                                style: theme
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(
                                                      color: cs
                                                          .onSecondaryContainer,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                              ),
                                              Row(
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      'ID: ${currentUser.id}',
                                                      style: theme
                                                          .textTheme
                                                          .bodySmall
                                                          ?.copyWith(
                                                            color: cs
                                                                .onSecondaryContainer
                                                                .withOpacity(
                                                                  0.7,
                                                                ),
                                                          ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  IconButton(
                                                    icon: Icon(
                                                      Icons.copy,
                                                      size: 16,
                                                      color: cs
                                                          .onSecondaryContainer
                                                          .withOpacity(0.7),
                                                    ),
                                                    padding: EdgeInsets.zero,
                                                    constraints:
                                                        const BoxConstraints(),
                                                    onPressed: () {
                                                      Clipboard.setData(
                                                        ClipboardData(
                                                          text: currentUser.id,
                                                        ),
                                                      );
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        SnackBar(
                                                          content: const Text(
                                                            'คัดลอก User ID แล้ว!',
                                                          ),
                                                          backgroundColor:
                                                              cs.secondary,
                                                          duration:
                                                              const Duration(
                                                                seconds: 1,
                                                              ),
                                                        ),
                                                      );
                                                    },
                                                    tooltip: 'คัดลอก User ID',
                                                  ),
                                                ],
                                              ),
                                              if (currentUser.bio != null &&
                                                  currentUser.bio!.isNotEmpty)
                                                Text(
                                                  currentUser.bio!,
                                                  style: theme
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.copyWith(
                                                        color: cs
                                                            .onSecondaryContainer
                                                            .withOpacity(0.8),
                                                      ),
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    SizedBox(
                                      width: double.infinity,
                                      child: FilledButton.icon(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: cs.secondary,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                        ),
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  const ProfileScreen(),
                                            ),
                                          );
                                        },
                                        icon: const Icon(Icons.edit),
                                        label: const Text('แก้ไขโปรไฟล์'),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ), // ปิด Container
                  ), // ปิด Card ของ Profile (if user != null)
                // Protocols Card
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  color: const Color(0xFF1A237E), // Navy blue card background
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.wifi_tethering,
                              color: const Color(0xFF1565C0),
                              size: 28,
                            ), // Navy blue icon
                            const SizedBox(width: 8),
                            const Text(
                              'Device Search Protocols',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ), // White text
                          ],
                        ),
                        const SizedBox(height: 20),
                        // WiFi Direct
                        _ProtocolSwitch(
                          icon: Icons.wifi,
                          title: 'WiFi Direct',
                          subtitle: 'Peer-to-peer connection',
                          value: protocols['wifi']!,
                          onChanged: (_) => toggleProtocol('wifi'),
                        ),
                        const SizedBox(height: 12),
                        // Bluetooth
                        _ProtocolSwitch(
                          icon: Icons.bluetooth,
                          title: 'Bluetooth',
                          subtitle: 'Short-range discovery',
                          value: protocols['bluetooth']!,
                          onChanged: (_) => toggleProtocol('bluetooth'),
                        ),
                        const SizedBox(height: 12),
                        // Radio Mesh
                        _ProtocolSwitch(
                          icon: Icons.radio,
                          title: 'Radio Mesh',
                          subtitle: 'Long-range network',
                          value: protocols['radio']!,
                          onChanged: (_) => toggleProtocol('radio'),
                        ),
                        const SizedBox(height: 24),
                        // Protocol Info
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF1565C0,
                            ).withOpacity(0.08), // Navy blue background
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFF1565C0).withOpacity(0.2),
                            ), // Navy blue border
                          ),
                          child: Text(
                            'Active Protocols: ' +
                                (protocols.entries
                                            .where((e) => e.value)
                                            .map((e) => e.key.toUpperCase())
                                            .join(', ') ==
                                        ''
                                    ? 'None'
                                    : protocols.entries
                                          .where((e) => e.value)
                                          .map((e) => e.key.toUpperCase())
                                          .join(', ')),
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.white70,
                            ), // White text
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Theme Preview Card Widget
class _ThemePreviewCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemePreviewCard({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOutCubic,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? cs.primary : cs.outline.withOpacity(0.2),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: cs.primary.withOpacity(0.3),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : [],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Theme icon (simple, no background)
            Icon(
              icon,
              size: 32,
              color: isSelected ? cs.primary : cs.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: isSelected ? cs.primary : cs.onSurfaceVariant,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProtocolSwitch extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ProtocolSwitch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: cs.secondaryContainer.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: cs.onSurfaceVariant, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: cs.onSurface.withOpacity(0.7),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged, activeColor: cs.primary),
        ],
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
