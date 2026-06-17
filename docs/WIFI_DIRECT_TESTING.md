# 📶 WiFi Direct Testing Guide

## 🔧 การแก้ไขล่าสุด

### ✅ แก้ไข Bug
1. **Stream Controller Crash** - แก้แล้ว ไม่ crash เมื่อสลับ protocol
2. **เพิ่ม Debug Logging** - ตอนนี้มี log เต็มรูปแบบสำหรับ WiFi Direct

---

## 📋 ขั้นตอนการทดสอบ WiFi Direct

### เตรียมการ (ทั้ง 2 เครื่อง)

#### 1. เช็ค WiFi
```
Settings → WiFi → เปิด ✅
```
⚠️ **สำคัญ:** ถ้าใช้ Airplane Mode ต้องเปิด WiFi กลับมา!

#### 2. เช็ค Location
```
Settings → Location → เปิด ✅
```
⚠️ **บังคับ:** Android ต้องการ Location สำหรับ WiFi Direct

#### 3. เช็ค Permissions (ในแอป)
```
Settings → Permissions → อนุญาตทั้งหมด ✅
- Location (Always)
- Nearby Devices
```

---

## 🧪 การทดสอบ

### ขั้นตอน 1: เครื่องที่ 1 (A)
```
1. เปิดแอป
2. ไปที่ Settings
3. เลือก Protocol = "WiFi Direct"
4. กลับหน้าหลัก
5. ดู log
```

### ขั้นตอน 2: เครื่องที่ 2 (B)
```
1. เปิดแอป (พร้อมกับเครื่อง A)
2. ไปที่ Settings
3. เลือก Protocol = "WiFi Direct"
4. กลับหน้าหลัก
5. ดู log
```

---

## 📊 Log ที่ควรเห็น

### ✅ กรณีสำเร็จ (เจอเครื่องอื่น):

```
D/WifiDirectChannel: ✅ WifiP2pManager initialized successfully
D/WifiDirectChannel: ✅ Channel initialized successfully
D/WifiDirectChannel: ✅ WiFi Direct Channel initialized - Receiver registered
D/WifiDirectChannel: 📡 discoverPeers() called
D/WifiDirectChannel: 🔍 Starting peer discovery...
D/WifiDirectChannel: ✅ Peer discovery initiated successfully
D/WifiDirectChannel: 📶 WiFi P2P state changed: ENABLED ✅
D/WifiDirectChannel: 👥 Peers changed - requesting peer list...
D/WifiDirectChannel: 📊 Peers updated: 0 → 1
D/WifiDirectChannel:   📱 Found: เครื่อง B (aa:bb:cc:dd:ee:ff)
D/WifiDirectChannel: 📤 Sent 1 peers to Flutter
I/flutter: 📶 [WiFi Direct] Found 1 peers
```

### ❌ กรณี WiFi ปิด:

```
D/WifiDirectChannel: 📶 WiFi P2P state changed: DISABLED ❌
D/WifiDirectChannel: ⚠️ WiFi Direct is disabled! Please enable WiFi.
```

### ❌ กรณีไม่เจอเครื่องอื่น:

```
D/WifiDirectChannel: ✅ Peer discovery initiated successfully
D/WifiDirectChannel: 📶 WiFi P2P state changed: ENABLED ✅
D/WifiDirectChannel: 👥 Peers changed - requesting peer list...
D/WifiDirectChannel: 📊 Peers updated: 0 → 0
D/WifiDirectChannel:   ℹ️ No peers found in range
I/flutter: 📶 [WiFi Direct] Found 0 peers
```

---

## 🐛 Troubleshooting

### ปัญหา: WiFi P2P state = DISABLED

**วิธีแก้:**
1. เปิด WiFi ใน Settings
2. ปิด Airplane Mode (หรือเปิด WiFi หลัง Airplane Mode)
3. Restart แอป

### ปัญหา: WifiP2pManager is NULL

**สาเหตุ:** อุปกรณ์ไม่รองรับ WiFi Direct

**วิธีเช็ค:**
```
Settings → About Phone → Software Info
→ ดูว่ามี WiFi Direct หรือไม่
```

### ปัญหา: Peer discovery initiated แต่ไม่เจอเครื่อง

**เหตุผลที่เป็นไปได้:**

1. **เครื่องอีกเครื่องยังไม่ได้เปิด WiFi Direct**
   - ต้องเปิดทั้ง 2 เครื่องพร้อมกัน
   
2. **ห่างเกินไป**
   - WiFi Direct มีระยะ ~200 เมตร
   - ลองเข้าใกล้กันมากขึ้น

3. **WiFi ถูกรบกวน**
   - ลองย้ายไปที่มี WiFi น้อยกว่า
   
4. **เครื่องมีปัญหา**
   - ลอง restart WiFi (ปิด-เปิด)
   - ลอง restart เครื่อง

---

## 📱 วิธีดู Log

### Android Studio / VSCode
```bash
adb logcat | grep "WifiDirectChannel"
```

### ใน Terminal
```bash
adb logcat -s WifiDirectChannel:D flutter:I
```

---

## 💡 Tips

### ทดสอบแบบ Offline
```
1. เปิด Airplane Mode
2. เปิด WiFi กลับมา (จะไม่เชื่อมเน็ต)
3. เปิด Location
4. เลือก WiFi Direct protocol
✅ ทำงานได้โดยไม่ต้องมีอินเทอร์เน็ต!
```

### เปรียบเทียบ Protocols

| Protocol | เทคโนโลยี | ระยะ | ความเร็ว | ต้องเปิด WiFi |
|----------|-----------|------|----------|---------------|
| Bluetooth | BLE + WiFi Direct | 100m | เร็ว | ✅ (auto) |
| WiFi Direct | WiFi P2P | 200m | เร็วมาก | ✅ (manual) |
| Radio Mesh | BLE + Multi-hop | 500m+ | ปานกลาง | ✅ (auto) |

---

## ✅ Checklist ก่อนทดสอบ

```
□ WiFi เปิดแล้ว (ทั้ง 2 เครื่อง)
□ Location เปิดแล้ว (ทั้ง 2 เครื่อง)
□ Permissions ให้ครบแล้ว
□ ไม่อยู่ใน Airplane Mode (หรือเปิด WiFi กลับมา)
□ ทั้ง 2 เครื่องเลือก "WiFi Direct" พร้อมกัน
□ อยู่ในระยะ 200 เมตร
□ เปิด logcat ดู debug log
```

---

## 📞 ถ้ายังใช้ไม่ได้

1. **เช็ค log** - ดูว่ามี error อะไร
2. **Restart แอป** - ปิดเปิดใหม่
3. **Restart WiFi** - ปิดเปิด WiFi ใหม่
4. **Restart เครื่อง** - รีบูทเครื่อง
5. **ลองเครื่องอื่น** - บางเครื่องอาจไม่รองรับ WiFi Direct ดี

---

**อัพเดท:** 2025-11-09
