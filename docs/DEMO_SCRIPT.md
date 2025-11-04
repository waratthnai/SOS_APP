# 🎬 DEMO SCRIPT - Week 5 Presentation
## Off-Grid SOS - Polish & Test

**เวลาโดยประมาณ:** 5-7 นาที  
**อุปกรณ์:** คอมพิวเตอร์ + Terminal + VS Code

---

## 📋 Part 1: แสดง Test Results (2 นาที)

### สิ่งที่พูด:
> "สวัสดีครับ วันนี้ผมจะนำเสนอผลงาน Week 5 ของโปรเจค Off-Grid SOS  
> Week นี้เน้นการ Polish และ Test โดยมีเป้าหมาย 4 ข้อหลัก  
> เริ่มจาก Test Cases ก่อนครับ"

### ขั้นตอน:

**1.1 เปิด Terminal และรัน tests**
```powershell
cd C:\Users\warat\Documents\Project2\offgrid_sos
flutter test
```

### สิ่งที่พูดขณะรัน:
> "ผมได้สร้าง automated tests ทั้งหมด 27 test cases  
> ซึ่งเกินเป้าหมายที่กำหนดไว้ 10 tests ถึง 270%"

**1.2 รอผลลัพธ์ (5 วินาที)**

### เมื่อเห็น "All tests passed!":
> "ตามที่เห็นครับ ทั้ง 27 tests ผ่านหมด  
> แบ่งเป็น 3 กลุ่ม:
> - Notification Service: 8 tests
> - Chat Filter Service: 12 tests  
> - Chat Models: 7 tests"

**1.3 เปิดไฟล์ test ให้ดู (เลือก 1 ไฟล์)**
```powershell
code test/notification_service_test.dart
```

### สิ่งที่พูด:
> "ผมจะขอแสดงตัวอย่างหนึ่ง test file ครับ  
> ใน notification_service_test นี้ จะมีการทดสอบ  
> การเพิ่มการแจ้งเตือน, การลบ, การจำกัดจำนวน  
> และการ notify listeners"

---

## Part 2: แสดง Accessibility Features (2 นาที)

**2.1 เปิดไฟล์ accessibility_helper.dart**
```powershell
code lib/core/accessibility_helper.dart
```

### สิ่งที่พูด:
> "ส่วนที่สอง คือ Accessibility Features  
> ผมได้สร้าง AccessibilityHelper class  
> ที่มีฟีเจอร์สำคัญหลายอย่าง"

**2.2 เลื่อนไปที่ส่วนสำคัญและอธิบาย:**

### Touch Target Size:
```dart
static const double minTouchTargetSize = 48.0;
```
> "ครั้งแรก คือ Touch Target Size  
> กำหนดให้ปุ่มทุกปุ่มมีขนาดขั้นต่ำ 48x48 pixels  
> ตามมาตรฐาน Material Design"

### Text Scaling:
```dart
static double getAccessibleTextScale(BuildContext context) {
  return textScale.clamp(minTextScale, maxTextScale);
}
```
> "รองรับการปรับขนาดตัวอักษรจาก 0.8 ถึง 3 เท่า  
> สำหรับผู้ที่มีปัญหาทางสายตา"

### WCAG Contrast:
```dart
static bool meetsWCAGAA(Color foreground, Color background)
```
> "และมีการตรวจสอบ contrast ratio  
> ให้เป็นไปตามมาตรฐาน WCAG AA และ AAA"

**2.3 แสดงการใช้งานจริง**
```powershell
code lib/main.dart
# ค้นหา "Semantics"
```

> "ตัวอย่างการใช้งานจริงในโค้ด  
> ผมได้เพิ่ม Semantic labels ให้กับปุ่มต่างๆ  
> เพื่อรองรับ screen reader อย่าง TalkBack และ VoiceOver"

---

## Part 3: แสดง UX Improvements (1.5 นาที)

**3.1 เปิดไฟล์ loading_overlay.dart**
```powershell
code lib/widgets/loading_overlay.dart
```

### สิ่งที่พูด:
> "ส่วนที่สาม คือ UX Stability  
> ผมได้สร้าง widgets สำหรับ UX ที่ดีขึ้น 4 ตัว"

**3.2 เลื่อนแสดงแต่ละ widget:**

### LoadingOverlay:
> "LoadingOverlay - แสดงตอน loading  
> พร้อม message บอกสถานะ"

### EmptyState:
> "EmptyState - แสดงเมื่อไม่มีข้อมูล  
> พร้อมไอคอน, ข้อความอธิบาย และปุ่ม action"

### ErrorState:
> "ErrorState - แสดงตอนเกิด error  
> พร้อมปุ่ม retry"

### ConnectionStatusBanner:
> "ConnectionStatusBanner - แสดงสถานะการเชื่อมต่อ  
> real-time ด้านบนของแอป"

---

## Part 4: แสดง Bug Tracking (1.5 นาที)

**4.1 เปิดไฟล์ WEEK5_POLISH.md**
```powershell
code WEEK5_POLISH.md
# เลื่อนไปที่ส่วน "ระบบบันทึกบั๊ก"
```

### สิ่งที่พูด:
> "สุดท้าย คือการบันทึกและแก้ไขบั๊ก  
> ผมได้จัดทำเอกสารบันทึกบั๊กที่พบ  
> และวิธีการแก้ไขไว้ครบถ้วน"

**4.2 อธิบายแต่ละบั๊ก:**

### Bug #1: Notification ID Collision
> "บั๊กแรก เป็นปัญหา notification ID ซ้ำกัน  
> เมื่อสร้างพร้อมกันใน millisecond เดียวกัน  
> แก้โดยเพิ่ม delay ระหว่างการสร้าง"

### Bug #2: ChatMessage Properties
> "บั๊กที่สอง คือ properties ไม่ตรงกับ test  
> แก้โดยเพิ่ม isEmergency field  
> และ helper getters ต่างๆ"

### Bug #3: Nearby Connections
> "บั๊กที่สาม คือ STATUS_ALREADY_ADVERTISING  
> เกิดจากเรียก start ซ้อนกัน  
> แก้โดยเพิ่ม state tracking flags  
> และหยุดก่อนเริ่มใหม่"

---

## 🎯 Part 5: สรุป (30 วินาที)

**5.1 เปิดไฟล์ WEEK5_SUBMISSION.md**
```powershell
code WEEK5_SUBMISSION.md
# เลื่อนไปที่ตารางสรุป
```

### สิ่งที่พูด:
> "สรุปผลงาน Week 5 ครับ  
> 
> Test Cases: 27/10 - เกินเป้า 270%  
> Accessibility: ครบทุกฟีเจอร์ที่กำหนด  
> UX Stability: 4 widgets สำหรับ states ต่างๆ  
> Bug Tracking: บันทึกและแก้ไข 3 bugs  
> 
> ผมได้จัดทำเอกสารครบถ้วนไว้ใน  
> - WEEK5_POLISH.md (รายละเอียดทางเทคนิค)  
> - WEEK5_SUBMISSION.md (เอกสารส่งอาจารย์)  
> 
> ขอบคุณครับ"

---

## 📌 Tips สำหรับการนำเสนอ:

### ✅ DO:
- ✅ เตรียม terminal ไว้แล้ว (cd ไปที่โฟลเดอร์)
- ✅ ปิด notification/popup ที่อาจรบกวน
- ✅ ตั้ง font size ใน terminal และ VS Code ให้ใหญ่พอ
- ✅ เตรียมข้อความที่จะพูดไว้ล่วงหน้า
- ✅ ฝึกซ้อม 2-3 รอบก่อนนำเสนอจริง

### ❌ DON'T:
- ❌ อย่ารัน `flutter run` ถ้าใช้เวลานาน
- ❌ อย่าแก้โค้ดขณะ demo
- ❌ อย่าพูดเร็วเกินไป
- ❌ อย่าลืมเปิด screen share/projector

---

## 🎥 ถ้ามีเวลาเหลือ (Optional):

### Demo แอปจริง:
```powershell
flutter run
```

**แสดง:**
1. หน้า Notifications ตอนว่าง (Empty State)
2. กดปุ่ม Scan (Loading State)
3. ปิด Bluetooth แล้วกด Scan (Error State)
4. เปิด TalkBack/VoiceOver (Screen Reader)

---

## 📱 Backup Plan (ถ้าเน็ตหรือเครื่องมีปัญหา):

### เตรียม:
1. **Screenshots:**
   - Test results
   - Code highlights
   - UX widgets
   - Bug documentation

2. **Video Recording:**
   - บันทึกการรัน tests
   - บันทึกการใช้แอป
   - บันทึกหน้าจอ VS Code

3. **PDF Export:**
   - Export WEEK5_SUBMISSION.md เป็น PDF
   - Print ออกมา 1 ชุด (เผื่อฉุกเฉิน)

---

**Good Luck! 🍀**
