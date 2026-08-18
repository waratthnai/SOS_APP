part of 'app_state.dart';

/// Keep-alive heartbeat + connection/reconnect monitoring — แยกออกจาก [AppState]
/// หลัก (Phase 1 ของ CLEANUP_PLAN.md)
mixin AppStateConnectionMonitorMixin on ChangeNotifier {
  Transport get transport;
  List<Peer> get peers;
  Future<void> startScan();
  Future<void> stopScan();

  Timer? _keepAliveTimer; // 🔄 Timer สำหรับ keep alive
  Timer? _reconnectTimer; // 🔁 Timer สำหรับ auto reconnect
  int _reconnectAttempts = 0; // 🔁 นับจำนวนครั้งที่พยายามเชื่อมต่อใหม่
  static const int _maxReconnectAttempts = 5; // 🔁 จำนวนครั้งสูงสุด

  // 💓 Keep Alive - ส่ง heartbeat ทุก 30 วินาที
  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (peers.isNotEmpty) {
        // ส่ง keep alive message เพื่อรักษาการเชื่อมต่อ (ไม่ await)
        try {
          transport.sendMessage(
            'KEEP_ALIVE:${DateTime.now().millisecondsSinceEpoch}',
          ); // ⚡ ไม่ await
          Log.d('💓 Keep Alive sent to ${peers.length} peers');
        } catch (e) {
          Log.d('❌ Keep Alive failed: $e');
        }
      }
    });
    Log.d('💓 เริ่ม Keep Alive ทุก 30 วินาที');
  }

  // 🔁 Connection Monitor - ตรวจสอบและ reconnect ทุก 10 วินาที
  void _startConnectionMonitor() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 10), (
      timer,
    ) async {
      // reconnect ทุก mode (รวม passive) เมื่อไม่มี peer และ discovery กำลังทำงานอยู่
      if (peers.isEmpty &&
          transport.discoveryState == DiscoveryState.scanning) {
        if (_reconnectAttempts < _maxReconnectAttempts) {
          _reconnectAttempts++;
          Log.d(
            '🔁 Reconnect attempt $_reconnectAttempts/$_maxReconnectAttempts',
          );

          // พยายาม scan ใหม่
          await stopScan();
          await Future.delayed(const Duration(seconds: 1));
          await startScan();
        } else if (_reconnectAttempts == _maxReconnectAttempts) {
          Log.d('⚠️ Reconnect failed after $_maxReconnectAttempts attempts');
          _reconnectAttempts++; // เพิ่มอีก 1 เพื่อไม่ให้ log ซ้ำ
        }
      }

      // ถ้ามี peer แล้ว reset counter
      if (peers.isNotEmpty && _reconnectAttempts > 0) {
        _reconnectAttempts = 0;
      }
    });
    Log.d('🔁 เริ่ม Connection Monitor ทุก 10 วินาที');
  }
}
