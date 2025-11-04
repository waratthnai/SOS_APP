# 🚀 Off-Grid SOS - Progress Tracker
**เริ่มทำ:** 25 ตุลาคม 2025  
**เป้าหมาย:** ทำให้โปรเจกต์สมบูรณ์ตามโจทย์ 100%

---

## 📋 รายการที่ต้องทำ (To-Do List)

### ⭐ Priority 1 - ต้องมี! (MUST HAVE)

- [x] **1. โหมดหน่วยกู้ภัย (Rescue Mode)** ✅ เสร็จแล้ว!
  - [x] 1.1 เพิ่ม `isRescueMode` flag ใน AppState
  - [x] 1.2 เพิ่มปุ่ม toggle "โหมดหน่วยกู้ภัย" ในหน้า Settings
  - [x] 1.3 Broadcast rescue status ผ่าน Nearby Connections
  - [x] 1.4 แสดง badge สีน้ำเงิน 🔵 ใน peer list
  - [x] 1.5 เก็บสถานะหน่วยกู้ภัยของ peers และแสดง UI
  - **เวลาที่ใช้:** ~2 ชั่วโมง ✅

- [x] **2. ระบบส่งรูปภาพ (Image Sharing)** ✅ เสร็จแล้ว!
  - [x] 2.1 เพิ่มปุ่มแนบรูปใน EmergencyChatScreen ✅
  - [x] 2.2 เพิ่มปุ่มแนบรูปใน FriendChatScreen ✅
  - [x] 2.3 ใช้ ImagePicker เลือกรูปจาก gallery/camera ✅
  - [x] 2.4 ส่งรูปผ่าน P2P (Nearby Connections) ✅
  - [x] 2.5 แสดงรูปภาพใน message bubble (พร้อม error handling) ✅
  - [x] 2.6 เพิ่ม ReceivedFile stream ใน transport layer ✅
  - [x] 2.7 File transfer tracking (PayloadTransferUpdate) ✅
  - [x] 2.8 เพิ่ม sendFriendImageMessage() ใน AppState ✅
  - **เวลาที่ใช้:** ~4 ชั่วโมง ✅
  - **หมายเหตุ:** 
    - ✅ ส่งรูปได้ทั้ง Emergency Chat และ Friend Chat
    - ✅ ไม่อัพโหลด Firebase Storage (เพราะ Free Plan)
    - ✅ เก็บ local + metadata อย่างเดียว
    - ⏳ ยังต้องทดสอบจริงระหว่าง 2 เครื่อง

- [ ] **3. SOS Status Broadcast** 🔴 HIGH PRIORITY
  - [ ] 3.1 เพิ่ม `isSOSActive` ใน AppState
  - [ ] 3.2 Broadcast SOS status + GPS coordinates เมื่อกดปุ่ม SOS
  - [ ] 3.3 เครื่องอื่นรับสถานะ → แสดง badge สีแดง 🔴
  - [ ] 3.4 แสดง SOS notification พร้อมตำแหน่ง
  - [ ] 3.5 เปิดแชทได้ทันทีจาก SOS notification
  - **ประมาณการเวลา:** 4-6 ชั่วโมง

### 🟡 Priority 2 - ควรมี (SHOULD HAVE)

- [ ] **4. ระบบส่งวิดีโอ (Video Sharing)** 🟡 MEDIUM PRIORITY
  - [ ] 4.1 เพิ่มปุ่มแนบวิดีโอ
  - [ ] 4.2 ใช้ ImagePicker เลือกวิดีโอ
  - [ ] 4.3 ส่งวิดีโอผ่าน `transport.sendFile()`
  - [ ] 4.4 แสดง video player ใน chat
  - **ประมาณการเวลา:** 6-8 ชั่วโมง

- [ ] **5. Message Queue & Sync Status** 🟡 MEDIUM PRIORITY
  - [ ] 5.1 แสดงสถานะข้อความ: "ค้างส่ง/ส่งแล้ว/ซิงก์แล้ว"
  - [ ] 5.2 เก็บ message queue เมื่อ offline
  - [ ] 5.3 Auto-sync เมื่อกลับมา online
  - [ ] 5.4 แสดง sync indicator
  - **ประมาณการเวลา:** 4-5 ชั่วโมง

### 🔵 Priority 3 - เสริม (NICE TO HAVE)

- [ ] **6. Multi-hop Message Routing** 🔵 LOW PRIORITY
  - [ ] 6.1 Message routing algorithm
  - [ ] 6.2 เก็บ message history เพื่อไม่วนลูป
  - [ ] 6.3 Forward messages ไปยัง connected peers
  - [ ] 6.4 แสดง network topology
  - **ประมาณการเวลา:** 10-12 ชั่วโมง

- [ ] **7. WiFi Direct & BLE Transport** 🔵 LOW PRIORITY
  - [ ] 7.1 Implement WiFiDirectTransport
  - [ ] 7.2 Implement BleTransport
  - [ ] 7.3 สลับ protocol ได้ใน Settings
  - **ประมาณการเวลา:** 8-10 ชั่วโมง

---

## ✅ สิ่งที่ทำเสร็จแล้ว (Completed)

### Week 1-4:
- ✅ Nearby Connections P2P
- ✅ Firebase Authentication
- ✅ Firestore Cloud Storage
- ✅ Text Chat (Emergency + Friend)
- ✅ Offline-First Architecture
- ✅ Device Name Setup
- ✅ SOS Button (UI + Confirmation)
- ✅ Notification System
- ✅ Friend Management
- ✅ Local Database (ChatDB, FriendDB)
- ✅ AppState Management
- ✅ Transport Layer (Interface)
- ✅ Settings Screen
- ✅ Map Screen (Google Maps)
- ✅ Profile Screen

### Week 5:
- ✅ Test Cases (27 tests)
- ✅ Accessibility Features
- ✅ UX Widgets (Loading, Error, Empty states)
- ✅ Bug Fixes

---

## 📊 Progress Summary

**ความสมบูรณ์รวม:** ~70%

### สถิติ:
- ✅ **Completed:** 15 features
- 🔄 **In Progress:** 0 features
- ⏳ **To-Do:** 7 features (ตามโจทย์)

### เวลาที่เหลือโดยประมาณ:
- **Priority 1 (MUST):** 18-24 ชั่วโมง
- **Priority 2 (SHOULD):** 10-13 ชั่วโมง  
- **Priority 3 (NICE):** 18-22 ชั่วโมง
- **รวมทั้งหมด:** 46-59 ชั่วโมง (~6-8 วันทำงาน)

---

## 🎯 เป้าหมายสัปดาห์นี้

**Week 6 Goal:** ทำ Priority 1 ให้เสร็จทั้งหมด (3 ฟีเจอร์)

- [ ] **Day 1-2:** โหมดหน่วยกู้ภัย (Rescue Mode)
- [ ] **Day 3-4:** ระบบส่งรูปภาพ (Image Sharing)
- [ ] **Day 5:** SOS Status Broadcast
- [ ] **Day 6-7:** ทดสอบและแก้บั๊ก

---

## 📝 Notes & Decisions

### วันที่ 25 ตุลาคม 2025:
- สร้างไฟล์ติดตาม progress
- วิเคราะห์โปรเจกต์พบว่าทำไปแล้ว ~70%
- เหลือ 7 ฟีเจอร์หลัก ตามโจทย์
- จัดลำดับความสำคัญ: Priority 1 (3 อย่าง) ต้องทำให้เสร็จเพื่อได้เกรด A

---

## 🔄 Current Task

**✅ เสร็จแล้ว:** Feature #1 - โหมดหน่วยกู้ภัย (Rescue Mode)  
**🔄 กำลังทำ:** ยังไม่ได้เริ่ม  
**ต่อไป:** Feature #2 - ระบบส่งรูปภาพ (Image Sharing)

---

### วันที่ 25 ตุลาคม 2025 - 15:00:
**✅ เสร็จ Feature #1: โหมดหน่วยกู้ภัย**
- เพิ่ม `isRescueMode`, `toggleRescueMode()` ใน AppState
- Broadcast `RESCUE_STATUS:deviceName:status` ผ่าน Nearby Connections
- รับสถานะผ่าน `_handleRescueStatus()` 
- เก็บสถานะใน `_rescuePeers` Map
- เพิ่มปุ่ม Toggle ในหน้า Settings พร้อม UI สวยงาม
- แสดง badge 🚑 สีน้ำเงินใน HomeScreen peer list
- เปลี่ยนสี icon และ button เป็นสีน้ำเงินสำหรับหน่วยกู้ภัย
- **ไฟล์ที่แก้:**
  * `lib/core/app_state.dart` - เพิ่ม rescue mode logic
  * `lib/main.dart` - เพิ่ม UI ใน Settings และ HomeScreen
- **❓ TODO: ถามผู้ใช้ว่า "โหมดหน่วยกู้ภัยคืออะไร?" เพื่อให้คำอธิบายที่ดีขึ้น**

### วันที่ 25 ตุลาคม 2025 - 15:15:
**🔄 เริ่มทำ Feature #2: ระบบส่งรูปภาพ**
- เป้าหมาย: ให้ผู้ใช้ส่งรูปภาพผ่าน emergency chat และ friend chat ได้

---

*อัพเดทล่าสุด: 25 ตุลาคม 2025 - 15:00*
