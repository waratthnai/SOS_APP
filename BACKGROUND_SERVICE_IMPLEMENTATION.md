# 🔄 Background Service Implementation

## ✅ สิ่งที่ติดตั้งเรียบร้อยแล้ว

### 1. **Dependencies ที่เพิ่มใน `pubspec.yaml`**
```yaml
flutter_foreground_task: ^8.15.0
flutter_local_notifications: ^18.0.1
```

### 2. **ไฟล์ใหม่ที่สร้าง**
- `lib/services/background_service.dart` - Background Service สำหรับแจ้งเตือน SOS

### 3. **Android Manifest Permissions**
เพิ่ม permissions ใน `android/app/src/main/AndroidManifest.xml`:
- `FOREGROUND_SERVICE`
- `FOREGROUND_SERVICE_LOCATION`
- `WAKE_LOCK`
- `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`

### 4. **Foreground Service Declaration**
เพิ่ม Service declaration ใน AndroidManifest.xml:
```xml
<service
    android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
    android:foregroundServiceType="location"
    android:exported="false"
    android:stopWithTask="false" />
```

---

## 🎯 ฟีเจอร์ที่ใช้งานได้

### 1. **Background Service**
- **เปิด/ปิด** จากหน้า Settings → แจ้งเตือนเบื้องหลัง
- แสดง **Persistent Notification** เมื่อแอปทำงานเบื้องหลัง
- อัปเดตสถานะทุก 1 นาที

### 2. **SOS Alert Notification**
- รับการแจ้งเตือน SOS แม้ **แอปย่อไปใช้แอปอื่น**
- แสดง:
  - ชื่อผู้ส่ง SOS
  - ข้อความ SOS
  - พิกัด GPS (ถ้ามี)
- **High Priority Notification** พร้อมเสียงและ vibration

### 3. **ปุ่มควบคุมในหน้า Settings**
- Switch เปิด/ปิด Background Service
- แสดงสถานะ "กำลังทำงาน" หรือ "ปิดอยู่"
- คำอธิบายการใช้งานและข้อจำกัด

---

## ⚠️ ข้อจำกัดที่สำคัญ

### **Nearby Connections จำเป็นต้องมีแอปทำงานอยู่**
Nearby Connections (Bluetooth/WiFi Direct) ของ Google **ไม่สามารถทำงานเมื่อแอปปิดสนิท**

#### ✅ สิ่งที่ทำได้:
- แอป**เปิดอยู่** แต่**ย่อไปใช้แอปอื่น** (กด Home button)
- Background Service จะทำให้แอปทำงานต่อเนื่อง
- รับสัญญาณ SOS ได้ปกติ

#### ❌ สิ่งที่ทำไม่ได้:
- แอป**ปิดสนิท** (swipe ออกจาก recent apps)
- Nearby Connections จะ**หยุดทำงานทันที**
- **ไม่สามารถรับสัญญาณ SOS ได้**

---

## 📱 วิธีใช้งาน

### 1. **เปิด Background Service**
1. ไปที่ Settings (⚙️)
2. เลื่อนลงมาหาส่วน "แจ้งเตือนเบื้องหลัง"
3. เปิด Switch
4. อนุญาต permissions ที่ระบบขอ (Battery Optimization)

### 2. **ทดสอบการแจ้งเตือน**
1. เปิด Background Service
2. กด Home button (ย่อแอป)
3. ให้เพื่อนส่งสัญญาณ SOS
4. จะได้รับ Notification แม้ใช้แอปอื่นอยู่

### 3. **ปิด Background Service**
1. กลับไปหน้า Settings
2. ปิด Switch "แจ้งเตือนเบื้องหลัง"
3. Notification จะหายไป

---

## 🔧 Technical Details

### **Background Service Handler**
```dart
class BackgroundTaskHandler extends TaskHandler {
  @override
  void onRepeatEvent(DateTime timestamp) {
    // ทำงานทุก 5 วินาที
    // อัปเดต Notification ทุก 1 นาที
  }
}
```

### **SOS Notification**
```dart
await _backgroundService.showSOSNotification(
  senderName: 'ชื่อผู้ส่ง',
  message: 'ข้อความ SOS',
  latitude: 13.7563,
  longitude: 100.5018,
);
```

### **Integration กับ AppState**
```dart
// เปิด Background Service
await appState.startBackgroundService();

// ปิด Background Service
await appState.stopBackgroundService();

// เช็คสถานะ
bool isRunning = appState.isBackgroundServiceEnabled;
```

---

## 🚀 การพัฒนาต่อยอด

### 1. **FCM (Firebase Cloud Messaging)** - สำหรับ Internet Connection
- ทำงานได้แม้แอปปิดสนิท
- ต้องมี **Internet Connection**
- เหมาะสำหรับการแจ้งเตือนทั่วไป

### 2. **Hybrid Approach**
- **Off-Grid**: Nearby Connections + Foreground Service
- **Online**: FCM
- เปลี่ยนโหมดอัตโนมัติตามสถานะ Network

### 3. **Battery Optimization**
- ลด interval จาก 5 วินาที เป็น 30 วินาที
- หยุด Background Service อัตโนมัติเมื่อ Battery ต่ำ
- ให้ผู้ใช้กำหนด interval เอง

---

## ✅ Checklist

- [x] ติดตั้ง `flutter_foreground_task`
- [x] ติดตั้ง `flutter_local_notifications`
- [x] แก้ไข AndroidManifest.xml
- [x] สร้าง BackgroundService class
- [x] เพิ่ม BackgroundService ใน AppState
- [x] เพิ่มปุ่มควบคุมในหน้า Settings
- [x] เชื่อมต่อกับ SOS notification system
- [x] ทดสอบและแก้ไข errors

---

## 📝 หมายเหตุ

1. **ต้อง Build บน Android ตัวจริง** - Foreground Service ไม่ทำงานบน Emulator
2. **ต้องอนุญาต Battery Optimization** - เพื่อให้แอปทำงานต่อเนื่อง
3. **แจ้งผู้ใช้** - อธิบายข้อจำกัดของ Nearby Connections ให้ชัดเจน
4. **Battery Usage** - แจ้งเตือนว่า Background Service จะกิน Battery

---

## 🎉 สรุป

Background Service ได้ถูกติดตั้งและตั้งค่าเรียบร้อยแล้ว! 

✅ **ทำงานได้**:
- แอปเปิดอยู่แต่ย่อไปใช้แอปอื่น
- รับ SOS Notification ได้ปกติ
- แสดง Persistent Notification

⚠️ **ข้อจำกัด**:
- Nearby Connections ต้องมีแอปเปิดอยู่
- ปิดแอปสนิทจะไม่ได้รับสัญญาณ
- ต้อง Build บนเครื่องจริงเพื่อทดสอบ

🚀 **พร้อมใช้งาน**!
