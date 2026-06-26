# TODO

## Known Issues (not yet fixed)

- [ ] **WiFi Direct — peer status/distance not displayed**
  - `WifiP2pManager` ไม่ expose RSSI/distance ตรงๆ
  - ปัจจุบัน `_distanceLabel()` ใช้ GPS diff — ใช้ได้เมื่อทั้งสองฝั่งส่ง `GPS_LOC:` เท่านั้น

- [ ] **BLE/Mesh — ยังไม่ได้ทดสอบบนอุปกรณ์จริง**
  - `lib/core/ble_transport.dart` และ `lib/core/mesh_transport.dart`
  - ต้องทดสอบ handshake, reconnect, และ message delivery บน physical device

- [ ] **WiFi Direct — system confirmation dialog (unavoidable)**
  - Android `WifiP2pManager` บังคับ pop-up ตอน connect ครั้งแรก
  - ไม่มีทาง bypass ผ่าน API — ต้องยอมรับ UX นี้ หรือเปลี่ยนไปใช้ transport อื่น

## Features / Improvements

- [ ] **Mesh file transfer**
  - `lib/core/mesh_transport.dart:180` — `sendFile()` throws `UnimplementedError`
  - ต้อง chunk ไฟล์ก่อนส่ง + reassemble ที่ปลายทาง

- [ ] **iOS support — WiFi Direct**
  - `lib/core/wifi_direct_transport.dart` ใช้ MethodChannel `wifi_direct` → Android only
  - `android/app/src/main/kotlin/.../WifiDirectChannel.kt` ไม่มี iOS counterpart
  - ตัวเลือก: Multipeer Connectivity หรือ Bonjour-based transport สำหรับ iOS
  - Transport อื่น (Nearby, BLE, Mesh) น่าจะรองรับ iOS ได้แล้ว
