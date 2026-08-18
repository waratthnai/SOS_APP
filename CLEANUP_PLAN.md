# Clean Code Plan — OffGrid SOS

แผนงาน clean code ทั้งระบบ แบ่งเป็นโมดูลย่อย ทำทีละส่วนตามลำดับด้านล่าง เช็คบ็อกซ์เมื่อเสร็จแต่ละงาน
อัปเดต section "สถานะปัจจุบัน" ทุกครั้งที่เริ่ม/จบ session เพื่อให้กลับมาทำต่อได้ทันทีโดยไม่ต้องไล่คุยใหม่

> **กติกา**: ห้ามแก้ WiFi Direct connection/discovery flow (`wifi_direct_transport.dart`,
> `WifiDirectChannel.kt` ส่วน connect/discover) — ทดสอบผ่านแล้ว ดู [[feedback_wifi_direct]] ในระบบ memory
> ยกเว้นถ้าเป็นแค่ style cleanup ที่ไม่กระทบ behavior ต้องถามผู้ใช้ก่อนทุกครั้ง

---

## สถานะปัจจุบัน

- **กำลังทำ**: Phase 1 — แตก `app_state.dart` ด้วย mixin (ผ่าน `part`/`part of`)
- **ทำล่าสุด**: แตกออกมาแล้ว 4 กลุ่ม (ดูรายละเอียดใน Phase 1 ด้านล่าง) —
  `app_state.dart` ลดจาก 3772 → **3438 บรรทัด** ทุกครั้งที่แตกแล้วรัน `flutter analyze lib`
  (0 issues) + `flutter test` (29/29 ผ่าน) ยืนยันก่อนไปกลุ่มถัดไป
- **ขั้นต่อไป**: กลุ่มที่เหลือใน `app_state.dart` มี dependency สูงขึ้นเรื่อย ๆ (ผูกกับ SOS/Rescue toggle,
  Nearby subs, Firebase merge) ต้องวางแผนละเอียดกว่าเดิมก่อนแตะ — ดู "กลุ่มที่เหลือ" ท้าย Phase 1

---

## หลักการ clean code ที่ใช้ตรวจทุกไฟล์

1. **ขนาด/ความรับผิดชอบ** — ไฟล์/คลาสทำหน้าที่เดียวชัดเจนไหม (SRP) ถ้าไฟล์ยาวเกิน ~500 บรรทัดและทำหลายเรื่อง ให้แยก
2. **ซ้ำซ้อน (DRY)** — logic ซ้ำกันระหว่าง transport ทั้ง 4 ตัว, ระหว่าง emergency/friend chat screen ฯลฯ
3. **dead code** — ฟังก์ชัน/ตัวแปร/import ที่ไม่ถูกเรียกใช้จริง
4. **error handling** — try/catch ที่กว้างเกินไป (`catch (e) {}` เงียบ ๆ), ไม่มี error handling ตรง boundary จริง (I/O, transport, Firebase)
5. **naming & readability** — ชื่อสื่อความหมาย, ฟังก์ชันยาวเกินไปควรแตกย่อย
6. **state management** — `AppState` เป็น singleton ขนาดใหญ่ ต้องระวัง side effect เวลาแก้
7. **security** — ห้าม log ข้อมูลอ่อนไหว (คีย์ E2EE, token), sanitize input จาก network เสมอ
8. **lint** — ให้ `flutter analyze` ผ่านสะอาดหลังแก้ทุก phase

---

## Phase 0 — Baseline (ทำก่อนเริ่ม)

- [x] รัน `flutter analyze` เก็บผลลัพธ์เป็น baseline (2026-08-18) — **หมายเหตุ**: มีโฟลเดอร์ `flutter/`
      (ดูเหมือน vendored Flutter SDK) อยู่ใต้ root โปรเจกต์ ทำให้ analyze สแกนโดน SDK เองด้วย เกิด error
      70 รายการ แต่ที่เกี่ยวกับโค้ดเราจริง (`lib/`) มีแค่ **18 รายการ ไม่มี error สักตัว มีแต่ info/warning**
      — แนะนำเช็คกับผู้ใช้ว่าโฟลเดอร์ `flutter/` ควรอยู่ใน `.gitignore`/analysis exclude ไหม (ไม่ใช่งาน
      cleanup ของแอพ แต่กระทบเวลารัน analyze ทุกครั้ง ทำให้ช้อยาวและ noisy)
- [ ] รัน `flutter test` ให้แน่ใจว่า test ที่มีอยู่ (`test/e2ee_service_test.dart`) ผ่าน ก่อนแตะโค้ด
- [ ] Commit สถานะปัจจุบันให้เรียบร้อยก่อนเริ่ม (working tree มีการแก้ไขค้างอยู่หลายไฟล์ — เช็คกับผู้ใช้ก่อนว่าจะ commit เป็น checkpoint ก่อนไหม)

### Baseline `flutter analyze` — เฉพาะ `lib/` (18 รายการ, ไม่มี error)

| ไฟล์ | บรรทัด | ปัญหา |
|---|---|---|
| `lib/core/app_state.dart` | 4, 5 | unnecessary_import (`foundation.dart`, `widgets.dart` ซ้ำกับ `material.dart`) |
| `lib/core/app_state.dart` | 1590, 1637, 2125, 3310 | curly_braces_in_flow_control_structures (if ไม่มี `{}`) |
| `lib/main.dart` | 756 | prefer_if_null_operators (`?:` ควรเป็น `??`) |
| `lib/ui/MapScreen.dart` | 1 | file_names — ชื่อไฟล์ควรเป็น `map_screen.dart` |
| `lib/ui/auth_gate.dart` | 82 | use_build_context_synchronously |
| `lib/ui/chat_history_screen.dart` | 317 | **unused_element** — `_buildSummaryCard` ไม่ถูกเรียกใช้เลย (dead code) |
| `lib/ui/debug_screen.dart` | 101, 113, 125, 147 | use_build_context_synchronously (4 จุด) |
| `lib/ui/emergency_chat_screen.dart` | 231, 234 | curly_braces_in_flow_control_structures |
| `lib/ui/friend_chat_screen.dart` | 793, 799 | use_build_context_synchronously |

**[x] แก้ครบทั้ง 18 จุดแล้ว (2026-08-18)** — สรุปสิ่งที่ทำ:
- ลบ import ซ้ำซ้อน 2 ตัวใน `app_state.dart` (`foundation.dart`, `widgets.dart`)
- ห่อ `{}` ให้ if-statement 6 จุดใน `app_state.dart` + 2 จุดใน `emergency_chat_screen.dart`
- แก้ `?:` เป็น `??` ใน `main.dart:756`
- เปลี่ยนชื่อไฟล์ `MapScreen.dart` → `map_screen.dart` (ตรวจแล้วว่าไม่มีที่ไหน import widget นี้เลย —
  น่าจะเป็นหน้าจอที่สร้างไว้แต่ยังไม่ได้เชื่อมเข้า routing จริง คุ้มค่าตรวจสอบเพิ่มถ้ามีเวลา)
- แก้ `use_build_context_synchronously` 7 จุด (`auth_gate.dart`, `debug_screen.dart` x4, `friend_chat_screen.dart` x2)
  ด้วยการเช็ค `context.mounted` แทน/เพิ่มเติมจาก `mounted` เดิม
- ลบ dead code ทั้งก้อนใน `chat_history_screen.dart`: เมธอด `_buildSummaryCard()`, widget class `_StatCard`,
  และ field `_allMessages` ที่ไม่มีจุดอ่านค่าเหลืออยู่เลยหลังลบสองตัวแรก (ตรวจ 3 ชั้นต่อเนื่องกันเพราะลบตัวแรกแล้ว
  ทำให้ตัวถัดไปกลายเป็น dead code ตามไปด้วย)

ผลลัพธ์: `flutter analyze lib` = **0 issues**, `flutter test` = **29/29 ผ่านหมด**
นอกจากนี้ยัง exclude โฟลเดอร์ `flutter/` ใน `analysis_options.yaml` ทำให้ analyze เร็วขึ้นจาก ~700s → ~10s

## ขนาดไฟล์ปัจจุบัน (อ้างอิงจัดลำดับความสำคัญ)

| ไฟล์ | บรรทัด | หมายเหตุ |
|---|---|---|
| `lib/core/app_state.dart` | 3772 | God object — timers, transport switching, chat, friend, notification ทั้งหมดอยู่ที่นี่ |
| `lib/main.dart` | 1816 | น่าจะมี UI/logic ปนกันเยอะ ต้องแยก widget ออก |
| `lib/ui/emergency_chat_screen.dart` | 1481 | หน้าจอเดียวแต่ยาวมาก |
| `lib/ui/friend_chat_screen.dart` | 1269 | คล้ายกับ emergency_chat_screen — มี logic ซ้ำกันสูง |
| `lib/core/nearby_transport.dart` | 1101 | transport หลัก |
| `lib/cloud/firebase_service.dart` | 853 | |
| `lib/core/friend_service.dart` | 725 | |
| `lib/core/mesh_transport.dart` | 685 | มี `sendFile()` เป็น `UnimplementedError` (ดู TODO.md) |
| `lib/ui/profile_screen.dart` | 640 | |
| `lib/ui/chat_history_screen.dart` | 635 | |
| `lib/ui/friends_screen.dart` | 585 | |
| `lib/ui/add_friend_screen.dart` | 509 | |
| `lib/core/e2ee_service.dart` | 487 | security-critical — แก้ระวังเป็นพิเศษ มี test คุ้มครองอยู่แล้ว |
| `lib/core/ble_transport.dart` | 461 | ยังไม่ได้ทดสอบบนอุปกรณ์จริง (ตาม TODO.md) — คลีนแบบไม่เปลี่ยน behavior |
| `lib/ui/friend_requests_screen.dart` | 405 | |
| `lib/ui/sos_orb.dart` | 387 | |
| `lib/core/wifi_direct_transport.dart` | 362 | **ห้ามแก้ core flow** ดูกติกาด้านบน |
| `lib/core/chat_db.dart` | 333 | |
| `lib/core/app_theme.dart` | 329 | |
| `lib/core/friend_db.dart` | 316 | |
| อื่น ๆ ต่ำกว่า 300 บรรทัด | - | ทำใน phase ท้าย ๆ แบบรวมกลุ่ม |

---

## Phase 1 — `lib/core/app_state.dart` (3772 บรรทัด) — ลำดับแรกเพราะเป็นจุดเสี่ยงสูงสุด

เป้าหมาย: แตก God object ออกเป็นส่วนย่อยที่ทดสอบ/อ่านง่ายขึ้น โดย **ไม่เปลี่ยน public API ที่ UI เรียกใช้** (เพื่อลดความเสี่ยง regression)

- [x] สำรวจ/จัดกลุ่ม responsibility ทั้งหมดในไฟล์ (grep หา method/field ทั้งหมด แบ่งเป็นกลุ่มตามหน้าที่)
- [x] **เทคนิคที่ใช้แตกไฟล์**: `part`/`part of` (ไม่ใช่ import แยก library) — เพราะ Dart privacy (`_`)
      เป็นระดับ **library** ไม่ใช่ระดับ class ถ้าแยกเป็น library ใหม่จริง ๆ (import ปกติ) จะเข้าถึง
      private field/method เดิมของ `AppState` ไม่ได้เลย ต้องใช้ `part of 'app_state.dart';` ในไฟล์ใหม่
      เพื่อให้ยังอยู่ library เดียวกัน แล้วห่อ group นั้นเป็น `mixin ... on ChangeNotifier { ... }`
      ที่ประกาศ cross-dependency (เช่น `transport`, `peers`, `isSOSActive`) เป็น **abstract getter**
      ซึ่ง `AppState` เองมีอยู่แล้วเป็น concrete member (ใส่ `@override` ให้ตรง) — วิธีนี้ทำให้ **ไม่ต้องเปลี่ยน
      public API ของ AppState เลย** ของเดิมที่ UI เรียกใช้ยังทำงานเหมือนเดิมทุกจุด
- [x] แยกเป็น mixin ทีละกลุ่ม เริ่มจากกลุ่ม dependency น้อยที่สุดก่อน — **เสร็จแล้ว 4 กลุ่ม**:
  1. `lib/core/app_state_location.dart` — `AppStateLocationMixin`: GPS real-time broadcast/stream
     (`_startLocationBroadcast`, `_broadcastCurrentGPS`, `retryLocationBroadcast`, `_stopLocationBroadcast`,
     field `_myCurrentPosition`/`_locationStreamSubscription`) — ต้องการ abstract `transport`, `peers`,
     `isSOSActive`, `isRescueMode` (มีอยู่แล้วทั้งหมด)
  2. `lib/core/app_state_connection_monitor.dart` — `AppStateConnectionMonitorMixin`: keep-alive heartbeat
     (30s) + connection/reconnect monitor (10s) — ต้องการ abstract `transport`, `peers`, `startScan()`,
     `stopScan()` (มีอยู่แล้วทั้งหมด)
  3. `lib/core/app_state_stable_peers.dart` — `AppStateStablePeersMixin`: stable peer list + cleanup timer
     (5s) — ไม่ต้องการ cross-dependency นอกจาก `notifyListeners()` (มาจาก `on ChangeNotifier`)
  4. `lib/core/app_state_online_status.dart` — `AppStateOnlineStatusMixin`: Firebase online-status
     heartbeat (5s) — ต้องการ abstract `isAppInForeground` (เพิ่ม public getter ใหม่ให้ `AppState`
     เพราะเดิมมีแค่ private field `_isAppInForeground` — เป็น additive change ปลอดภัย)

  ทุกกลุ่มยืนยันด้วย `flutter analyze lib` (0 issues) + `flutter test` (29/29 ผ่าน) แยกกันทีละกลุ่ม
  ก่อนไปกลุ่มถัดไป — ผลลัพธ์: `app_state.dart` 3772 → **3438 บรรทัด**

- [ ] **กลุ่มที่เหลือ (ยังไม่แตะ) — dependency สูงกว่าเดิมมาก ต้องวางแผนเพิ่มก่อนแตะ**:
  - `_subs()` (Nearby transport event subscriptions, ~420 บรรทัด) — เป็นจุดศูนย์กลางที่ผูกกับแทบทุกกลุ่ม
    (chat, SOS, rescue, GPS, friend) การแตกออกมาต้องระวังเรื่องลำดับการเรียก callback มาก
  - `_mergeFirebaseMessagesIntoState()` (~530 บรรทัด) — ใหญ่สุดในไฟล์ ผูกกับ friend chat + read receipt
    ที่เพิ่งแก้และยังไม่ได้ทดสอบบนอุปกรณ์จริง (ตาม TODO.md) — ความเสี่ยงสูงถ้าแตกแล้วพลาด ควรรอจนกว่า
    จะทดสอบ read-receipt flow จริงก่อน หรือแตกแบบระมัดระวังเป็นพิเศษ + เพิ่ม test coverage ก่อนแตะ
  - `_handleSOSStatus`/`_handleRescueStatus`/`broadcastSOSStatus`/`toggleSOSMode` (~400 บรรทัด รวมกัน) —
    ผูกกับ background service sync, location broadcast mode, notification พร้อมกันหลายจุด
  - `_handleReadReceipt`, `_handleGPSLocation`, chat compose/parse (`_composeChatWireBody` ฯลฯ) —
    กลุ่มกลาง ๆ ผูกกับ E2EE session และ message queue
  - แนะนำ: ทำ Phase 2 (`main.dart`) หรือ Phase 3 (chat screens) ต่อก่อน แล้วค่อยกลับมาแตะกลุ่มเสี่ยงสูง
    เหล่านี้ทีหลัง เมื่อมี test coverage ที่ดีขึ้นหรือได้ทดสอบบนอุปกรณ์จริงแล้ว
- [ ] ลบ dead code / ตัวแปรที่ไม่ใช้ (เช่นเช็คว่า `_isPassiveListening` ที่ note ไว้ใน TODO.md ว่าไม่เคย reset — ตัดสินใจว่าจะแก้หรือปล่อยตามที่ตั้งใจไว้ ถามผู้ใช้ก่อนถ้าเป็น behavior change)
- [ ] รวม logic ที่ซ้ำกันระหว่าง flow ของ 4 transport ให้เป็นจุดเดียว ถ้าเป็นไปได้
- [ ] รัน `flutter analyze` + `flutter test` + ทดสอบ manual smoke test (เปิดแอพ, สลับโหมด, เปิดแชท) ก่อนปิด phase

## Phase 2 — `lib/main.dart` (1816 บรรทัด)

- [ ] แยก widget ย่อยออกจากไฟล์เดียว (screen setup, routing, top-level providers ถ้ามี) ไปเป็นไฟล์ใน `lib/ui/`
- [ ] เช็คว่ามี business logic หลุดมาอยู่ใน `main.dart` ที่ควรอยู่ใน `app_state.dart` หรือ service อื่นไหม
- [ ] ลบ import ที่ไม่ใช้, จัดกลุ่ม import ให้เป็นระเบียบ

## Phase 3 — Chat screens: `emergency_chat_screen.dart` + `friend_chat_screen.dart` (รวมกัน ~2750 บรรทัด)

สองไฟล์นี้มี UI/logic คล้ายกันมาก (message bubble, status icon, input bar, file picker) — เป้าหมายคือดึงส่วนที่ใช้ร่วมกันออกมาเป็น shared widget/helper ใน `lib/widgets/`

- [ ] เทียบสองไฟล์หา logic ที่ซ้ำกัน (message list rendering, read receipt display, file/image handling)
- [ ] แยก shared widget ออกมา (เช่น message bubble, input toolbar) โดยพารามิเตอร์ต่างที่จำเป็น (P2P vs cloud) ส่งผ่าน props
- [ ] แยก business logic (การเรียก appState, การ format ข้อความ) ออกจาก build method ให้มากที่สุด
- [ ] คงพฤติกรรม read-receipt/E2EE ที่เพิ่งแก้ไว้ล่าสุดให้เหมือนเดิมทุกกรณี (มี note ใน TODO.md ว่ายังไม่ได้ทดสอบบนอุปกรณ์จริง — ห้ามเปลี่ยน behavior โดยไม่ตั้งใจ)

## Phase 4 — Transport layer: `nearby_transport.dart`, `ble_transport.dart`, `mesh_transport.dart`

- [ ] ตรวจว่า `Transport` interface (`lib/core/transport.dart`) ครอบคลุมพอ ไม่ต้องมี transport-specific hack ใน `app_state.dart`
- [ ] `nearby_transport.dart` (1101 บรรทัด) — แยก responsibility ถ้าปนกันหลายเรื่อง (discovery, connection, message framing, file transfer)
- [ ] `mesh_transport.dart` — คลีนคู่กับการดู `sendFile()` ที่ยัง `UnimplementedError` อยู่ (เป็น feature ค้าง ไม่ใช่ cleanup — แยก task ออกจากกันชัดเจน อย่าทำปนกัน)
- [ ] `ble_transport.dart` — คลีนแบบ conservative เพราะยังไม่ได้ทดสอบบนอุปกรณ์จริงตาม TODO.md ห้ามเปลี่ยน behavior เดา ๆ
- [ ] `wifi_direct_transport.dart` — **เฉพาะ dead code/import/comment cleanup เท่านั้น ห้ามแตะ connect/discover flow** ตามกติกาบนสุด

## Phase 5 — Cloud/Firebase layer: `firebase_service.dart`, `friend_service.dart`, `fcm_service.dart`

- [ ] แยก Firestore query logic ออกจาก business logic ถ้าปนกัน
- [ ] เช็ค error handling รอบ network call ทั้งหมด (ต้องไม่ crash แอพเวลา offline)
- [ ] เช็คว่าไม่มี PII หลุด log (มี fix ไปแล้วเรื่อง `users/{userId}` ตาม TODO.md — ตรวจซ้ำว่าไม่มีจุดอื่นหลุดอีก)

## Phase 6 — UI ที่เหลือ (screens < 700 บรรทัด)

ทำเป็นกลุ่มตามความคล้ายกัน แทนที่จะทำทีละไฟล์:

- [ ] กลุ่ม friend management: `friends_screen.dart`, `add_friend_screen.dart`, `friend_requests_screen.dart`, `friend_profile_screen.dart`
- [ ] กลุ่ม profile/setup: `profile_screen.dart`, `device_name_setup_screen.dart`, `auth_gate.dart`
- [ ] กลุ่ม widget ย่อย: `lib/widgets/*` (message_status_icon, loading_overlay, floating_notification)
- [ ] `sos_orb.dart`, `debug_screen.dart`, `MapScreen.dart`, `notification_panel.dart`, `chat_filter_bar.dart`

## Phase 7 — Core services ที่เหลือ (< 350 บรรทัด)

- [ ] `chat_db.dart`, `friend_db.dart`, `chat_models.dart`, `friend_models.dart`, `chat_filter_service.dart`, `message_queue_service.dart`, `device_id_manager.dart`, `notification_service.dart`, `app_theme.dart`

## Phase 8 — Final pass

- [ ] รัน `flutter analyze` เทียบกับ baseline (Phase 0) — ต้องไม่มี warning เพิ่มขึ้น
- [ ] รัน `flutter test` ทั้งหมดผ่าน
- [ ] Manual smoke test ครบทุกโหมด (passive, SOS, rescue) และทั้ง 4 transport อย่างน้อยแบบ UI-level (ไม่ต้องมีอุปกรณ์คู่ถ้าทำไม่ได้ ให้บอกผู้ใช้ชัดเจนว่าทดสอบระดับไหน)
- [ ] อัปเดต `CLAUDE.md` ถ้าโครงสร้างไฟล์เปลี่ยนไปจากที่ระบุไว้เดิม

---

## Log การทำงาน

> เพิ่มบรรทัดใหม่ทุกครั้งที่จบ session หนึ่งรอบ (วันที่ + phase + สรุปสั้น ๆ)

- 2026-08-18 — สร้างแผนนี้ ยังไม่เริ่มแก้โค้ด
- 2026-08-18 — Phase 0 เสร็จสมบูรณ์: รัน baseline analyze, exclude `flutter/` ออกจาก analysis
  (ทำ analyze เร็วขึ้น 700s→10s), แก้ lint quick-win ครบ 18 จุด (รวมลบ dead code
  `_buildSummaryCard`/`_StatCard`/`_allMessages` ใน `chat_history_screen.dart`), analyze = 0 issues,
  test = 29/29 ผ่าน — commit `f171b8b`
- 2026-08-18 — Phase 1 (บางส่วน): แตก `app_state.dart` ด้วย `part`/`part of` + mixin สำเร็จ 4 กลุ่ม
  (location broadcast, connection monitor, stable peers, online status heartbeat) แต่ละกลุ่มยืนยันด้วย
  analyze (0 issues) + test (29/29) แยกกัน — `app_state.dart` 3772 → 3438 บรรทัด กลุ่มที่เหลือ
  (`_subs()`, `_mergeFirebaseMessagesIntoState`, SOS/Rescue handling) ผูก dependency แน่นกว่ามาก
  ต้องวางแผนเพิ่มก่อนแตะ — ดูรายละเอียดใน Phase 1 checklist
