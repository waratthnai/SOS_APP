# 🧪 คู่มือทดสอบ Protocols

## 📋 สิ่งที่แก้ไข (ล่าสุด)

### ✅ Mesh Protocol
- แก้ substring error ใน _emitPeers
- เพิ่ม logging ครอบคลุมทั้งการส่งและรับ message
- ปรับ sendMessage ให้ handle string ยาวได้

### ✅ WiFi Direct
- ลบ rethrow เพื่อไม่ให้ app crash เมื่อส่ง message ล้มเหลว
- เพิ่ม logging ครอบคลุม
- เพิ่ม connection status tracking

### ⚠️ Notifications
- System notifications ทำงานผ่าน BackgroundService
- **ต้องเปิด Background Service ก่อน** (Settings > Background Service)

---

## 🔍 วิธีทดสอบ Mesh

### 1. เปิดโหมด Mesh ทั้งสองเครื่อง
- เครื่อง A (oat): เปลี่ยนเป็นโหมด Mesh
- เครื่อง B (poo): เปลี่ยนเป็นโหมด Mesh

### 2. ตรวจสอบ Logs (ควรเห็น)
```
📡 [MESH] Saved device name for direct peer: 45RY = poo
📡 [MESH] _emitPeers: Processing 1 peer entries
📡 [MESH] Adding peer: poo (direct)
📡 [MESH] ✅ Emitted 1 unique peers
  📱 poo (direct)
```

### 3. ทดสอบส่ง SOS/Rescue Status
- กด toggle SOS Mode หรือ Rescue Mode
- ควรเห็น log:
```
📡 [MESH] sendMessage called: SOS_STATUS:oat:SOS_MODE:...
📡 [MESH] Broadcasting message: SOS_STATUS:oat:SOS_MODE:...
📡 [MESH] Broadcasting encoded message: MESH:device_...
```

### 4. เครื่องอีกเครื่องควรเห็น
```
📡 [MESH] ✅ Message for us from device_...: SOS_STATUS:oat:...
📡 [MESH] ✅ Forwarding message to app: SOS_STATUS:oat:...
🔍 [DEBUG] ✅ พบข้อความ SOS_STATUS! กำลังเรียก _handleSOSStatus()
```

### 5. ทดสอบแชท
- ส่งข้อความในห้องแชท
- ควรเห็น message ปรากฏทั้งสองเครื่อง

---

## 🔍 วิธีทดสอบ WiFi Direct

### 1. เปิดโหมด WiFi Direct ทั้งสองเครื่อง
- **สำคัญ:** WiFi Direct ใช้เวลาในการ auto-connect (10-30 วินาที)

### 2. รอให้เชื่อมต่อ (ดู logs)
```
📡 Connection status changed
✅ Group formed - Connection established
👑 I am group owner, starting server...
🔌 Connection status: Connected (role: server)
```
หรือ
```
📱 I am client, connecting to 192.168.49.1...
✅ Connected to server: 192.168.49.1
🔌 Connection status: Connected (role: client)
```

### 3. ทดสอบส่งข้อความ
- หลังจาก Connected แล้ว ลองส่งข้อความ
- ควรเห็น:
```
📶 [WiFi Direct] Sending message to all: สวัสดี
✅ [WiFi Direct] Message sent successfully
```

### 4. เครื่องรับควรเห็น
```
📥 Received message: สวัสดี
📶 [WiFi Direct] Received message from poo: สวัสดี
```

### 5. ทดสอบ SOS/Rescue Mode
- Toggle SOS/Rescue mode
- ควรเห็น status แสดงบนเครื่องอีกเครื่อง

---

## 🔔 วิธีเปิด System Notifications

### 1. เปิด Background Service
- ไปที่ Settings (⚙️)
- เลื่อนลงมาหา "Background Service"
- เปิด toggle

### 2. อนุญาต permissions
- Notification permission
- Battery optimization exemption (ถ้าขอ)

### 3. ทดสอบ
- กดปุ่ม SOS
- ควรเห็น notification ปรากฏที่ notification bar ของโทรศัพท์

---

## ❌ ถ้าเจอปัญหา

### Mesh: หากันเจอแต่ส่งข้อความไม่ไป
1. เช็ค log ว่ามี "Broadcasting encoded message" หรือไม่
2. ถ้าไม่มี → ปัญหาที่การส่ง
3. ถ้ามี แต่ไม่มี "✅ Message for us" → ปัญหาที่การรับ

### WiFi Direct: Discover เจอแต่ส่งไม่ไป
1. เช็คว่า "Connection status: Connected" หรือยัง
2. ถ้ายัง → รอต่อ (auto-connect ใช้เวลา)
3. ถ้าเชื่อมต่อแล้วแต่ส่งไม่ไป → เช็ค "⚠️ Cannot send message - not connected"

### Notifications ไม่ขึ้น
1. เช็คว่าเปิด Background Service แล้วหรือยัง
2. Settings > Apps > OffGrid SOS > Notifications → ต้องเปิด
3. Settings > Battery > Battery optimization → OffGrid SOS → "Don't optimize"

---

## 📝 Log Keywords สำคัญ

### ✅ Signs of Success
- `✅ Emitted X unique peers` (Mesh)
- `Connection status: Connected` (WiFi Direct)
- `✅ Forwarding message to app` (Mesh)
- `📥 Received message` (WiFi Direct)
- `พบข้อความ SOS_STATUS!` (App State)

### ❌ Signs of Problems
- `Valid peers after filtering: 0` (Mesh broken)
- `Cannot send message - not connected` (WiFi Direct not connected)
- `RangeError` (Substring error)
- `No active connection` (Socket issue)

---

## 🚀 Quick Test Checklist

- [ ] Mesh: เห็น peers
- [ ] Mesh: ส่งแชทได้
- [ ] Mesh: SOS/Rescue status แสดง
- [ ] WiFi Direct: เชื่อมต่อสำเร็จ (Connected)
- [ ] WiFi Direct: ส่งแชทได้
- [ ] WiFi Direct: SOS/Rescue status แสดง
- [ ] Bluetooth: ยังทำงานได้ตามปกติ (baseline)
- [ ] Notifications: ขึ้นที่ notification bar (ต้องเปิด Background Service)

