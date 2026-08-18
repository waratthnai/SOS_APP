import 'package:flutter/material.dart';
import 'package:offgrid_sos/core/transport.dart';
import 'package:offgrid_sos/core/app_state.dart';
import 'package:offgrid_sos/ui/emergency_chat_screen.dart';

class NearbyShareScreen extends StatefulWidget {
  const NearbyShareScreen({super.key});

  @override
  State<NearbyShareScreen> createState() => _NearbyShareScreenState();
}

class _NearbyShareScreenState extends State<NearbyShareScreen> {
  final _msgCtrl = TextEditingController();
  Peer? _selected;

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final peers = appState.peers;
    final msgs = appState.messages;
    final currentProtocol = appState.selectedProtocol; // 🔧 เพิ่มตัวแปร

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Share (Demo)'),
        actions: [
          IconButton(
            tooltip:
                appState.transport.discoveryState == DiscoveryState.scanning
                ? 'Stop Scan'
                : 'Scan',
            onPressed: () {
              // ⚡ Real-time: แสดงผลทันทีและทำงาน background
              final isScanning = appState.transport.discoveryState == DiscoveryState.scanning;
              
              if (isScanning) {
                // แสดงผลทันที
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('⏸️ หยุดการสแกน...'),
                    duration: Duration(milliseconds: 800),
                  ),
                );
                setState(() {}); // refresh UI ทันที
                
                // ทำงานใน background
                appState.stopScan().then((_) {
                  if (mounted) {
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      const SnackBar(
                        content: Text('✅ หยุดการสแกนแล้ว'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  }
                });
              } else {
                // แสดงผลทันที
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('🔍 กำลังค้นหาอุปกรณ์...'),
                    duration: Duration(milliseconds: 800),
                  ),
                );
                setState(() {}); // refresh UI ทันที
                
                // ทำงานใน background
                appState.startScan().then((_) {
                  if (mounted) {
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      const SnackBar(
                        content: Text('✅ กำลังค้นหาอุปกรณ์รอบข้าง'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  }
                });
              }
            },
            icon: Icon(
              appState.transport.discoveryState == DiscoveryState.scanning
                  ? Icons.stop_circle_outlined
                  : Icons.sensors,
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // กล่องพิมพ์ข้อความ
            TextField(
              controller: _msgCtrl,
              decoration: const InputDecoration(
                labelText: 'Message / Coordinates',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 12),

            // ปุ่มส่ง
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: peers.isEmpty
                        ? null
                        : () {
                            if (_msgCtrl.text.isNotEmpty) {
                              appState.send(_msgCtrl.text); // ⚡ ไม่ await
                              _msgCtrl.clear();
                            }
                          },
                    icon: const Icon(Icons.wifi_tethering),
                    label: const Text('Broadcast'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (_selected != null && _msgCtrl.text.isNotEmpty)
                        ? () {
                            appState.send(_msgCtrl.text, to: _selected); // ⚡ ไม่ await
                            _msgCtrl.clear();
                          }
                        : null,
                    icon: const Icon(Icons.send),
                    label: const Text('Send to Selected'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // รายชื่อเพื่อนที่ค้นพบ
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Discovered devices',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              flex: 1,
              child: peers.isEmpty
                  ? Card(
                      child: ListTile(
                        leading: Icon(Icons.info, color: cs.primary),
                        title: Text(
                          // 🔧 แสดงสถานะเฉพาะสำหรับ WiFi Direct
                          currentProtocol == 'wifi_direct'
                              ? '⚠️ WiFi Direct ต้องมี 2 เครื่องเปิดพร้อมกัน'
                              : 'No devices yet'
                        ),
                        subtitle: Text(
                          currentProtocol == 'wifi_direct'
                              ? 'เปิด WiFi Direct บนอุปกรณ์อีกเครื่อง แล้วกด Scan'
                              : 'Tap the sensor icon to Scan'
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: peers.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final p = peers[i];
                        final selected = _selected?.id == p.id;
                        return ListTile(
                          leading: Icon(
                            Icons.device_hub,
                            color: selected ? cs.primary : null,
                          ),
                          title: Text(
                            p.name.isNotEmpty ? p.name : 'อุปกรณ์ไม่ระบุชื่อ',
                          ),
                          subtitle: Text('ID: ${p.id}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.chat, color: Colors.green),
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          EmergencyChatScreen(peer: p),
                                    ),
                                  );
                                },
                                tooltip: 'แชทกับอุปกรณ์นี้',
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                selected
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                color: selected ? cs.primary : null,
                              ),
                            ],
                          ),
                          selected: selected,
                          onTap: () => setState(() => _selected = p),
                        );
                      },
                    ),
            ),

            const SizedBox(height: 12),

            // ประวัติข้อความ
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Messages',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              flex: 1,
              child: Card(
                child: ListView.separated(
                  padding: const EdgeInsets.all(8),
                  itemCount: msgs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final m = msgs[i];
                    final incoming = m.fromPeerId != 'me';
                    return ListTile(
                      leading: Icon(incoming ? Icons.device_hub : Icons.person),
                      title: Text(m.body),
                      subtitle: Text(
                        'From: ${m.fromPeerId}${m.toPeerId != null ? ' → ${m.toPeerId}' : ''}',
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

