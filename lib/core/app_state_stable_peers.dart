part of 'app_state.dart';

/// Stable Peer List — เก็บ peers ที่เคยพบไว้ชั่วคราว (กัน peer หายวูบเวลาสัญญาณ
/// สั่น ๆ) พร้อม cleanup timer อัตโนมัติ แยกออกจาก [AppState] หลัก
/// (Phase 1 ของ CLEANUP_PLAN.md)
mixin AppStateStablePeersMixin on ChangeNotifier {
  final Map<String, Peer> _stablePeers = {};
  Timer? _peerCleanupTimer;
  final Map<String, DateTime> _peerLastSeen = {};
  // 💓 เพิ่ม timeout เป็น 45 วินาที (Keep Alive ส่งทุก 30 วินาที + buffer 15 วินาที)
  // เพื่อให้มั่นใจว่าไม่ timeout ก่อนรับ Keep Alive ครั้งถัดไป
  static const Duration _peerTimeout = Duration(seconds: 45);

  // Getter สำหรับ stable peers
  UnmodifiableListView<Peer> get stablePeers =>
      UnmodifiableListView(_stablePeers.values);

  /// 🔄 อัปเดต Stable Peers List - เก็บ peers ที่เคยเห็นไว้ชั่วคราว
  void _updateStablePeers(List<Peer> currentPeers) {
    final now = DateTime.now();
    bool hasChanges = false;

    // เพิ่ม/อัปเดต peers ที่เห็นอยู่
    for (final peer in currentPeers) {
      if (!_stablePeers.containsKey(peer.id)) {
        hasChanges = true;
        Log.d('✅ เพิ่ม stable peer: ${peer.name} (${peer.id})');
      }
      _stablePeers[peer.id] = peer;
      _peerLastSeen[peer.id] = now;
    }

    // ลบ peers ที่ไม่เห็นนานเกินไป (15 วินาที)
    _peerLastSeen.removeWhere((peerId, lastSeen) {
      if (now.difference(lastSeen) > _peerTimeout) {
        _stablePeers.remove(peerId);
        Log.d('🔄 ลบ peer $peerId (timeout after ${_peerTimeout.inSeconds}s)');
        hasChanges = true;
        return true;
      }
      return false;
    });

    // ⚡ เพิ่ม cleanup frequency จาก 10 วินาที → 5 วินาที
    // เพื่อให้ UI อัปเดตไวขึ้น
    _peerCleanupTimer ??= Timer.periodic(const Duration(seconds: 5), (_) {
      _updateStablePeers([]); // เรียกเพื่อทำ cleanup
    });

    // ⚡ แจ้ง UI ทันทีเมื่อมีการเปลี่ยนแปลง
    if (hasChanges) {
      notifyListeners();
    }
  }
}
