import 'package:flutter/material.dart';
import 'package:offgrid_sos/core/notification_service.dart';
import 'package:offgrid_sos/ui/notification_panel.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 120,
            automaticallyImplyLeading: false,
            flexibleSpace: FlexibleSpaceBar(
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cs.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.notifications_active,
                      color: cs.error,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('การแจ้งเตือน', style: theme.textTheme.headlineSmall),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              titlePadding: const EdgeInsets.only(left: 16, right: 8, bottom: 8),
            ),
            actions: [
              ListenableBuilder(
                listenable: NotificationService(),
                builder: (context, child) {
                  final hasNotifications =
                      NotificationService().inAppNotifications.isNotEmpty;
                  return hasNotifications
                      ? IconButton(
                          icon: const Icon(Icons.clear_all),
                          onPressed: () {
                            NotificationService().clearAllNotifications();
                          },
                        )
                      : const SizedBox.shrink();
                },
              ),
            ],
          ),
          const NotificationPanel(),
        ],
      ),
    );
  }
}
