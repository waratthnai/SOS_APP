import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:offgrid_sos/core/app_state.dart';
import 'package:offgrid_sos/cloud/firebase_service.dart';
import 'package:offgrid_sos/core/logger.dart';
import 'package:offgrid_sos/ui/device_name_setup_screen.dart';
import 'package:offgrid_sos/ui/debug_screen.dart';
import 'package:offgrid_sos/main.dart';

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
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Logged out'),
          backgroundColor: Colors.blueGrey,
        ),
      );
    }
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

    final offGridState = context.findAncestorStateOfType<OffGridAppState>();
    final currentMode = offGridState?.themeMode ?? ThemeMode.system;
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

