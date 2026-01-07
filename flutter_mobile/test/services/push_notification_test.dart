import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/services/push_notification_service.dart';

void main() {
  group('NotificationType', () {
    test('enum values exist', () {
      expect(NotificationType.values, contains(NotificationType.teamMessage));
      expect(NotificationType.values, contains(NotificationType.directMessage));
      expect(NotificationType.values, contains(NotificationType.mention));
      expect(NotificationType.values, contains(NotificationType.agentUpdate));
    });
  });

  group('NotificationPayload', () {
    test('toJson serializes correctly', () {
      final payload = NotificationPayload(
        type: NotificationType.teamMessage,
        threadId: 123,
        channelId: 456,
        messageId: 789,
      );

      final json = payload.toJson();

      expect(json, contains('"type":"teamMessage"'));
      expect(json, contains('"threadId":123'));
      expect(json, contains('"channelId":456'));
      expect(json, contains('"messageId":789'));
    });

    test('toJson handles null values', () {
      final payload = NotificationPayload(
        type: NotificationType.directMessage,
        threadId: 100,
      );

      final json = payload.toJson();

      expect(json, contains('"type":"directMessage"'));
      expect(json, contains('"threadId":100'));
      expect(json, contains('"channelId":null'));
      expect(json, contains('"messageId":null'));
    });

    test('fromJson parses team message payload', () {
      const json = '{"type":"teamMessage","threadId":123,"channelId":456,"messageId":789}';

      final payload = NotificationPayload.fromJson(json);

      expect(payload.type, equals(NotificationType.teamMessage));
      expect(payload.threadId, equals(123));
      expect(payload.channelId, equals(456));
      expect(payload.messageId, equals(789));
    });

    test('fromJson parses direct message payload', () {
      const json = '{"type":"directMessage","threadId":100,"channelId":null,"messageId":200}';

      final payload = NotificationPayload.fromJson(json);

      expect(payload.type, equals(NotificationType.directMessage));
      expect(payload.threadId, equals(100));
      expect(payload.channelId, isNull);
      expect(payload.messageId, equals(200));
    });

    test('fromJson handles unknown type', () {
      const json = '{"type":"unknownType","threadId":1,"channelId":null,"messageId":null}';

      final payload = NotificationPayload.fromJson(json);

      // Should default to teamMessage for unknown types
      expect(payload.type, equals(NotificationType.teamMessage));
    });

    test('fromJson handles mention type', () {
      const json = '{"type":"mention","threadId":50,"channelId":60,"messageId":70}';

      final payload = NotificationPayload.fromJson(json);

      expect(payload.type, equals(NotificationType.mention));
      expect(payload.threadId, equals(50));
      expect(payload.channelId, equals(60));
      expect(payload.messageId, equals(70));
    });

    test('fromJson handles agentUpdate type', () {
      const json = '{"type":"agentUpdate","threadId":10,"channelId":null,"messageId":20}';

      final payload = NotificationPayload.fromJson(json);

      expect(payload.type, equals(NotificationType.agentUpdate));
      expect(payload.threadId, equals(10));
      expect(payload.messageId, equals(20));
    });

    test('roundtrip serialization works', () {
      final original = NotificationPayload(
        type: NotificationType.mention,
        threadId: 999,
        channelId: 888,
        messageId: 777,
      );

      final json = original.toJson();
      final parsed = NotificationPayload.fromJson(json);

      expect(parsed.type, equals(original.type));
      expect(parsed.threadId, equals(original.threadId));
      expect(parsed.channelId, equals(original.channelId));
      expect(parsed.messageId, equals(original.messageId));
    });
  });
}
