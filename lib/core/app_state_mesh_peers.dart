part of 'app_state.dart';

/// ตำแหน่ง GPS ของ peer อื่น ๆ + สถิติ mesh network (dedup ข้อความที่ forward แล้ว,
/// TTL, network topology) แยกออกจาก [AppState] หลัก (Phase 1 ของ CLEANUP_PLAN.md)
///
/// หมายเหตุ: `_handleRelayMessage` (จัดการข้อความ mesh relay) ยังอยู่ใน AppState หลัก
/// เพราะต้องเขียน `_chatMessages` โดยตรง — แต่เรียกใช้ `_cleanupOldMessages()` และ field
/// dedup (`_forwardedMessages` ฯลฯ) ของ mixin นี้ได้ตามปกติ (เป็น library เดียวกัน)
mixin AppStateMeshPeerMixin on ChangeNotifier, AppStateLocationMixin {
  // (transport มาจาก AppStateLocationMixin ใน `on` clause อยู่แล้ว ไม่ต้องประกาศซ้ำ)

  // 📍 GPS Locations ของ peers
  final Map<String, PeerLocation> _peerLocations = {};

  Map<String, PeerLocation> get peerLocations =>
      Map.unmodifiable(_peerLocations);

  // 🌐 Mesh Network: เก็บ ID ข้อความที่เคยส่งต่อแล้ว (ป้องกันการส่งซ้ำ)
  final Set<String> _forwardedMessages = {};
  final Map<String, int> _messageTTL = {}; // Time To Live สำหรับแต่ละข้อความ
  final Map<String, DateTime> _messageTimestamps = {}; // เก็บเวลาที่รับข้อความ

  // 📊 Network Topology: เก็บข้อมูลเครือข่าย
  final Map<String, Set<String>> _networkTopology =
      {}; // peerId -> connected peers

  // 🧹 ล้างข้อความเก่าเพื่อป้องกัน memory leak
  void _cleanupOldMessages() {
    const maxMessages = 100;

    if (_forwardedMessages.length > maxMessages) {
      // เก็บแค่ข้อความล่าสุด
      final sortedMessages = _messageTimestamps.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      final toRemove = sortedMessages
          .skip(maxMessages)
          .map((e) => e.key)
          .toList();

      for (final msgId in toRemove) {
        _forwardedMessages.remove(msgId);
        _messageTTL.remove(msgId);
        _messageTimestamps.remove(msgId);
      }

      Log.d(
        '🧹 ล้างข้อความเก่า: ${toRemove.length} ข้อความ (เหลือ ${_forwardedMessages.length})',
      );
    }
  }

  // 📍 จัดการข้อความ GPS Location (ไม่บันทึกลง chat)
  void _handleGPSLocation(String message, String fromPeerId) {
    // Format: "GPS_LOC:lat,lng,timestamp"
    final parts = message.split(':');
    Log.d('🔍 [GPS] รับข้อความ GPS: $message');

    if (parts.length >= 2 && parts[0] == 'GPS_LOC') {
      try {
        final location = PeerLocation.fromString(parts[1]);
        _peerLocations[fromPeerId] = location;
        Log.d(
          '📍 [Real-time] อัพเดทตำแหน่ง peer $fromPeerId: ${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}',
        );
        Log.d('💾 [GPS] จำนวน peer locations: ${_peerLocations.length}');

        // ⚡ คำนวณระยะห่างทันทีและอัพเดท UI
        if (_myCurrentPosition != null) {
          final distance = Geolocator.distanceBetween(
            _myCurrentPosition!.latitude,
            _myCurrentPosition!.longitude,
            location.latitude,
            location.longitude,
          );
          Log.d(
            '📏 [Real-time] ระยะห่างจาก peer $fromPeerId: ${distance.toStringAsFixed(1)}m',
          );
        } else {
          Log.d(
            '⚠️ [GPS] ยังไม่มีตำแหน่งของตัวเอง (_myCurrentPosition = null)',
          );
        }

        notifyListeners(); // ⚡ อัพเดท UI ทันที
      } catch (e) {
        Log.d('❌ ไม่สามารถแปลงข้อมูล GPS: $e (message: $message)');
      }
    } else {
      Log.d('⚠️ [GPS] ข้อความ GPS format ไม่ถูกต้อง: $message');
    }
  }

  // 📍 คำนวณระยะห่างจาก peer (Real-time version)
  double? getDistanceToPeerSync(String peerId, Position? myPosition) {
    // ⚡ ใช้ตำแหน่งที่เก็บไว้ (real-time) ถ้าไม่ส่งมา
    final position = myPosition ?? _myCurrentPosition;
    if (position == null) {
      Log.d('⚠️ [Distance] ไม่มีตำแหน่งของตัวเอง (position = null)');
      return null;
    }

    final peerLoc = _peerLocations[peerId];
    if (peerLoc == null) {
      Log.d('⚠️ [Distance] ไม่มีตำแหน่งของ peer $peerId');
      return null;
    }

    // ใช้ Haversine formula คำนวณระยะทาง
    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      peerLoc.latitude,
      peerLoc.longitude,
    );

    Log.d(
      '📏 [Distance] คำนวณระยะห่าง peer $peerId: ${distance.toStringAsFixed(1)}m',
    );
    return distance;
  }

  // 📍 ส่ง GPS Location ของตัวเองไปให้ peers
  Future<void> broadcastMyLocation() async {
    try {
      Position? position;

      // พยายามดึง GPS ปัจจุบัน (timeout 15 วินาที)
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium, // ลดความแม่นยำเพื่อความเร็ว
          timeLimit: const Duration(seconds: 15),
        );
      } catch (e) {
        // ถ้าไม่ได้ ให้ใช้ตำแหน่งล่าสุดแทน
        Log.d('⚠️ ไม่สามารถดึง GPS ปัจจุบัน: $e');
        Log.d('📍 กำลังใช้ตำแหน่งล่าสุดแทน...');
        position = await Geolocator.getLastKnownPosition();
      }

      if (position == null) {
        Log.d('❌ ไม่มีข้อมูล GPS (ทั้งปัจจุบันและล่าสุด)');
        return;
      }

      final location = PeerLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        timestamp: DateTime.now(),
      );

      final message = 'GPS_LOC:${location.toString()}';
      transport.sendMessage(
        message,
      ); // ⚡ ไม่ await - broadcast แบบ fire-and-forget
      Log.d(
        '📍 ส่งตำแหน่ง: ${location.latitude}, ${location.longitude} (±${position.accuracy.toStringAsFixed(1)}m)',
      );
    } catch (e) {
      Log.d('❌ ไม่สามารถดึง GPS ได้: $e');
    }
  }

  // 📊 ดึงข้อมูล Network Topology
  Map<String, Set<String>> get networkTopology =>
      Map.unmodifiable(_networkTopology);

  // 📊 สถิติ Mesh Network
  Map<String, dynamic> getMeshNetworkStats() {
    return {
      'totalForwardedMessages': _forwardedMessages.length,
      'averageTTL': _messageTTL.values.isEmpty
          ? 0
          : _messageTTL.values.reduce((a, b) => a + b) / _messageTTL.length,
      'networkNodes': _networkTopology.length,
      'oldestMessage': _messageTimestamps.values.isEmpty
          ? null
          : _messageTimestamps.values.reduce((a, b) => a.isBefore(b) ? a : b),
    };
  }
}
