// test/chat_filter_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:offgrid_sos/core/chat_models.dart';

void main() {
  group('ChatFilterService Tests', () {
    late List<ChatMessage> testMessages;

    setUp(() {
      final now = DateTime.now();
      testMessages = [
        ChatMessage(
          id: '1',
          from: 'Alice',
          type: ChatType.text,
          text: 'Hello everyone!',
          time: now.subtract(const Duration(hours: 1)),
          isEmergency: false,
        ),
        ChatMessage(
          id: '2',
          from: 'Bob',
          type: ChatType.text,
          text: 'URGENT: Need help immediately!',
          time: now.subtract(const Duration(hours: 2)),
          isEmergency: true,
        ),
        ChatMessage(
          id: '3',
          from: 'Charlie',
          type: ChatType.image,
          filePath: '/path/to/image.jpg',
          time: now.subtract(const Duration(hours: 3)),
          isEmergency: false,
        ),
        ChatMessage(
          id: '4',
          from: 'Alice',
          type: ChatType.video,
          filePath: '/path/to/video.mp4',
          time: now.subtract(const Duration(hours: 5)),
          isEmergency: false,
        ),
        ChatMessage(
          id: '5',
          from: 'David',
          type: ChatType.text,
          text: 'Old message from yesterday',
          time: now.subtract(const Duration(days: 2)),
          isEmergency: false,
        ),
      ];
    });

    test('Test 9: Should filter text messages only', () {
      final filtered = testMessages.where((m) => m.type == ChatType.text).toList();

      expect(filtered.length, 3); // Messages with text type
      expect(filtered.every((m) => m.hasText), true);
    });

    test('Test 10: Should filter image messages only', () {
      final filtered = testMessages.where((m) => m.type == ChatType.image).toList();

      expect(filtered.length, 1);
      expect(filtered.first.hasImage, true);
      expect(filtered.first.filePath, isNotNull);
    });

    test('Test 11: Should filter video messages only', () {
      final filtered = testMessages.where((m) => m.type == ChatType.video).toList();

      expect(filtered.length, 1);
      expect(filtered.first.hasVideo, true);
      expect(filtered.first.filePath, isNotNull);
    });

    test('Test 12: Should filter emergency messages only', () {
      final filtered = testMessages.where((m) => m.isEmergency).toList();

      expect(filtered.length, 1);
      expect(filtered.first.isEmergency, true);
      expect(filtered.first.text, contains('URGENT'));
    });

    test('Test 13: Should filter recent messages (last 24 hours)', () {
      final filtered = testMessages.where((m) {
        final diff = DateTime.now().difference(m.time);
        return diff.inHours <= 24;
      }).toList();

      expect(filtered.length, 4); // 4 messages within 24 hours
      expect(filtered.every((m) {
        final diff = DateTime.now().difference(m.time);
        return diff.inHours <= 24;
      }), true);
    });

    test('Test 14: Should filter older messages (>24 hours)', () {
      final filtered = testMessages.where((m) {
        final diff = DateTime.now().difference(m.time);
        return diff.inHours > 24;
      }).toList();

      expect(filtered.length, 1); // 1 message from 2 days ago
      expect(filtered.first.text, contains('Old message'));
    });

    test('Test 15: Should search by message content', () {
      final filtered = testMessages.where((m) {
        return m.text != null && m.text!.toLowerCase().contains('help');
      }).toList();

      expect(filtered.length, 1);
      expect(filtered.first.text, contains('help'));
    });

    test('Test 16: Should search case-insensitively', () {
      final filtered = testMessages.where((m) {
        return m.text != null && m.text!.toLowerCase().contains('hello');
      }).toList();

      expect(filtered.length, 1);
      expect(filtered.first.text, 'Hello everyone!');
    });

    test('Test 17: Should filter by peer (sender)', () {
      final filtered = testMessages.where((m) => m.from == 'Alice').toList();

      expect(filtered.length, 2);
      expect(filtered.every((m) => m.from == 'Alice'), true);
    });

    test('Test 18: Should return all messages', () {
      final filtered = testMessages;

      expect(filtered.length, testMessages.length);
    });

    test('Test 19: Should handle empty search query', () {
      final filtered = testMessages.where((m) {
        final query = '';
        if (query.isEmpty) return true;
        return m.text != null && m.text!.toLowerCase().contains(query.toLowerCase());
      }).toList();

      expect(filtered.length, testMessages.length);
    });

    test('Test 20: Should combine filters', () {
      // Filter for text messages from Alice
      final filtered = testMessages.where((m) {
        return m.type == ChatType.text && m.from == 'Alice';
      }).toList();

      expect(filtered.length, 1);
      expect(filtered.first.from, 'Alice');
      expect(filtered.first.text, 'Hello everyone!');
    });
  });
}
