import 'package:flutter/material.dart';

/// แจ้งเตือนเมื่อ E2EE identity key ของ peer เปลี่ยนจากที่เคย trust ไว้ (TOFU mismatch)
class KeyMismatchBanner extends StatelessWidget {
  final String peerName;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;
  const KeyMismatchBanner({
    super.key,
    required this.peerName,
    required this.onAccept,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.orange.shade900.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'คีย์เข้ารหัสของ $peerName เปลี่ยนจากครั้งก่อน — ข้อความจะยังเข้ารหัสด้วยคีย์เดิมจนกว่าคุณจะยืนยันตัวตนแล้วกดรับคีย์ใหม่',
                  style: const TextStyle(color: Colors.orange, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onDismiss,
                child: const Text('ปิด', style: TextStyle(fontSize: 12)),
              ),
              TextButton(
                onPressed: onAccept,
                child: const Text(
                  'ยืนยันรับคีย์ใหม่',
                  style: TextStyle(fontSize: 12, color: Colors.orange),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
