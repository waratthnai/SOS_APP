# 🎨 Off-Grid SOS Theme System

## ภาพรวม
ระบบธีมที่ออกแบบมาเพื่อความสวยงาม สอดคล้อง และใช้งานง่าย รองรับทั้ง Light และ Dark Mode

## หลักการออกแบบ

### 1. สีหลัก (Primary Colors)
- **Emergency Red** (#E53935) - สีแดงเข้ม สำหรับฟังก์ชันหลักและ Emergency
- **SOS Orange** (#FF6F00) - สีส้ม สำหรับปุ่ม SOS และการเตือน
- **Info Blue** (#1976D2) - สีน้ำเงิน สำหรับข้อมูลและลิงก์
- **Success Green** (#43A047) - สีเขียว สำหรับสถานะสำเร็จ

### 2. สีพื้นหลัง
**Light Mode:**
- Background: #F5F5F5 (เทาอ่อนมาก)
- Surface: #FFFFFF (ขาว)
- Surface Variant: #F0F0F0 (เทาอ่อน)

**Dark Mode:**
- Background: #121212 (ดำเข้ม)
- Surface: #1E1E1E (เทาดำ)
- Surface Variant: #2C2C2C (เทาดำอ่อน)

### 3. Typography (ขนาดและน้ำหนักตัวอักษร)

| Type | Size | Weight | Use Case |
|------|------|--------|----------|
| Display Large | 32px | Bold | หัวข้อใหญ่มาก |
| Display Medium | 28px | Bold | หัวข้อใหญ่ |
| Display Small | 24px | Bold | หัวข้อปานกลาง |
| Headline Large | 22px | Semi-bold | หัวข้อส่วน |
| Headline Medium | 20px | Semi-bold | หัวข้อย่อย |
| Headline Small | 18px | Semi-bold | หัวข้อเล็ก |
| Title Large | 18px | Medium | ชื่อการ์ด |
| Title Medium | 16px | Medium | ชื่อรายการ |
| Title Small | 14px | Medium | ชื่อเล็ก |
| Body Large | 16px | Normal | ข้อความหลัก |
| Body Medium | 14px | Normal | ข้อความธรรมดา |
| Body Small | 12px | Normal | ข้อความเสริม |
| Label Large | 14px | Medium | ป้ายกำกับ |
| Label Medium | 12px | Medium | ป้ายกำกับเล็ก |
| Label Small | 11px | Medium | ป้ายกำกับเล็กมาก |

## การใช้งาน

### 1. ใช้สีจากธีม
```dart
// ✅ ดี - ใช้สีจาก Theme
final color = Theme.of(context).colorScheme.primary;
final textColor = Theme.of(context).colorScheme.onSurface;
final bgColor = Theme.of(context).colorScheme.surface;

// ❌ ไม่ดี - Hard-code สี
final color = Colors.red;
final textColor = Colors.black;
```

### 2. ใช้ Typography จากธีม
```dart
// ✅ ดี - ใช้ text style จาก Theme
Text(
  'หัวข้อ',
  style: Theme.of(context).textTheme.headlineMedium,
)

Text(
  'ข้อความ',
  style: Theme.of(context).textTheme.bodyMedium,
)

// ❌ ไม่ดี - Hard-code font size
Text(
  'หัวข้อ',
  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
)
```

### 3. ใช้ Card และ Container
```dart
// ✅ ดี - ใช้ Card จาก Theme
Card(
  child: Padding(
    padding: EdgeInsets.all(16),
    child: Text('เนื้อหา'),
  ),
)

// ✅ ดี - Container พร้อม decoration
Container(
  decoration: BoxDecoration(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(
      color: Theme.of(context).colorScheme.outline,
    ),
  ),
  child: Text('เนื้อหา'),
)
```

### 4. ใช้ปุ่มตามมาตรฐาน
```dart
// Primary Action - ใช้ ElevatedButton
ElevatedButton(
  onPressed: () {},
  child: Text('ยืนยัน'),
)

// Secondary Action - ใช้ OutlinedButton
OutlinedButton(
  onPressed: () {},
  child: Text('ยกเลิก'),
)

// Tertiary Action - ใช้ TextButton
TextButton(
  onPressed: () {},
  child: Text('ข้าม'),
)
```

### 5. สี Alert และ Status
```dart
// Emergency/Error
Container(
  color: Theme.of(context).colorScheme.error,
  child: Text(
    'ข้อผิดพลาด',
    style: TextStyle(
      color: Theme.of(context).colorScheme.onError,
    ),
  ),
)

// Warning - ใช้ secondary (orange)
Container(
  color: Theme.of(context).colorScheme.secondary,
  child: Text(
    'คำเตือน',
    style: TextStyle(
      color: Theme.of(context).colorScheme.onSecondary,
    ),
  ),
)

// Success - ใช้ custom color
Container(
  color: AppTheme.successGreen,
  child: Text(
    'สำเร็จ',
    style: TextStyle(color: Colors.white),
  ),
)
```

## Component Guidelines

### AppBar
```dart
AppBar(
  title: Text('ชื่อหน้า'),
  // ไม่ต้องกำหนดสี จะใช้จาก theme อัตโนมัติ
)
```

### Bottom Navigation
```dart
NavigationBar(
  selectedIndex: _index,
  onDestinationSelected: (i) => setState(() => _index = i),
  destinations: [
    NavigationDestination(
      icon: Icon(Icons.home),
      label: 'หน้าหลัก',
    ),
  ],
)
```

### TextField
```dart
TextField(
  decoration: InputDecoration(
    labelText: 'ชื่อ',
    hintText: 'กรอกชื่อของคุณ',
    // ไม่ต้องกำหนด decoration อื่น จะใช้จาก theme
  ),
)
```

### Dialog
```dart
showDialog(
  context: context,
  builder: (context) => AlertDialog(
    title: Text('ยืนยัน'),
    content: Text('คุณต้องการดำเนินการหรือไม่?'),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text('ยกเลิก'),
      ),
      ElevatedButton(
        onPressed: () => Navigator.pop(context),
        child: Text('ยืนยัน'),
      ),
    ],
  ),
)
```

### SnackBar
```dart
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text('บันทึกสำเร็จ'),
    action: SnackBarAction(
      label: 'เลิกทำ',
      onPressed: () {},
    ),
  ),
)
```

## Spacing & Sizing

### Standard Padding/Margin
- Extra Small: 4px
- Small: 8px
- Medium: 12px
- Standard: 16px
- Large: 24px
- Extra Large: 32px

### Border Radius
- Small: 8px
- Standard: 12px
- Large: 16px
- Extra Large: 20px
- Circle: 999px

### Elevation
- Flat: 0
- Low: 1-2
- Medium: 4-6
- High: 8-12

## Best Practices

### ✅ DO
- ใช้ Theme.of(context) เสมอ
- ใช้ colorScheme แทนการ hard-code สี
- ใช้ textTheme สำหรับ typography
- รักษา spacing ให้สม่ำเสมอ (8px, 16px, 24px)
- ใช้ border radius ที่กลมกลืน (8px, 12px, 16px)
- เว้นระยะให้พอดี ไม่แน่นเกินไป

### ❌ DON'T
- Hard-code สี (Colors.red, Color(0xFF...))
- Hard-code font size/weight
- ใช้ elevation สูงเกินไป (>12)
- ใช้สีฉูดฉาด
- ทำให้หน้าจอรกเกินไป
- ใช้ spacing ที่ไม่สม่ำเสมอ

## Migration Guide

### แปลงโค้ดเก่าเป็นใช้ธีมใหม่

**Before:**
```dart
Container(
  color: Colors.white,
  child: Text(
    'ข้อความ',
    style: TextStyle(
      fontSize: 16,
      color: Colors.black,
      fontWeight: FontWeight.bold,
    ),
  ),
)
```

**After:**
```dart
Container(
  color: Theme.of(context).colorScheme.surface,
  child: Text(
    'ข้อความ',
    style: Theme.of(context).textTheme.titleMedium,
  ),
)
```

## สรุป

ระบบธีมนี้ออกแบบมาเพื่อ:
1. **ความสวยงาม** - สีสันและ typography ที่เหมาะสม
2. **ความสอดคล้อง** - ทุกหน้าใช้ธีมเดียวกัน
3. **ใช้งานง่าย** - เขียนโค้ดน้อยลง
4. **Responsive** - รองรับทั้ง Light/Dark mode
5. **มืออาชีพ** - ดูดีมีมิติ ไม่รก

---

**Created:** 2025-10-27
**Version:** 1.0
**Status:** Production Ready ✅
