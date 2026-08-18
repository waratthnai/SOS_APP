import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:offgrid_sos/core/app_state.dart';
import 'package:offgrid_sos/core/chat_models.dart';
import 'package:offgrid_sos/widgets/chat_video_player.dart';
import 'package:offgrid_sos/widgets/full_screen_image_viewer.dart';
import 'package:offgrid_sos/widgets/message_status_icon.dart';

/// บับเบิลข้อความสำหรับแชทฉุกเฉิน P2P (ใช้ [ChatMessage]) — ดู `friend_chat_screen.dart`
/// สำหรับบับเบิลข้อความแชทเพื่อนออนไลน์ ที่ใช้ type คนละแบบ ([FriendChatMessage])
class EmergencyMessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isFromMe;
  final String peerName;

  const EmergencyMessageBubble({
    super.key,
    required this.message,
    required this.isFromMe,
    required this.peerName,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isFromMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isFromMe) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.red.withValues(alpha: 0.2),
              child: Icon(Icons.phone_android, size: 14, color: Colors.red),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: GestureDetector(
              // 🗑️ กดค้างเพื่อลบข้อความ
              onLongPress: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('ลบข้อความ'),
                    content: const Text('คุณต้องการลบข้อความนี้หรือไม่?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('ยกเลิก'),
                      ),
                      TextButton(
                        onPressed: () async {
                          Navigator.pop(context);
                          // ลบข้อความ
                          await appState.deleteMessage(message.id);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('✅ ลบข้อความแล้ว'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          }
                        },
                        child: const Text(
                          'ลบ',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                );
              },
              child: Column(
                crossAxisAlignment: isFromMe
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  if (!isFromMe)
                    Padding(
                      padding: const EdgeInsets.only(left: 12, bottom: 4),
                      child: Text(
                        peerName.isNotEmpty ? peerName : 'อุปกรณ์ฉุกเฉิน',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withValues(alpha: 0.6),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isFromMe ? Colors.red : cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(18).copyWith(
                        bottomRight: isFromMe ? const Radius.circular(4) : null,
                        bottomLeft: !isFromMe ? const Radius.circular(4) : null,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 📷 แสดงรูปภาพ (ถ้ามี)
                        if (message.hasImage && message.filePath != null) ...[
                          GestureDetector(
                            onTap: () => openFullScreenImage(
                              context,
                              heroTag: 'img_${message.id}',
                              filePath: message.filePath!,
                            ),
                            child: Hero(
                              tag: 'img_${message.id}',
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.file(
                                  File(message.filePath!),
                                  width: 200,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      padding: const EdgeInsets.all(16),
                                      color: Colors.red.withValues(alpha: 0.1),
                                      child: Column(
                                        children: [
                                          const Icon(
                                            Icons.error_outline,
                                            color: Colors.red,
                                          ),
                                          const SizedBox(height: 8),
                                          const Text(
                                            'ไม่สามารถโหลดรูปภาพได้',
                                            style: TextStyle(fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                          if (message.text != null && message.text!.isNotEmpty)
                            const SizedBox(height: 8),
                        ],
                        // 🎥 แสดงวิดีโอ (ถ้ามี)
                        if (message.hasVideo && message.filePath != null) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: ChatVideoPlayer(
                              videoPath: message.filePath!,
                            ),
                          ),
                          if (message.text != null && message.text!.isNotEmpty)
                            const SizedBox(height: 8),
                        ],
                        // ข้อความ (ถ้ามี)
                        if (message.text != null && message.text!.isNotEmpty)
                          _buildTextContent(message.text!, isFromMe, cs),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${message.time.hour.toString().padLeft(2, '0')}:${message.time.minute.toString().padLeft(2, '0')}',
                              style: TextStyle(
                                fontSize: 11,
                                color: isFromMe
                                    ? Colors.white.withValues(alpha: 0.8)
                                    : cs.onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                            // 📊 แสดงสถานะข้อความ + retry button (สำหรับข้อความที่เราส่ง)
                            if (isFromMe) ...[
                              const SizedBox(width: 4),
                              if (message.status == MessageStatus.pending)
                                GestureDetector(
                                  onTap: () =>
                                      appState.retrySendMessage(message.id),
                                  child: const Icon(
                                    Icons.refresh,
                                    size: 14,
                                    color: Colors.orange,
                                  ),
                                )
                              else
                                // isRead: true = peer เปิดอ่านแล้ว (read receipt) — โชว์เป็นติ๊กฟ้า
                                // แบบเดียวกับที่ friend_chat_screen ใช้ (ทับความหมาย MessageStatus.synced เดิม)
                                MessageStatusIcon(
                                  status: message.isRead
                                      ? MessageStatus.synced
                                      : message.status,
                                  size: 12,
                                ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextContent(String text, bool isFromMe, ColorScheme cs) {
    final mapsUrl = _extractMapsUrl(text);
    if (mapsUrl == null) {
      return Text(
        text,
        style: TextStyle(
          color: isFromMe ? Colors.white : cs.onSurface,
          fontSize: 15,
        ),
      );
    }

    // แสดง location card
    final lines = text
        .split('\n')
        .where((l) => !l.startsWith('http'))
        .join('\n');
    return GestureDetector(
      onTap: () =>
          launchUrl(Uri.parse(mapsUrl), mode: LaunchMode.externalApplication),
      child: Container(
        decoration: BoxDecoration(
          color: isFromMe
              ? Colors.white.withValues(alpha: 0.15)
              : cs.primaryContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isFromMe
                ? Colors.white.withValues(alpha: 0.3)
                : cs.primary.withValues(alpha: 0.3),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.location_on,
              color: isFromMe ? Colors.white : cs.primary,
              size: 20,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lines.trim(),
                    style: TextStyle(
                      color: isFromMe ? Colors.white : cs.onSurface,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'แตะเพื่อเปิด Google Maps',
                    style: TextStyle(
                      color: isFromMe ? Colors.white70 : cs.primary,
                      fontSize: 12,
                      decoration: TextDecoration.underline,
                      decorationColor: isFromMe ? Colors.white70 : cs.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _extractMapsUrl(String text) {
    final match = RegExp(r'https://www\.google\.com/maps\S+').firstMatch(text);
    return match?.group(0);
  }
}
