# TODO

## Fixed (2026-08-18, profile picture upload)

- [x] **ปุ่มกล้องในหน้าโปรไฟล์ใช้งานได้จริงแล้ว** — เดิม `onPressed` เป็นแค่ stub โชว์ snackbar
      "ฟีเจอร์นี้จะพัฒนาในเวอร์ชันต่อไป" ไม่เคยเปิด camera/gallery เลย ตอนนี้กดแล้วเปิดเมนูเลือก
      "ถ่ายรูป"/"เลือกจากคลัง" (ใช้ `image_picker` ที่มีอยู่แล้วในโปรเจกต์), บีบอัดรูป (`maxWidth: 800,
      imageQuality: 85`), อัปโหลดขึ้น Firebase Storage ที่ path `avatars/{userId}.{ext}` (ใช้
      `firebaseService.uploadFile()` ที่มีอยู่แล้ว เดิมใช้แค่กับรูปแชท) แล้วบันทึก URL ผ่าน
      `friendService.updateUserProfile()` ซึ่ง sync ขึ้นทั้ง `users/{id}` และ `public_profiles/{id}`
      ให้อัตโนมัติอยู่แล้ว (`lib/ui/profile_screen.dart`)
      — ต้องออนไลน์ + login ถึงจะเปลี่ยนรูปได้ (มี guard เช็คแล้วโชว์ข้อความแจ้ง ถ้าไม่ผ่าน) เพราะรูปต้องมี URL
      จริงถึงจะแสดงผ่าน `NetworkImage` ได้ ไม่รองรับตั้งรูปแบบออฟไลน์
      — ยังไม่ได้ทดสอบจริงบนอุปกรณ์ (ทั้งกล้อง, คลังภาพ, และว่า Firebase Storage rules อนุญาต path
      `avatars/` หรือไม่ — repo นี้ไม่มี `storage.rules` จัดการเอง คาดว่า config อยู่ที่ Firebase console)

## Fixed (2026-08-18, read receipts — online friend chat)

- [x] **Read receipt สำหรับแชทเพื่อน (online) — ผู้ส่งเห็นสถานะ "อ่านแล้ว" จริง** — เดิม `isRead`
      เป็นแค่ local flag อัปเดตเฉพาะในเครื่องผู้รับ (ใช้นับ unread badge) ไม่เคยเขียนกลับขึ้น Firestore
      ตอนนี้ `markFriendMessagesAsRead()` เขียน `isRead: true` กลับขึ้น Firestore ด้วย (batch update,
      `lib/cloud/firebase_service.dart` เพิ่ม `markFriendChatMessagesAsRead()`, เรียกจาก
      `lib/core/app_state.dart`) และ `_mergeFirebaseMessagesIntoState()` (ตัวรับ real-time stream
      `streamFriendChatMessages`) แก้ให้อัปเดต `isRead` ของข้อความที่มีอยู่แล้วด้วย ไม่ใช่แค่เพิ่มข้อความใหม่
      อย่างเดียวเหมือนเดิม — UI (`friend_chat_screen.dart`) มี `MessageStatusIcon` แสดงติ๊กฟ้า
      (`MessageStatus.synced`) ตาม `message.isRead` อยู่แล้ว ไม่ต้องแก้ UI เพิ่ม
      — แก้ `firestore.rules` (เดิม `allow update: if false` บล็อกการแก้ไข message document ทั้งหมด
      ตอนนี้เปลี่ยนเป็นอนุญาตเฉพาะผู้รับ `toUserId` แก้ได้แค่ field `isRead` เท่านั้น) และ **deploy ขึ้น
      Firebase แล้ว** (2026-08-18) — ยังไม่ได้ทดสอบ flow จริงบนอุปกรณ์ (เปิดแชท 2 เครื่อง เช็คว่าติ๊กฟ้าขึ้นจริง)
- [x] **Read receipt สำหรับแชทฉุกเฉิน (offline P2P)** — เพิ่ม protocol ใหม่ 2 ส่วน:
      (1) ข้อความแชทที่ส่งตรง (`sendChatText`, รวม retry ผ่าน `MessageQueueService`) ตอนนี้ห่อด้วย
      `CHATMSG:<id>:<text>` ก่อนเข้ารหัส (`_composeChatWireBody`/`_parseChatWireBody` ใน
      `lib/core/app_state.dart`) ทำให้ผู้ส่ง/ผู้รับใช้ message id เดียวกัน (เดิมผู้รับสร้าง id ใหม่เองทุกครั้ง
      ไม่มีทางอ้างอิงข้อความเดิมได้เลย) (2) เปิดห้องแชทฉุกเฉิน → `markPeerMessagesAsRead()` มาร์คข้อความจาก
      peer นั้นว่าอ่านแล้วในเครื่อง แล้วส่ง `READ:<id1>,<id2>,...` กลับผ่าน transport ปัจจุบันทันที (best-effort,
      ไม่ await) ฝั่งผู้ส่งรับ `READ:` แล้วอัปเดต `isRead` ของข้อความที่ส่งไปเป็น true (`_handleReadReceipt`)
      — UI (`emergency_chat_screen.dart`) โชว์ติ๊กฟ้าเหมือนฝั่ง friend chat (`message.isRead ? synced : status`)
      และแก้ `_onMessagesChanged` ให้ rebuild เมื่อจำนวนข้อความที่อ่านแล้วเปลี่ยน ไม่ใช่แค่ตอนจำนวนข้อความ
      เปลี่ยนอย่างเดียว (เดิม read receipt จะไม่โชว์ผลจนกว่าจะปิด-เปิดหน้าจอใหม่)
      — **ข้อจำกัดตามที่คุยไว้ตั้งแต่แรก:** ใช้ได้เฉพาะตอนทั้งสองอุปกรณ์ยังเชื่อมต่อกันอยู่ ไม่มี cloud fallback,
      และ `READ:` ส่งแบบ direct เท่านั้น ไม่ผ่าน mesh relay (ต่างจากข้อความแชทที่ relay ได้เมื่อมีหลาย peer)
      — ยังไม่ได้ทดสอบจริงบนอุปกรณ์ 2 เครื่อง

## Known Issues (not yet fixed)

- [ ] **WiFi Direct — peer status/distance not displayed**
  - `WifiP2pManager` ไม่ expose RSSI/distance ตรงๆ
  - ปัจจุบัน `_distanceLabel()` ใช้ GPS diff — ใช้ได้เมื่อทั้งสองฝั่งส่ง `GPS_LOC:` เท่านั้น

- [ ] **BLE/Mesh — ยังไม่ได้ทดสอบบนอุปกรณ์จริง**
  - `lib/core/ble_transport.dart` และ `lib/core/mesh_transport.dart`
  - ต้องทดสอบ handshake, reconnect, และ message delivery บน physical device

> **WiFi Direct** — connection/discovery flow ทดสอบผ่านแล้ว ห้ามแก้ส่วนนั้น
> (ยกเว้น `WifiDirectChannel.kt` ส่วนรับไฟล์ ที่แก้ด้าน security ไปแล้วเมื่อ 2026-08-18 — ดูหัวข้อ Security ด้านล่าง ยังไม่ได้ retest การรับไฟล์จริงบนอุปกรณ์)

- [ ] **WiFi Direct — system confirmation dialog (unavoidable)**
  - Android `WifiP2pManager` บังคับ pop-up ตอน connect ครั้งแรก
  - ไม่มีทาง bypass ผ่าน API — ต้องยอมรับ UX นี้ หรือเปลี่ยนไปใช้ transport อื่น

## Fixed (2026-08-18, security review)

- [x] **E2EE — เพิ่ม forward secrecy ด้วย X3DH-lite** — เดิมใช้ static X25519 identity key
      คำนวณ shared secret ตรงๆ ทุก session ถ้า long-term key หลุดจะย้อนถอดรหัสข้อความเก่าได้ทั้งหมด
      ตอนนี้ทุก handshake (`E2E_HELLO`/`E2E_ACK`) สร้าง ephemeral X25519 keypair ใหม่ที่ไม่ persist ที่ไหนเลย
      แล้วรวม ECDH 4 เทอม (identity×identity, ephemeral×ephemeral, และ cross term ทั้งสองทาง) เข้า HKDF
      ก่อนได้ session key จริง — โครงสร้างแบบเดียวกับ X3DH ของ Signal (ไม่มี prekey bundle เพราะเป็น P2P
      real-time handshake ไม่ใช่ async messaging) คีย์ ephemeral ถูกทิ้งทันทีหลัง derive เสร็จ ทำให้ต่อให้
      identity key หลุดในอนาคต ก็ไม่สามารถย้อนคำนวณ session key เก่าได้ (`lib/core/e2ee_service.dart`)
      — เพิ่ม unit test `test/e2ee_service_test.dart` ยืนยันว่า initiator/responder derive session key ตรงกัน
      และ re-handshake หลัง `clearSession()` ยังคุยกันได้ปกติ (ผ่านทั้งคู่) — ยังไม่ได้ทดสอบ handshake จริงบน
      อุปกรณ์ผ่าน transport จริง (Nearby/BLE/WiFi Direct/Mesh) มีแต่ unit test ระดับ logic เท่านั้น
- [x] **Firestore `users/{userId}` เปิดอ่าน PII ให้ทุกคน** — จำกัดอ่านเฉพาะเจ้าของ,
      แยก `public_profiles/{userId}` (ไม่มี email/fcmToken) ให้ friend search/online-status ใช้แทน
      (`firestore.rules`, `lib/cloud/firebase_service.dart`, `lib/core/friend_service.dart`)
      — **ยังไม่ได้ deploy rules ขึ้น Firebase**, ยังไม่ได้ทดสอบ add-friend/search/online-status จริง
- [x] **ปลอมแจ้งเตือน SOS ผ่าน `notifications` collection** — Cloud Function ดึง fcmToken/senderName
      เองจาก Firestore แทนการเชื่อค่าที่ client ส่งมา (`functions/index.js`, `lib/core/fcm_service.dart`)
      — **ยังไม่ได้ deploy Cloud Function ใหม่**
- [x] **BLE file transfer — path traversal** — sanitize ชื่อไฟล์ด้วย `path.basename()` ก่อนเขียน
      (`lib/core/ble_transport.dart`)
- [x] **WiFi Direct file transfer — path traversal** — sanitize ชื่อไฟล์ด้วย `File(name).name` ก่อนเขียน
      (`android/app/src/main/kotlin/.../WifiDirectChannel.kt`) — ยังไม่ได้ retest รับไฟล์จริงบนอุปกรณ์
- [x] **E2EE — TOFU key mismatch ตอนนี้ block การใช้ key ใหม่จริง** — เมื่อ peer ส่ง public key ใหม่มาไม่ตรงกับที่
      trust ไว้ ระบบจะ**ไม่**ใช้ key ใหม่ derive session ทันทีอีกต่อไป (เก็บเป็น pending) session เดิม (ถ้ามี)
      ยังใช้งานต่อได้ตามปกติ จนกว่า user จะกด "ยืนยันรับคีย์ใหม่" ใน banner ที่หน้าแชท ถึงจะสลับไปใช้ key ใหม่
      (`lib/core/e2ee_service.dart`, `lib/core/app_state.dart`, `lib/ui/emergency_chat_screen.dart`)
      — ยังไม่ได้ทดสอบบนอุปกรณ์จริง (ต้องจำลอง peer เปลี่ยนคีย์แล้วเช็ค banner/ปุ่มยืนยัน)
- [x] **Mesh transport — เซ็น routing/control message ด้วย Ed25519 ป้องกัน route/identity spoofing**
      ข้อความ `MESH:` ทุกอันตอนนี้มี public key + signature ของผู้สร้าง (originator) แนบมาด้วย เซ็นทับ
      `id|from|to|body`, ผู้รับ TOFU-bind public key เข้ากับ `from` deviceId ครั้งแรกที่เจอ แล้วปฏิเสธ/ทิ้ง
      ข้อความทันทีถ้า `from` เดิมส่ง public key ใหม่มา (สงสัยว่าเป็นการปลอมตัว) หรือ signature ไม่ตรง — ก่อนจะ
      เอาข้อมูลไปอัปเดต routing table หรือแสดงผล (`lib/core/e2ee_service.dart` เพิ่ม `meshSigningPubKeyB64`/
      `signMeshMessage`/`verifyMeshMessage`, `lib/core/mesh_transport.dart` เปลี่ยน wire format เป็น
      `MESH:id:from:to:ttl:hops:pubKey:sig:body`) — **เปลี่ยน wire format ของ mesh protocol** ทำให้ข้อความ
      mesh รุ่นเก่า (ไม่มี pubKey/sig) parse ไม่ผ่านแล้ว (ยอมรับได้เพราะ mesh ยังไม่เคย deploy จริง) —
      ยังไม่ได้ทดสอบ multi-hop จริงบนอุปกรณ์หลายเครื่อง ต้องทำคู่กับ BLE/Mesh device testing ด้านบน

## Battery / Power — พบจากการรีวิว 2026-08-18

- [ ] **GPS ไม่หยุดตอนแอพเข้า background** — ตั้งใจ**ไม่แก้** ตามคำขอ เพราะต้องการให้ตำแหน่ง/สถานะ
      ยังอัปเดตต่อแม้ผู้ขอความช่วยเหลือปิดหน้าจอไว้ (`lib/core/app_state.dart`, `didChangeAppLifecycleState`)

## Fixed (2026-08-18, battery/power review)

- [x] **GPS accuracy ผูกกับโหมด SOS/Rescue** — เดิม `_startLocationBroadcast()` ใช้
      `LocationAccuracy.high` + `distanceFilter: 5` ตลอดเวลาไม่ว่าจะอยู่โหมดไหน ตอนนี้โหมด passive (ไม่ได้
      SOS/Rescue) ใช้ `LocationAccuracy.medium` + `distanceFilter: 30` แทน ประหยัดแบตขึ้นมาก ส่วนโหมด
      SOS/Rescue ยังคง high-accuracy/real-time เหมือนเดิมเพราะจำเป็นต้องรู้ตำแหน่งแม่นยำ — สลับอัตโนมัติทันทีที่
      toggle SOS/Rescue ผ่าน `_updateLocationBroadcastMode()` (`lib/core/app_state.dart`)
      — ยังไม่ได้วัดผลจริงบนอุปกรณ์ (แนะนำเทียบ battery usage ก่อน/หลังตอนเปิดแอพทิ้งไว้นาน ๆ)
- [x] **GPS stream ซ้อนตัวที่สองในหน้าแชทถูกลบออก** — `StreamBuilder<Position>` ที่เปิด
      `Geolocator.getPositionStream(distanceFilter: 1)` ใหม่ทุกครั้งที่ widget rebuild ถูกแทนที่ด้วยการอ่าน
      `appState.myCurrentPosition` ที่มีอยู่แล้วจาก GPS stream กลางตัวเดียวของ AppState
      (`lib/ui/emergency_chat_screen.dart`)
- [x] **Background service เปิดอัตโนมัติตั้งแต่เริ่ม passive listening (ไม่ต้องรอ SOS/Rescue)** —
      เดิม `startBackgroundService()`/`stopBackgroundService()` มีอยู่แต่ไม่มีอะไรเรียกใช้ (dead code)
      ตอนนี้ `_syncBackgroundServiceWithMode()` ถูกเรียกทั้งตอน `_startPassiveListening()` สำเร็จ และตอน
      toggle SOS/Rescue — เปิด foreground service (wakelock/wifilock) ทันทีที่เริ่ม scan/passive listening
      (ซึ่งปกติเริ่มตั้งแต่เปิดแอพ) เพื่อให้เครื่อง**ยัง discoverable และเป็นตัวกลาง mesh relay ได้แม้ย่อแอพ/ปิดจอ**
      ให้ผู้รอความช่วยเหลือเห็นว่ามีคนอยู่ใกล้ ๆ ตลอด — เป็นการตัดสินใจตั้งใจแลก battery saving บางส่วนจากข้อ GPS
      ด้านบน เพื่อความน่าเชื่อถือของการค้นหา/ถูกค้นหาแทน (`lib/core/app_state.dart`) — เนื่องจาก
      `_isPassiveListening` ไม่เคยถูก reset กลับเป็น false ในโค้ดปัจจุบัน service นี้จะเปิดค้างเกือบตลอดที่แอพทำงาน
      ไม่ได้ปิดเป็นช่วง ๆ เหมือนที่คิดไว้ตอนแรก — การเปิดครั้งแรกจะเด้ง system dialog ขอ ignore battery
      optimization (`_requestPermissions()` ใน `background_service.dart`) ยังไม่ได้ทดสอบจริงบนอุปกรณ์ว่า
      UX ตรงนี้เป็นอย่างไร (ขึ้นตอนไหน, กระทบ first-run experience หรือไม่)
- [x] **Online-status heartbeat ทำงานต่อแม้แอพถูกย่อ/ปิดจอ** — เดิมตอนแอพเข้า background จะ
      set offline + หยุด heartbeat ทันที ตอนนี้เปลี่ยนให้คงสถานะออนไลน์และ heartbeat (ทุก 5 วิ) ทำงานต่อไป
      แม้ปิดหน้าจอ เพื่อให้คนอื่นเห็นว่าผู้ขอความช่วยเหลือยัง "ออนไลน์ รอความช่วยเหลืออยู่" — จะ set offline จริง
      เฉพาะตอน logout หรือแอพถูกปิดจริง (`AppLifecycleState.detached`) เท่านั้น (`lib/core/app_state.dart`)
      — ตอนนี้มี background service ค้ำให้ตั้งแต่ passive listening (ดูรายการด้านบน) ทำให้ heartbeat ทนต่อการ
      ปิดจอได้ดีขึ้นกว่าพึ่ง Dart timer เฉย ๆ — ยังไม่ได้ทดสอบจริงว่าทนอยู่ได้นานแค่ไหนบนอุปกรณ์แต่ละยี่ห้อ/เวอร์ชัน OS
      (โดยเฉพาะ iOS ที่ background execution เข้มงวดกว่า Android มาก)

## Fixed (2026-08-18, chat sync efficiency)

- [x] **เปิดหน้าแชทเพื่อนไม่ดึงประวัติทั้งหมดจาก Firebase ซ้ำทุกครั้งแล้ว** — เดิม
      `loadFriendChatMessages()` เรียก `getFriendChatMessages()` ดึงข้อความ**ทั้งหมด**ของแชทนั้นจาก Firestore
      ทุกครั้งที่เปิดหน้าแชท แล้ว dedup กับ local ทีละข้อความ (เห็น log `⏭️ ข้าม: ข้อความซ้ำ` รัวๆ ตอนแชทมี
      ประวัติเยอะ) ตอนนี้ query Firestore ด้วย `.where('time', isGreaterThan: ...)` filter เอาเฉพาะข้อความ
      ที่ใหม่กว่าข้อความล่าสุดที่มีอยู่ในเครื่องแล้ว (มี buffer 5 วิ กัน clock skew) แทน — ลด Firestore read และ
      เวลาเปิดหน้าแชทลงตามจำนวนประวัติที่มี โดยเฉพาะแชทที่คุยกันมานาน
      (`lib/cloud/firebase_service.dart` เพิ่ม param `since` ให้ `getFriendChatMessages()`,
      `lib/core/app_state.dart` คำนวณ `since` จาก timestamp ล่าสุดของข้อความใน local ก่อน sync)
      — ครั้งแรกที่เปิดแชท (ยังไม่มีข้อความ local) ยังคงดึงประวัติทั้งหมดเหมือนเดิมตามปกติ

## Features / Improvements

- [ ] **Mesh file transfer**
  - `lib/core/mesh_transport.dart:180` — `sendFile()` throws `UnimplementedError`
  - ต้อง chunk ไฟล์ก่อนส่ง + reassemble ที่ปลายทาง

- [ ] **iOS support — WiFi Direct**
  - `lib/core/wifi_direct_transport.dart` ใช้ MethodChannel `wifi_direct` → Android only
  - `android/app/src/main/kotlin/.../WifiDirectChannel.kt` ไม่มี iOS counterpart
  - ตัวเลือก: Multipeer Connectivity หรือ Bonjour-based transport สำหรับ iOS
  - Transport อื่น (Nearby, BLE, Mesh) น่าจะรองรับ iOS ได้แล้ว
