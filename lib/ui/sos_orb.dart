import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../core/app_state.dart';
import '../core/logger.dart';

/// SOS Orb — self-contained widget: status badge + pulsing orb + rescue button.
/// Manages its own animation and hold-to-emergency state.
class SosOrb extends StatefulWidget {
  const SosOrb({super.key});

  @override
  State<SosOrb> createState() => _SosOrbState();
}

class _SosOrbState extends State<SosOrb> with SingleTickerProviderStateMixin {
  late AnimationController _blink;

  Timer? _holdTimer;
  double _holdProgress = 0.0;
  bool _isHolding = false;
  bool _isEmergencyActive = false;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _warningSnackBar;

  @override
  void initState() {
    super.initState();
    _blink = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _blink.dispose();
    super.dispose();
  }

  Future<void> _handleSOSTap(BuildContext context, {bool emergency = false}) async {
    final wasActive = appState.isSOSActive;

    if (wasActive && !emergency) {
      HapticFeedback.mediumImpact();
      await appState.toggleSOSMode();
      if (mounted) setState(() => _isEmergencyActive = false);
      if (appState.peers.isNotEmpty) {
        appState.broadcastSOSStatus(isActive: false);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ปิดการขอความช่วยเหลือ'), duration: Duration(seconds: 2)),
        );
      }
      return;
    }

    if (!wasActive) await appState.toggleSOSMode();

    if (emergency) {
      HapticFeedback.heavyImpact();
      if (mounted) setState(() => _isEmergencyActive = true);
    } else {
      HapticFeedback.mediumImpact();
      if (mounted) setState(() => _isEmergencyActive = false);
    }

    String? lat;
    String? lng;
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );
      lat = pos.latitude.toStringAsFixed(6);
      lng = pos.longitude.toStringAsFixed(6);
    } catch (e) {
      Log.d('⚠️ Cannot get GPS: $e');
    }

    if (appState.peers.isNotEmpty) {
      final now = DateTime.now();
      final t = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      final loc = (lat != null && lng != null) ? '\n📍 ตำแหน่ง: https://www.google.com/maps?q=$lat,$lng' : '';
      final msg = emergency
          ? '🚨 SOS ฉุกเฉิน! ต้องการความช่วยเหลือด่วน!\n⏰ เวลา: $t$loc'
          : '🆘 ขอความช่วยเหลือ\n⏰ เวลา: $t$loc';
      appState.send(msg);
      appState.broadcastSOSStatus(
        isActive: true,
        isEmergency: emergency,
        latitude: lat != null ? double.parse(lat) : null,
        longitude: lng != null ? double.parse(lng) : null,
      );
    }

    if (context.mounted && !emergency) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ส่งคำขอความช่วยเหลือแล้ว'), duration: Duration(seconds: 2)),
      );
    }
  }

  void _startHold(BuildContext context) {
    if (_isHolding) return;
    _isHolding = true;
    _holdProgress = 0.0;

    _warningSnackBar = ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.gavel, color: Colors.white, size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'หากกดขอความช่วยเหลือโดยไม่ได้มีเหตุจำเป็น มีโทษทางกฎหมาย',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFE65100),
        duration: const Duration(seconds: 10),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    const totalMs = 5000;
    const intervalMs = 80;
    _holdTimer = Timer.periodic(const Duration(milliseconds: intervalMs), (timer) {
      if (!_isHolding || !mounted) {
        timer.cancel();
        if (mounted) setState(() => _holdProgress = 0.0);
        return;
      }
      setState(() => _holdProgress = (_holdProgress + intervalMs / totalMs).clamp(0.0, 1.0));
      if (_holdProgress >= 1.0) {
        timer.cancel();
        _isHolding = false;
        setState(() => _holdProgress = 0.0);
        _warningSnackBar?.close();
        _warningSnackBar = null;
        _handleSOSTap(context, emergency: true);
      }
    });
  }

  void _cancelHold() {
    if (!_isHolding) return;
    _isHolding = false;
    _holdTimer?.cancel();
    _warningSnackBar?.close();
    _warningSnackBar = null;
    if (mounted) setState(() => _holdProgress = 0.0);
  }

  Widget _statusBadge(bool isSOSActive) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isSOSActive ? const Color(0xFFFFEBEE) : const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _blink,
            builder: (_, __) => Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isSOSActive
                    ? Color.lerp(Colors.red, Colors.redAccent, _blink.value)!
                    : const Color(0xFF4CAF50),
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            isSOSActive ? 'SOS Active' : "You're Safe",
            style: TextStyle(
              color: isSOSActive ? Colors.red.shade700 : const Color(0xFF2E7D32),
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _orbButton(BuildContext context, bool isSOSActive) {
    return GestureDetector(
      onTap: () {
        if (_isHolding) return;
        _handleSOSTap(context);
      },
      onLongPressStart: (_) {
        if (_isEmergencyActive) return;
        _startHold(context);
      },
      onLongPressEnd: (_) => _cancelHold(),
      onLongPressCancel: () => _cancelHold(),
      child: AnimatedBuilder(
        animation: _blink,
        builder: (context, _) {
          final pulse = _blink.value;
          final isEmergency = isSOSActive && _isEmergencyActive;
          final buttonColor = isEmergency
              ? Color.lerp(const Color(0xFFB71C1C), const Color(0xFFD32F2F), pulse)!
              : const Color(0xFFD32F2F);
          return SizedBox(
            width: 260,
            height: 260,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (isSOSActive) ...[
                  Container(
                    width: 210 + (pulse * (isEmergency ? 50 : 40)),
                    height: 210 + (pulse * (isEmergency ? 50 : 40)),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.red.withValues(alpha: (1 - pulse) * (isEmergency ? 0.14 : 0.08)),
                    ),
                  ),
                  Container(
                    width: 188 + (pulse * (isEmergency ? 30 : 24)),
                    height: 188 + (pulse * (isEmergency ? 30 : 24)),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.red.withValues(alpha: (1 - pulse) * (isEmergency ? 0.18 : 0.12)),
                    ),
                  ),
                ] else
                  Container(
                    width: 200,
                    height: 200,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0x14D32F2F),
                    ),
                  ),
                if (_holdProgress > 0)
                  SizedBox(
                    width: 186,
                    height: 186,
                    child: CircularProgressIndicator(
                      value: _holdProgress,
                      strokeWidth: 7,
                      color: Colors.orangeAccent,
                      backgroundColor: Colors.red.withValues(alpha: 0.2),
                    ),
                  ),
                Container(
                  width: 170,
                  height: 170,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: buttonColor,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withValues(
                          alpha: isSOSActive ? (isEmergency ? 0.6 : 0.45) : 0.25,
                        ),
                        blurRadius: isSOSActive ? (isEmergency ? 50 : 40) : 20,
                        spreadRadius: isSOSActive ? (isEmergency ? 12 : 8) : 2,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isEmergency ? Icons.crisis_alert : Icons.warning_amber_rounded,
                        size: 54,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'SOS',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _holdProgress > 0
                            ? 'Emergency in ${((1.0 - _holdProgress) * 5).ceil()}s...'
                            : isSOSActive
                                ? (isEmergency ? 'EMERGENCY ACTIVE' : 'HELP ACTIVE')
                                : 'Tap / Hold 5s',
                        style: TextStyle(
                          fontSize: _holdProgress > 0 ? 10 : 12,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _rescueButton(BuildContext context, bool isRescueMode) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        appState.toggleRescueMode().then((_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(!isRescueMode ? 'เปิดโหมดหน่วยกู้ภัย' : 'ปิดโหมดหน่วยกู้ภัย'),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: isRescueMode ? const Color(0x141565C0) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF1976D2), width: 2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isRescueMode ? Icons.shield : Icons.shield_outlined,
              color: const Color(0xFF1976D2),
              size: 22,
            ),
            const SizedBox(width: 10),
            Text(
              isRescueMode ? 'Rescue Mode: ON' : 'Rescue Others',
              style: const TextStyle(
                color: Color(0xFF1976D2),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final isSOSActive = appState.isSOSActive;
        final isRescueMode = appState.isRescueMode;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _statusBadge(isSOSActive),
            const SizedBox(height: 40),
            _orbButton(context, isSOSActive),
            const SizedBox(height: 32),
            _rescueButton(context, isRescueMode),
          ],
        );
      },
    );
  }
}
