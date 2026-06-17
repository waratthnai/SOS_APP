# 🚀 WiFi Direct Quick Start (ทดสอบง่ายใน 2 นาที)

## ⚡ เตรียมอุปกรณ์

**ต้องมี 2 เครื่อง!** (WiFi Direct ไม่สามารถทดสอบเครื่องเดียวได้)

```
📱 เครื่องที่ 1: เปิด App + เลือก WiFi Direct
📱 เครื่องที่ 2: เปิด App + เลือก WiFi Direct
```

---

## 📋 Checklist (ทั้ง 2 เครื่อง)

- [x] เปิด WiFi (Settings → WiFi → ON)
- [x] เปิด Location (Settings → Location → ON)
- [x] เปิด App
- [x] เลือก WiFi Direct (Settings → WiFi Direct)

---

## 🔍 ขั้นตอนทดสอบ

### 1️⃣ เครื่องที่ 1
```
กด Scan (🔍) → รอ 5 วินาที
```

### 2️⃣ เครื่องที่ 2 (ภายใน 10 วินาที)
```
กด Scan (🔍) → รอ 5 วินาที
```

### 3️⃣ ผลลัพธ์
✅ **สำเร็จ:** เห็นชื่ออุปกรณ์ในรายการ  
❌ **ล้มเหลว:** "No peers found" → ลองใหม่อีกครั้ง

---

## 🐛 ถ้าไม่เจอ Peer

### แก้ไขเร่งด่วน:
1. ✅ เช็คว่า**ทั้ง 2 เครื่อง**เปิด WiFi + Location
2. ✅ กด Scan **พร้อมกัน** (ห่างไม่เกิน 10 วินาที)
3. ✅ รอ 30 วินาที แล้วลองใหม่

### ถ้ายังไม่ได้:
```
ใช้ Bluetooth/Nearby แทน (ทดสอบง่ายกว่า)
Settings → เลือก "Bluetooth & Nearby"
```

---

## 📊 Log ที่ถูกต้อง

```
✅ Peer discovery initiated successfully
👥 Peers changed - requesting peer list...
📱 Found: <ชื่อเครื่อง>
🔄 Auto-connecting...
✅ Group formed - Connection established
```

---

## 💡 เคล็ดลับ

- 🔄 **System busy?** → รอ 30 วินาที
- ⏰ **Too soon?** → รอให้ครบเวลา
- 📱 **No peers?** → ให้เครื่องที่ 2 กด Scan ด้วย

---

**📖 คู่มือฉบับเต็ม:** [WIFI_DIRECT_TROUBLESHOOTING.md](WIFI_DIRECT_TROUBLESHOOTING.md)
