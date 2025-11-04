// test/chat_models_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:offgrid_sos/core/chat_models.dart';

void main() {
  group('ChatMessage Model Tests', () {
    test('Test 21: Should create text message correctly', () {
      final now = DateTime.now();
      final message = ChatMessage(
        id: '1',
        from: 'Alice',
        type: ChatType.text,
        text: 'Hello',
        time: now,
        isEmergency: false,
      );

      expect(message.id, '1');
      expect(message.from, 'Alice');
      expect(message.text, 'Hello');
      expect(message.time, now);
      expect(message.isEmergency, false);
      expect(message.filePath, null);
      expect(message.type, ChatType.text);
    });

    test('Test 22: Should create image message correctly', () {
      final message = ChatMessage(
        id: '2',
        from: 'Bob',
        type: ChatType.image,
        filePath: '/path/to/image.jpg',
        time: DateTime.now(),
        isEmergency: false,
      );

      expect(message.filePath, '/path/to/image.jpg');
      expect(message.type, ChatType.image);
      expect(message.hasImage, true);
      expect(message.text, null);
    });

    test('Test 23: Should create video message correctly', () {
      final message = ChatMessage(
        id: '3',
        from: 'Charlie',
        type: ChatType.video,
        filePath: '/path/to/video.mp4',
        time: DateTime.now(),
        isEmergency: false,
      );

      expect(message.filePath, '/path/to/video.mp4');
      expect(message.type, ChatType.video);
      expect(message.hasVideo, true);
      expect(message.text, null);
    });

    test('Test 24: Should create emergency message correctly', () {
      final message = ChatMessage(
        id: '4',
        from: 'Emergency',
        type: ChatType.text,
        text: 'SOS - Need help!',
        time: DateTime.now(),
        isEmergency: true,
      );

      expect(message.isEmergency, true);
      expect(message.text, contains('SOS'));
    });

    test('Test 25: Should convert to/from JSON correctly', () {
      final now = DateTime.now();
      final original = ChatMessage(
        id: '5',
        from: 'David',
        type: ChatType.text,
        text: 'Test message',
        time: now,
        isEmergency: false,
      );

      final json = original.toJson();
      final restored = ChatMessage.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.from, original.from);
      expect(restored.text, original.text);
      expect(restored.isEmergency, original.isEmergency);
      expect(restored.type, original.type);
    });

    test('Test 26: Should have correct helper getters', () {
      final textMsg = ChatMessage(
        id: '6',
        from: 'Test',
        type: ChatType.text,
        text: 'Hello',
        time: DateTime.now(),
      );

      final imageMsg = ChatMessage(
        id: '7',
        from: 'Test',
        type: ChatType.image,
        filePath: '/image.jpg',
        time: DateTime.now(),
      );

      expect(textMsg.hasText, true);
      expect(textMsg.hasImage, false);
      expect(textMsg.hasVideo, false);

      expect(imageMsg.hasImage, true);
      expect(imageMsg.hasText, false);
      expect(imageMsg.hasVideo, false);
    });

    test('Test 27: Should default isEmergency to false', () {
      final message = ChatMessage(
        id: '8',
        from: 'Test',
        type: ChatType.text,
        text: 'Normal message',
        time: DateTime.now(),
      );

      expect(message.isEmergency, false);
    });
  });
}
