part of 'app_state.dart';

/// โหมด SOS/Rescue — toggle state, broadcast สถานะของตัวเอง, และรับ/จัดการสถานะ
/// SOS/Rescue ของ peer อื่น ๆ แยกออกจาก [AppState] หลัก (Phase 1 ของ CLEANUP_PLAN.md)
mixin AppStateSOSRescueMixin on ChangeNotifier, AppStateLocationMixin {
  // ต้องมีสมาชิกเหล่านี้จาก AppState เอง (ประกาศเป็น concrete member อยู่แล้ว)
  // (transport มาจาก AppStateLocationMixin ใน `on` clause อยู่แล้ว ไม่ต้องประกาศซ้ำ)
  String get deviceName;
  bool get isPassiveListening;
  Future<void> _syncBackgroundServiceWithMode();
  Future<void> _showSOSNotification({
    required String senderName,
    String? message,
    double? latitude,
    double? longitude,
  });
  Future<void> _showSOSModeNotification({
    required String senderName,
    double? latitude,
    double? longitude,
  });

  // 🔒 ป้องกันการกดปุ่มซ้ำ
  bool _isTogglingRescue = false;
  bool _isTogglingSOS = false;

  // 🔒 ป้องกัน broadcast ซ้ำเร็วเกินไป
  DateTime? _lastSOSBroadcast;
  DateTime? _lastRescueBroadcast;
  static const Duration _minBroadcastInterval = Duration(seconds: 2);

  // 🚑 โหมดหน่วยกู้ภัย (Rescue Mode)
  bool _isRescueMode = false;
  @override
  bool get isRescueMode => _isRescueMode;

  // 🚨 โหมด SOS (Emergency SOS Mode)
  bool _isSOSActive = false;
  @override
  bool get isSOSActive => _isSOSActive;

  // 🚑 เปิด/ปิด โหมดหน่วยกู้ภัย
  Future<void> toggleRescueMode() async {
    // 🔒 ป้องกันการกดซ้ำ
    if (_isTogglingRescue) {
      Log.d('⚠️ กำลังประมวลผลอยู่ กรุณารอสักครู่...');
      return;
    }

    _isTogglingRescue = true;

    // ⚡ อัปเดต state ทันทีและ notify listeners
    _isRescueMode = !_isRescueMode;
    Log.d('🔍 [DEBUG] toggleRescueMode: _isRescueMode = $_isRescueMode');
    _updateLocationBroadcastMode(); // 🔋 ปรับ GPS accuracy ตามโหมดใหม่
    _syncBackgroundServiceWithMode(); // 🔋 เปิด/ปิด background service ตามโหมดใหม่ — ไม่ await
    notifyListeners(); // ✅ แจ้ง UI ทันทีก่อนทำงาน async

    try {
      // ⚠️ ถ้าเปิด Rescue Mode ให้ปิด SOS Mode อัตโนมัติ
      if (_isRescueMode && _isSOSActive) {
        Log.d('⚠️ ปิด SOS Mode เพื่อเปิด Rescue Mode');
        _isSOSActive = false;
        broadcastSOSStatus(isActive: false); // ⚡ ไม่ await
      }

      // 🔄 อัพเดท UI ทันที
      notifyListeners();

      // Broadcast สถานะหน่วยกู้ภัย
      if (_isRescueMode) {
        Log.d('🚑 กำลังเปิดโหมดหน่วยกู้ภัย...');
        _broadcastRescueStatus(true); // ⚡ ไม่ await

        // ✅ ไม่ต้อง stop/start scan เพราะ Passive Listening ทำงานอยู่แล้ว
        // แค่ broadcast สถานะก็พอ

        Log.d('🚑 ✅ เปิดโหมดหน่วยกู้ภัย (Passive Listening ทำงานต่อเนื่อง)');
      } else {
        Log.d('🚑 กำลังปิดโหมดหน่วยกู้ภัย...');
        _broadcastRescueStatus(false); // ⚡ ไม่ await
        // 📡 ไม่ stop scan เพื่อให้ Passive Listening ยังทำงาน
        Log.d('🚑 ✅ ปิดโหมดหน่วยกู้ภัย (Passive Listening ยังทำงาน)');
      }

      // อัพเดท UI อีกครั้งหลัง operation เสร็จ
      notifyListeners();
    } catch (e) {
      Log.d('❌ Error in toggleRescueMode: $e');
      // ถ้า error ให้ rollback state
      _isRescueMode = !_isRescueMode;
      _updateLocationBroadcastMode();
      _syncBackgroundServiceWithMode();
      notifyListeners();
    } finally {
      _isTogglingRescue = false;
    }
  }

  // Broadcast สถานะหน่วยกู้ภัย
  void _broadcastRescueStatus(bool isRescue) {
    // 🔒 ป้องกัน broadcast ซ้ำเร็วเกินไป
    final now = DateTime.now();
    if (_lastRescueBroadcast != null &&
        now.difference(_lastRescueBroadcast!) < _minBroadcastInterval) {
      Log.d(
        '⏭️ Skip Rescue broadcast (too soon: ${now.difference(_lastRescueBroadcast!).inMilliseconds}ms)',
      );
      return;
    }
    _lastRescueBroadcast = now;

    final status = isRescue ? 'RESCUE_MODE_ON' : 'RESCUE_MODE_OFF';
    final message = 'RESCUE_STATUS:$deviceName:$status';
    Log.d('🔍 [DEBUG] กำลังส่ง Broadcast: $message');
    // ⚡ ไม่ await - ส่งแบบ fire-and-forget เพื่อความเร็ว
    transport.sendMessage(message);
    Log.d('📡 Broadcast: $message');
  }

  // 🚨 เปิด/ปิด โหมด SOS
  // toggle SOS state + broadcast (ใช้โดยทั้งสองปุ่ม)
  Future<void> _toggleSOSState() async {
    _isSOSActive = !_isSOSActive;
    if (_isSOSActive && _isRescueMode) _isRescueMode = false;
    _updateLocationBroadcastMode(); // 🔋 ปรับ GPS accuracy ตามโหมดใหม่
    _syncBackgroundServiceWithMode(); // 🔋 เปิด/ปิด background service ตามโหมดใหม่ — ไม่ await
    notifyListeners();
    _broadcastSOSMode(isActive: _isSOSActive);
  }

  // ปุ่มใหญ่: ฉุกเฉิน urgent — toggle state + broadcast
  Future<void> toggleSOSMode() async {
    if (_isTogglingSOS) {
      Log.d('⚠️ กำลังประมวลผลอยู่ กรุณารอสักครู่...');
      return;
    }
    _isTogglingSOS = true;
    try {
      await _toggleSOSState();
      Log.d('🚨 toggleSOSMode: isSOSActive=$_isSOSActive');
    } catch (e) {
      Log.d('❌ Error in toggleSOSMode: $e');
      _isSOSActive = !_isSOSActive; // rollback
      _updateLocationBroadcastMode();
      _syncBackgroundServiceWithMode();
      notifyListeners();
    } finally {
      _isTogglingSOS = false;
    }
  }

  // ปุ่มเล็ก: ขอความช่วยเหลือ — toggle state + broadcast เหมือนกัน
  Future<void> toggleSOSRequest() async {
    if (_isTogglingSOS) return;
    _isTogglingSOS = true;
    try {
      await _toggleSOSState();
      Log.d('🆘 toggleSOSRequest: isSOSActive=$_isSOSActive');
    } catch (e) {
      Log.d('❌ Error in toggleSOSRequest: $e');
      _isSOSActive = !_isSOSActive; // rollback
      _updateLocationBroadcastMode();
      _syncBackgroundServiceWithMode();
      notifyListeners();
    } finally {
      _isTogglingSOS = false;
    }
  }

  // 🚨 Broadcast โหมด SOS (เข้า/ออกโหมด - ยังไม่ขอความช่วยเหลือ)
  void _broadcastSOSMode({
    required bool isActive,
    double? latitude,
    double? longitude,
  }) {
    // 🔒 ป้องกัน broadcast ซ้ำเร็วเกินไป
    final now = DateTime.now();
    if (_lastSOSBroadcast != null &&
        now.difference(_lastSOSBroadcast!) < _minBroadcastInterval) {
      Log.d(
        '⏭️ Skip SOS broadcast (too soon: ${now.difference(_lastSOSBroadcast!).inMilliseconds}ms)',
      );
      return;
    }
    _lastSOSBroadcast = now;

    final status = isActive ? 'SOS_MODE_ON' : 'SOS_MODE_OFF';

    // ใช้ location ที่ส่งมา หรือ 0,0 (ไม่บังคับต้องมี location สำหรับ SOS Mode)
    final lat = latitude ?? 0.0;
    final lng = longitude ?? 0.0;

    final message = 'SOS_STATUS:$deviceName:$status:$lat:$lng:0'; // timestamp = 0
    Log.d('📡 Broadcast SOS Mode: $message');

    // ⚡ ไม่ await - ส่งแบบ fire-and-forget เพื่อความเร็ว
    transport.sendMessage(message);
  }

  // 🚨 Broadcast สถานะ SOS (กดปุ่มขอความช่วยเหลือ)
  void broadcastSOSStatus({
    required bool isActive,
    double? latitude,
    double? longitude,
    bool isEmergency = false,
  }) {
    final String status;
    if (!isActive) {
      status = 'SOS_INACTIVE';
    } else if (isEmergency) {
      status = 'SOS_EMERGENCY';
    } else {
      status = 'SOS_ACTIVE';
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();

    String message;
    if (latitude != null && longitude != null) {
      message = 'SOS_STATUS:$deviceName:$status:$latitude:$longitude:$timestamp';
      Log.d('📡 Broadcast SOS: $message');
      Log.d('📍 Location: https://www.google.com/maps?q=$latitude,$longitude');
      Log.d('⏰ Timestamp: ${DateTime.now()}');
    } else {
      message = 'SOS_STATUS:$deviceName:$status:0:0:$timestamp';
      Log.d('📡 Broadcast SOS (no location): $message');
      Log.d('⏰ Timestamp: ${DateTime.now()}');
    }

    // ⚡ ไม่ await - ส่งแบบ fire-and-forget เพื่อความเร็ว
    transport.sendMessage(message);
  }

  void _handleRescueStatus(String message, String fromPeerId) {
    Log.d('🔍 [DEBUG] _handleRescueStatus เรียกแล้ว');
    Log.d('🔍 [DEBUG] ข้อความที่ได้รับ: $message');
    Log.d('🔍 [DEBUG] จาก Peer ID: $fromPeerId');

    // Format: "RESCUE_STATUS:deviceName:status"
    final parts = message.split(':');
    Log.d('🔍 [DEBUG] แยกข้อความได้ ${parts.length} ส่วน: $parts');

    if (parts.length >= 3 && parts[0] == 'RESCUE_STATUS') {
      final peerDeviceName = parts[1];
      final status = parts[2];
      final isRescue = status == 'RESCUE_MODE_ON';

      // 🔧 ⚠️ ตรวจสอบว่าเป็นข้อความจากตัวเองหรือไม่ - SKIP ทั้งหมด
      if (peerDeviceName == deviceName) {
        Log.d('🔇 [SKIP] RESCUE_STATUS จากตัวเอง ($peerDeviceName) - ไม่ประมวลผล');
        return; // ⛔ ออกทันที ไม่ทำอะไรเลย
      }

      Log.d(
        '🚑 ${isRescue ? "เปิด" : "ปิด"}โหมดหน่วยกู้ภัย: $peerDeviceName ($fromPeerId)',
      );
      Log.d('🔍 [DEBUG] isRescue = $isRescue');
      Log.d('🔍 [DEBUG] _isSOSActive = $_isSOSActive');

      // 🔧 ใช้ device name เป็น key แทน fromPeerId (เพื่อรองรับ mesh ที่มีหลาย ID)
      _rescuePeers[peerDeviceName] = isRescue;
      Log.d(
        '💾 [MESH] Saved rescue status for device name: $peerDeviceName = $isRescue',
      );

      // 🚨 ถ้าเราเปิดโหมด SOS อยู่ และพบหน่วยกู้ภัย -> แจ้งเตือนพิเศษ!
      if (isRescue && _isSOSActive) {
        Log.d(
          '🔍 [DEBUG] 🎯 เข้าเงื่อนไขแจ้งเตือนพิเศษ! กำลังแสดงการแจ้งเตือน...',
        );

        NotificationService().showInAppNotification(
          title: '🚑💚 มีหน่วยกู้ภัยมาช่วยแล้ว!',
          message:
              'พบหน่วยกู้ภัย "$peerDeviceName" อยู่ใกล้คุณ\nกำลังจะมีคนมาช่วยเหลือแล้ว อย่าท้อแท้นะ!',
          type: NotificationType.success,
        );

        // 📳 สั่น 5 ครั้ง เพื่อให้กำลังใจและยืนยัน
        for (int i = 0; i < 5; i++) {
          Future.delayed(Duration(milliseconds: i * 300), () {
            HapticFeedback.mediumImpact();
          });
        }

        Log.d('💚 ✨ พบหน่วยกู้ภัย! ให้กำลังใจผู้ประสบภัย (สั่น 5 ครั้ง)');
      } else if (isRescue) {
        Log.d('🔍 [DEBUG] เข้าเงื่อนไขแจ้งเตือนปกติ (ไม่ได้เปิด SOS)');
        // กรณีปกติ (ไม่ได้เปิด SOS)
        NotificationService().showInAppNotification(
          title: '🚑 หน่วยกู้ภัยใกล้เคียง',
          message: '$peerDeviceName พร้อมให้ความช่วยเหลือ',
          type: NotificationType.info,
        );

        // 📳 สั่น 5 ครั้ง เมื่อพบหน่วยกู้ภัย
        for (int i = 0; i < 5; i++) {
          Future.delayed(Duration(milliseconds: i * 300), () {
            HapticFeedback.mediumImpact();
          });
        }
      } else {
        Log.d('🔍 [DEBUG] ไม่เข้าเงื่อนไขแจ้งเตือนใดๆ');
      }

      notifyListeners();
    } else {
      Log.d('🔍 [DEBUG] ❌ ข้อความไม่ตรงรูปแบบ RESCUE_STATUS');
    }
  }

  /// 🚨 รับสถานะ SOS จากเครื่องอื่น
  void _handleSOSStatus(String message, String fromPeerId) {
    // Format: "SOS_STATUS:deviceName:status:lat:lng:timestamp"
    final parts = message.split(':');
    if (parts.length >= 3 && parts[0] == 'SOS_STATUS') {
      final peerDeviceName = parts[1];
      final status = parts[2];

      // 🔧 ⚠️ ตรวจสอบว่าเป็นข้อความจากตัวเองหรือไม่ - SKIP ทั้งหมด
      if (peerDeviceName == deviceName) {
        Log.d('🔇 [SKIP] SOS_STATUS จากตัวเอง ($peerDeviceName) - ไม่ประมวลผล');
        return; // ⛔ ออกทันที ไม่ทำอะไรเลย
      }

      // แยก status ออกเป็น 3 แบบ:
      // - SOS_MODE_ON = เข้าโหมด SOS (แสดงสีแดง แต่ไม่กระพริบ)
      // - SOS_ACTIVE = กดปุ่มขอความช่วยเหลือ (แสดงสีแดง + กระพริบ + เวลา)
      // - SOS_INACTIVE/SOS_MODE_OFF = ปิด SOS

      final isSOSMode = status == 'SOS_MODE_ON';
      final isSOSActive = status == 'SOS_ACTIVE';
      final isSOSEmergency = status == 'SOS_EMERGENCY';

      // ดึงพิกัด GPS ถ้ามี
      String? latitude;
      String? longitude;
      if (parts.length >= 5) {
        latitude = parts[3];
        longitude = parts[4];
      }

      // ดึง timestamp ถ้ามี (เฉพาะ SOS_ACTIVE)
      DateTime? sosTimestamp;
      if (parts.length >= 6) {
        final timestampMs = int.tryParse(parts[5]);
        if (timestampMs != null && timestampMs > 0) {
          sosTimestamp = DateTime.fromMillisecondsSinceEpoch(timestampMs);
        }
      }

      Log.d('🚨 Status: $status from $peerDeviceName ($fromPeerId)');
      if (latitude != null && longitude != null) {
        Log.d('📍 Location: $latitude, $longitude');
      }
      if (sosTimestamp != null) {
        Log.d('⏰ SOS Timestamp: $sosTimestamp');
      }

      // 🔧 ใช้ device name เป็น key แทน fromPeerId (เพื่อรองรับ mesh ที่มีหลาย ID)
      if (isSOSMode) {
        // เข้าโหมด SOS - แสดงสีแดงแต่ไม่กระพริบ
        _sosModePeers[peerDeviceName] = true;
        _sosPeers.remove(
          peerDeviceName,
        ); // ❌ ลบออกเพราะยังไม่มี timestamp (ไม่ได้กดปุ่ม)
        Log.d('🚨 $peerDeviceName เข้าโหมด SOS (ยังไม่ขอความช่วยเหลือ)');
        Log.d('💾 [MESH] Saved SOS mode for device name: $peerDeviceName = true');

        // 🔔 แจ้งเตือนเมื่อพบอุปกรณ์เข้าโหมด SOS (แต่ยังไม่ขอความช่วยเหลือ)
        String locationInfo = '';
        if (latitude != null &&
            longitude != null &&
            latitude != '0.0' &&
            longitude != '0.0') {
          locationInfo =
              '\n📍 ตำแหน่ง: https://www.google.com/maps?q=$latitude,$longitude';
        }

        // แสดง In-App notification
        NotificationService().showInAppNotification(
          title: '⚠️ พบอุปกรณ์ขอความช่วยเหลือ SOS',
          message: '$peerDeviceName ต้องการความช่วยเหลือ$locationInfo',
          type: NotificationType.warning,
        );

        // 📳 สั่น 5 ครั้ง เมื่อพบอุปกรณ์ SOS Mode
        for (int i = 0; i < 5; i++) {
          Future.delayed(Duration(milliseconds: i * 300), () {
            HapticFeedback.mediumImpact();
          });
        }

        // 🔔 แสดง System notification
        _showSOSModeNotification(
          senderName: peerDeviceName,
          latitude: latitude != null ? double.tryParse(latitude) : null,
          longitude: longitude != null ? double.tryParse(longitude) : null,
        );
      } else if (isSOSEmergency) {
        // กดปุ่ม SOS แบบฉุกเฉิน (ค้าง 5 วินาที) - แสดงสีแดงกระพริบเด่น
        _sosModePeers[peerDeviceName] = true;
        _sosPeers[peerDeviceName] = sosTimestamp ?? DateTime.now();
        _emergencySOSPeers[peerDeviceName] = sosTimestamp ?? DateTime.now();
        Log.d('🚨🚨 $peerDeviceName กดปุ่ม SOS ฉุกเฉิน!');

        String locationInfo = '';
        if (latitude != null && longitude != null) {
          locationInfo =
              '\n📍 Location: https://www.google.com/maps?q=$latitude,$longitude';
        }

        NotificationService().showInAppNotification(
          title: '🚨🚨 SOS ฉุกเฉิน! ต้องการความช่วยเหลือด่วนที่สุด!',
          message: '$peerDeviceName อยู่ในสถานการณ์ฉุกเฉิน!$locationInfo',
          type: NotificationType.emergency,
        );

        for (int i = 0; i < 8; i++) {
          Future.delayed(Duration(milliseconds: i * 200), () {
            HapticFeedback.heavyImpact();
          });
        }

        _showSOSNotification(
          senderName: peerDeviceName,
          message: 'ฉุกเฉิน! ต้องการความช่วยเหลือด่วนที่สุด!',
          latitude: latitude != null ? double.tryParse(latitude) : null,
          longitude: longitude != null ? double.tryParse(longitude) : null,
        );
      } else if (isSOSActive) {
        // กดปุ่ม SOS ปกติ - แสดงสีแดง + กระพริบ + เวลา
        _sosModePeers[peerDeviceName] = true;
        _sosPeers[peerDeviceName] = sosTimestamp ?? DateTime.now();
        _emergencySOSPeers.remove(peerDeviceName);
        Log.d('🚨 $peerDeviceName กดปุ่ม SOS - ขอความช่วยเหลือ!');
        Log.d(
          '💾 [MESH] Saved SOS active for device name: $peerDeviceName with timestamp',
        );

        String locationInfo = '';
        if (latitude != null && longitude != null) {
          locationInfo =
              '\n📍 Location: https://www.google.com/maps?q=$latitude,$longitude';
        }

        NotificationService().showInAppNotification(
          title: '🚨 SOS! ขอความช่วยเหลือด่วน!',
          message: '$peerDeviceName ต้องการความช่วยเหลือเร่งด่วน!$locationInfo',
          type: NotificationType.emergency,
        );

        for (int i = 0; i < 5; i++) {
          Future.delayed(Duration(milliseconds: i * 250), () {
            HapticFeedback.heavyImpact();
          });
        }

        _showSOSNotification(
          senderName: peerDeviceName,
          message: 'ต้องการความช่วยเหลือเร่งด่วน!',
          latitude: latitude != null ? double.tryParse(latitude) : null,
          longitude: longitude != null ? double.tryParse(longitude) : null,
        );
      } else {
        // ปิด SOS
        _sosModePeers.remove(peerDeviceName);
        _sosPeers.remove(peerDeviceName);
        _emergencySOSPeers.remove(peerDeviceName);
        Log.d('🚨 $peerDeviceName ปิดโหมด SOS');
        Log.d('💾 [MESH] Removed SOS status for device name: $peerDeviceName');
      }

      notifyListeners();
    }
  }

  // เก็บ emergency SOS peers (กด SOS แบบค้าง 5 วินาที)
  final Map<String, DateTime?> _emergencySOSPeers = {};

  bool isEmergencySOSPeer(String peerNameOrId) =>
      _emergencySOSPeers[peerNameOrId] != null;

  // เก็บสถานะหน่วยกู้ภัยของแต่ละ peer
  final Map<String, bool> _rescuePeers = {};

  // เก็บว่า peer ไหนอยู่ในโหมด SOS (แต่ยังไม่ได้กดปุ่มขอความช่วยเหลือ)
  final Map<String, bool> _sosModePeers = {}; // peerId -> true = อยู่ในโหมด SOS

  // เก็บสถานะ SOS ของแต่ละ peer พร้อมเวลาที่กด SOS (ขอความช่วยเหลือแล้ว)
  final Map<String, DateTime?> _sosPeers =
      {}; // peerId -> เวลาที่กด SOS (null = ยังไม่ได้กด)

  // 🔧 Getters สำหรับ UI - รับ peer name แทน peer ID (เพื่อรองรับ mesh)
  bool isRescuePeer(String peerNameOrId) {
    // ลองหาทั้ง name และ ID
    return _rescuePeers[peerNameOrId] ?? false;
  }

  bool isSOSModePeer(String peerNameOrId) {
    // ลองหาทั้ง name และ ID
    return _sosModePeers[peerNameOrId] ?? false;
  }

  bool isSOSPeer(String peerNameOrId) {
    // ต้องเช็คว่ามี key และ value ไม่เป็น null (กดปุ่ม SOS แล้ว)
    final timestamp = _sosPeers[peerNameOrId];
    return timestamp != null; // return true เฉพาะตอนมี timestamp จริงๆ
  }

  DateTime? getSOSTimestamp(String peerNameOrId) =>
      _sosPeers[peerNameOrId]; // ดึงเวลาที่กด SOS

  Map<String, bool> get rescuePeers => Map.unmodifiable(_rescuePeers);

  // เช็คว่า peer เป็นหน่วยกู้ภัยหรือไม่
  bool isPeerRescue(String peerNameOrId) {
    return _rescuePeers[peerNameOrId] ?? false;
  }
}
