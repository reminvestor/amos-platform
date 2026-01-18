import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/chat.dart';

void main() {
  group('MessageRole', () {
    test('value returns correct string', () {
      expect(MessageRole.user.value, equals('user'));
      expect(MessageRole.assistant.value, equals('assistant'));
    });

    test('fromString converts string to enum correctly', () {
      expect(MessageRoleX.fromString('user'), equals(MessageRole.user));
      expect(MessageRoleX.fromString('assistant'), equals(MessageRole.assistant));
    });

    test('fromString returns user for unknown values', () {
      expect(MessageRoleX.fromString('unknown'), equals(MessageRole.user));
      expect(MessageRoleX.fromString(''), equals(MessageRole.user));
    });
  });

  group('ChatMessage', () {
    test('fromJson parses complete JSON correctly', () {
      final json = {
        'id': 'msg-123',
        'role': 'assistant',
        'content': 'Hello, how can I help you?',
        'timestamp': '2024-01-15T10:30:00.000Z',
        'is_streaming': false,
        'metadata': {'agent': 'support'},
      };

      final message = ChatMessage.fromJson(json);

      expect(message.id, equals('msg-123'));
      expect(message.role, equals(MessageRole.assistant));
      expect(message.content, equals('Hello, how can I help you?'));
      expect(message.timestamp, equals(DateTime.parse('2024-01-15T10:30:00.000Z')));
      expect(message.isStreaming, isFalse);
      expect(message.metadata, equals({'agent': 'support'}));
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'id': 'msg-123',
        'timestamp': '2024-01-15T10:30:00.000Z',
      };

      final message = ChatMessage.fromJson(json);

      expect(message.id, equals('msg-123'));
      expect(message.role, equals(MessageRole.user));
      expect(message.content, equals(''));
      expect(message.isStreaming, isFalse);
      expect(message.metadata, isNull);
    });

    test('toJson serializes correctly', () {
      final message = ChatMessage(
        id: 'msg-123',
        role: MessageRole.assistant,
        content: 'Test content',
        timestamp: DateTime.parse('2024-01-15T10:30:00.000Z'),
        isStreaming: true,
        metadata: {'key': 'value'},
      );

      final json = message.toJson();

      expect(json['id'], equals('msg-123'));
      expect(json['role'], equals('assistant'));
      expect(json['content'], equals('Test content'));
      expect(json['timestamp'], equals('2024-01-15T10:30:00.000Z'));
      expect(json['is_streaming'], isTrue);
      expect(json['metadata'], equals({'key': 'value'}));
    });

    test('toJson excludes null metadata', () {
      final message = ChatMessage(
        id: 'msg-123',
        role: MessageRole.user,
        content: 'Test',
        timestamp: DateTime.parse('2024-01-15T10:30:00.000Z'),
      );

      final json = message.toJson();

      expect(json.containsKey('metadata'), isFalse);
    });

    test('copyWith creates new message with updated values', () {
      final original = ChatMessage(
        id: 'msg-123',
        role: MessageRole.assistant,
        content: 'Original content',
        timestamp: DateTime.parse('2024-01-15T10:30:00.000Z'),
        isStreaming: true,
      );

      final modified = original.copyWith(
        content: 'Modified content',
        isStreaming: false,
      );

      expect(modified.id, equals('msg-123'));
      expect(modified.role, equals(MessageRole.assistant));
      expect(modified.content, equals('Modified content'));
      expect(modified.isStreaming, isFalse);
      expect(original.content, equals('Original content'));
      expect(original.isStreaming, isTrue);
    });

    test('copyWith preserves unmodified values', () {
      final original = ChatMessage(
        id: 'msg-123',
        role: MessageRole.user,
        content: 'Test content',
        timestamp: DateTime.parse('2024-01-15T10:30:00.000Z'),
        isStreaming: false,
        metadata: {'key': 'value'},
      );

      final modified = original.copyWith(content: 'New content');

      expect(modified.id, equals('msg-123'));
      expect(modified.role, equals(MessageRole.user));
      expect(modified.timestamp, equals(original.timestamp));
      expect(modified.isStreaming, isFalse);
      expect(modified.metadata, equals({'key': 'value'}));
    });

    test('default isStreaming is false', () {
      final message = ChatMessage(
        id: 'msg-123',
        role: MessageRole.user,
        content: 'Test',
        timestamp: DateTime.now(),
      );

      expect(message.isStreaming, isFalse);
    });
  });
}
