# 📊 สรุประบบแชทและเพื่อน - OffGrid SOS

## ✅ สิ่งที่แก้ไขและปรับปรุงแล้ว

### 1. 🔐 ระบบ User ID แบบไม่ซ้ำกัน
- ✅ เปลี่ยนจากระบบเก่า (5 หลัก ซ้ำได้ง่าย) → UUID-based (ไม่ซ้ำ 100%)
- ✅ รูปแบบ: `USER_a1b2c3d4_5678` (18 ตัวอักษร)
- ✅ ปุ่ม Copy User ID ในหน้า Settings และ Add Friend
- ✅ แต่ละ User มี ID เป็นของตัวเอง ไม่ซ้ำกันแม้จะ Logout/Login

### 2. 💬 ระบบแชทแบบแยกตาม User
- ✅ Database เพิ่ม field `user_id` และ `receiver`
- ✅ แต่ละ User เห็นเฉพาะแชทของตัวเอง
- ✅ แชทแยกตามห้อง (peer-to-peer)
- ✅ Friend chat แยกต่างหากจาก General chat

### 3. 🚪 ระบบ Login/Logout
- ✅ **ตอน Login:** โหลดข้อมูลแชทและเพื่อนของ user นั้น
- ✅ **ตอน Logout:** 
  - ลบข้อมูลแชททั้งหมด
  - ลบข้อมูลเพื่อนทั้งหมด
  - ลบ User ID
  - ซ่อนส่วน "โปรไฟล์ผู้ใช้" ในหน้า Settings

### 4. 👥 ระบบเพื่อน (Friend System)
- ✅ ค้นหาเพื่อนด้วยชื่อหรือ User ID
- ✅ ส่งคำขอเป็นเพื่อน
- ✅ ยอมรับ/ปฏิเสธคำขอ
- ✅ แชทกับเพื่อน (แยกห้องแชทต่อคน)
- ✅ แสดงข้อความล่าสุดและจำนวนข้อความที่ยังไม่อ่าน

### 5. 🎨 UI/UX
- ✅ SOS button ย้ายไปกลาง Navigation Bar
- ✅ สีธีม Navy Blue สม่ำเสมอทุกหน้า
- ✅ Notification Panel ทำงานจริง (ไม่มี sample notifications)
- ✅ Device naming สำหรับ Nearby Connections
- ✅ Chat buttons สำหรับ discovered devices

---

## 📁 โครงสร้างข้อมูล

### ChatDB (SQLite)
```sql
CREATE TABLE chat_messages (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,        -- เจ้าของแชท
  sender TEXT NOT NULL,          -- ผู้ส่ง
  receiver TEXT,                 -- ผู้รับ (สำหรับห้องแชท)
  type TEXT NOT NULL,
  text TEXT,
  filePath TEXT,
  time INTEGER NOT NULL
)
```

### FriendDB (SharedPreferences)
- `current_user` - ข้อมูล User ปัจจุบัน
- `friends` - รายชื่อเพื่อนทั้งหมด
- `friend_requests` - คำขอเป็นเพื่อนที่รอดำเนินการ
- `friend_chats_{userId}` - แชทกับเพื่อนแต่ละคน

---

## 🔄 Data Flow

### Login Flow
```
1. User Login (Firebase Auth)
2. friendService.init()
   - โหลด current user หรือสร้างใหม่ (User ID ใหม่)
   - โหลดรายชื่อเพื่อน
   - โหลด friend requests
3. appState.onUserLogin()
   - โหลดข้อความแชททั่วไป
   - Sync กับ Firebase
```

### Logout Flow
```
1. appState.logout()
   - ลบข้อความทั้งหมดของ user จาก ChatDB
   - ล้าง _chatMessages, _friendChats, _messages, _peers
   - เรียก FriendDB.clearAllData()
2. firebaseService.signOut()
3. UI Update
   - ซ่อนส่วน "โปรไฟล์ผู้ใช้"
   - แสดงฟอร์ม Login
```

### Send Message Flow
```
1. user ส่งข้อความ
2. สร้าง ChatMessage object
3. เพิ่มใน _chatMessages (in-memory)
4. ChatDB.insertMessage(msg, userId, receiver)
5. transport.sendMessage() ผ่าน Nearby/BLE/WiFi
6. firebaseService.saveChatMessage() (ถ้า online)
7. notifyListeners()
```

### Add Friend Flow
```
1. ค้นหาเพื่อนด้วยชื่อหรือ User ID
2. friendService.searchUsers(query)
   - ค้นหาจาก Firebase
3. กดปุ่ม Add Friend
4. friendService.sendFriendRequest()
   - บันทึก request ใน Firebase
   - เพื่อนได้รับการแจ้งเตือน
5. เพื่อนยอมรับ/ปฏิเสธ
6. ถ้ายอมรับ → เพิ่มใน friends list ของทั้งสองฝ่าย
```

---

## 🔧 API หลักๆ

### AppState
```dart
// User Management
Future<void> onUserLogin()
Future<void> logout()

// Chat Management
void sendChatText(String text, {String? receiverId})
Future<List<ChatMessage>> getChatConversation(String peerId)
void addChatImage(String path)
void addChatVideo(String path)

// Friend Chat Management
Future<void> sendFriendChatMessage(String friendUserId, String text)
Future<void> loadFriendChatMessages(String friendUserId)
Future<void> markFriendMessagesAsRead(String friendUserId)
```

### FriendService
```dart
// Friend Operations
Future<List<UserProfile>> searchUsers(String query)
Future<void> sendFriendRequest(UserProfile targetUser)
Future<void> acceptFriendRequest(FriendRequest request)
Future<void> rejectFriendRequest(String requestId)
Future<void> removeFriend(String friendUserId)

// User Profile
UserProfile? get currentUser
Future<void> updateProfile(...)
```

### ChatDB
```dart
// Database Operations
static Future<void> insertMessage(ChatMessage msg, String userId, {String? receiver})
static Future<List<ChatMessage>> getMessages(String userId)
static Future<List<ChatMessage>> getConversation(String userId, String peerId)
static Future<void> clearUserMessages(String userId)
```

---

## 🧪 การทดสอบ

### Test Case 1: User ID ไม่ซ้ำกัน
1. เครื่อง A: Login → คัดลอก User ID
2. เครื่อง A: Logout
3. เครื่อง A: Login ใหม่ → คัดลอก User ID ใหม่
4. ✅ ยืนยัน: User ID ทั้งสองต่างกัน

### Test Case 2: แชทแยกตาม User
1. เครื่อง A: Login เป็น User A → ส่งแชท "Hello from A"
2. เครื่อง A: Logout
3. เครื่อง A: Login เป็น User B → ตรวจสอบแชท
4. ✅ ยืนยัน: User B ไม่เห็นแชทของ User A

### Test Case 3: เพิ่มเพื่อนด้วย User ID
1. เครื่อง A: Login → คัดลอก User ID
2. เครื่อง B: Login → Add Friend → วาง User ID ของ A → Search
3. เครื่อง B: กด Add Friend
4. เครื่อง A: ยอมรับคำขอ
5. ✅ ยืนยัน: ทั้งสองเป็นเพื่อนกัน สามารถแชทได้

### Test Case 4: แชทกับเพื่อน
1. เครื่อง A และ B เป็นเพื่อนกัน
2. เครื่อง A: ส่งข้อความหา B
3. เครื่อง B: ตรวจสอบแชท
4. ✅ ยืนยัน: B เห็นข้อความจาก A และสามารถตอบกลับได้

### Test Case 5: Logout ล้างข้อมูล
1. User A มีเพื่อน 3 คน และมีแชท
2. Logout
3. Login เป็น User B
4. ✅ ยืนยัน: 
   - User B มี User ID ใหม่
   - ไม่มีเพื่อนคนเดิมของ User A
   - ไม่มีแชทคนเดิมของ User A

---

## 📝 ข้อควรระวัง

1. **Firebase Sync** - ข้อมูลแชทจะ sync กับ Firebase เมื่อมีอินเทอร์เน็ต
2. **Offline Mode** - สามารถแชทได้แม้ไม่มีเน็ต (ผ่าน Nearby/BLE)
3. **User ID** - เก็บไว้ดี ไม่สามารถเปลี่ยนได้ (ต้อง Logout/Login ใหม่)
4. **Database Migration** - ChatDB จะ auto upgrade จาก v1 → v2
5. **Friend Data** - เก็บใน SharedPreferences (Local)

---

## 🐛 Known Issues / TODO

- [ ] ระบบ block/unblock friends
- [ ] Group chat
- [ ] แชทส่งรูป/วิดีโอให้เพื่อน
- [ ] การแจ้งเตือน push notification
- [ ] Online/Offline status real-time
- [ ] Message encryption

---

## 📚 เอกสารเพิ่มเติม

- [HOW_TO_ADD_FRIENDS.md](HOW_TO_ADD_FRIENDS.md) - คู่มือการเพิ่มเพื่อน
- [WEEK4_FEATURES.md](WEEK4_FEATURES.md) - Features Week 4
- [WEEK5_POLISH.md](WEEK5_POLISH.md) - Polish & Testing

---

**อัพเดทล่าสุด:** 20 ตุลาคม 2025  
**Version:** 2.0.0 (Chat System Refactoring)
