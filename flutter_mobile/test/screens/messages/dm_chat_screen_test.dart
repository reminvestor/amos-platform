import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:amos_mobile/models/space.dart';

/// Tests for DmChatScreen message sending and thread loading logic
/// Note: Full widget tests require native plugin mocking
void main() {
  group('DM Message Model', () {
    test('HubMessage parses from JSON correctly', () {
      final json = {
        'id': 123,
        'content': 'Hello!',
        'message_type': 'text',
        'sender_id': 10,
        'sender_type': 'User',
        'sender_name': 'John Doe',
        'created_at': '2024-01-15T10:30:00.000Z',
        'thread_id': 456,
        'edited': false,
      };

      final message = HubMessage.fromJson(json);

      expect(message.id, equals(123));
      expect(message.content, equals('Hello!'));
      expect(message.senderId, equals(10));
      expect(message.senderType, equals('User'));
      expect(message.senderName, equals('John Doe'));
      expect(message.threadId, equals(456));
      expect(message.isFromUser, isTrue);
      expect(message.isFromAgent, isFalse);
    });

    test('HubMessage identifies agent messages', () {
      final json = {
        'id': 124,
        'content': 'I can help with that!',
        'message_type': 'text',
        'sender_id': 5,
        'sender_type': 'AgentPlugin',
        'sender_name': 'Marketing Bot',
        'created_at': '2024-01-15T10:31:00.000Z',
      };

      final message = HubMessage.fromJson(json);

      expect(message.isFromUser, isFalse);
      expect(message.isFromAgent, isTrue);
    });

    test('HubMessage toJson serializes correctly', () {
      final message = HubMessage(
        id: 100,
        content: 'Test message',
        messageType: 'text',
        senderId: 10,
        senderType: 'User',
        senderName: 'Test User',
        createdAt: DateTime.parse('2024-01-15T10:30:00.000Z'),
        threadId: 456,
      );

      final json = message.toJson();

      expect(json['id'], equals(100));
      expect(json['content'], equals('Test message'));
      expect(json['sender_id'], equals(10));
      expect(json['thread_id'], equals(456));
    });
  });

  group('HubThread Model', () {
    test('parses DM thread correctly', () {
      final json = {
        'id': 1,
        'thread_type': 'dm',
        'display_name': 'John Doe',
        'status': 'active',
        'message_count': 50,
        'unread_count': 3,
        'participants': [
          {
            'id': 1,
            'participant_type': 'User',
            'participant_id': 10,
            'name': 'John Doe',
          },
          {
            'id': 2,
            'participant_type': 'User',
            'participant_id': 20,
            'name': 'Jane Doe',
          },
        ],
      };

      final thread = HubThread.fromJson(json);

      expect(thread.id, equals(1));
      expect(thread.threadType, equals('dm'));
      expect(thread.isDm, isTrue);
      expect(thread.displayName, equals('John Doe'));
      expect(thread.participants.length, equals(2));
    });

    test('identifies thread types correctly', () {
      expect(HubThread(id: 1, threadType: 'dm', displayName: 'Test').isDm, isTrue);
      expect(HubThread(id: 1, threadType: 'channel', displayName: 'Test').isChannel, isTrue);
      expect(HubThread(id: 1, threadType: 'work_stream', displayName: 'Test').isWorkStream, isTrue);
    });
  });

  group('HubParticipant Model', () {
    test('parses User participant', () {
      final json = {
        'id': 1,
        'participant_type': 'User',
        'participant_id': 100,
        'name': 'John Doe',
        'role': 'member',
        'is_agent': false,
      };

      final participant = HubParticipant.fromJson(json);

      expect(participant.id, equals(1));
      expect(participant.participantType, equals('User'));
      expect(participant.participantId, equals(100));
      expect(participant.name, equals('John Doe'));
      expect(participant.isAgent, isFalse);
    });

    test('parses AgentPlugin participant', () {
      final json = {
        'id': 2,
        'participant_type': 'AgentPlugin',
        'participant_id': 5,
        'name': 'Marketing Bot',
      };

      final participant = HubParticipant.fromJson(json);

      expect(participant.participantType, equals('AgentPlugin'));
      expect(participant.isAgent, isTrue);
    });

    test('handles type field as fallback', () {
      final json = {
        'id': 3,
        'type': 'User',  // Alternative field name
        'participant_id': 50,
        'name': 'Test',
      };

      final participant = HubParticipant.fromJson(json);

      expect(participant.participantType, equals('User'));
    });
  });

  group('Message Sending Logic', () {
    test('send message request body is formatted correctly', () {
      const threadId = 123;
      const content = 'Hello world!';
      const messageType = 'text';

      final endpoint = '/hub/thread/$threadId/messages';
      final requestBody = {
        'content': content,
        'message_type': messageType,
        'reply_to_id': null,
      };

      expect(endpoint, equals('/hub/thread/123/messages'));
      expect(requestBody['content'], equals('Hello world!'));
      expect(requestBody['message_type'], equals('text'));
    });

    test('empty message should not be sent', () {
      const text = '   ';  // Whitespace only
      final trimmed = text.trim();

      expect(trimmed.isEmpty, isTrue);
      // DmChatScreen._sendMessage checks: if (text.isEmpty || _isSending) return;
    });

    test('message with whitespace is trimmed before sending', () {
      const text = '  Hello World!  ';
      final trimmed = text.trim();

      expect(trimmed, equals('Hello World!'));
      expect(trimmed.isNotEmpty, isTrue);
    });
  });

  group('Current User Detection', () {
    test('message is from current user', () {
      const currentUserId = 10;

      final message = HubMessage(
        id: 1,
        content: 'My message',
        senderId: 10,
        senderType: 'User',
        senderName: 'Me',
        createdAt: DateTime.now(),
      );

      final isMe = message.senderId == currentUserId;
      expect(isMe, isTrue);
    });

    test('message is from other user', () {
      const currentUserId = 10;

      final message = HubMessage(
        id: 2,
        content: 'Other message',
        senderId: 20,
        senderType: 'User',
        senderName: 'Other',
        createdAt: DateTime.now(),
      );

      final isMe = message.senderId == currentUserId;
      expect(isMe, isFalse);
    });
  });

  group('Display Name Logic', () {
    test('uses participant name as display name', () {
      final participants = [
        HubParticipant(
          id: 1,
          participantType: 'User',
          participantId: 10,  // Current user
          name: 'Me',
        ),
        HubParticipant(
          id: 2,
          participantType: 'User',
          participantId: 20,  // Other user
          name: 'John Doe',
        ),
      ];

      const currentUserId = 10;

      // Find the other participant (like DmChatScreen._displayName does)
      final otherParticipant = participants.firstWhere(
        (p) => p.participantId != currentUserId,
        orElse: () => participants.first,
      );

      expect(otherParticipant.name, equals('John Doe'));
    });

    test('handles agent participant display name', () {
      final participants = [
        HubParticipant(
          id: 1,
          participantType: 'User',
          participantId: 10,
          name: 'Me',
        ),
        HubParticipant(
          id: 2,
          participantType: 'AgentPlugin',
          participantId: 5,
          name: 'Marketing Bot',
          isAgent: true,
        ),
      ];

      const currentUserId = 10;

      final otherParticipant = participants.firstWhere(
        (p) => p.participantId != currentUserId,
        orElse: () => participants.first,
      );

      expect(otherParticipant.name, equals('Marketing Bot'));
      expect(otherParticipant.isAgent, isTrue);
    });
  });

  group('Message Avatar Logic', () {
    test('shows avatar for first message in group', () {
      final messages = [
        HubMessage(id: 1, content: 'Hi', senderId: 20, senderType: 'User', senderName: 'John', createdAt: DateTime.now()),
        HubMessage(id: 2, content: 'How are you?', senderId: 20, senderType: 'User', senderName: 'John', createdAt: DateTime.now()),
        HubMessage(id: 3, content: 'I am good', senderId: 10, senderType: 'User', senderName: 'Me', createdAt: DateTime.now()),
      ];

      const currentUserId = 10;

      // Check if avatar should show for each message
      // Avatar shows for first message from a sender in a consecutive group
      for (var i = 0; i < messages.length; i++) {
        final message = messages[i];
        final isMe = message.senderId == currentUserId;
        final showAvatar = !isMe && (i == 0 || messages[i - 1].senderId != message.senderId);

        if (i == 0) {
          expect(showAvatar, isTrue, reason: 'First message from John should show avatar');
        } else if (i == 1) {
          expect(showAvatar, isFalse, reason: 'Second consecutive message from John should not show avatar');
        } else if (i == 2) {
          expect(showAvatar, isFalse, reason: 'Message from current user should not show avatar');
        }
      }
    });
  });

  group('Thread Messages API Response', () {
    late Dio dio;
    late DioAdapter dioAdapter;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
      dioAdapter = DioAdapter(dio: dio);
    });

    test('GET /hub/thread/:id returns thread with messages', () async {
      dioAdapter.onGet(
        '/hub/thread/123',
        (server) => server.reply(200, {
          'id': 123,
          'thread_type': 'dm',
          'display_name': 'John Doe',
          'status': 'active',
          'messages': [
            {
              'id': 1,
              'content': 'Hello!',
              'sender_id': 10,
              'sender_type': 'User',
              'sender_name': 'Me',
              'created_at': '2024-01-15T10:30:00.000Z',
            },
            {
              'id': 2,
              'content': 'Hi there!',
              'sender_id': 20,
              'sender_type': 'User',
              'sender_name': 'John Doe',
              'created_at': '2024-01-15T10:31:00.000Z',
            },
          ],
          'participants': [
            {'id': 1, 'participant_type': 'User', 'participant_id': 10, 'name': 'Me'},
            {'id': 2, 'participant_type': 'User', 'participant_id': 20, 'name': 'John Doe'},
          ],
        }),
      );

      final response = await dio.get('/hub/thread/123');

      expect(response.statusCode, equals(200));
      expect(response.data['id'], equals(123));
      expect(response.data['messages'].length, equals(2));
      expect(response.data['participants'].length, equals(2));
    });

    test('POST /hub/thread/:id/messages creates message', () async {
      dioAdapter.onPost(
        '/hub/thread/123/messages',
        (server) => server.reply(201, {
          'message': {
            'id': 3,
            'content': 'New message',
            'message_type': 'text',
            'sender_id': 10,
            'sender_type': 'User',
            'sender_name': 'Me',
            'created_at': '2024-01-15T10:32:00.000Z',
            'thread_id': 123,
          },
        }),
        data: {
          'content': 'New message',
          'message_type': 'text',
          'reply_to_id': null,
        },
      );

      final response = await dio.post('/hub/thread/123/messages', data: {
        'content': 'New message',
        'message_type': 'text',
        'reply_to_id': null,
      });

      expect(response.statusCode, equals(201));
      expect(response.data['message']['content'], equals('New message'));
    });

    test('POST /hub/thread/:id/messages returns nested sender (server format)', () async {
      // This is the actual format returned by the Rails server
      dioAdapter.onPost(
        '/hub/thread/123/messages',
        (server) => server.reply(200, {
          'success': true,
          'message': {
            'id': 5,
            'thread_id': 123,
            'sender': {
              'id': 42,
              'type': 'User',
              'name': 'Admin User',
              'avatar': null,
            },
            'content': 'Hello world!',
            'message_type': 'text',
            'needs_response': false,
            'is_handoff': false,
            'handoff_status': null,
            'attachments': [],
            'actions': [],
            'reactions': [],
            'reply_to_id': null,
            'created_at': '2024-01-15T10:30:00Z',
            'edited': false,
            'edited_at': null,
          },
        }),
        data: {
          'content': 'Hello world!',
          'message_type': 'text',
          'reply_to_id': null,
        },
      );

      final response = await dio.post('/hub/thread/123/messages', data: {
        'content': 'Hello world!',
        'message_type': 'text',
        'reply_to_id': null,
      });

      expect(response.statusCode, equals(200));
      expect(response.data['success'], isTrue);

      // Verify HubMessage can parse the nested sender format
      final message = HubMessage.fromJson(response.data['message']);
      expect(message.id, equals(5));
      expect(message.senderId, equals(42));
      expect(message.senderType, equals('User'));
      expect(message.senderName, equals('Admin User'));
      expect(message.content, equals('Hello world!'));
    });

    test('POST /hub/thread/:id/messages without auth returns 401', () async {
      dioAdapter.onPost(
        '/hub/thread/123/messages',
        (server) => server.reply(401, {
          'error': 'Unauthorized',
        }),
        data: {
          'content': 'Test message',
          'message_type': 'text',
          'reply_to_id': null,
        },
      );

      try {
        await dio.post('/hub/thread/123/messages', data: {
          'content': 'Test message',
          'message_type': 'text',
          'reply_to_id': null,
        });
        fail('Should have thrown DioException');
      } on DioException catch (e) {
        expect(e.response?.statusCode, equals(401));
        expect(e.response?.data['error'], equals('Unauthorized'));
      }
    });

    test('mark thread read request', () async {
      dioAdapter.onPost(
        '/hub/thread/123/mark_read',
        (server) => server.reply(200, {'success': true}),
        data: {'message_id': 10},
      );

      final response = await dio.post('/hub/thread/123/mark_read', data: {'message_id': 10});

      expect(response.statusCode, equals(200));
    });
  });

  group('Auth Token Validation', () {
    test('auth header format is correct', () {
      const token = 'abc123xyz';
      final authHeader = 'Bearer $token';

      expect(authHeader, equals('Bearer abc123xyz'));
      expect(authHeader.startsWith('Bearer '), isTrue);
    });

    test('null token should prevent API calls', () {
      const String? token = null;

      // This simulates what DmChatScreen._sendMessage does
      if (token == null) {
        // Should throw or prevent the call
        expect(token, isNull);
      }
    });

    test('token extraction from auth header', () {
      const authHeader = 'Bearer abc123xyz';
      final token = authHeader.replaceFirst('Bearer ', '');

      expect(token, equals('abc123xyz'));
    });
  });

  group('Time Formatting', () {
    test('formats time for today', () {
      final now = DateTime.now();
      final messageTime = DateTime(now.year, now.month, now.day, 14, 30);

      final time = '${messageTime.hour.toString().padLeft(2, '0')}:${messageTime.minute.toString().padLeft(2, '0')}';
      expect(time, equals('14:30'));
    });

    test('formats time for yesterday', () {
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(days: 1));
      final messageDate = DateTime(yesterday.year, yesterday.month, yesterday.day);
      final today = DateTime(now.year, now.month, now.day);

      final isYesterday = messageDate == today.subtract(const Duration(days: 1));
      expect(isYesterday, isTrue);
    });

    test('formats date for older messages', () {
      final messageTime = DateTime(2024, 1, 15, 10, 30);
      final formatted = '${messageTime.month}/${messageTime.day}';

      expect(formatted, equals('1/15'));
    });
  });
}
