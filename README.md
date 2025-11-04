# 🆘 OffGrid SOS

> **แอปพลิเคชันสื่อสารฉุกเฉินที่ทำงานได้แม้ไม่มีอินเทอร์เน็ต**

แอปพลิเคชัน Flutter สำหรับการสื่อสารในสถานการณ์ฉุกเฉิน รองรับการทำงานแบบออฟไลน์ผ่าน WiFi Direct, Bluetooth และ Firebase Cloud Messaging

## ✨ ฟีเจอร์หลัก

- 🆘 **ระบบแจ้งเหตุฉุกเฉิน (SOS)** - ส่งสัญญาณพร้อมตำแหน่งที่ตั้ง
- 💬 **แชทออฟไลน์** - สื่อสารแบบ P2P ผ่าน WiFi Direct & Bluetooth
- 👥 **ระบบเพื่อน** - เพิ่มเพื่อน ส่งคำขอเป็นเพื่อน
- 📍 **แชร์ตำแหน่งแบบเรียลไทม์** - แสดงบนแผนที่
- 📸 **แชร์รูปภาพ** - ส่งรูปในแชท
- 🔔 **การแจ้งเตือน** - Push notifications ผ่าน Firebase
- 🎨 **UI สไตล์ Neon** - สวยงาม ทันสมัย
- 📱 **ใช้งานได้หลายแพลตฟอร์ม** - Android, iOS, Web

## 🚀 เริ่มต้นใช้งาน

### ความต้องการของระบบ

- Flutter SDK (เวอร์ชันล่าสุด)
- Android Studio / Xcode (สำหรับพัฒนาแอปมือถือ)
- Firebase account และ project

### 📥 ติดตั้ง

```bash
# 1. Clone repository
git clone https://github.com/waratthnai/SOS_APP.git
cd offgrid_sos

# 2. ติดตั้ง dependencies
flutter pub get

# 3. ตั้งค่า Firebase
# - เพิ่ม google-services.json ใน android/app/
# - เพิ่ม GoogleService-Info.plist ใน ios/Runner/

# 4. รันแอป
flutter run
```

## 📁 โครงสร้างโปรเจกต์

```
offgrid_sos/
├── lib/                    # โค้ดหลักของแอป
│   ├── core/              # ฟังก์ชันหลัก, models, services
│   ├── ui/                # หน้าจอต่างๆ
│   ├── widgets/           # Widget ที่ใช้ซ้ำ
│   └── main.dart          # จุดเริ่มต้นของแอป
├── docs/                   # 📚 เอกสารทั้งหมด
├── android/               # โค้ด Android native
├── ios/                   # โค้ด iOS native
└── test/                  # Unit tests

```

## 📚 เอกสาร

เอกสารทั้งหมดถูกจัดเก็บไว้ในโฟลเดอร์ [`docs/`](docs/)

- 📖 [คู่มืออ้างอิงด่วน](docs/QUICK_REFERENCE.md)
- 🎨 [คู่มือธีม Neon](docs/THEME_GUIDE.md)
- 🏗️ [สถาปัตยกรรมระบบ](docs/)
- 📝 [แผนการพัฒนา](docs/PROGRESS_TRACKER.md)

## 🛠️ เทคโนโลยีที่ใช้

- **Frontend**: Flutter (Dart)
- **Backend**: Firebase (Firestore, Cloud Functions, FCM)
- **Offline Communication**: WiFi Direct, Bluetooth
- **Maps**: Google Maps API
- **State Management**: Provider / setState
- **Notifications**: Firebase Cloud Messaging

## 📱 การใช้งาน Git

### อัพเดทโค้ดขึ้น GitHub

```bash
# 1. เพิ่มไฟล์ที่แก้ไข
git add .

# 2. Commit พร้อมข้อความ
git commit -m "คำอธิบายการแก้ไข"

# 3. Push ขึ้น GitHub
git push origin main
```

## 👨‍💻 ผู้พัฒนา

- Waratthnai (waratthnai47)

## 📄 License

This project is for educational purposes.

---

💡 **หมายเหตุ**: โปรเจกต์นี้พัฒนาเพื่อการศึกษา สำหรับวิชา Mobile Application Development
