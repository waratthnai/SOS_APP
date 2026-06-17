# 📡 คู่มือการทำงานของ Mesh Protocol

## 🎯 ภาพรวมการทำงาน

Mesh Protocol ถูกออกแบบมาให้อุปกรณ์สามารถสื่อสารกันได้แม้จะอยู่ห่างเกินระยะการเชื่อมต่อโดยตรง โดยใช้อุปกรณ์ตัวกลางเป็น "สะพาน" ในการส่งต่อข้อความ

### ตัวอย่างการทำงาน:
```
[A] ←── 10m ──→ [B] ←── 10m ──→ [C]
        ✅           ✅
        
[A] ←────── 25m (ไกลเกินไป) ──────→ [C]
                    ❌

แต่ A และ C สามารถสื่อสารกันได้ผ่าน B:
[A] → [B] → [C] ✅ (Multi-hop)
```

---

## 🔄 วงจรการทำงาน

### 1. การค้นหาอุปกรณ์ (Device Discovery)

เมื่อเปิดใช้งาน Mesh Protocol:

- **ทุก 20 วินาที**: ทำ periodic scan เพื่อค้นหาอุปกรณ์ใหม่
- **ทุก 30 วินาที**: ส่ง HELLO message เพื่อแจ้งตำแหน่งและขอข้อมูล peer list

```
Timeline:
0s   → เริ่ม scan, ส่ง HELLO ครั้งแรก
20s  → Periodic scan #1
30s  → ส่ง HELLO + ขอ peer list
40s  → Periodic scan #2
60s  → ส่ง HELLO + ขอ peer list
...
```

### 2. การแลกเปลี่ยนข้อมูล Peer List

#### กระบวนการ:

1. **A ส่ง `PEER_LIST_REQUEST`** → broadcast ไปยังทุกเครื่องที่เชื่อมต่ออยู่
2. **B รับ request และตอบกลับ** → ส่ง `PEER_LIST_RESPONSE` พร้อมรายชื่ออุปกรณ์ที่ B เชื่อมต่ออยู่
3. **A รับ response** → อัปเดต routing table ด้วย peers ใหม่จาก B

```
Scenario: A และ C ไม่เจอกัน แต่ B เจอทั้ง A และ C

[A] ส่ง PEER_LIST_REQUEST
    ↓
[B] ตอบ: "ฉันเชื่อมต่อกับ A, C"
    ↓
[A] อัปเดต: "C อยู่ผ่าน B (mesh)"
    ↓
[A] แสดง C ในรายชื่อพร้อม badge "📡 mesh"
```

---

## 📊 Routing Table

Routing table เก็บข้อมูลเส้นทางไปยังแต่ละอุปกรณ์:

| Peer ID | Next Hop | ประเภท |
|---------|----------|--------|
| B       | B        | Direct (เชื่อมตรง) |
| C       | B        | Mesh (ผ่าน B) |
| D       | C        | Mesh (ผ่าน C) |

### การอัปเดต Routing Table:

1. **Direct Connection**: เมื่อ scan เจออุปกรณ์ → `next_hop = peer_id` (เชื่อมตรง)
2. **Mesh Discovery**: เมื่อได้รับ PEER_LIST_RESPONSE → `next_hop = ผู้ส่ง response` (mesh)

---

## 💬 การส่งข้อความ

### Direct Message (เชื่อมตรง):
```dart
// A ส่งถึง B (direct peer)
A → B: "สวัสดี" (ไม่มี MESH: protocol)
```

### Mesh Message (ผ่านตัวกลาง):
```dart
// A ส่งถึง C ผ่าน B
A → B: "MESH:msgId:A:C:5:DIRECT:สวัสดี"
B → C: "MESH:msgId:A:C:4:B:สวัสดี" (forward)
```

### Format ของ Mesh Message:
```
MESH:{id}:{from}:{to}:{ttl}:{hops}:{body}

- id: unique message ID
- from: ผู้ส่งต้นทาง
- to: ผู้รับปลายทาง (ALL = broadcast)
- ttl: Time To Live (จำกัด 5 hops)
- hops: รายชื่อเครื่องที่ผ่าน (DIRECT หรือ B,C,D)
- body: เนื้อหาข้อความ
```

---

## 🏷️ การแสดงผลใน UI

### Badge สำหรับ Peers:

- **ไม่มี badge** → Direct connection (เชื่อมตรงกับเรา)
  ```
  📱 Alice
  📡 150m
  ```

- **มี badge "📡 mesh"** → Mesh connection (เชื่อมผ่านเครื่องอื่น)
  ```
  📱 Charlie (📡 mesh)
  📡 150m (ผ่าน Bob)
  ```

### การกรอง Duplicate Peers:

ถ้าเจออุปกรณ์เดียวกันทั้งแบบ direct และ mesh:
- **เลือก direct** → แสดงแค่ 1 รายการ (ไม่มี badge)
- **เหตุผล**: Direct connection ดีกว่า mesh (latency ต่ำกว่า)

---

## 🔐 ความปลอดภัย

### ป้องกัน Message Loop:

1. **Message History**: บันทึก message ID ที่เคยได้รับ → ไม่ forward ซ้ำ
2. **TTL (Time To Live)**: ลดลง 1 ทุกครั้งที่ forward → เมื่อถึง 0 จะหยุด
3. **Self-Detection**: ไม่ process message ที่ส่งมาจากตัวเอง

### ตัวอย่าง Loop Prevention:
```
[A] → [B] → [C] → [A] ❌ (A เคยเห็น message นี้แล้ว)

หรือ

[A] → [B] → [C] → [D] → [E] → [F] ❌ (TTL = 0)
```

---

## 📋 Control Messages

| Message | TTL | คำอธิบาย |
|---------|-----|----------|
| `HELLO:{name}` | 3 | แจ้งตำแหน่งและชื่ออุปกรณ์ |
| `PEER_LIST_REQUEST` | 1 | ขอรายชื่อ peers จากเพื่อนบ้าน |
| `PEER_LIST_RESPONSE:{data}` | 3 | ส่งรายชื่อ peers กลับไป |

### Format ของ PEER_LIST_RESPONSE:
```
PEER_LIST_RESPONSE:peerA|Alice|1,peerB|Bob|0

- peerA|Alice|1: ID = peerA, ชื่อ = Alice, isDirect = 1 (ใช่)
- peerB|Bob|0: ID = peerB, ชื่อ = Bob, isDirect = 0 (ไม่ใช่)
```

---

## 🧪 วิธีทดสอบ

### ทดสอบพื้นฐาน (2 เครื่อง):
1. เปิดแอพใน 2 เครื่อง (A, B)
2. เลือก "Radio Mesh" protocol
3. กด Scan ทั้ง 2 เครื่อง
4. ✅ ควรเห็นกันและกัน (ไม่มี badge mesh)

### ทดสอบ Multi-Hop (3 เครื่อง):

**Scenario 1: เรียงตรง**
```
[A] ←─ 5m ─→ [B] ←─ 5m ─→ [C]
```

1. เปิดแอพทั้ง 3 เครื่อง
2. เลือก "Radio Mesh" protocol
3. กด Scan ทุกเครื่อง
4. รอ 30-40 วินาที (ให้ peer list ถูกแลกเปลี่ยน)
5. ✅ A ควรเห็น:
   - B (ไม่มี badge) ← direct
   - C (📡 mesh) ← ผ่าน B

**Scenario 2: เดินห่างให้ A ไม่เจอ C**
```
[A] ←─ 20m ─→ [B] ←─ 20m ─→ [C]
       ✅              ✅
[A] ←──────── 40m ────────→ [C]
              ❌
```

1. จัดวางเครื่องตามรูป
2. ทดสอบส่งข้อความจาก A → C
3. ✅ C ควรได้รับ (ผ่าน B)
4. ตรวจสอบ log ว่ามี `Forwarding message` ที่เครื่อง B

---

## 📝 Logs สำคัญ

### สำเร็จ:
```
✅ Emitted X unique peers (from Y routes)
✅ Discovered new mesh peer: Charlie via Bob
✅ Forwarding message to app: สวัสดี
📡 [MESH] Sent PEER_LIST_RESPONSE with 2 peers
```

### ผิดพลาด:
```
❌ No route to C - broadcasting instead
❌ Duplicate message {id} - ignored
❌ Error processing message: ...
```

### ตรวจสอบ Routing Table:
```
📡 [MESH] Routes: 3, emitting peers...
📡 [MESH]   Route: B → B (direct)
📡 [MESH]   Route: C → B (mesh via B)
📡 [MESH]   Route: D → C (mesh via C)
```

---

## ⚙️ การตั้งค่า

### ค่า Timing:
```dart
Periodic Scan:     ทุก 20 วินาที  // ค้นหาอุปกรณ์ใหม่
HELLO Broadcast:   ทุก 30 วินาที  // แจ้งตำแหน่งและขอ peer list
Message Cleanup:   ทุก 5 นาที     // ลบ message เก่าออก
Message Expiry:    30 นาที        // เวลาเก็บ message history
```

### ค่า Message:
```dart
Max TTL:           5 hops         // จำกัดการ forward
Max Hops:          unlimited      // แต่ถูกจำกัดด้วย TTL
```

---

## 🔧 Troubleshooting

### ปัญหา: ไม่เห็น mesh peers
- ✅ รอ 30-40 วินาที ให้ PEER_LIST แลกเปลี่ยนกัน
- ✅ ตรวจสอบ log ว่ามี `PEER_LIST_RESPONSE`
- ✅ ตรวจสอบว่า B เชื่อมต่อกับทั้ง A และ C

### ปัญหา: ส่งข้อความไม่ถึง
- ✅ ตรวจสอบ routing table ที่เครื่องต้นทาง
- ✅ ดู log ที่เครื่องกลางว่ามี `Forwarding message`
- ✅ เช็ค TTL ว่ายังไม่หมด (> 0)

### ปัญหา: แสดง peer ซ้ำ
- ✅ ระบบจะกรอง duplicate ตามชื่อโดยอัตโนมัติ
- ✅ เลือก direct connection มากกว่า mesh

---

## 📌 สรุป

Mesh Protocol ช่วยให้:
- ✅ อุปกรณ์สื่อสารกันได้ไกลกว่าระยะ Bluetooth/WiFi ธรรมดา
- ✅ เครือข่ายขยายตัวอัตโนมัติเมื่อมีอุปกรณ์ใหม่เข้ามา
- ✅ ทำงานได้แม้อุปกรณ์บางตัวหลุดการเชื่อมต่อ (self-healing)
- ✅ แสดงผลใน UI ชัดเจนว่าเป็น direct หรือ mesh connection

**สำคัญ**: Mesh จะค้นหาและอัปเดต peer list อยู่ตลอดเวลาโดยอัตโนมัติ ✨
