// lib/core/device_id_manager.dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// จัดการ Device ID ที่ไม่เปลี่ยนแปลง
/// - ก่อน login: ใช้ Device ID ถาวร (UUID)
/// - หลัง login: ใช้ Firebase User ID
class DeviceIdManager {
  static const _deviceIdKey = 'persistent_device_id';
  static const _uuid = Uuid();
  
  static String? _cachedDeviceId;
  static String? _cachedUserId;
  
  /// ดึง Device ID ถาวร (สร้างครั้งแรกแล้วเก็บไว้)
  static Future<String> getDeviceId() async {
    // ถ้ามี cache แล้ว ใช้เลย
    if (_cachedDeviceId != null) {
      return _cachedDeviceId!;
    }
    
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString(_deviceIdKey);
    
    if (deviceId == null) {
      // สร้าง UUID ใหม่ และบันทึก
      deviceId = 'device_${_uuid.v4()}';
      await prefs.setString(_deviceIdKey, deviceId);
      print('[DeviceId] 🆕 Created new device ID: $deviceId');
    } else {
      print('[DeviceId] 📱 Loaded existing device ID: $deviceId');
    }
    
    _cachedDeviceId = deviceId;
    return deviceId;
  }
  
  /// ตั้งค่า User ID (เมื่อ login)
  static void setUserId(String? userId) {
    _cachedUserId = userId;
    if (userId != null) {
      print('[DeviceId] 👤 User logged in: $userId');
    } else {
      print('[DeviceId] 👤 User logged out - using device ID');
    }
  }
  
  /// ดึง ID ที่ใช้งานจริง (User ID ถ้า login, Device ID ถ้ายังไม่ login)
  static Future<String> getCurrentId() async {
    if (_cachedUserId != null) {
      return _cachedUserId!;
    }
    return await getDeviceId();
  }
  
  /// ตรวจสอบว่า login แล้วหรือยัง
  static bool get isLoggedIn => _cachedUserId != null;
  
  /// ล้างข้อมูล (สำหรับ debug)
  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_deviceIdKey);
    _cachedDeviceId = null;
    _cachedUserId = null;
    print('[DeviceId] 🔄 Reset device ID');
  }
}
