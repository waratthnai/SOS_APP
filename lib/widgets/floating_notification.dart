import 'package:flutter/material.dart';
import '../core/notification_service.dart';

/// แสดงการแจ้งเตือนแบบ floating ที่มุมบนขวา (เหมือน chat heads)
class FloatingNotificationOverlay extends StatefulWidget {
  final Widget child;

  const FloatingNotificationOverlay({
    super.key,
    required this.child,
  });

  @override
  State<FloatingNotificationOverlay> createState() => _FloatingNotificationOverlayState();
}

class _FloatingNotificationOverlayState extends State<FloatingNotificationOverlay>
    with SingleTickerProviderStateMixin {
  InAppNotification? _currentNotification;
  AnimationController? _animationController;
  Animation<Offset>? _slideAnimation;

  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController!,
      curve: Curves.easeOut,
    ));

    // ฟังการเปลี่ยนแปลงของ notifications
    NotificationService().addListener(_onNotificationChanged);
  }

  @override
  void dispose() {
    NotificationService().removeListener(_onNotificationChanged);
    _animationController?.dispose();
    super.dispose();
  }

  void _onNotificationChanged() {
    final notifications = NotificationService().inAppNotifications;
    
    debugPrint('🔔 [FloatingNotification] Notification changed: ${notifications.length} total');
    
    if (notifications.isEmpty) {
      // ไม่มี notification → ซ่อน
      if (_currentNotification != null) {
        debugPrint('🔔 [FloatingNotification] Hiding notification');
        _animationController?.reverse().then((_) {
          if (mounted) {
            setState(() {
              _currentNotification = null;
            });
          }
        });
      }
    } else {
      // มี notification ใหม่ → แสดง
      final latest = notifications.first;
      debugPrint('🔔 [FloatingNotification] Latest: ${latest.title} - ${latest.message}');
      if (_currentNotification?.id != latest.id) {
        debugPrint('🔔 [FloatingNotification] Showing new notification');
        setState(() {
          _currentNotification = latest;
        });
        _animationController?.forward();
        
        // ซ่อนอัตโนมัติหลัง 5 วินาที (ถ้าไม่ใช่ emergency)
        if (latest.type != NotificationType.emergency) {
          Future.delayed(const Duration(seconds: 5), () {
            if (mounted && _currentNotification?.id == latest.id) {
              debugPrint('🔔 [FloatingNotification] Auto-hiding notification');
              _animationController?.reverse().then((_) {
                if (mounted) {
                  setState(() {
                    _currentNotification = null;
                  });
                }
              });
            }
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          widget.child,
          if (_currentNotification != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 8,
              right: 8,
              child: SlideTransition(
                position: _slideAnimation!,
                child: _buildFloatingNotification(context, _currentNotification!),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFloatingNotification(BuildContext context, InAppNotification notification) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    
    Color backgroundColor;
    Color iconColor;
    
    switch (notification.type) {
      case NotificationType.emergency:
        backgroundColor = Colors.red.shade900;
        iconColor = Colors.white;
        break;
      case NotificationType.warning:
        backgroundColor = Colors.orange.shade900;
        iconColor = Colors.white;
        break;
      case NotificationType.success:
        backgroundColor = Colors.green.shade900;
        iconColor = Colors.white;
        break;
      case NotificationType.info:
      default:
        backgroundColor = cs.surfaceContainerHighest;
        iconColor = cs.primary;
    }

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      color: backgroundColor,
      child: InkWell(
        onTap: () {
          // เรียก onReply ถ้ามี (สำหรับข้อความแชท)
          if (notification.onReply != null) {
            notification.onReply!();
            _animationController?.reverse().then((_) {
              if (mounted) {
                setState(() {
                  _currentNotification = null;
                });
              }
            });
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  notification.type.icon,
                  color: iconColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      notification.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: notification.type == NotificationType.info
                            ? cs.onSurface
                            : Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification.message,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: notification.type == NotificationType.info
                            ? cs.onSurfaceVariant
                            : Colors.white.withOpacity(0.9),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              
              // Close button
              IconButton(
                icon: Icon(
                  Icons.close,
                  color: notification.type == NotificationType.info
                      ? cs.onSurfaceVariant
                      : Colors.white,
                  size: 20,
                ),
                onPressed: () {
                  NotificationService().clearNotification(notification.id);
                  _animationController?.reverse().then((_) {
                    if (mounted) {
                      setState(() {
                        _currentNotification = null;
                      });
                    }
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
