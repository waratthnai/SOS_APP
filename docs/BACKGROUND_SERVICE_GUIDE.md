# 🔔 คู่มือทำให้แอพรันเบื้องหลัง (Background Service)

## ⚠️ ข้อจำกัดสำคัญ:

**Nearby Connections ไม่สามารถทำงานเบื้องหลังได้** เพราะ:
- ต้องการให้แอพอยู่ใน Foreground
- Android/iOS จะหยุด Bluetooth/WiFi scanning เมื่อแอพปิด
- เป็นข้อจำกัดของระบบปฏิบัติการ

## 💡 แนวทางแก้ไข 2 วิธี:

---

## วิธีที่ 1: ✅ **Foreground Service** (แนะนำ!)

ทำให้แอพรันตลอดเวลาด้วย Notification แบบ persistent

### ขั้นตอนการทำ:

### 1. เพิ่ม Dependencies

เพิ่มใน `pubspec.yaml`:

```yaml
dependencies:
  flutter_foreground_task: ^8.15.0  # สำหรับ Foreground Service
  flutter_local_notifications: ^18.0.1  # สำหรับ Notifications
```

จากนั้นรัน:
```bash
flutter pub get
```

---

### 2. ตั้งค่า Android (android/app/src/main/AndroidManifest.xml)

เพิ่ม permissions และ service:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- เพิ่ม permissions เหล่านี้ -->
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />
    <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"/>

    <application>
        <!-- เพิ่ม Service นี้ใน <application> tag -->
        <service
            android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
            android:foregroundServiceType="location|connectedDevice"
            android:exported="false" />
    </application>
</manifest>
```

---

### 3. สร้างไฟล์ Background Service

สร้างไฟล์ใหม่: `lib/services/background_service.dart`

```dart
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter/material.dart';

class BackgroundService {
  static BackgroundService? _instance;
  static BackgroundService get instance => _instance ??= BackgroundService._();
  BackgroundService._();

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  // เริ่ม Foreground Service
  Future<bool> start() async {
    if (_isRunning) {
      debugPrint('⚠️ Background Service กำลังทำงานอยู่แล้ว');
      return false;
    }

    // Initialize Foreground Task
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'offgrid_sos_foreground',
        channelName: 'Off-Grid SOS Service',
        channelDescription: 'รับสัญญาณ SOS และค้นหาผู้ต้องการความช่วยเหลือ',
        channelImportance: NotificationChannelImportance.HIGH,
        priority: NotificationPriority.HIGH,
        iconData: const NotificationIconData(
          resType: ResourceType.mipmap,
          resPrefix: ResourcePrefix.ic,
          name: 'launcher',
        ),
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 5000, // เช็คทุก 5 วินาที
        isOnceEvent: false,
        autoRunOnBoot: true, // เริ่มอัตโนมัติเมื่อเปิดเครื่อง
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    // Start Service
    final success = await FlutterForegroundTask.startService(
      notificationTitle: '🚨 Off-Grid SOS กำลังทำงาน',
      notificationText: 'พร้อมรับสัญญาณฉุกเฉิน',
      callback: backgroundTaskCallback,
    );

    if (success) {
      _isRunning = true;
      debugPrint('✅ Background Service เริ่มทำงาน');
    } else {
      debugPrint('❌ ไม่สามารถเริ่ม Background Service ได้');
    }

    return success;
  }

  // หยุด Foreground Service
  Future<bool> stop() async {
    if (!_isRunning) {
      debugPrint('⚠️ Background Service ไม่ได้ทำงานอยู่');
      return false;
    }

    final success = await FlutterForegroundTask.stopService();
    
    if (success) {
      _isRunning = false;
      debugPrint('✅ Background Service หยุดทำงาน');
    } else {
      debugPrint('❌ ไม่สามารถหยุด Background Service ได้');
    }

    return success;
  }

  // อัพเดท Notification
  Future<void> updateNotification({
    required String title,
    required String text,
  }) async {
    if (!_isRunning) return;

    await FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: text,
    );
  }
}

// Background Task Callback
@pragma('vm:entry-point')
void backgroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(BackgroundTaskHandler());
}

class BackgroundTaskHandler extends TaskHandler {
  @override
  void onStart(DateTime timestamp) {
    debugPrint('🔄 Background Task Started at: $timestamp');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // ทำงานทุก 5 วินาที (ตาม interval ที่ตั้งไว้)
    debugPrint('💓 Background Task Heartbeat: $timestamp');
    
    // อัพเดท notification
    FlutterForegroundTask.updateService(
      notificationTitle: '🚨 Off-Grid SOS กำลังทำงาน',
      notificationText: 'พร้อมรับสัญญาณฉุกเฉิน - ${timestamp.hour}:${timestamp.minute}',
    );
  }

  @override
  void onDestroy(DateTime timestamp) {
    debugPrint('⛔ Background Task Destroyed at: $timestamp');
  }

  @override
  void onNotificationButtonPressed(String id) {
    debugPrint('🔘 Notification Button Pressed: $id');
  }

  @override
  void onNotificationPressed() {
    debugPrint('📱 Notification Pressed - Opening App');
    FlutterForegroundTask.launchApp('/');
  }
}
```

---

### 4. แก้ไข main.dart

เพิ่มการเริ่ม Background Service:

```dart
import 'services/background_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // ... Firebase และ services อื่นๆ ...
  
  // 🔔 เริ่ม Background Service
  await BackgroundService.instance.start();
  
  runApp(OffGridApp());
}
```

---

### 5. เพิ่มปุ่มควบคุม Background Service ในหน้าตั้งค่า

ใน Settings Screen เพิ่มปุ่ม:

```dart
// ใน lib/ui/settings_screen.dart หรือหน้าตั้งค่า

ListTile(
  leading: Icon(
    BackgroundService.instance.isRunning 
      ? Icons.notifications_active 
      : Icons.notifications_off,
    color: BackgroundService.instance.isRunning 
      ? Colors.green 
      : Colors.grey,
  ),
  title: Text('บริการเบื้องหลัง'),
  subtitle: Text(
    BackgroundService.instance.isRunning
      ? 'กำลังทำงาน - รับสัญญาณ SOS ตลอดเวลา'
      : 'ปิดอยู่ - จะไม่ได้รับสัญญาณเมื่อปิดแอพ',
  ),
  trailing: Switch(
    value: BackgroundService.instance.isRunning,
    onChanged: (value) async {
      if (value) {
        await BackgroundService.instance.start();
      } else {
        await BackgroundService.instance.stop();
      }
      setState(() {});
    },
  ),
)
```

---

## วิธีที่ 2: 🔔 **Firebase Cloud Messaging (FCM)** (สำหรับอินเทอร์เน็ต)

ถ้ามีอินเทอร์เน็ต ใช้ FCM ส่ง push notification:

### ข้อดี:
- ✅ ทำงานแม้แอพปิด
- ✅ ไม่กิน Battery
- ✅ รับ Notification ได้ทันที

### ข้อเสีย:
- ❌ **ต้องมีอินเทอร์เน็ต**
- ❌ ไม่ใช่ Off-Grid แท้

### วิธีทำ:

1. เมื่อมีคนกด SOS → ส่งข้อความไปที่ Firebase
2. Firebase ส่ง Push Notification ไปยังอุปกรณ์ทั้งหมดในพื้นที่
3. ผู้รับเห็น Notification แม้แอพปิด

---

## 📊 เปรียบเทียบ:

| ฟีเจอร์ | Foreground Service | FCM |
|---------|-------------------|-----|
| ทำงานแบบ Off-Grid | ✅ ใช่ | ❌ ต้องมีเน็ต |
| ทำงานเมื่อแอพปิด | ⚠️ แอพต้อง minimize | ✅ ใช่ |
| กิน Battery | ⚠️ ปานกลาง | ✅ น้อย |
| Nearby Connections | ✅ ทำงาน | ❌ ไม่ทำงาน |

---

## 🎯 คำแนะนำสำหรับแอพ SOS:

**ใช้ Foreground Service** เพราะ:
- ✅ ทำงานได้แบบ Off-Grid
- ✅ Nearby Connections ยังทำงานได้
- ✅ แสดง Notification แบบ persistent
- ⚠️ แต่ต้องให้ผู้ใช้เปิดแอพไว้ (minimize) ไม่ใช่ปิดสนิท

**ผู้ใช้งานต้อง:**
1. เปิดแอพ
2. เปิดโหมด SOS หรือ Rescue
3. กด Home (ไม่ใช่ปิดแอพ)
4. แอพจะรันเบื้องหลังพร้อม Notification

---

## ⚡ Tips เพิ่มเติม:

### ป้องกันแอพถูกปิด:

1. **ปิด Battery Optimization**
```dart
// เพิ่มใน main.dart
await Permission.ignoreBatteryOptimizations.request();
```

2. **ตั้งค่า Auto-start** (ต้องให้ผู้ใช้ตั้งเอง)
- Settings → Apps → Off-Grid SOS → Battery → Unrestricted

3. **Lock App ใน Recent Apps**
- ผู้ใช้ต้อง lock ไว้ไม่ให้ระบบปิด

---

## 🚀 สรุป:

**สำหรับแอพ SOS Off-Grid:**
- ใช้ **Foreground Service** + **Persistent Notification**
- แอพต้องเปิดไว้ (minimize) ตลอดเวลา
- ไม่สามารถทำงานได้ถ้าปิดแอพสนิท (ข้อจำกัดของ Nearby Connections)

ต้องการให้ผมสร้างโค้ดสำเร็จรูปให้ไหมครับ? 🛠️
