# 🚨 Feature #3: SOS Status Broadcast

## 🎯 เป้าหมาย
เมื่อผู้ใช้กดปุ่ม SOS → ส่งสัญญาณฉุกเฉินไปยัง peers ทั้งหมด พร้อมแสดงตำแหน่ง GPS

---

## 📋 สิ่งที่ต้องทำ

### 1. **Backend (AppState)**
- [ ] เพิ่ม `bool _isSOSActive` flag
- [ ] เพิ่ม `GPSLocation? _currentSOSLocation` 
- [ ] Method `activateSOS()` - เปิดโหมด SOS + ส่ง broadcast
- [ ] Method `deactivateSOS()` - ปิดโหมด SOS
- [ ] Broadcast: `"SOS_STATUS:deviceName:active:lat:lng"`
- [ ] Receive SOS status จาก peers
- [ ] เก็บ `Map<String, SOSPeer>` - peers ที่กด SOS
- [ ] แสดง notification เมื่อมี SOS ใกล้เคียง

### 2. **GPS Location**
- [ ] เพิ่ม dependency: `geolocator: ^10.1.0`
- [ ] Request location permission
- [ ] Get current location
- [ ] ส่ง lat, lng พร้อม SOS broadcast

### 3. **UI - HomeScreen**
- [ ] ปุ่ม SOS ใหญ่ กลางหน้าจอ
- [ ] สีแดง + animation เมื่อกด
- [ ] Confirmation dialog ก่อนเปิด SOS
- [ ] แสดง badge แดง 🔴 ใน peer list (SOS peers)
- [ ] แสดงระยะทาง + ตำแหน่ง (ถ้ามี GPS)

### 4. **Notification**
- [ ] แจ้งเตือนเมื่อมี SOS broadcast ใกล้เคียง
- [ ] Quick action: "แชทเลย" → เปิด EmergencyChatScreen
- [ ] แสดงชื่อ + ตำแหน่ง

---

## 🔧 Implementation Plan

### Step 1: เพิ่ม GPS Location
```dart
// pubspec.yaml
dependencies:
  geolocator: ^10.1.0

// lib/core/app_state.dart
class SOSLocation {
  final double latitude;
  final double longitude;
  final DateTime time;
}

Future<SOSLocation?> _getCurrentLocation() async {
  try {
    LocationPermission permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) return null;
    
    Position position = await Geolocator.getCurrentPosition();
    return SOSLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      time: DateTime.now(),
    );
  } catch (e) {
    return null;
  }
}
```

### Step 2: SOS State Management
```dart
class AppState {
  bool _isSOSActive = false;
  bool get isSOSActive => _isSOSActive;
  
  SOSLocation? _sosLocation;
  SOSLocation? get sosLocation => _sosLocation;
  
  Map<String, SOSPeer> _sosPeers = {};
  
  Future<void> activateSOS() async {
    _isSOSActive = true;
    _sosLocation = await _getCurrentLocation();
    
    // Broadcast SOS
    final lat = _sosLocation?.latitude ?? 0.0;
    final lng = _sosLocation?.longitude ?? 0.0;
    final message = 'SOS_STATUS:$_deviceName:active:$lat:$lng';
    await transport.sendMessage(message);
    
    notifyListeners();
  }
  
  Future<void> deactivateSOS() async {
    _isSOSActive = false;
    
    // Broadcast SOS OFF
    await transport.sendMessage('SOS_STATUS:$_deviceName:inactive:0:0');
    
    notifyListeners();
  }
  
  void _handleSOSStatus(String message, String fromPeerId) {
    // Parse: "SOS_STATUS:deviceName:active/inactive:lat:lng"
    final parts = message.split(':');
    if (parts.length >= 5) {
      final deviceName = parts[1];
      final isActive = parts[2] == 'active';
      final lat = double.tryParse(parts[3]) ?? 0.0;
      final lng = double.tryParse(parts[4]) ?? 0.0;
      
      if (isActive) {
        _sosPeers[fromPeerId] = SOSPeer(
          peerId: fromPeerId,
          deviceName: deviceName,
          location: SOSLocation(latitude: lat, longitude: lng, time: DateTime.now()),
        );
        
        // แสดง notification
        NotificationService().showInAppNotification(
          title: '🚨 SOS ฉุกเฉิน!',
          message: '$deviceName ต้องการความช่วยเหลือ',
        );
      } else {
        _sosPeers.remove(fromPeerId);
      }
      
      notifyListeners();
    }
  }
  
  bool isPeerSOS(String peerId) => _sosPeers.containsKey(peerId);
}
```

### Step 3: Message Listener
```dart
transport.onMessage.listen((m) {
  if (m.body.startsWith('SOS_STATUS:')) {
    _handleSOSStatus(m.body, m.fromPeerId);
    return;
  }
  // ... other handlers
});
```

### Step 4: UI - SOS Button
```dart
// HomeScreen
Center(
  child: Column(
    children: [
      // ปุ่ม SOS ใหญ่
      GestureDetector(
        onTap: _toggleSOS,
        child: AnimatedContainer(
          duration: Duration(milliseconds: 300),
          width: appState.isSOSActive ? 180 : 150,
          height: appState.isSOSActive ? 180 : 150,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: appState.isSOSActive ? Colors.red : Colors.red.withOpacity(0.8),
            boxShadow: appState.isSOSActive ? [
              BoxShadow(
                color: Colors.red.withOpacity(0.5),
                blurRadius: 30,
                spreadRadius: 10,
              )
            ] : [],
          ),
          child: Icon(
            Icons.warning_amber_rounded,
            size: appState.isSOSActive ? 100 : 80,
            color: Colors.white,
          ),
        ),
      ),
      SizedBox(height: 16),
      Text(
        appState.isSOSActive ? 'กำลังส่งสัญญาณ SOS' : 'กด SOS เพื่อขอความช่วยเหลือ',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: appState.isSOSActive ? Colors.red : Colors.grey[700],
        ),
      ),
    ],
  ),
)

Future<void> _toggleSOS() async {
  if (appState.isSOSActive) {
    // ปิด SOS
    await appState.deactivateSOS();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('🔕 ปิดสัญญาณ SOS แล้ว')),
    );
  } else {
    // ยืนยันก่อนเปิด SOS
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('🚨 ยืนยันการส่งสัญญาณ SOS'),
        content: Text('คุณต้องการส่งสัญญาณฉุกเฉินไปยังอุปกรณ์ใกล้เคียงหรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('ส่งสัญญาณ SOS'),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      await appState.activateSOS();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🚨 กำลังส่งสัญญาณ SOS...'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
```

### Step 5: Peer List - SOS Badge
```dart
// แสดง badge แดงสำหรับ SOS peers
final isSOS = appState.isPeerSOS(p.id);

Container(
  decoration: BoxDecoration(
    color: isSOS ? Colors.red.withOpacity(0.15) : ...,
    border: isSOS ? Border.all(color: Colors.red, width: 2) : ...,
  ),
  child: Row(
    children: [
      Icon(
        isSOS ? Icons.warning_amber_rounded : Icons.device_hub,
        color: isSOS ? Colors.red : ...,
      ),
      // Badge: '🚨 SOS' if active
      if (isSOS)
        Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '🚨 SOS',
            style: TextStyle(color: Colors.white, fontSize: 10),
          ),
        ),
    ],
  ),
)
```

---

## ⏱️ Timeline

**ประมาณการเวลา:** 4-6 ชั่วโมง

### Phase 1: Backend (2 ชม.)
- GPS location service
- SOS state management
- Broadcast/Receive logic

### Phase 2: UI (2 ชม.)
- SOS button + animation
- Peer list badges
- Confirmation dialog

### Phase 3: Testing & Polish (1-2 ชม.)
- ทดสอบ SOS broadcast
- ทดสอบ GPS accuracy
- Notification testing

---

## 🎯 Success Criteria

✅ กดปุ่ม SOS → ส่งสัญญาณไปยัง peers ทั้งหมด
✅ Peers รับ SOS → แสดง badge แดง + notification
✅ ส่ง GPS location พร้อม SOS
✅ แสดงระยะทางจาก SOS peer (ถ้ามี GPS)
✅ ปิด SOS ได้ → peers ได้รับสัญญาณปิด
✅ Notification มี quick action เปิดแชท

---

## 📝 Notes

- **GPS Permission:** ต้อง request runtime permission (Android)
- **Background Location:** ไม่จำเป็นต้องใช้ (ส่งแค่ตอนกด SOS)
- **Accuracy:** ใช้ `desiredAccuracy: LocationAccuracy.high`
- **Timeout:** ตั้ง timeout 10 วินาที สำหรับ getCurrentPosition()
- **Fallback:** ถ้าไม่ได้ GPS → ส่ง SOS แบบไม่มีตำแหน่ง

---

**พร้อมเริ่มทำ Feature #3 เลยไหม?** 🚀
