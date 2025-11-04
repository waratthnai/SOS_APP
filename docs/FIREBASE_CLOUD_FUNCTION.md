# Firebase Cloud Function สำหรับส่ง Push Notification

## วิธีติดตั้ง Cloud Function:

### 1. ติดตั้ง Firebase CLI
```bash
npm install -g firebase-tools
firebase login
```

### 2. Initialize Functions ในโปรเจค
```bash
cd offgrid_sos
firebase init functions
```
เลือก:
- Use existing project → เลือกโปรเจค Firebase ของคุณ
- Language → JavaScript
- ESLint → Yes
- Install dependencies → Yes

### 3. แก้ไขไฟล์ `functions/index.js`:

```javascript
const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

// ฟังก์ชันส่ง FCM notification เมื่อมีข้อความใหม่
exports.sendFriendMessageNotification = functions.firestore
  .document('notifications/{notificationId}')
  .onCreate(async (snap, context) => {
    const data = snap.data();
    
    // ข้อมูลจาก Firestore
    const toToken = data.toToken; // FCM token ของผู้รับ
    const senderName = data.senderName;
    const message = data.message;
    const fromUserId = data.fromUserId;
    const type = data.type || 'friend_message';

    console.log('Sending notification to:', toToken);

    // สร้าง notification payload
    const payload = {
      notification: {
        title: '💬 New Message',
        body: `${senderName}: ${message}`,
      },
      data: {
        type: type,
        fromUserId: fromUserId,
        senderName: senderName,
        message: message,
        clickAction: 'FLUTTER_NOTIFICATION_CLICK',
      },
      token: toToken,
    };

    try {
      // ส่ง FCM
      const response = await admin.messaging().send(payload);
      console.log('Successfully sent message:', response);
      
      // Mark as read
      await snap.ref.update({ sent: true, sentAt: admin.firestore.FieldValue.serverTimestamp() });
      
      return response;
    } catch (error) {
      console.error('Error sending message:', error);
      return null;
    }
  });

// ฟังก์ชันส่ง SOS notification
exports.sendSOSNotification = functions.firestore
  .document('sos_alerts/{alertId}')
  .onCreate(async (snap, context) => {
    const data = snap.data();
    
    // ดึง tokens ของ friends ทั้งหมด
    const userId = data.userId;
    const userDoc = await admin.firestore().collection('users').doc(userId).get();
    const userData = userDoc.data();
    
    // ส่ง notification ไปยัง friends (ต้องมี logic ดึง friends' tokens)
    // ... Implementation here
    
    return null;
  });
```

### 4. Deploy Cloud Function:
```bash
firebase deploy --only functions
```

### 5. ตรวจสอบใน Firebase Console:
- ไปที่ Firebase Console → Functions
- ตรวจสอบว่า function deploy สำเร็จ
- ดู logs ได้ที่ Functions → Logs

## การทดสอบ:

1. Login ในทั้งสองเครื่อง
2. เพิ่มเป็นเพื่อนกัน
3. **ปิด Bluetooth** (เพื่อทดสอบ FCM เพียงอย่างเดียว)
4. ส่งข้อความจากเครื่องหนึ่ง
5. เครื่องที่สองควรได้รับ Push Notification ผ่านอินเทอร์เน็ต

## การทดสอบ Hybrid Mode:

1. **เปิด Bluetooth + มีอินเทอร์เน็ต**
2. ส่งข้อความ
3. ควรได้รับข้อความผ่าน:
   - ✅ Bluetooth/WiFi Direct (P2P)
   - ✅ Firebase Cloud Messaging (FCM)
   - ✅ Firestore (บันทึกข้อความ)

## หมายเหตุ:

- Cloud Function จะ auto-scale ตามจำนวนผู้ใช้
- Free tier มี limits: 125K invocations/month
- ข้อความจะถูกส่งผ่าน FCM แม้แอพปิดอยู่
- Notification จะปรากฏใน notification tray ของ Android
