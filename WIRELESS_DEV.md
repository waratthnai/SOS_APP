# Wireless ADB — ทดสอบ 2 เครื่อง สายเดียว

## ครั้งแรก (ตั้งค่าครั้งเดียว)

### เครื่องที่ 1 — ต่อสายก่อน
```powershell
adb devices          # ต้องเห็นเครื่องขึ้น
adb tcpip 5555       # เปิด TCP mode
adb connect 192.168.1.xxx:5555   # ใส่ IP ของเครื่องนั้น
# ถอดสายได้แล้ว
```

### เครื่องที่ 2 — Wireless Debugging (Android 11+)
```
Settings → Developer Options → Wireless debugging → เปิด
→ "Pair device with pairing code" → จะได้ IP:PORT + 6-digit code
```
```powershell
adb pair 192.168.1.xxx:PAIR_PORT    # ใส่ code เมื่อถาม
adb connect 192.168.1.xxx:DEBUG_PORT  # port จากหน้า Wireless debugging หลัก (ไม่ใช่ pair port)
```

> **หา DEBUG_PORT**: กลับไปหน้า Wireless debugging จะเห็น `IP address & Port` ตรงกลางหน้า

---

## รัน Flutter บนสองเครื่องพร้อมกัน

```powershell
flutter devices   # ดู device id ทั้งหมด
```

เปิด **2 terminal** แล้วรันคนละอัน:
```powershell
# Terminal 1
flutter run -d <device_id_1>

# Terminal 2
flutter run -d <device_id_2>
```

---

## ใช้งานระหว่าง dev

| กด | ผล |
|---|---|
| `r` | Hot Reload — UI อัปเดตทันที ไม่ reset state |
| `R` | Hot Restart — reset state ใหม่ทั้งหมด |
| `q` | ออกจาก session |

> แก้โค้ด Dart → กด `r` ได้เลย ไม่ต้อง build ใหม่
> ยกเว้นแก้ native (Kotlin/Swift) หรือเพิ่ม plugin ใหม่ → ต้อง build ใหม่

---

## ครั้งต่อไป (ถ้า connect หลุด)

เครื่องที่ 1 (tcpip):
```powershell
adb connect 192.168.1.xxx:5555
```

เครื่องที่ 2 (Wireless Debugging):
```powershell
adb connect 192.168.1.xxx:DEBUG_PORT   # port เปลี่ยนทุกครั้งที่ reboot — ดูจาก Settings
```

---

## IP ของแต่ละเครื่อง

| เครื่อง | IP | Port |
|---|---|---|
| เครื่อง 1 (Samsung R52W) | 192.168.1.150 | 5555 |
| เครื่อง 2 (Samsung R5CX) | 192.168.1.117 | ดูจาก Wireless Debugging |
