import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:amos_mobile/models/space.dart';
import 'package:amos_mobile/services/hub_service.dart';

// Note: HubService uses ApiClient which requires native plugins.
// For unit tests, we test the data models, query parameter building,
// and response parsing logic separately.

void main() {
  group('TeamChannel Model', () {
    test('parses from JSON correctly', () {
      final json = {
        'id': 1,
        'name': 'general',
        'description': 'General discussion channel',
        'channel_type': 'general',
        'icon': 'hash',
        'is_private': false,
        'member_count': 10,
        'agent_count': 2,
        'unread': 5,
        'last_activity_at': '2024-01-15T10:30:00.000Z',
        'main_thread_id': 100,
      };

      final channel = TeamChannel.fromJson(json);

      expect(channel.id, equals(1));
      expect(channel.name, equals('general'));
      expect(channel.description, equals('General discussion channel'));
      expect(channel.channelType, equals('general'));
      expect(channel.icon, equals('hash'));
      expect(channel.isPrivate, isFalse);
      expect(channel.memberCount, equals(10));
      expect(channel.agentCount, equals(2));
      expect(channel.unreadCount, equals(5));
      expect(channel.lastActivityAt, equals(DateTime.parse('2024-01-15T10:30:00.000Z')));
      expect(channel.mainThreadId, equals(100));
    });

    test('handles missing optional fields', () {
      final json = {
        'id': 2,
        'name': 'random',
      };

      final channel = TeamChannel.fromJson(json);

      expect(channel.id, equals(2));
      expect(channel.name, equals('random'));
      expect(channel.description, isNull);
      expect(channel.channelType, equals('general'));
      expect(channel.icon, isNull);
      expect(channel.isPrivate, isFalse);
      expect(channel.memberCount, equals(0));
      expect(channel.agentCount, equals(0));
      expect(channel.unreadCount, equals(0));
      expect(channel.lastActivityAt, isNull);
      expect(channel.mainThreadId, isNull);
    });

    test('handles unread_count field variant', () {
      final json = {
        'id': 3,
        'name': 'support',
        'unread_count': 10,
      };

      final channel = TeamChannel.fromJson(json);

      expect(channel.unreadCount, equals(10));
    });
  });

  group('TeamChannel displayIcon', () {
    test('returns hash for general channel type', () {
      final channel = TeamChannel(id: 1, name: 'general', channelType: 'general');
      expect(channel.displayIcon, equals('#'));
    });

    test('returns lock emoji for private channel', () {
      final channel = TeamChannel(id: 1, name: 'private', isPrivate: true);
      expect(channel.displayIcon, equals('🔒'));
    });

    test('returns megaphone for announcements channel', () {
      final channel = TeamChannel(id: 1, name: 'news', channelType: 'announcements');
      expect(channel.displayIcon, equals('📢'));
    });

    test('returns headphones for support channel', () {
      final channel = TeamChannel(id: 1, name: 'help', channelType: 'support');
      expect(channel.displayIcon, equals('🎧'));
    });

    test('maps Lucide icon names to characters', () {
      expect(TeamChannel(id: 1, name: 'test', icon: 'hash').displayIcon, equals('#'));
      expect(TeamChannel(id: 1, name: 'test', icon: 'lock').displayIcon, equals('🔒'));
      expect(TeamChannel(id: 1, name: 'test', icon: 'megaphone').displayIcon, equals('📢'));
      expect(TeamChannel(id: 1, name: 'test', icon: 'headphones').displayIcon, equals('🎧'));
      expect(TeamChannel(id: 1, name: 'test', icon: 'users').displayIcon, equals('👥'));
      expect(TeamChannel(id: 1, name: 'test', icon: 'star').displayIcon, equals('⭐'));
      expect(TeamChannel(id: 1, name: 'test', icon: 'heart').displayIcon, equals('❤️'));
      expect(TeamChannel(id: 1, name: 'test', icon: 'message-circle').displayIcon, equals('💬'));
    });

    test('returns emoji directly if icon is emoji', () {
      final channel = TeamChannel(id: 1, name: 'rockets', icon: '🚀');
      expect(channel.displayIcon, equals('🚀'));
    });
  });

  group('TeamChannel toJson', () {
    test('converts to JSON correctly', () {
      final channel = TeamChannel(
        id: 1,
        name: 'general',
        description: 'Main channel',
        channelType: 'general',
        icon: 'hash',
        isPrivate: false,
        memberCount: 10,
        agentCount: 2,
        unreadCount: 5,
        lastActivityAt: DateTime.parse('2024-01-15T10:30:00.000Z'),
      );

      final json = channel.toJson();

      expect(json['id'], equals(1));
      expect(json['name'], equals('general'));
      expect(json['description'], equals('Main channel'));
      expect(json['channel_type'], equals('general'));
      expect(json['icon'], equals('hash'));
      expect(json['is_private'], isFalse);
      expect(json['member_count'], equals(10));
      expect(json['agent_count'], equals(2));
      expect(json['unread'], equals(5));
      expect(json['last_activity_at'], equals('2024-01-15T10:30:00.000Z'));
    });
  });

  group('HubThread Model', () {
    test('parses from JSON correctly', () {
      final json = {
        'id': 1,
        'thread_type': 'dm',
        'subject': 'Direct Message',
        'display_name': 'John Doe',
        'status': 'active',
        'last_activity_at': '2024-01-15T10:30:00.000Z',
        'message_count': 50,
        'unread_count': 3,
        'participants': [
          {
            'id': 1,
            'participant_type': 'User',
            'participant_id': 10,
            'name': 'John Doe',
            'role': 'member',
          },
        ],
      };

      final thread = HubThread.fromJson(json);

      expect(thread.id, equals(1));
      expect(thread.threadType, equals('dm'));
      expect(thread.subject, equals('Direct Message'));
      expect(thread.displayName, equals('John Doe'));
      expect(thread.status, equals('active'));
      expect(thread.lastActivityAt, equals(DateTime.parse('2024-01-15T10:30:00.000Z')));
      expect(thread.messageCount, equals(50));
      expect(thread.unreadCount, equals(3));
      expect(thread.participants, hasLength(1));
      expect(thread.isDm, isTrue);
      expect(thread.isChannel, isFalse);
    });

    test('handles missing optional fields', () {
      final json = {
        'id': 2,
        'display_name': 'Test Thread',
      };

      final thread = HubThread.fromJson(json);

      expect(thread.id, equals(2));
      expect(thread.threadType, equals('dm'));
      expect(thread.subject, isNull);
      expect(thread.status, equals('active'));
      expect(thread.lastActivityAt, isNull);
      expect(thread.messageCount, equals(0));
      expect(thread.unreadCount, equals(0));
      expect(thread.participants, isEmpty);
    });

    test('identifies channel type correctly', () {
      final channelThread = HubThread.fromJson({
        'id': 1,
        'thread_type': 'channel',
        'display_name': 'general',
      });

      expect(channelThread.isChannel, isTrue);
      expect(channelThread.isDm, isFalse);
    });

    test('identifies work_stream type correctly', () {
      final workThread = HubThread.fromJson({
        'id': 1,
        'thread_type': 'work_stream',
        'display_name': 'Project',
      });

      expect(workThread.isWorkStream, isTrue);
    });
  });

  group('HubParticipant Model', () {
    test('parses from JSON correctly', () {
      final json = {
        'id': 1,
        'participant_type': 'User',
        'participant_id': 10,
        'name': 'John Doe',
        'role': 'admin',
        'is_agent': false,
      };

      final participant = HubParticipant.fromJson(json);

      expect(participant.id, equals(1));
      expect(participant.participantType, equals('User'));
      expect(participant.participantId, equals(10));
      expect(participant.name, equals('John Doe'));
      expect(participant.role, equals('admin'));
      expect(participant.isAgent, isFalse);
    });

    test('handles agent participant', () {
      final json = {
        'id': 2,
        'participant_type': 'AgentPlugin',
        'participant_id': 5,
        'name': 'Marketing Assistant',
        'role': 'member',
      };

      final participant = HubParticipant.fromJson(json);

      expect(participant.participantType, equals('AgentPlugin'));
      expect(participant.isAgent, isTrue);
    });

    test('handles type field variant', () {
      final json = {
        'id': 3,
        'type': 'User',
        'participant_id': 15,
        'name': 'Jane Doe',
      };

      final participant = HubParticipant.fromJson(json);

      expect(participant.participantType, equals('User'));
    });
  });

  group('HubMessage Model', () {
    test('parses from JSON correctly', () {
      final json = {
        'id': 1,
        'content': 'Hello world!',
        'message_type': 'text',
        'sender_id': 10,
        'sender_type': 'User',
        'sender_name': 'John Doe',
        'created_at': '2024-01-15T10:30:00.000Z',
        'edited': false,
        'reactions': {'👍': 3, '❤️': 1},
        'reply_to_id': null,
        'attachments': [],
        'thread_id': 100,
        'channel_id': 5,
      };

      final message = HubMessage.fromJson(json);

      expect(message.id, equals(1));
      expect(message.content, equals('Hello world!'));
      expect(message.messageType, equals('text'));
      expect(message.senderId, equals(10));
      expect(message.senderType, equals('User'));
      expect(message.senderName, equals('John Doe'));
      expect(message.createdAt, equals(DateTime.parse('2024-01-15T10:30:00.000Z')));
      expect(message.edited, isFalse);
      expect(message.reactions, isNotNull);
      expect(message.reactions!['👍'], equals(3));
      expect(message.replyToId, isNull);
      expect(message.attachments, isEmpty);
      expect(message.threadId, equals(100));
      expect(message.channelId, equals(5));
      expect(message.isFromUser, isTrue);
      expect(message.isFromAgent, isFalse);
    });

    test('handles agent message', () {
      final json = {
        'id': 2,
        'content': 'I can help with that!',
        'message_type': 'text',
        'sender_id': 5,
        'sender_type': 'AgentPlugin',
        'sender_name': 'Marketing Bot',
        'created_at': '2024-01-15T10:31:00.000Z',
      };

      final message = HubMessage.fromJson(json);

      expect(message.isFromAgent, isTrue);
      expect(message.isFromUser, isFalse);
    });

    test('handles gif message type', () {
      final json = {
        'id': 3,
        'content': 'https://giphy.com/example.gif',
        'message_type': 'gif',
        'sender_id': 10,
        'sender_type': 'User',
        'sender_name': 'John',
        'created_at': '2024-01-15T10:32:00.000Z',
      };

      final message = HubMessage.fromJson(json);

      expect(message.isGif, isTrue);
    });

    test('handles message with attachments', () {
      final json = {
        'id': 4,
        'content': 'Check this file',
        'message_type': 'text',
        'sender_id': 10,
        'sender_type': 'User',
        'sender_name': 'John',
        'created_at': '2024-01-15T10:33:00.000Z',
        'attachments': [
          {'filename': 'report.pdf', 'url': 'https://example.com/report.pdf'},
        ],
      };

      final message = HubMessage.fromJson(json);

      expect(message.hasAttachments, isTrue);
      expect(message.attachments, hasLength(1));
    });

    test('handles alternative thread_id and channel_id fields', () {
      final json = {
        'id': 5,
        'content': 'Test',
        'sender_id': 10,
        'sender_type': 'User',
        'sender_name': 'John',
        'created_at': '2024-01-15T10:34:00.000Z',
        'hub_thread_id': 200,
        'hub_channel_id': 10,
      };

      final message = HubMessage.fromJson(json);

      expect(message.threadId, equals(200));
      expect(message.channelId, equals(10));
    });
  });

  group('HubMessage toJson', () {
    test('converts to JSON correctly', () {
      final message = HubMessage(
        id: 1,
        content: 'Hello!',
        messageType: 'text',
        senderId: 10,
        senderType: 'User',
        senderName: 'John',
        createdAt: DateTime.parse('2024-01-15T10:30:00.000Z'),
        edited: true,
        reactions: {'👍': 2},
        replyToId: 50,
        threadId: 100,
        channelId: 5,
      );

      final json = message.toJson();

      expect(json['id'], equals(1));
      expect(json['content'], equals('Hello!'));
      expect(json['message_type'], equals('text'));
      expect(json['sender_id'], equals(10));
      expect(json['sender_type'], equals('User'));
      expect(json['sender_name'], equals('John'));
      expect(json['edited'], isTrue);
      expect(json['reactions'], equals({'👍': 2}));
      expect(json['reply_to_id'], equals(50));
      expect(json['thread_id'], equals(100));
      expect(json['channel_id'], equals(5));
    });
  });

  group('TeamMember Model', () {
    test('parses from JSON correctly', () {
      final json = {
        'id': 1,
        'first_name': 'John',
        'last_name': 'Doe',
        'email': 'john@example.com',
        'role': 'admin',
        'avatar_url': 'https://example.com/avatar.jpg',
        'status': 'online',
        'status_message': 'Working from home',
        'is_online': true,
      };

      final member = TeamMember.fromJson(json);

      expect(member.id, equals(1));
      expect(member.firstName, equals('John'));
      expect(member.lastName, equals('Doe'));
      expect(member.email, equals('john@example.com'));
      expect(member.role, equals('admin'));
      expect(member.avatarUrl, equals('https://example.com/avatar.jpg'));
      expect(member.status, equals('online'));
      expect(member.statusMessage, equals('Working from home'));
      expect(member.isOnline, isTrue);
      expect(member.fullName, equals('John Doe'));
      expect(member.initials, equals('JD'));
    });

    test('handles missing optional fields', () {
      final json = {
        'id': 2,
        'first_name': 'Jane',
        'last_name': 'Smith',
        'email': 'jane@example.com',
      };

      final member = TeamMember.fromJson(json);

      expect(member.role, isNull);
      expect(member.avatarUrl, isNull);
      expect(member.status, equals('offline'));
      expect(member.statusMessage, isNull);
      expect(member.isOnline, isFalse);
    });

    test('derives isOnline from status when is_online not provided', () {
      final json = {
        'id': 3,
        'first_name': 'Bob',
        'last_name': 'Jones',
        'email': 'bob@example.com',
        'status': 'online',
      };

      final member = TeamMember.fromJson(json);

      expect(member.isOnline, isTrue);
    });

    test('handles empty names for initials', () {
      final json = {
        'id': 4,
        'first_name': '',
        'last_name': '',
        'email': 'test@example.com',
      };

      final member = TeamMember.fromJson(json);

      expect(member.initials, equals(''));
      expect(member.fullName, equals(''));
    });
  });

  group('DmThread Model', () {
    test('parses from JSON correctly', () {
      final json = {
        'id': 1,
        'display_name': 'John Doe',
        'participant': {
          'id': 10,
          'participant_type': 'User',
          'participant_id': 10,
          'name': 'John Doe',
        },
        'unread_count': 5,
        'last_activity_at': '2024-01-15T10:30:00.000Z',
        'last_message': 'Hey, how are you?',
      };

      final thread = DmThread.fromJson(json);

      expect(thread.id, equals(1));
      expect(thread.displayName, equals('John Doe'));
      expect(thread.otherParticipant, isNotNull);
      expect(thread.otherParticipant!.name, equals('John Doe'));
      expect(thread.unreadCount, equals(5));
      expect(thread.lastActivityAt, equals(DateTime.parse('2024-01-15T10:30:00.000Z')));
      expect(thread.lastMessage, equals('Hey, how are you?'));
    });

    test('handles missing optional fields', () {
      final json = {
        'id': 2,
        'display_name': 'Marketing Bot',
      };

      final thread = DmThread.fromJson(json);

      expect(thread.otherParticipant, isNull);
      expect(thread.unreadCount, equals(0));
      expect(thread.lastActivityAt, isNull);
      expect(thread.lastMessage, isNull);
    });
  });

  group('ChannelMessagesResponse', () {
    test('parses from JSON correctly', () {
      final json = {
        'channel': {
          'id': 1,
          'name': 'general',
          'channel_type': 'general',
        },
        'thread_id': 100,
        'messages': [
          {
            'id': 1,
            'content': 'Hello!',
            'sender_id': 10,
            'sender_type': 'User',
            'sender_name': 'John',
            'created_at': '2024-01-15T10:30:00.000Z',
          },
          {
            'id': 2,
            'content': 'Hi there!',
            'sender_id': 20,
            'sender_type': 'User',
            'sender_name': 'Jane',
            'created_at': '2024-01-15T10:31:00.000Z',
          },
        ],
      };

      final response = ChannelMessagesResponse.fromJson(json);

      expect(response.channel.name, equals('general'));
      expect(response.threadId, equals(100));
      expect(response.messages, hasLength(2));
      expect(response.messages[0].content, equals('Hello!'));
    });

    test('handles empty messages', () {
      final json = {
        'channel': {
          'id': 1,
          'name': 'empty',
        },
        'thread_id': 101,
        'messages': null,
      };

      final response = ChannelMessagesResponse.fromJson(json);

      expect(response.messages, isEmpty);
    });
  });

  group('ThreadMessagesResponse', () {
    test('parses from JSON correctly', () {
      final json = {
        'id': 1,
        'thread_type': 'dm',
        'display_name': 'John Doe',
        'messages': [
          {
            'id': 1,
            'content': 'Hello!',
            'sender_id': 10,
            'sender_type': 'User',
            'sender_name': 'John',
            'created_at': '2024-01-15T10:30:00.000Z',
          },
        ],
        'participants': [
          {
            'id': 1,
            'participant_type': 'User',
            'participant_id': 10,
            'name': 'John Doe',
          },
        ],
      };

      final response = ThreadMessagesResponse.fromJson(json);

      expect(response.thread.displayName, equals('John Doe'));
      expect(response.messages, hasLength(1));
      expect(response.participants, hasLength(1));
    });
  });

  group('GiphyGif Model', () {
    test('parses from JSON correctly', () {
      final json = {
        'id': 'abc123',
        'url': 'https://giphy.com/gifs/abc123',
        'preview_url': 'https://giphy.com/gifs/abc123-preview',
        'title': 'Funny cat',
        'width': 480,
        'height': 360,
      };

      final gif = GiphyGif.fromJson(json);

      expect(gif.id, equals('abc123'));
      expect(gif.url, equals('https://giphy.com/gifs/abc123'));
      expect(gif.previewUrl, equals('https://giphy.com/gifs/abc123-preview'));
      expect(gif.title, equals('Funny cat'));
      expect(gif.width, equals(480));
      expect(gif.height, equals(360));
    });

    test('handles missing optional fields', () {
      final json = {
        'id': 'def456',
        'url': 'https://giphy.com/gifs/def456',
      };

      final gif = GiphyGif.fromJson(json);

      expect(gif.previewUrl, equals('https://giphy.com/gifs/def456')); // falls back to url
      expect(gif.title, equals(''));
      expect(gif.width, equals(200)); // default
      expect(gif.height, equals(200)); // default
    });
  });

  group('Create Channel Request Building', () {
    test('builds create request with required fields', () {
      const name = 'new-channel';
      const channelType = 'general';
      const isPrivate = false;

      final data = {
        'channel': {
          'name': name,
          'channel_type': channelType,
          'is_private': isPrivate,
        },
      };

      expect(data['channel']!['name'], equals('new-channel'));
      expect(data['channel']!['channel_type'], equals('general'));
      expect(data['channel']!['is_private'], isFalse);
    });

    test('builds create request with optional description', () {
      const name = 'announcements';
      const description = 'Company announcements';
      const channelType = 'announcements';
      const isPrivate = false;

      final data = {
        'channel': {
          'name': name,
          'description': description,
          'channel_type': channelType,
          'is_private': isPrivate,
        },
      };

      expect(data['channel']!['description'], equals('Company announcements'));
    });
  });

  group('Send Message Request Building', () {
    test('builds message request with required fields', () {
      const content = 'Hello everyone!';
      const messageType = 'text';

      final data = {
        'content': content,
        'message_type': messageType,
      };

      expect(data['content'], equals('Hello everyone!'));
      expect(data['message_type'], equals('text'));
    });

    test('builds message request with reply_to_id', () {
      const content = 'Good point!';
      const messageType = 'text';
      const replyToId = 50;

      final data = {
        'content': content,
        'message_type': messageType,
        'reply_to_id': replyToId,
      };

      expect(data['reply_to_id'], equals(50));
    });
  });

  group('Create DM Request Building', () {
    test('builds DM request with user', () {
      const participantType = 'User';
      const participantId = 10;
      const initialMessage = 'Hi!';

      final data = {
        'participant_type': participantType,
        'participant_id': participantId,
        'message': initialMessage,
      };

      expect(data['participant_type'], equals('User'));
      expect(data['participant_id'], equals(10));
      expect(data['message'], equals('Hi!'));
    });

    test('builds DM request with agent', () {
      const participantType = 'AgentPlugin';
      const participantId = 5;

      final data = {
        'participant_type': participantType,
        'participant_id': participantId,
        'message': null,
      };

      expect(data['participant_type'], equals('AgentPlugin'));
      expect(data['participant_id'], equals(5));
    });
  });

  group('Presence Update Request Building', () {
    test('builds presence update with status only', () {
      const status = 'away';

      final data = {
        'status': status,
        'message': null,
        'emoji': null,
      };

      expect(data['status'], equals('away'));
    });

    test('builds presence update with all fields', () {
      const status = 'online';
      const message = 'Working from home';
      const emoji = '🏠';

      final data = {
        'status': status,
        'message': message,
        'emoji': emoji,
      };

      expect(data['status'], equals('online'));
      expect(data['message'], equals('Working from home'));
      expect(data['emoji'], equals('🏠'));
    });
  });

  group('Team Invite Request Building', () {
    test('builds invite request', () {
      const email = 'newuser@example.com';
      const role = 'member';

      final data = {
        'team_invite': {
          'email': email,
          'role': role,
        },
      };

      expect(data['team_invite']!['email'], equals('newuser@example.com'));
      expect(data['team_invite']!['role'], equals('member'));
    });
  });

  group('Dio HTTP Client Tests', () {
    late Dio dio;
    late DioAdapter dioAdapter;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
      dioAdapter = DioAdapter(dio: dio);
    });

    test('GET /hub/channels returns channels list', () async {
      dioAdapter.onGet(
        '/hub/channels',
        (server) => server.reply(200, [
          {
            'id': 1,
            'name': 'general',
            'channel_type': 'general',
            'member_count': 10,
          },
          {
            'id': 2,
            'name': 'random',
            'channel_type': 'general',
            'member_count': 8,
          },
        ]),
      );

      final response = await dio.get('/hub/channels');

      expect(response.statusCode, equals(200));
      final channels = (response.data as List)
          .map((json) => TeamChannel.fromJson(json))
          .toList();
      expect(channels, hasLength(2));
      expect(channels[0].name, equals('general'));
    });

    test('GET /hub/channels/:id/messages returns channel messages', () async {
      dioAdapter.onGet(
        '/hub/channels/1/messages',
        (server) => server.reply(200, {
          'channel': {'id': 1, 'name': 'general'},
          'thread_id': 100,
          'messages': [
            {
              'id': 1,
              'content': 'Hello!',
              'sender_id': 10,
              'sender_type': 'User',
              'sender_name': 'John',
              'created_at': '2024-01-15T10:30:00.000Z',
            },
          ],
        }),
      );

      final response = await dio.get('/hub/channels/1/messages');

      expect(response.statusCode, equals(200));
      final messagesResponse = ChannelMessagesResponse.fromJson(response.data);
      expect(messagesResponse.channel.name, equals('general'));
      expect(messagesResponse.messages, hasLength(1));
    });

    test('POST /hub/channels/:id/messages sends message', () async {
      dioAdapter.onPost(
        '/hub/channels/1/messages',
        (server) => server.reply(201, {
          'message': {
            'id': 100,
            'content': 'New message',
            'sender_id': 10,
            'sender_type': 'User',
            'sender_name': 'John',
            'created_at': '2024-01-15T10:30:00.000Z',
          },
        }),
        data: {
          'content': 'New message',
          'message_type': 'text',
        },
      );

      final response = await dio.post('/hub/channels/1/messages', data: {
        'content': 'New message',
        'message_type': 'text',
      });

      expect(response.statusCode, equals(201));
      final message = HubMessage.fromJson(response.data['message']);
      expect(message.content, equals('New message'));
    });

    test('POST /hub/channels creates channel', () async {
      dioAdapter.onPost(
        '/hub/channels',
        (server) => server.reply(201, {
          'channel': {
            'id': 10,
            'name': 'new-channel',
            'channel_type': 'general',
          },
        }),
        data: {
          'channel': {
            'name': 'new-channel',
            'channel_type': 'general',
            'is_private': false,
          },
        },
      );

      final response = await dio.post('/hub/channels', data: {
        'channel': {
          'name': 'new-channel',
          'channel_type': 'general',
          'is_private': false,
        },
      });

      expect(response.statusCode, equals(201));
      final channel = TeamChannel.fromJson(response.data['channel']);
      expect(channel.name, equals('new-channel'));
    });

    test('GET /hub/dms returns DM threads', () async {
      dioAdapter.onGet(
        '/hub/dms',
        (server) => server.reply(200, [
          {
            'id': 1,
            'display_name': 'John Doe',
            'unread_count': 3,
          },
          {
            'id': 2,
            'display_name': 'Marketing Bot',
            'unread_count': 0,
          },
        ]),
      );

      final response = await dio.get('/hub/dms');

      expect(response.statusCode, equals(200));
      final threads = (response.data as List)
          .map((json) => DmThread.fromJson(json))
          .toList();
      expect(threads, hasLength(2));
    });

    test('GET /hub/giphy/search returns GIFs', () async {
      dioAdapter.onGet(
        '/hub/giphy/search',
        (server) => server.reply(200, {
          'success': true,
          'gifs': [
            {
              'id': 'abc123',
              'url': 'https://giphy.com/gifs/abc123',
              'title': 'Funny cat',
            },
          ],
        }),
        queryParameters: {
          'q': 'cat',
          'limit': 20,
        },
      );

      final response = await dio.get('/hub/giphy/search', queryParameters: {
        'q': 'cat',
        'limit': 20,
      });

      expect(response.statusCode, equals(200));
      expect(response.data['success'], isTrue);
      final gifs = (response.data['gifs'] as List)
          .map((g) => GiphyGif.fromJson(g))
          .toList();
      expect(gifs, hasLength(1));
      expect(gifs[0].title, equals('Funny cat'));
    });

    test('POST /api/v1/team/invite invites team member', () async {
      dioAdapter.onPost(
        '/api/v1/team/invite',
        (server) => server.reply(201, {
          'success': true,
          'message': 'Invitation sent',
        }),
        data: {
          'team_invite': {
            'email': 'newuser@example.com',
            'role': 'member',
          },
        },
      );

      final response = await dio.post('/api/v1/team/invite', data: {
        'team_invite': {
          'email': 'newuser@example.com',
          'role': 'member',
        },
      });

      expect(response.statusCode, equals(201));
      expect(response.data['success'], isTrue);
    });

    test('handles 401 unauthorized error', () async {
      dioAdapter.onGet(
        '/hub/channels',
        (server) => server.reply(401, {'error': 'Unauthorized'}),
      );

      expect(
        () => dio.get('/hub/channels'),
        throwsA(isA<DioException>()),
      );
    });

    test('handles 403 forbidden error', () async {
      dioAdapter.onDelete(
        '/hub/channels/1',
        (server) => server.reply(403, {'error': 'Not authorized to delete this channel'}),
      );

      expect(
        () => dio.delete('/hub/channels/1'),
        throwsA(isA<DioException>()),
      );
    });
  });
}
