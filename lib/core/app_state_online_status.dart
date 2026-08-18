part of 'app_state.dart';

/// Online-status heartbeat (Firebase presence) — แยกออกจาก [AppState] หลัก
/// (Phase 1 ของ CLEANUP_PLAN.md)
mixin AppStateOnlineStatusMixin on ChangeNotifier {
  bool get isAppInForeground;

  Timer? _onlineStatusTimer; // Timer สำหรับอัปเดตสถานะออนไลน์

  /// เริ่มอัปเดตสถานะออนไลน์แบบอัตโนมัติ (ทุก 5 วินาที)
  void _startOnlineStatusUpdates() {
    Log.d('[AppState] 🔧 เริ่มต้น _startOnlineStatusUpdates...');
    _stopOnlineStatusUpdates(); // ยกเลิก timer เก่าก่อน (ถ้ามี)

    if (friendService.currentUser == null) {
      Log.d('[AppState] ⚠️ ไม่มี currentUser - ข้าม timer');
      return;
    }

    if (!isAppInForeground) {
      Log.d('[AppState] ⚠️ แอพไม่ได้อยู่ foreground - ข้าม timer');
      return;
    }

    Log.d(
      '[AppState] ✅ สร้าง Timer สำหรับ ${friendService.currentUser!.name} (${friendService.currentUser!.id})',
    );
    // ⚠️ ตั้งใจไม่เช็ค isAppInForeground ในนี้ — heartbeat ต้องทำงานต่อแม้แอพถูกย่อ/ปิดจอ
    // เพื่อให้ผู้ขอความช่วยเหลือยังแสดงสถานะ "ออนไลน์" ได้แม้ไม่ได้เฝ้าหน้าจอ (ประหยัดแบต)
    // Timer นี้จะหยุดทำงานจริงก็ต่อเมื่อ OS ระงับ process (เช่นเข้า Doze mode นานๆ) เท่านั้น
    _onlineStatusTimer = Timer.periodic(const Duration(seconds: 5), (
      timer,
    ) async {
      if (friendService.currentUser != null &&
          firebaseService.isOnline &&
          firebaseService.isSignedIn) {
        Log.d(
          '[AppState] 🔄 [Heartbeat] อัปเดตสถานะออนไลน์สำหรับ: ${friendService.currentUser!.name}',
        );
        await firebaseService.updateOnlineStatus(
          friendService.currentUser!.id,
          true,
        );
      } else {
        Log.d(
          '[AppState] ⚠️ [Heartbeat] ข้ามการอัปเดต - currentUser=${friendService.currentUser?.name}, online=${firebaseService.isOnline}, signedIn=${firebaseService.isSignedIn}',
        );
      }
    });
    Log.d('[AppState] ✅ Timer สร้างเสร็จแล้ว - จะอัปเดตทุก 5 วินาที');
  }

  /// หยุดอัปเดตสถานะออนไลน์
  void _stopOnlineStatusUpdates() {
    if (_onlineStatusTimer != null) {
      Log.d('[AppState] 🛑 หยุด Timer heartbeat');
    }
    _onlineStatusTimer?.cancel();
    _onlineStatusTimer = null;
  }

  void _setOnlineStatus(bool isOnline) async {
    if (friendService.currentUser != null && firebaseService.isSignedIn) {
      Log.d(
        '[AppState] 🔄 ตั้งสถานะ: ${isOnline ? "ออนไลน์" : "ออฟไลน์"} สำหรับ ${friendService.currentUser!.name}',
      );
      await firebaseService.updateOnlineStatus(
        friendService.currentUser!.id,
        isOnline,
      );
    }
  }
}
