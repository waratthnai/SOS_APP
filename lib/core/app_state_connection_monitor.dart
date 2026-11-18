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
  int _reconnectAttempts = 0; // 🔁 นับจำนวนครั้งที่พยายามเชื่อมต่อใหม่ (ไว้ log เท่านั้น ไม่จำกัดจำนวนครั้ง)

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

  // 🔁 Connection Monitor - ตรวจสอบทุก 10 วินาที (tick นับรวม ไม่ reset เมื่อยัง peers ว่าง)
  int _reconnectTick = 0;

  // จำนวน tick แรกที่ยัง retry ถี่ทุก 10 วิ ก่อนถอยไปช้าลง
  static const int _fastRetryTicks = 3;
  // หลังพ้นช่วง fast retry แล้ว ให้ retry ทุก ๆ กี่ tick (10s * 6 = 60s)
  static const int _slowRetryEveryNTicks = 6;

  void _startConnectionMonitor() {
    _reconnectTimer?.cancel();
    _reconnectTick = 0;
    _reconnectTimer = Timer.periodic(const Duration(seconds: 10), (
      timer,
    ) async {
      // reconnect ทุก mode (รวม passive) เมื่อไม่มี peer และ discovery กำลังทำงานอยู่
      if (peers.isEmpty &&
          transport.discoveryState == DiscoveryState.scanning) {
        _reconnectTick++;

        // ⚠️ stopScan() ทำลาย endpoint ที่กำลัง handshake อยู่ (stopAllEndpoints())
        // ถ้า retry ถี่เกินไปตลอดเวลา จะตัด handshake ที่ใช้เวลานานกว่า interval ทิ้งซ้ำ ๆ
        // ไม่มีวันเชื่อมต่อสำเร็จ — จึงถี่แค่ช่วงแรก แล้วถอยไปช้าลงเพื่อให้ handshake มีเวลาจบ
        final shouldAttempt = _reconnectTick <= _fastRetryTicks ||
            _reconnectTick % _slowRetryEveryNTicks == 0;
        if (shouldAttempt) {
          _reconnectAttempts++;
          Log.d('🔁 Reconnect attempt $_reconnectAttempts (tick $_reconnectTick)');
          await stopScan();
          await Future.delayed(const Duration(seconds: 1));
          await startScan();
        }
      }

      // ถ้ามี peer แล้ว reset counter
      if (peers.isNotEmpty && _reconnectAttempts > 0) {
        _reconnectAttempts = 0;
        _reconnectTick = 0;
      }
    });
    Log.d('🔁 เริ่ม Connection Monitor ทุก 10 วินาที');
  }
}
