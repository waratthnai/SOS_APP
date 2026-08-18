import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:offgrid_sos/core/transport.dart';
import 'package:offgrid_sos/core/app_state.dart';
import 'package:offgrid_sos/core/nearby_transport.dart';
import 'package:offgrid_sos/core/notification_service.dart';
import 'package:offgrid_sos/ui/sos_orb.dart';
import 'package:offgrid_sos/ui/emergency_chat_screen.dart';
import 'package:offgrid_sos/ui/notifications_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late AnimationController _blinkController;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }

  String? _distanceLabel(String peerId) {
    final d = appState.getDistanceToPeerSync(peerId, null);
    if (d == null) return null;
    return d < 1000 ? '~${d.toStringAsFixed(0)} m' : '~${(d / 1000).toStringAsFixed(1)} km';
  }

  Widget _gpsStatusRow(ColorScheme cs) {
    final hasOwnGps = appState.myCurrentPosition != null;
    final peerGpsCount = appState.peerLocations.length;
    final peers = appState.peers;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(Icons.gps_fixed, size: 12,
              color: hasOwnGps ? Colors.green : cs.onSurfaceVariant.withValues(alpha: 0.4)),
          const SizedBox(width: 4),
          Text(
            hasOwnGps ? 'GPS ✓' : 'GPS —',
            style: TextStyle(
              fontSize: 11,
              color: hasOwnGps ? Colors.green : cs.onSurfaceVariant.withValues(alpha: 0.4),
            ),
          ),
          if (!hasOwnGps) ...[
            const SizedBox(width: 2),
            GestureDetector(
              onTap: () => appState.retryLocationBroadcast(),
              child: Icon(Icons.refresh, size: 12, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
            ),
          ],
          if (peers.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(
              '· peer GPS $peerGpsCount/${peers.length}',
              style: TextStyle(
                fontSize: 11,
                color: peerGpsCount == peers.length
                    ? Colors.green.withValues(alpha: 0.8)
                    : cs.onSurfaceVariant.withValues(alpha: 0.4),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 📡 รายการโปรโตคอลการเชื่อมต่อที่เลือกได้
  static const _protocolOptions = [
    (key: 'nearby', label: 'Nearby Connections', subtitle: 'BLE + WiFi รวมกัน (แนะนำ)', icon: Icons.share_outlined),
    (key: 'ble', label: 'Bluetooth LE', subtitle: 'เชื่อมต่อผ่าน BLE โดยตรง', icon: Icons.bluetooth),
    (key: 'wifi_direct', label: 'WiFi Direct', subtitle: 'ต้องเปิด WiFi Direct ทั้ง 2 เครื่อง', icon: Icons.wifi_tethering),
    (key: 'mesh', label: 'Radio Mesh', subtitle: 'ส่งต่อข้อความหลาย hop ผ่านอุปกรณ์ตัวกลาง', icon: Icons.hub_outlined),
  ];

  void _showProtocolPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        // 🔒 อยู่นอก StatefulBuilder.builder เพื่อให้ค่าคงอยู่ข้าม rebuild ของ setSheetState
        var isSwitching = false;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'เลือกโปรโตคอลการเชื่อมต่อ',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final option in _protocolOptions)
                      ListTile(
                        leading: Icon(
                          option.icon,
                          color: appState.selectedProtocol == option.key ? const Color(0xFF1976D2) : Colors.grey[600],
                        ),
                        title: Text(
                          option.label,
                          style: TextStyle(
                            fontWeight: appState.selectedProtocol == option.key ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(option.subtitle, style: const TextStyle(fontSize: 12)),
                        trailing: appState.selectedProtocol == option.key
                            ? const Icon(Icons.check_circle, color: Color(0xFF1976D2))
                            : null,
                        enabled: !isSwitching,
                        onTap: appState.selectedProtocol == option.key
                            ? null
                            : () async {
                                setSheetState(() => isSwitching = true);
                                try {
                                  await appState.switchTransport(option.key);
                                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                                  if (mounted) {
                                    ScaffoldMessenger.of(this.context).showSnackBar(
                                      SnackBar(
                                        content: Text('✅ สลับไปใช้ ${option.label} แล้ว'),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  setSheetState(() => isSwitching = false);
                                  if (mounted) {
                                    ScaffoldMessenger.of(this.context).showSnackBar(
                                      SnackBar(
                                        content: Text('❌ สลับโปรโตคอลไม่สำเร็จ: $e'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                }
                              },
                      ),
                    if (isSwitching)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) {
        final peers = appState.peers;

        return Scaffold(
          appBar: AppBar(
            title: const Text('SOS Rescue'),
            leading: IconButton(
              icon: const Icon(Icons.settings_input_antenna),
              tooltip: 'เลือกโปรโตคอลการเชื่อมต่อ',
              onPressed: () => _showProtocolPicker(context),
            ),
            elevation: 0,
            centerTitle: true,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(0.5),
              child: Container(height: 0.5, color: cs.outlineVariant),
            ),
            actions: [
              AnimatedBuilder(
                animation: NotificationService(),
                builder: (context, child) {
                  final notificationCount = NotificationService().inAppNotifications.length;
                  return Stack(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.notifications_outlined),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (context) => const NotificationsScreen()),
                          );
                        },
                      ),
                      if (notificationCount > 0)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: cs.error,
                              shape: BoxShape.circle,
                              border: Border.all(color: cs.surface, width: 1.5),
                            ),
                            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                            child: Text(
                              notificationCount > 9 ? '9+' : '$notificationCount',
                              style: TextStyle(color: cs.onError, fontSize: 10, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              await appState.startScan();
              appState.retryLocationBroadcast();
            },
            child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  const SosOrb(),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.devices, color: cs.secondary, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Nearby Devices',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: cs.onSurface),
                            ),
                            const Spacer(),
                            if (peers.isNotEmpty)
                              Text('${peers.length} device${peers.length > 1 ? 's' : ''}',
                                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _gpsStatusRow(cs),
                        if (peers.isEmpty)
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                'No nearby devices found',
                                style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: 0.35), fontStyle: FontStyle.italic),
                              ),
                            ),
                          )
                        else
                          ...peers.take(5).map((p) {
                            final isRescue = appState.isPeerRescue(p.name);
                            final isEmergencySOS = appState.isEmergencySOSPeer(p.name);
                            final isSOS = isEmergencySOS || appState.isSOSModePeer(p.name) || appState.isSOSPeer(p.name);
                            if (isEmergencySOS) {
                              return AnimatedBuilder(
                                animation: _blinkController,
                                builder: (ctx, _) {
                                  final blink = _blinkController.value;
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withValues(alpha: 0.06 + blink * 0.18),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Colors.red.withValues(alpha: 0.4 + blink * 0.6),
                                        width: 1.5 + blink * 1.5,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.red.withValues(alpha: blink * 0.3),
                                          blurRadius: 8 + blink * 8,
                                          spreadRadius: blink * 2,
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.crisis_alert, color: Color.lerp(Colors.red.shade700, Colors.red.shade300, blink)!, size: 18),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Flexible(
                                                    child: Text.rich(
                                                      TextSpan(
                                                        children: [
                                                          TextSpan(
                                                            text: p.name.isNotEmpty ? p.name : 'Unknown Device',
                                                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color.lerp(Colors.red.shade800, Colors.red.shade500, blink)!),
                                                          ),
                                                          TextSpan(
                                                            text: '  🚨 ฉุกเฉิน!',
                                                            style: TextStyle(fontSize: 11, color: Colors.red.shade700, fontWeight: FontWeight.w600),
                                                          ),
                                                        ],
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 5),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                    decoration: BoxDecoration(
                                                      color: Colors.red.withValues(alpha: 0.12),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      _distanceLabel(p.id) ?? '—',
                                                      style: TextStyle(fontSize: 10, color: Colors.red.shade700, fontWeight: FontWeight.w600),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        GestureDetector(
                                          onTap: () => Navigator.of(context).push(
                                            MaterialPageRoute(builder: (_) => EmergencyChatScreen(peer: p)),
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(8)),
                                            child: const Text('Chat', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            }
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isSOS
                                    ? Colors.red.withValues(alpha: 0.08)
                                    : isRescue
                                        ? cs.secondary.withValues(alpha: 0.08)
                                        : cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSOS
                                      ? Colors.red.withValues(alpha: 0.3)
                                      : isRescue
                                          ? cs.secondary.withValues(alpha: 0.3)
                                          : Colors.transparent,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isSOS ? Icons.warning_amber_rounded : isRescue ? Icons.local_hospital : Icons.device_hub,
                                    color: isSOS ? cs.error : isRescue ? cs.secondary : cs.onSurfaceVariant,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            p.name.isNotEmpty ? p.name : 'Unknown Device',
                                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: cs.onSurface),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: cs.surfaceContainerHighest,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            _distanceLabel(p.id) ?? '—',
                                            style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () => Navigator.of(context).push(
                                      MaterialPageRoute(builder: (_) => EmergencyChatScreen(peer: p)),
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isRescue ? cs.secondary : isSOS ? cs.error : Colors.green,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text('Chat', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
          ),
        );
      },
    );
  }
}

/// แสดงสถานะ scan + permission เพื่อ debug บนอุปกรณ์จริง
class _ScanDiagnosticBanner extends StatefulWidget {
  @override
  State<_ScanDiagnosticBanner> createState() => _ScanDiagnosticBannerState();
}

class _ScanDiagnosticBannerState extends State<_ScanDiagnosticBanner> {
  String? _missingPerm;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _checkPerms();
  }

  Future<void> _checkPerms() async {
    final missing = await NearbyTransport.checkPermissions();
    if (mounted) setState(() { _missingPerm = missing; _checked = true; });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final scanState = appState.transport.discoveryState;
    final scanError = appState.scanError;

    if (!_checked) return const SizedBox.shrink();

    // ทุกอย่างดี → ไม่แสดง banner
    if (_missingPerm == null && scanError == null && scanState == DiscoveryState.scanning) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.sensors, color: Colors.green, size: 16),
            const SizedBox(width: 8),
            Text('กำลังสแกน (${appState.selectedProtocol})', style: const TextStyle(fontSize: 12, color: Colors.green)),
          ],
        ),
      );
    }

    // มีปัญหา → แสดง error banner
    final isPermanentDenied = scanError?.contains('Settings') == true || scanError?.contains('PERM_PERMANENTLY') == true;
    final message = _missingPerm != null
        ? 'ยังไม่ได้อนุญาต: $_missingPerm'
        : scanError ??
            (scanState == DiscoveryState.idle
                ? 'Scan ยังไม่ได้เริ่ม (${appState.selectedProtocol})'
                : 'สถานะ: $scanState');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.error.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: cs.error, size: 16),
              const SizedBox(width: 6),
              Expanded(child: Text(message, style: TextStyle(fontSize: 12, color: cs.onErrorContainer))),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (isPermanentDenied || _missingPerm != null)
                TextButton.icon(
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  onPressed: () => openAppSettings(),
                  icon: const Icon(Icons.settings, size: 14),
                  label: const Text('เปิด Settings', style: TextStyle(fontSize: 12)),
                ),
              const SizedBox(width: 8),
              TextButton.icon(
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                onPressed: () async {
                  await appState.startScan();
                  _checkPerms();
                },
                icon: const Icon(Icons.refresh, size: 14),
                label: const Text('ลอง Scan ใหม่', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

