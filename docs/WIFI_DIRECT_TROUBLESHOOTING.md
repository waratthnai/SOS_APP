# 📡 WiFi Direct Troubleshooting Guide

## ปัญหา: ไม่พบ Peers

### สาเหตุหลัก
WiFi Direct **ต้องมี 2 เครื่องขึ้นไป** ที่เปิด WiFi Direct พร้อมกัน แตกต่างจาก Bluetooth/Nearby ที่ค้นหาได้เลย

---

## ✅ วิธีทดสอบ WiFi Direct อย่างถูกต้อง

### ขั้นตอนที่ 1: เตรียมอุปกรณ์ 2 เครื่อง
- 📱 **เครื่องที่ 1**: Samsung/Xiaomi/อื่นๆ (เครื่อง A)
- 📱 **เครื่องที่ 2**: อุปกรณ์ Android อีกเครื่อง (เครื่อง B)

### ขั้นตอนที่ 2: เปิด WiFi ทั้ง 2 เครื่อง
```
Settings → WiFi → เปิด (ON)
```
⚠️ **ไม่ต้องต่อ WiFi internet** - แค่เปิด WiFi ให้ทำงาน

### ขั้นตอนที่ 3: เปิด Location Services
```
Settings → Location → เปิด (ON)
```
📍 **จำเป็น!** Android ต้องใช้ Location เพื่อค้นหา WiFi Direct peers

### ขั้นตอนที่ 4: ติดตั้ง App ทั้ง 2 เครื่อง
```powershell
flutter install
```

### ขั้นตอนที่ 5: เลือก WiFi Direct Protocol
**ทั้ง 2 เครื่อง:**
1. เปิด App
2. กด Settings (⚙️)
3. เลือก "WiFi Direct"
4. กลับหน้าหลัก

### ขั้นตอนที่ 6: เริ่มค้นหา
**เครื่อง A (เครื่องแรก):**
1. กด Scan (🔍)
2. รอ 5-10 วินาที

**เครื่อง B (ภายใน 10 วินาที):**
1. กด Scan (🔍)
2. รอ 5-10 วินาที

### ขั้นตอนที่ 7: ตรวจสอบ Log
**เครื่อง A ควรเห็น:**
```
D/WifiDirectChannel: ✅ Peer discovery initiated successfully
D/WifiDirectChannel: 👥 Peers changed - requesting peer list...
D/WifiDirectChannel: 📱 Found: <ชื่อเครื่อง B>
D/WifiDirectChannel: 🔄 Auto-connecting to <ชื่อเครื่อง B>...
```

**เครื่อง B ควรเห็น:**
```
D/WifiDirectChannel: ✅ Peer discovery initiated successfully
D/WifiDirectChannel: 👥 Peers changed - requesting peer list...
D/WifiDirectChannel: 📱 Found: <ชื่อเครื่อง A>
D/WifiDirectChannel: 🔄 Auto-connecting to <ชื่อเครื่อง A>...
```

---

## ⚠️ ปัญหาที่พบบ่อย

### 1. "System busy (code: 2)"
**สาเหตุ:** Discovery ทับซ้อนกัน
**แก้ไข:** รอ 30 วินาที แล้วกด Scan ใหม่

### 2. "No peers found in range"
**สาเหตุ:** 
- ไม่มีเครื่องอื่นเปิด WiFi Direct
- เครื่องอีกเครื่องยังไม่ได้กด Scan

**แก้ไข:** 
- เช็คว่าเครื่องที่ 2 เปิด WiFi Direct แล้ว
- ให้ทั้ง 2 เครื่องกด Scan พร้อมกัน (ภายใน 10 วินาที)

### 3. "WiFi Direct is disabled"
**สาเหตุ:** WiFi ปิดอยู่

**แก้ไข:** เปิด WiFi ใน Settings

### 4. พบ Peer แต่ไม่เชื่อมต่อ
**สาเหตุ:** Android บางรุ่นต้อง manual accept connection

**แก้ไข:** 
- ดู notification บนหน้าจอ
- กด "Accept" เมื่อมี connection request

---

## 🔧 การ Debug

### เช็ค WiFi State
```
D/WifiDirectChannel: 📶 WiFi P2P state changed: ENABLED ✅
```
✅ **ENABLED** = พร้อมใช้งาน
❌ **DISABLED** = ต้องเปิด WiFi

### เช็ค Discovery Status
```
D/WifiDirectChannel: ✅ Peer discovery initiated successfully
D/WifiDirectChannel: ⏳ Waiting for WIFI_P2P_PEERS_CHANGED_ACTION broadcast...
```

### เช็ค Peers Found
```
D/WifiDirectChannel: 👥 Peers changed - requesting peer list...
D/WifiDirectChannel: 📊 Peers updated: 0 → 1
D/WifiDirectChannel: 📱 Found: Device_Name (XX:XX:XX:XX:XX:XX)
```

### เช็ค Connection
```
D/WifiDirectChannel: ✅ Group formed - Connection established
D/WifiDirectChannel: 🔌 Connection status: Connected (role: server)
```

---

## 📋 Checklist ก่อนทดสอบ

- [ ] มีอุปกรณ์ Android 2 เครื่อง
- [ ] ทั้ง 2 เครื่องเปิด WiFi
- [ ] ทั้ง 2 เครื่องเปิด Location Services
- [ ] ทั้ง 2 เครื่องติดตั้ง App แล้ว
- [ ] ทั้ง 2 เครื่องเลือก WiFi Direct Protocol
- [ ] ทั้ง 2 เครื่องกด Scan ภายใน 10 วินาที

---

## 🎯 ผลลัพธ์ที่คาดหวัง

### เมื่อพบ Peer สำเร็จ:
1. ✅ เห็นชื่ออุปกรณ์ในรายการ
2. ✅ Log แสดง "Found: <device_name>"
3. ✅ Auto-connect เริ่มทำงาน
4. ✅ Group formed (server/client)
5. ✅ ส่งข้อความได้

### Log ที่ถูกต้อง:
```
📶 [WiFi Direct] Starting peer discovery...
📶 [WiFi Direct] Device name: 22
📡 discoverPeers() called
✅ Stopped previous discovery
🔍 Starting peer discovery...
✅ Peer discovery initiated successfully
👥 Peers changed - requesting peer list...
📱 Found: Device_Name (XX:XX:XX:XX:XX:XX)
🔄 Auto-connecting to Device_Name...
✅ Group formed - Connection established
🔌 Connection status: Connected
```

---

## 💡 Tips

### WiFi Direct vs Bluetooth/Nearby
| Feature | WiFi Direct | Bluetooth | Nearby |
|---------|-------------|-----------|---------|
| ระยะทาง | 100-200m | 10-30m | 10-30m |
| ความเร็ว | สูง (25+ Mbps) | ต่ำ (1-3 Mbps) | ปานกลาง |
| Auto-discover | ❌ ต้อง 2 เครื่อง | ✅ ได้เลย | ✅ ได้เลย |
| Manual setup | ⚠️ บางรุ่น | ✅ Auto | ✅ Auto |

### แนะนำสำหรับการทดสอบ
1. **ทดสอบ Bluetooth/Nearby ก่อน** - เพื่อให้แน่ใจว่า App ทำงาน
2. **ใช้ WiFi Direct ตอนจริง** - เมื่อต้องการระยะไกล/ความเร็วสูง
3. **เตรียมอุปกรณ์ 2+ เครื่อง** - สำหรับทดสอบ WiFi Direct

---

## 🐛 หาก WiFi Direct ยังใช้ไม่ได้

### ทดสอบด้วย Bluetooth/Nearby แทน:
```dart
Settings → เลือก "Bluetooth & Nearby"
```

### เหตุผล:
- ✅ Auto-discover ไม่ต้องมีเครื่องอื่น
- ✅ ไม่ต้อง manual accept
- ✅ ทดสอบได้ง่ายกว่า

### WiFi Direct เหมาะกับ:
- 📡 การใช้งานระยะไกล (50m+)
- 💨 การส่งไฟล์ขนาดใหญ่
- 🏔️ สถานที่ห่างไกล (ป่า/ภูเขา)

---

## 📞 Support

หาก WiFi Direct ยังใช้ไม่ได้หลังทำตาม checklist ทั้งหมด:

1. ดู Log แล้วหา error code
2. เช็ค Android version (ต้อง 4.0+)
3. ทดสอบ WiFi Direct ด้วย app อื่น (WiFi Direct Demo)
4. เช็ค permissions ใน AndroidManifest.xml
