import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/space.dart';

void main() {
  group('Space', () {
    test('predefined spaces are correct', () {
      expect(Space.personal.slug, equals('personal'));
      expect(Space.personal.name, equals('Personal'));
      expect(Space.personal.isPersonal, isTrue);
      expect(Space.personal.isWork, isFalse);
      expect(Space.personal.isTeam, isFalse);

      expect(Space.work.slug, equals('work'));
      expect(Space.work.name, equals('Workspace'));
      expect(Space.work.isPersonal, isFalse);
      expect(Space.work.isWork, isTrue);
      expect(Space.work.isTeam, isFalse);

      expect(Space.team.slug, equals('team'));
      expect(Space.team.name, equals('Team Space'));
      expect(Space.team.isPersonal, isFalse);
      expect(Space.team.isWork, isFalse);
      expect(Space.team.isTeam, isTrue);
    });

    test('all spaces list contains all predefined spaces', () {
      expect(Space.all.length, equals(3));
      expect(Space.all.map((s) => s.slug).toList(),
          containsAll(['personal', 'work', 'team']));
    });

    test('fromJson parses correctly', () {
      final json = {
        'slug': 'custom',
        'name': 'Custom Space',
        'description': 'A custom space',
        'icon': 'star',
        'enabled': true,
        'display_order': 5,
      };

      final space = Space.fromJson(json);

      expect(space.slug, equals('custom'));
      expect(space.name, equals('Custom Space'));
      expect(space.description, equals('A custom space'));
      expect(space.icon, equals('star'));
      expect(space.enabled, isTrue);
      expect(space.displayOrder, equals(5));
    });

    test('toJson serializes correctly', () {
      final space = Space(
        slug: 'test',
        name: 'Test Space',
        description: 'Description',
        icon: 'test-icon',
        enabled: false,
        displayOrder: 10,
      );

      final json = space.toJson();

      expect(json['slug'], equals('test'));
      expect(json['name'], equals('Test Space'));
      expect(json['description'], equals('Description'));
      expect(json['icon'], equals('test-icon'));
      expect(json['enabled'], isFalse);
      expect(json['display_order'], equals(10));
    });
  });

  group('TeamChannel', () {
    test('fromJson parses complete JSON correctly', () {
      final json = {
        'id': 1,
        'name': 'general',
        'description': 'General discussion',
        'channel_type': 'general',
        'icon': '#',
        'is_private': false,
        'member_count': 10,
        'agent_count': 2,
        'unread': 5,
        'last_activity_at': '2024-01-15T10:30:00.000Z',
        'main_thread_id': 42,
      };

      final channel = TeamChannel.fromJson(json);

      expect(channel.id, equals(1));
      expect(channel.name, equals('general'));
      expect(channel.description, equals('General discussion'));
      expect(channel.channelType, equals('general'));
      expect(channel.icon, equals('#'));
      expect(channel.isPrivate, isFalse);
      expect(channel.memberCount, equals(10));
      expect(channel.agentCount, equals(2));
      expect(channel.unreadCount, equals(5));
      expect(channel.lastActivityAt, isNotNull);
      expect(channel.mainThreadId, equals(42));
    });

    test('displayIcon returns correct icon based on type', () {
      final generalChannel = TeamChannel(
        id: 1,
        name: 'general',
        channelType: 'general',
      );
      expect(generalChannel.displayIcon, equals('#'));

      final announcementChannel = TeamChannel(
        id: 2,
        name: 'announcements',
        channelType: 'announcements',
      );
      expect(announcementChannel.displayIcon, equals('📢'));

      final supportChannel = TeamChannel(
        id: 3,
        name: 'support',
        channelType: 'support',
      );
      expect(supportChannel.displayIcon, equals('🎧'));

      final privateChannel = TeamChannel(
        id: 4,
        name: 'private',
        isPrivate: true,
      );
      expect(privateChannel.displayIcon, equals('🔒'));

      final customIconChannel = TeamChannel(
        id: 5,
        name: 'custom',
        icon: '🚀',
      );
      expect(customIconChannel.displayIcon, equals('🚀'));
    });
  });

  group('HubMessage', () {
    test('fromJson parses complete JSON correctly', () {
      final json = {
        'id': 123,
        'content': 'Hello world!',
        'message_type': 'text',
        'sender_id': 456,
        'sender_type': 'User',
        'sender_name': 'John Doe',
        'created_at': '2024-01-15T10:30:00.000Z',
        'edited': false,
        'reactions': {'👍': 3, '❤️': 1},
        'reply_to_id': 100,
        'attachments': [{'type': 'image', 'url': 'https://example.com/img.png'}],
        'thread_id': 789,
        'channel_id': 42,
      };

      final message = HubMessage.fromJson(json);

      expect(message.id, equals(123));
      expect(message.content, equals('Hello world!'));
      expect(message.messageType, equals('text'));
      expect(message.senderId, equals(456));
      expect(message.senderType, equals('User'));
      expect(message.senderName, equals('John Doe'));
      expect(message.edited, isFalse);
      expect(message.reactions, isNotNull);
      expect(message.reactions!['👍'], equals(3));
      expect(message.replyToId, equals(100));
      expect(message.attachments, isNotNull);
      expect(message.attachments!.length, equals(1));
      expect(message.threadId, equals(789));
      expect(message.channelId, equals(42));
    });

    test('isFromUser and isFromAgent work correctly', () {
      final userMessage = HubMessage(
        id: 1,
        content: 'User message',
        senderId: 1,
        senderType: 'User',
        senderName: 'User',
        createdAt: DateTime.now(),
      );
      expect(userMessage.isFromUser, isTrue);
      expect(userMessage.isFromAgent, isFalse);

      final agentMessage = HubMessage(
        id: 2,
        content: 'Agent message',
        senderId: 2,
        senderType: 'AgentPlugin',
        senderName: 'Scout',
        createdAt: DateTime.now(),
      );
      expect(agentMessage.isFromUser, isFalse);
      expect(agentMessage.isFromAgent, isTrue);
    });

    test('isGif detects GIF messages', () {
      final textMessage = HubMessage(
        id: 1,
        content: 'Hello',
        messageType: 'text',
        senderId: 1,
        senderType: 'User',
        senderName: 'User',
        createdAt: DateTime.now(),
      );
      expect(textMessage.isGif, isFalse);

      final gifMessage = HubMessage(
        id: 2,
        content: 'https://giphy.com/gif.gif',
        messageType: 'gif',
        senderId: 1,
        senderType: 'User',
        senderName: 'User',
        createdAt: DateTime.now(),
      );
      expect(gifMessage.isGif, isTrue);
    });

    test('hasAttachments detects attachments correctly', () {
      final messageWithoutAttachments = HubMessage(
        id: 1,
        content: 'No attachments',
        senderId: 1,
        senderType: 'User',
        senderName: 'User',
        createdAt: DateTime.now(),
      );
      expect(messageWithoutAttachments.hasAttachments, isFalse);

      final messageWithEmptyAttachments = HubMessage(
        id: 2,
        content: 'Empty attachments',
        senderId: 1,
        senderType: 'User',
        senderName: 'User',
        createdAt: DateTime.now(),
        attachments: [],
      );
      expect(messageWithEmptyAttachments.hasAttachments, isFalse);

      final messageWithAttachments = HubMessage(
        id: 3,
        content: 'Has attachments',
        senderId: 1,
        senderType: 'User',
        senderName: 'User',
        createdAt: DateTime.now(),
        attachments: [{'type': 'file', 'url': 'https://example.com/file.pdf'}],
      );
      expect(messageWithAttachments.hasAttachments, isTrue);
    });

    test('toJson serializes correctly', () {
      final message = HubMessage(
        id: 123,
        content: 'Test message',
        messageType: 'text',
        senderId: 456,
        senderType: 'User',
        senderName: 'Test User',
        createdAt: DateTime.parse('2024-01-15T10:30:00.000Z'),
        edited: true,
        threadId: 789,
        channelId: 42,
      );

      final json = message.toJson();

      expect(json['id'], equals(123));
      expect(json['content'], equals('Test message'));
      expect(json['message_type'], equals('text'));
      expect(json['sender_id'], equals(456));
      expect(json['sender_type'], equals('User'));
      expect(json['sender_name'], equals('Test User'));
      expect(json['edited'], isTrue);
      expect(json['thread_id'], equals(789));
      expect(json['channel_id'], equals(42));
    });
  });

  group('TeamMember', () {
    test('fromJson parses complete JSON correctly', () {
      final json = {
        'id': 1,
        'first_name': 'John',
        'last_name': 'Doe',
        'email': 'john@example.com',
        'role': 'admin',
        'avatar_url': 'https://example.com/avatar.png',
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
      expect(member.avatarUrl, equals('https://example.com/avatar.png'));
      expect(member.status, equals('online'));
      expect(member.statusMessage, equals('Working from home'));
      expect(member.isOnline, isTrue);
    });

    test('fullName combines first and last name', () {
      final member = TeamMember(
        id: 1,
        firstName: 'Jane',
        lastName: 'Smith',
        email: 'jane@example.com',
      );
      expect(member.fullName, equals('Jane Smith'));
    });

    test('initials are generated correctly', () {
      final member = TeamMember(
        id: 1,
        firstName: 'Jane',
        lastName: 'Smith',
        email: 'jane@example.com',
      );
      expect(member.initials, equals('JS'));

      final singleName = TeamMember(
        id: 2,
        firstName: 'Bob',
        lastName: '',
        email: 'bob@example.com',
      );
      expect(singleName.initials, equals('B'));
    });
  });

  group('HubThread', () {
    test('fromJson parses complete JSON correctly', () {
      final json = {
        'id': 1,
        'thread_type': 'dm',
        'subject': 'Discussion',
        'display_name': 'John Doe',
        'status': 'active',
        'last_activity_at': '2024-01-15T10:30:00.000Z',
        'message_count': 25,
        'unread_count': 3,
        'participants': [
          {
            'id': 1,
            'participant_type': 'User',
            'participant_id': 100,
            'name': 'John',
            'role': 'member',
          }
        ],
      };

      final thread = HubThread.fromJson(json);

      expect(thread.id, equals(1));
      expect(thread.threadType, equals('dm'));
      expect(thread.subject, equals('Discussion'));
      expect(thread.displayName, equals('John Doe'));
      expect(thread.status, equals('active'));
      expect(thread.messageCount, equals(25));
      expect(thread.unreadCount, equals(3));
      expect(thread.participants.length, equals(1));
    });

    test('type checks work correctly', () {
      final dmThread = HubThread(
        id: 1,
        threadType: 'dm',
        displayName: 'DM Thread',
      );
      expect(dmThread.isDm, isTrue);
      expect(dmThread.isChannel, isFalse);
      expect(dmThread.isWorkStream, isFalse);

      final channelThread = HubThread(
        id: 2,
        threadType: 'channel',
        displayName: 'Channel Thread',
      );
      expect(channelThread.isDm, isFalse);
      expect(channelThread.isChannel, isTrue);
      expect(channelThread.isWorkStream, isFalse);

      final workStreamThread = HubThread(
        id: 3,
        threadType: 'work_stream',
        displayName: 'Work Stream',
      );
      expect(workStreamThread.isDm, isFalse);
      expect(workStreamThread.isChannel, isFalse);
      expect(workStreamThread.isWorkStream, isTrue);
    });
  });

  group('DmThread', () {
    test('fromJson parses complete JSON correctly', () {
      final json = {
        'id': 1,
        'display_name': 'John Doe',
        'participant': {
          'id': 100,
          'participant_type': 'User',
          'participant_id': 100,
          'name': 'John',
        },
        'unread_count': 5,
        'last_activity_at': '2024-01-15T10:30:00.000Z',
        'last_message': 'Hey there!',
      };

      final thread = DmThread.fromJson(json);

      expect(thread.id, equals(1));
      expect(thread.displayName, equals('John Doe'));
      expect(thread.otherParticipant, isNotNull);
      expect(thread.otherParticipant!.name, equals('John'));
      expect(thread.unreadCount, equals(5));
      expect(thread.lastMessage, equals('Hey there!'));
    });
  });

  group('HubParticipant', () {
    test('fromJson parses User participant correctly', () {
      final json = {
        'id': 1,
        'participant_type': 'User',
        'participant_id': 100,
        'name': 'John Doe',
        'role': 'admin',
      };

      final participant = HubParticipant.fromJson(json);

      expect(participant.id, equals(1));
      expect(participant.participantType, equals('User'));
      expect(participant.participantId, equals(100));
      expect(participant.name, equals('John Doe'));
      expect(participant.role, equals('admin'));
      expect(participant.isAgent, isFalse);
    });

    test('fromJson identifies Agent participants', () {
      final json = {
        'id': 2,
        'participant_type': 'AgentPlugin',
        'participant_id': 50,
        'name': 'Scout',
        'is_agent': true,
      };

      final participant = HubParticipant.fromJson(json);

      expect(participant.isAgent, isTrue);
    });
  });
}
