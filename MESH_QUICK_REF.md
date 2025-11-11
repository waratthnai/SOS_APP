# 🎯 Mesh Protocol - Quick Reference

## การทำงานแบบง่าย ๆ

### สถานการณ์: A, B, C

```
[Alice] ←─── 10m ───→ [Bob] ←─── 10m ───→ [Charlie]
           ✅                   ✅

[Alice] ←──────── 25m (ไกลเกินไป) ────────→ [Charlie]
                        ❌
```

### สิ่งที่เกิดขึ้น:

**T = 0s - เริ่มต้น:**
```
Alice เห็น:    Bob ✅
Bob เห็น:      Alice ✅, Charlie ✅  
Charlie เห็น:  Bob ✅
```

**T = 30s - หลัง Peer Exchange:**
```
Alice เห็น:    Bob ✅, Charlie (📡 mesh) ✅
Bob เห็น:      Alice ✅, Charlie ✅
Charlie เห็น:  Bob ✅, Alice (📡 mesh) ✅
```

### Alice ส่งข้อความถึง Charlie:

1. Alice ส่งไปหา Bob (เพราะ routing table บอกว่า Charlie อยู่ผ่าน Bob)
2. Bob รับข้อความ แล้ว forward ต่อให้ Charlie
3. Charlie ได้รับข้อความ ✅

---

## ⏱️ Timeline อัตโนมัติ

```
ทุก 20 วินาที  → ค้นหาอุปกรณ์ใหม่
ทุก 30 วินาที  → ขอรายชื่อเพื่อนจากเพื่อนบ้าน
```

### ตัวอย่าง:

```
0s:   Scan → เจอ Bob
20s:  Scan → เจอ Bob (ยังคงอยู่)
30s:  ถาม Bob: "นายเชื่อมต่อกับใครบ้าง?"
      Bob ตอบ: "Alice, Charlie"
      → เพิ่ม Charlie (mesh) ใน peer list ✅
40s:  Scan → เจอ Bob
60s:  ถาม Bob อีกครั้ง (อาจมีคนใหม่)
```

---

## 📱 การแสดงผล

### Peer List:

```
📱 Bob          ← เชื่อมตรง (ไม่มี badge)
📡 150m

📱 Charlie (📡 mesh)  ← เชื่อมผ่าน Bob
📡 150m
```

### กฏการแสดง Badge:

- **ไม่มี badge** = เราเชื่อมตรงกับเครื่องนี้
- **มี 📡 mesh** = เชื่อมผ่านเครื่องอื่น

---

## ✅ เช็คว่าทำงานถูกต้อง

### Log ที่ควรเห็น:

```
📡 [MESH] Periodic scan: refreshing device discovery...
📡 [MESH] Requesting peer lists from neighbors
📡 [MESH] ✅ Discovered new mesh peer: Charlie via Bob
📡 [MESH] ✅ Emitted 2 unique peers
  📱 Bob (direct)
  📱 Charlie (mesh)
```

### การทดสอบ:

1. เปิด 3 เครื่อง (A, B, C)
2. จัดวางให้ A ไม่เจอ C
3. เลือก Radio Mesh ทุกเครื่อง
4. รอ 40 วินาที
5. ✅ A ควรเห็น C พร้อม badge mesh
6. ส่งข้อความจาก A → C
7. ✅ C ควรได้รับ

---

## 🔧 ปัญหาที่พบบ่อย

### Q: ไม่เห็น mesh peers
**A**: รอ 30-40 วินาที ให้ peer list แลกเปลี่ยนกัน

### Q: ส่งข้อความไม่ถึง
**A**: ตรวจสอบว่า B (เครื่องกลาง) เชื่อมต่อกับทั้ง A และ C

### Q: เห็น peer ซ้ำ
**A**: ระบบจะกรองอัตโนมัติ (เลือก direct มากกว่า mesh)

---

## 💡 ทำความเข้าใจง่าย ๆ

Mesh Protocol = **ส่งต่อข้อความผ่านเพื่อน**

- เหมือนบอกให้เพื่อนช่วยส่งข้อความต่อ
- เครื่องกลางทำหน้าที่เป็น "สะพาน"
- ระบบจัดการเส้นทางให้อัตโนมัติ

**สำคัญ**: ไม่ต้องทำอะไร มันจะจัดการเองหมด! 🎉
