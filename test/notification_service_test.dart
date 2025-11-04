// test/notification_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:offgrid_sos/core/notification_service.dart';

void main() {
  group('NotificationService Tests', () {
    late NotificationService notificationService;

    setUp(() {
      notificationService = NotificationService();
      notificationService.clearAllNotifications();
    });

    test('Test 1: Should add SOS notification', () {
      notificationService.showSOSNotification('SOS signal received from nearby device');

      expect(notificationService.inAppNotifications.length, 1);
      expect(notificationService.inAppNotifications.first.type, NotificationType.emergency);
      expect(notificationService.inAppNotifications.first.title, '🆘 EMERGENCY');
    });

    test('Test 2: Should add device notification', () {
      notificationService.showDeviceNotification('Device123', true);

      expect(notificationService.inAppNotifications.length, 1);
      expect(notificationService.inAppNotifications.first.message, contains('Device123'));
    });

    test('Test 3: Should add message notification', () {
      notificationService.showMessageNotification('User123', 'Hello there!');

      expect(notificationService.inAppNotifications.length, 1);
      expect(notificationService.inAppNotifications.first.type, NotificationType.info);
      expect(notificationService.inAppNotifications.first.message, contains('User123'));
    });

    test('Test 4: Should limit notifications to 20', () {
      // Add 25 notifications
      for (int i = 0; i < 25; i++) {
        notificationService.showMessageNotification('User$i', 'Message $i');
      }

      expect(notificationService.inAppNotifications.length, 20);
      // Should keep newest 20 (0-19, removing oldest)
      expect(notificationService.inAppNotifications.first.message, contains('User24'));
    });

    test('Test 5: Should clear individual notification', () async {
      notificationService.showSOSNotification('Alert 1');
      await Future.delayed(const Duration(milliseconds: 2));
      notificationService.showSOSNotification('Alert 2');
      await Future.delayed(const Duration(milliseconds: 2));
      notificationService.showSOSNotification('Alert 3');

      expect(notificationService.inAppNotifications.length, 3);

      // Notifications are inserted at index 0, so [0] is newest (Alert 3)
      final idToRemove = notificationService.inAppNotifications[1].id; // Alert 2
      notificationService.clearNotification(idToRemove);

      expect(notificationService.inAppNotifications.length, 2);
      expect(notificationService.inAppNotifications.any((n) => n.id == idToRemove), false);
    });

    test('Test 6: Should clear all notifications', () {
      notificationService.showSOSNotification('Alert 1');
      notificationService.showDeviceNotification('Device1', true);
      notificationService.showMessageNotification('User1', 'Message');

      expect(notificationService.inAppNotifications.length, 3);

      notificationService.clearAllNotifications();

      expect(notificationService.inAppNotifications.length, 0);
    });

    test('Test 7: Should notify listeners on change', () {
      bool listenerCalled = false;
      
      notificationService.addListener(() {
        listenerCalled = true;
      });

      notificationService.showSOSNotification('Test');

      expect(listenerCalled, true);
    });

    test('Test 8: Should have correct type for device connection/disconnection', () {
      notificationService.showDeviceNotification('Device1', true);
      notificationService.showDeviceNotification('Device2', false);

      expect(notificationService.inAppNotifications[1].type, NotificationType.success); // connected
      expect(notificationService.inAppNotifications[0].type, NotificationType.warning); // disconnected
    });
  });
}
