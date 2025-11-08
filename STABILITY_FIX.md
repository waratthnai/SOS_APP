# 🔧 คู่มือแก้ปัญหาความเสถียรของโหมด SOS และ Rescue

## ปัญหาที่พบ:
1. โหมด SOS ไม่เสถียร เวลาใช้งานครั้งแรก
2. UI ไม่อัพเดททันเวลา
3. กดปุ่มซ้ำเร็วๆ ทำให้ state ผิดพลาด

## วิธีแก้ (ใน `lib/core/app_state.dart`):

### ขั้นตอนที่ 1: เพิ่ม Lock Flags

หาบรรทัดที่มี:
```dart
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
```

แล้วเพิ่มด้านล่าง:
```dart
  // 🔒 ป้องกันการกดปุ่มซ้ำ
  bool _isTogglingRescue = false;
  bool _isTogglingSOS = false;
```

---

### ขั้นตอนที่ 2: แก้ไข `toggleRescueMode()`

หาฟังก์ชัน `Future<void> toggleRescueMode() async {`

แทนที่ทั้งฟังก์ชันด้วย:

```dart
Future<void> toggleRescueMode() async {
  // 🔒 ป้องกันการกดซ้ำ
  if (_isTogglingRescue) {
    debugPrint('⚠️ กำลังประมวลผลอยู่ กรุณารอสักครู่...');
    return;
  }
  
  _isTogglingRescue = true;
  _isRescueMode = !_isRescueMode;
  debugPrint('🔍 [DEBUG] toggleRescueMode: _isRescueMode = $_isRescueMode');
  
  try {
    // ⚠️ ถ้าเปิด Rescue Mode ให้ปิด SOS Mode อัตโนมัติ
    if (_isRescueMode && _isSOSActive) {
      debugPrint('⚠️ ปิด SOS Mode เพื่อเปิด Rescue Mode');
      _isSOSActive = false;
      await broadcastSOSStatus(isActive: false);
    }
    
    // 🔄 อัพเดท UI ทันที
    notifyListeners();
    
    // Broadcast สถานะหน่วยกู้ภัย
    if (_isRescueMode) {
      debugPrint('🚑 กำลังเปิดโหมดหน่วยกู้ภัย...');
      await _broadcastRescueStatus(true);
      
      // หยุดก่อน แล้วค่อยเริ่มใหม่ (เพิ่มความเสถียร)
      await stopScan();
      await Future.delayed(const Duration(milliseconds: 500));
      await startScan();
      
      debugPrint('🚑 ✅ เปิดโหมดหน่วยกู้ภัย + เริ่มสแกนสำเร็จ');
    } else {
      debugPrint('🚑 กำลังปิดโหมดหน่วยกู้ภัย...');
      await _broadcastRescueStatus(false);
      await stopScan();
      debugPrint('🚑 ✅ ปิดโหมดหน่วยกู้ภัย + หยุดสแกนสำเร็จ');
    }
    
    // อัพเดท UI อีกครั้งหลัง operation เสร็จ
    notifyListeners();
  } catch (e) {
    debugPrint('❌ Error in toggleRescueMode: $e');
    // ถ้า error ให้ rollback state
    _isRescueMode = !_isRescueMode;
    notifyListeners();
  } finally {
    _isTogglingRescue = false;
  }
}
```

---

### ขั้นตอนที่ 3: แก้ไข `toggleSOSMode()`

หาฟังก์ชัน `Future<void> toggleSOSMode() async {`

แทนที่ทั้งฟังก์ชันด้วย:

```dart
Future<void> toggleSOSMode() async {
  // 🔒 ป้องกันการกดซ้ำ
  if (_isTogglingSOS) {
    debugPrint('⚠️ กำลังประมวลผลอยู่ กรุณารอสักครู่...');
    return;
  }
  
  _isTogglingSOS = true;
  _isSOSActive = !_isSOSActive;
  debugPrint('🔍 [DEBUG] toggleSOSMode: _isSOSActive = $_isSOSActive');
  
  try {
    // ⚠️ ถ้าเปิด SOS Mode ให้ปิด Rescue Mode อัตโนมัติ
    if (_isSOSActive && _isRescueMode) {
      debugPrint('⚠️ ปิด Rescue Mode เพื่อเปิด SOS Mode');
      _isRescueMode = false;
      await _broadcastRescueStatus(false);
    }
    
    // 🔄 อัพเดท UI ทันที
    notifyListeners();
    
    if (_isSOSActive) {
      debugPrint('🚨 กำลังเปิดโหมด SOS...');
      
      // ดึงตำแหน่งปัจจุบัน
      Position? position = await _getCurrentLocation();
      
      // Broadcast SOS พร้อมพิกัด
      await broadcastSOSStatus(
        isActive: true,
        latitude: position?.latitude,
        longitude: position?.longitude,
      );
      
      // หยุดก่อน แล้วค่อยเริ่มใหม่ (เพิ่มความเสถียร)
      await stopScan();
      await Future.delayed(const Duration(milliseconds: 500));
      await startScan();
      
      debugPrint('🚨 ✅ เปิดโหมด SOS + เริ่มสแกนสำเร็จ');
    } else {
      debugPrint('🚨 กำลังปิดโหมด SOS...');
      await broadcastSOSStatus(isActive: false);
      await stopScan();
      debugPrint('🚨 ✅ ปิดโหมด SOS + หยุดสแกนสำเร็จ');
    }
    
    // อัพเดท UI อีกครั้งหลัง operation เสร็จ
    notifyListeners();
  } catch (e) {
    debugPrint('❌ Error in toggleSOSMode: $e');
    // ถ้า error ให้ rollback state
    _isSOSActive = !_isSOSActive;
    notifyListeners();
  } finally {
    _isTogglingSOS = false;
  }
}
```

---

## สิ่งที่เปลี่ยนแปลง:

✅ **เพิ่ม Lock Flags** - ป้องกันการกดปุ่มซ้ำเร็วๆ
✅ **Update UI ทันที** - `notifyListeners()` แรกหลัง toggle state
✅ **Delay 500ms** - ระหว่าง stopScan และ startScan
✅ **Error Handling** - Rollback state ถ้าเกิด error
✅ **Finally Block** - ปลดล็อค flag เสมอ

## ผลลัพธ์:
- โหมด SOS/Rescue เสถียรขึ้น
- UI ตอบสนองทันที
- ไม่เกิด race condition
- กดซ้ำเร็วๆ ไม่เกิดปัญหา

---

**หมายเหตุ:** หลังแก้เสร็จให้ Hot Restart แอพทั้งหมดเพื่อให้การเปลี่ยนแปลงมีผล
