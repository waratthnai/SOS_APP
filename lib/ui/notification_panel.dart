import 'package:flutter/material.dart';
import '../core/notification_service.dart';

class NotificationPanel extends StatefulWidget {
  const NotificationPanel({super.key});

  @override
  State<NotificationPanel> createState() => _NotificationPanelState();
}

class _NotificationPanelState extends State<NotificationPanel> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    
    return ListenableBuilder(
      listenable: NotificationService(),
      builder: (context, child) {
        final notifications = NotificationService().inAppNotifications;
        
        if (notifications.isEmpty) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: Text(
                  'ไม่มีการแจ้งเตือน',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        }

        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final notification = notifications[index];
              return _buildNotificationCard(context, notification);
            },
            childCount: notifications.length,
          ),
        );
      },
    );
  }

  Widget _buildNotificationCard(BuildContext context, InAppNotification notification) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    
    // ตรวจสอบว่ามีปุ่มตอบกลับหรือไม่ (ใช้สำหรับข้อความแชท)
    final hasReplyButton = notification.onReply != null;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cs.outlineVariant,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                notification.type.icon,
                color: cs.primary,
                size: 24,
              ),
            ),
            title: Text(
              notification.title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  notification.message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _formatTimestamp(notification.timestamp),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.outline,
                  ),
                ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.close, size: 20),
              color: cs.onSurfaceVariant,
              onPressed: () {
                NotificationService().clearNotification(notification.id);
              },
            ),
            isThreeLine: true,
          ),
          // แสดงปุ่มตอบกลับถ้ามี callback
          if (hasReplyButton)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FilledButton.icon(
                    onPressed: () {
                      // เรียก callback ที่ส่งมา
                      notification.onReply?.call();
                      // ลบการแจ้งเตือนหลังจากกดตอบกลับ
                      NotificationService().clearNotification(notification.id);
                    },
                    icon: const Icon(Icons.reply, size: 18),
                    label: const Text('ตอบกลับ'),
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.primaryContainer,
                      foregroundColor: cs.onPrimaryContainer,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }
}