# OffGrid SOS

> แอปพลิเคชันสื่อสารฉุกเฉินแบบ P2P ที่ทำงานได้โดยไม่ต้องใช้อินเทอร์เน็ต

## ฟีเจอร์หลัก

- **SOS / Rescue Mode** — ส่งสัญญาณฉุกเฉินพร้อม GPS ไปยังอุปกรณ์ใกล้เคียง
- **P2P Chat แบบออฟไลน์** — แชทผ่าน Nearby Connections, BLE, Mesh หรือ WiFi Direct โดยไม่ต้องมีเน็ต
- **Mesh Routing** — ส่งต่อข้อมูล multi-hop ผ่านอุปกรณ์กลางด้วย TTL-based routing
- **แชร์ตำแหน่งแบบเรียลไทม์** — broadcast GPS ทุก 8 วินาที แสดงบน Google Maps
- **Friend System (Cloud)** — เพิ่มเพื่อน, แชทผ่าน Firestore, รับ push notification ผ่าน FCM
- **E2EE** — การเข้ารหัสข้อความแบบ end-to-end (`cryptography` package)
- **แชร์ไฟล์/รูปภาพ/วิดีโอ** — ผ่าน Nearby หรือ Firebase Storage
- **Background Service** — ทำงานเบื้องหลังด้วย `flutter_foreground_task`

## Transport Layer

มีทั้งหมด 4 implementation สลับได้ที่ runtime:

| Transport | Package | หมายเหตุ |
| --- | --- | --- |
| **Nearby** (หลัก) | `nearby_connections` | P2P_CLUSTER, serviceId `com.example.offgrid_sos.nearby` |
| **BLE** | `bluetooth_low_energy` | GATT Central+Peripheral, scan restart ทุก 15s |
| **Mesh** | wraps NearbyTransport | HELLO/PEER_LIST_REQUEST ทุก 30s, TTL-based hop |
| **WiFi Direct** | MethodChannel native | WifiP2pManager, periodic discovery ทุก 45s |

## โครงสร้างโปรเจกต์

```
lib/
├── core/
│   ├── transport.dart          # abstract interface: Transport, Peer, Message
│   ├── nearby_transport.dart   # Google Nearby Connections
│   ├── ble_transport.dart      # BLE GATT
│   ├── mesh_transport.dart     # multi-hop mesh (wraps Nearby)
│   ├── wifi_direct_transport.dart
│   ├── app_state.dart          # global singleton ChangeNotifier
│   ├── chat_db.dart            # SQLite: P2P chat + friend chat
│   ├── chat_models.dart
│   ├── friend_models.dart
│   ├── friend_service.dart
│   ├── friend_db.dart
│   ├── fcm_service.dart
│   ├── notification_service.dart
│   ├── message_queue_service.dart
│   ├── chat_filter_service.dart
│   ├── e2ee_service.dart
│   ├── device_id_manager.dart
│   ├── app_theme.dart
│   └── logger.dart
├── cloud/
│   └── firebase_service.dart
├── services/
│   └── background_service.dart
├── ui/                         # หน้าจอทั้งหมด
│   ├── emergency_chat_screen.dart
│   ├── friend_chat_screen.dart
│   ├── friends_screen.dart
│   ├── add_friend_screen.dart
│   ├── friend_requests_screen.dart
│   ├── chat_history_screen.dart
│   ├── MapScreen.dart
│   ├── sos_orb.dart
│   ├── profile_screen.dart
│   ├── notification_panel.dart
│   ├── video_player_page.dart
│   ├── debug_screen.dart
│   ├── device_name_setup_screen.dart
│   ├── auth_gate.dart
│   └── chat_filter_bar.dart
├── widgets/
│   ├── floating_notification.dart
│   ├── loading_overlay.dart
│   └── message_status_icon.dart
├── firebase_options.dart
└── main.dart
```

## State Management

`AppState` (`lib/core/app_state.dart`) เป็น global singleton `ChangeNotifier` ที่ใช้ direct access (`appState`) โดยไม่ผ่าน Provider/Riverpod

Timers ที่รันอยู่ตลอดเวลา:

- Keep Alive: 30s → ส่ง `KEEP_ALIVE:timestamp` ไปยัง peers
- Connection Monitor: 10s → reconnect อัตโนมัติเมื่ออยู่ใน SOS/Rescue mode
- Stable Peers cleanup: 5s → ลบ peer ที่ไม่เห็นมากกว่า 45s
- Location Broadcast: 8s → ส่ง GPS ไปยัง peers

## เริ่มต้นใช้งาน

### ความต้องการ

- Flutter SDK `^3.9.2`
- Android Studio (เป้าหมายหลักคือ Android)
- Firebase project พร้อม `google-services.json`
- Google Maps API Key

### ติดตั้ง

```bash
git clone https://github.com/waratthnai47/SOS_APP.git
cd SOS_APP

flutter pub get
```

ตั้งค่า Firebase:

- วาง `google-services.json` ไว้ที่ `android/app/`
- เพิ่ม Google Maps API Key ใน `android/app/src/main/AndroidManifest.xml`

### คำสั่งที่ใช้บ่อย

```bash
flutter run                       # รันบนอุปกรณ์/emulator
flutter build apk --debug         # สร้าง debug APK
flutter build apk --release       # สร้าง release APK
flutter analyze                   # static analysis
```

## Android Permissions

| Permission | Android Version | วัตถุประสงค์ |
| --- | --- | --- |
| `ACCESS_FINE_LOCATION` | ทุกเวอร์ชัน | Nearby, WiFi scanning, GPS |
| `BLUETOOTH_SCAN/CONNECT/ADVERTISE` | 12+ | Nearby Connections, BLE |
| `NEARBY_WIFI_DEVICES` | 13+ | WiFi component ของ Nearby |

## Dependencies หลัก

| Package | การใช้งาน |
| --- | --- |
| `nearby_connections` | P2P transport หลัก |
| `bluetooth_low_energy` | BLE GATT |
| `firebase_core/auth/firestore/storage/messaging` | Cloud features |
| `google_maps_flutter` + `geolocator` | แผนที่และ GPS |
| `sqflite` | SQLite สำหรับ chat ออฟไลน์ |
| `cryptography` | E2EE |
| `flutter_foreground_task` | Background service |
| `flutter_local_notifications` | Local notifications |
| `google_fonts` | Typography |

## Known Issues

- **WiFi Direct**: แสดง system dialog เมื่อ connect ครั้งแรก, ยังไม่แสดง peer status/distance
- **BLE/Mesh**: ยังไม่ได้ทดสอบบนอุปกรณ์จริง
- **`MeshTransport._startPeriodicScan()`**: timer ทำงานทุก 20s แต่ body ว่างเปล่า
- **Transport listener leak**: การสลับ transport เพิ่ม `onPeers.listen` ใหม่โดยไม่ cancel อันเก่า
- **Connection Monitor**: auto-reconnect ทำงานเฉพาะเมื่ออยู่ใน SOS/Rescue mode เท่านั้น

## ผู้พัฒนา

- Waratthnai ([@waratthnai47](https://github.com/waratthnai47))

## License

Educational purposes only.
