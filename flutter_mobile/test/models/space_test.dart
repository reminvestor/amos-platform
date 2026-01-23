import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/space.dart';

void main() {
  group('Space', () {
    test('fromJson parses correctly', () {
      final json = {
        'slug': 'custom_space',
        'name': 'Custom Space',
        'description': 'A custom workspace',
        'icon': '🎯',
        'enabled': true,
        'display_order': 5,
      };

      final space = Space.fromJson(json);

      expect(space.slug, equals('custom_space'));
      expect(space.name, equals('Custom Space'));
      expect(space.description, equals('A custom workspace'));
      expect(space.icon, equals('🎯'));
      expect(space.enabled, isTrue);
      expect(space.displayOrder, equals(5));
    });

    test('fromJson handles missing values with defaults', () {
      final json = <String, dynamic>{};

      final space = Space.fromJson(json);

      expect(space.slug, equals(''));
      expect(space.name, equals(''));
      expect(space.description, isNull);
      expect(space.icon, isNull);
      expect(space.enabled, isTrue);
      expect(space.displayOrder, equals(0));
    });

    test('toJson serializes correctly', () {
      final space = Space(
        slug: 'test_space',
        name: 'Test Space',
        description: 'Test description',
        icon: '📌',
        enabled: false,
        displayOrder: 3,
      );

      final json = space.toJson();

      expect(json['slug'], equals('test_space'));
      expect(json['name'], equals('Test Space'));
      expect(json['description'], equals('Test description'));
      expect(json['icon'], equals('📌'));
      expect(json['enabled'], isFalse);
      expect(json['display_order'], equals(3));
    });

    test('isPersonal returns true for personal space', () {
      expect(Space.personal.isPersonal, isTrue);
      expect(Space.personal.isWork, isFalse);
      expect(Space.personal.isTeam, isFalse);
    });

    test('isWork returns true for work space', () {
      expect(Space.work.isPersonal, isFalse);
      expect(Space.work.isWork, isTrue);
      expect(Space.work.isTeam, isFalse);
    });

    test('isTeam returns false for all current spaces', () {
      // Team space was removed - isTeam is always false now
      expect(Space.personal.isTeam, isFalse);
      expect(Space.work.isTeam, isFalse);
    });

    test('predefined spaces have correct slugs', () {
      expect(Space.personal.slug, equals('personal'));
      expect(Space.work.slug, equals('operations')); // work is now alias for operations
    });

    test('all contains all predefined spaces', () {
      expect(Space.all, hasLength(2)); // Now only personal and operations
      expect(Space.all, contains(Space.personal));
      expect(Space.all, contains(Space.operations));
    });
  });

  group('TeamChannel', () {
    test('fromJson parses complete JSON correctly', () {
      final json = {
        'id': 123,
        'name': 'general',
        'description': 'General discussion',
        'channel_type': 'general',
        'icon': 'hash',
        'is_private': false,
        'member_count': 10,
        'agent_count': 2,
        'unread': 5,
        'last_activity_at': '2024-01-15T10:30:00.000Z',
        'main_thread_id': 456,
      };

      final channel = TeamChannel.fromJson(json);

      expect(channel.id, equals(123));
      expect(channel.name, equals('general'));
      expect(channel.description, equals('General discussion'));
      expect(channel.channelType, equals('general'));
      expect(channel.icon, equals('hash'));
      expect(channel.isPrivate, isFalse);
      expect(channel.memberCount, equals(10));
      expect(channel.agentCount, equals(2));
      expect(channel.unreadCount, equals(5));
      expect(channel.lastActivityAt, equals(DateTime.parse('2024-01-15T10:30:00.000Z')));
      expect(channel.mainThreadId, equals(456));
    });

    test('fromJson handles missing optional values', () {
      final json = <String, dynamic>{};

      final channel = TeamChannel.fromJson(json);

      expect(channel.id, equals(0));
      expect(channel.name, equals(''));
      expect(channel.description, isNull);
      expect(channel.channelType, equals('general'));
      expect(channel.isPrivate, isFalse);
      expect(channel.memberCount, equals(0));
      expect(channel.agentCount, equals(0));
      expect(channel.unreadCount, equals(0));
      expect(channel.lastActivityAt, isNull);
      expect(channel.mainThreadId, isNull);
    });

    test('displayIcon returns correct icon for hash', () {
      final channel = TeamChannel(id: 1, name: 'test', icon: 'hash');
      expect(channel.displayIcon, equals('#'));
    });

    test('displayIcon returns correct icon for lock', () {
      final channel = TeamChannel(id: 1, name: 'test', icon: 'lock');
      expect(channel.displayIcon, equals('🔒'));
    });

    test('displayIcon returns correct icon for megaphone', () {
      final channel = TeamChannel(id: 1, name: 'test', icon: 'megaphone');
      expect(channel.displayIcon, equals('📢'));
    });

    test('displayIcon returns emoji directly', () {
      final channel = TeamChannel(id: 1, name: 'test', icon: '🎉');
      expect(channel.displayIcon, equals('🎉'));
    });

    test('displayIcon returns lock for private channel without icon', () {
      final channel = TeamChannel(id: 1, name: 'test', isPrivate: true);
      expect(channel.displayIcon, equals('🔒'));
    });

    test('displayIcon returns hash for general channel type', () {
      final channel = TeamChannel(id: 1, name: 'test', channelType: 'general');
      expect(channel.displayIcon, equals('#'));
    });

    test('displayIcon returns megaphone for announcements', () {
      final channel = TeamChannel(id: 1, name: 'test', channelType: 'announcements');
      expect(channel.displayIcon, equals('📢'));
    });

    test('toJson serializes correctly', () {
      final channel = TeamChannel(
        id: 123,
        name: 'general',
        description: 'General discussion',
        channelType: 'general',
        icon: '#',
        isPrivate: false,
        memberCount: 10,
        agentCount: 2,
        unreadCount: 5,
        lastActivityAt: DateTime.parse('2024-01-15T10:30:00.000Z'),
      );

      final json = channel.toJson();

      expect(json['id'], equals(123));
      expect(json['name'], equals('general'));
      expect(json['description'], equals('General discussion'));
      expect(json['channel_type'], equals('general'));
      expect(json['is_private'], isFalse);
      expect(json['member_count'], equals(10));
      expect(json['agent_count'], equals(2));
      expect(json['unread'], equals(5));
    });
  });

  group('HubThread', () {
    test('fromJson parses complete JSON correctly', () {
      final json = {
        'id': 123,
        'thread_type': 'dm',
        'subject': 'Hello',
        'display_name': 'John Doe',
        'status': 'active',
        'last_activity_at': '2024-01-15T10:30:00.000Z',
        'message_count': 50,
        'unread_count': 3,
        'participants': [
          {'id': 1, 'participant_type': 'User', 'participant_id': 1, 'name': 'John'},
        ],
      };

      final thread = HubThread.fromJson(json);

      expect(thread.id, equals(123));
      expect(thread.threadType, equals('dm'));
      expect(thread.subject, equals('Hello'));
      expect(thread.displayName, equals('John Doe'));
      expect(thread.status, equals('active'));
      expect(thread.lastActivityAt, equals(DateTime.parse('2024-01-15T10:30:00.000Z')));
      expect(thread.messageCount, equals(50));
      expect(thread.unreadCount, equals(3));
      expect(thread.participants, hasLength(1));
    });

    test('fromJson handles missing values', () {
      final json = <String, dynamic>{};

      final thread = HubThread.fromJson(json);

      expect(thread.id, equals(0));
      expect(thread.threadType, equals('dm'));
      expect(thread.subject, isNull);
      expect(thread.displayName, equals(''));
      expect(thread.status, equals('active'));
      expect(thread.messageCount, equals(0));
      expect(thread.unreadCount, equals(0));
      expect(thread.participants, isEmpty);
    });

    test('isDm returns true for dm threads', () {
      final thread = HubThread(id: 1, threadType: 'dm', displayName: 'Test');
      expect(thread.isDm, isTrue);
      expect(thread.isChannel, isFalse);
      expect(thread.isWorkStream, isFalse);
    });

    test('isChannel returns true for channel threads', () {
      final thread = HubThread(id: 1, threadType: 'channel', displayName: 'Test');
      expect(thread.isDm, isFalse);
      expect(thread.isChannel, isTrue);
      expect(thread.isWorkStream, isFalse);
    });

    test('isWorkStream returns true for work_stream threads', () {
      final thread = HubThread(id: 1, threadType: 'work_stream', displayName: 'Test');
      expect(thread.isDm, isFalse);
      expect(thread.isChannel, isFalse);
      expect(thread.isWorkStream, isTrue);
    });
  });

  group('HubParticipant', () {
    test('fromJson parses correctly', () {
      final json = {
        'id': 123,
        'participant_type': 'User',
        'participant_id': 456,
        'name': 'John Doe',
        'role': 'admin',
        'is_agent': false,
      };

      final participant = HubParticipant.fromJson(json);

      expect(participant.id, equals(123));
      expect(participant.participantType, equals('User'));
      expect(participant.participantId, equals(456));
      expect(participant.name, equals('John Doe'));
      expect(participant.role, equals('admin'));
      expect(participant.isAgent, isFalse);
    });

    test('fromJson handles AgentPlugin type', () {
      final json = {
        'id': 1,
        'participant_type': 'AgentPlugin',
        'participant_id': 2,
        'name': 'Marketing Bot',
      };

      final participant = HubParticipant.fromJson(json);

      expect(participant.participantType, equals('AgentPlugin'));
      expect(participant.isAgent, isTrue);
    });

    test('fromJson handles missing values', () {
      final json = <String, dynamic>{};

      final participant = HubParticipant.fromJson(json);

      expect(participant.id, equals(0));
      expect(participant.participantType, equals('User'));
      expect(participant.role, equals('member'));
      expect(participant.isAgent, isFalse);
    });
  });

  group('HubMessage', () {
    test('fromJson parses complete JSON correctly', () {
      final json = {
        'id': 123,
        'content': 'Hello world',
        'message_type': 'text',
        'sender_id': 1,
        'sender_type': 'User',
        'sender_name': 'John Doe',
        'created_at': '2024-01-15T10:30:00.000Z',
        'edited': true,
        'reactions': {'👍': 3},
        'reply_to_id': 100,
        'attachments': [{'name': 'file.pdf'}],
        'thread_id': 456,
        'channel_id': 789,
      };

      final message = HubMessage.fromJson(json);

      expect(message.id, equals(123));
      expect(message.content, equals('Hello world'));
      expect(message.messageType, equals('text'));
      expect(message.senderId, equals(1));
      expect(message.senderType, equals('User'));
      expect(message.senderName, equals('John Doe'));
      expect(message.createdAt, equals(DateTime.parse('2024-01-15T10:30:00.000Z')));
      expect(message.edited, isTrue);
      expect(message.reactions, equals({'👍': 3}));
      expect(message.replyToId, equals(100));
      expect(message.attachments, hasLength(1));
      expect(message.threadId, equals(456));
      expect(message.channelId, equals(789));
    });

    test('fromJson handles missing values', () {
      final json = <String, dynamic>{};

      final message = HubMessage.fromJson(json);

      expect(message.id, equals(0));
      expect(message.content, equals(''));
      expect(message.messageType, equals('text'));
      expect(message.senderId, equals(0));
      expect(message.senderType, equals('User'));
      expect(message.senderName, equals('Unknown'));
      expect(message.edited, isFalse);
    });

    test('isFromUser returns true for User type', () {
      final message = HubMessage(
        id: 1,
        content: 'Test',
        senderId: 1,
        senderType: 'User',
        senderName: 'John',
        createdAt: DateTime.now(),
      );
      expect(message.isFromUser, isTrue);
      expect(message.isFromAgent, isFalse);
    });

    test('isFromAgent returns true for AgentPlugin type', () {
      final message = HubMessage(
        id: 1,
        content: 'Test',
        senderId: 1,
        senderType: 'AgentPlugin',
        senderName: 'Bot',
        createdAt: DateTime.now(),
      );
      expect(message.isFromUser, isFalse);
      expect(message.isFromAgent, isTrue);
    });

    test('isGif returns true for gif message type', () {
      final message = HubMessage(
        id: 1,
        content: 'https://example.com/gif.gif',
        messageType: 'gif',
        senderId: 1,
        senderType: 'User',
        senderName: 'John',
        createdAt: DateTime.now(),
      );
      expect(message.isGif, isTrue);
    });

    test('hasAttachments returns true when attachments present', () {
      final message = HubMessage(
        id: 1,
        content: 'Test',
        senderId: 1,
        senderType: 'User',
        senderName: 'John',
        createdAt: DateTime.now(),
        attachments: [{'name': 'file.pdf'}],
      );
      expect(message.hasAttachments, isTrue);
    });

    test('hasAttachments returns false when no attachments', () {
      final message = HubMessage(
        id: 1,
        content: 'Test',
        senderId: 1,
        senderType: 'User',
        senderName: 'John',
        createdAt: DateTime.now(),
      );
      expect(message.hasAttachments, isFalse);
    });

    test('toJson serializes correctly', () {
      final message = HubMessage(
        id: 123,
        content: 'Test message',
        messageType: 'text',
        senderId: 1,
        senderType: 'User',
        senderName: 'John',
        createdAt: DateTime.parse('2024-01-15T10:30:00.000Z'),
        edited: false,
        threadId: 456,
        channelId: 789,
      );

      final json = message.toJson();

      expect(json['id'], equals(123));
      expect(json['content'], equals('Test message'));
      expect(json['sender_id'], equals(1));
      expect(json['sender_type'], equals('User'));
      expect(json['thread_id'], equals(456));
      expect(json['channel_id'], equals(789));
    });

    test('fromJson handles nested sender object (server format)', () {
      // This is the actual format returned by the Rails server
      final json = {
        'id': 1,
        'thread_id': 117,
        'sender': {
          'id': 42,
          'type': 'User',
          'name': 'Admin User',
          'avatar': null,
        },
        'content': 'Hello!',
        'message_type': 'text',
        'created_at': '2024-01-15T10:30:00Z',
        'edited': false,
      };

      final message = HubMessage.fromJson(json);

      expect(message.id, equals(1));
      expect(message.senderId, equals(42));
      expect(message.senderType, equals('User'));
      expect(message.senderName, equals('Admin User'));
      expect(message.content, equals('Hello!'));
    });

    test('fromJson handles nested sender with AgentPlugin type', () {
      final json = {
        'id': 2,
        'sender': {
          'id': 5,
          'type': 'AgentPlugin',
          'name': 'Marketing Bot',
        },
        'content': 'I can help!',
        'message_type': 'text',
        'created_at': '2024-01-15T10:31:00Z',
      };

      final message = HubMessage.fromJson(json);

      expect(message.senderId, equals(5));
      expect(message.senderType, equals('AgentPlugin'));
      expect(message.senderName, equals('Marketing Bot'));
      expect(message.isFromAgent, isTrue);
    });

    test('fromJson prefers nested sender over flat fields', () {
      // If both formats are present, prefer nested sender
      final json = {
        'id': 3,
        'sender': {
          'id': 100,
          'type': 'User',
          'name': 'Nested User',
        },
        'sender_id': 999,  // Should be ignored
        'sender_type': 'AgentPlugin',  // Should be ignored
        'sender_name': 'Flat Name',  // Should be ignored
        'content': 'Test',
        'message_type': 'text',
        'created_at': '2024-01-15T10:32:00Z',
      };

      final message = HubMessage.fromJson(json);

      expect(message.senderId, equals(100), reason: 'Should use nested sender.id');
      expect(message.senderType, equals('User'), reason: 'Should use nested sender.type');
      expect(message.senderName, equals('Nested User'), reason: 'Should use nested sender.name');
    });
  });

  group('TeamMember', () {
    test('fromJson parses complete JSON correctly', () {
      final json = {
        'id': 123,
        'user_id': 456,
        'first_name': 'John',
        'last_name': 'Doe',
        'email': 'john@example.com',
        'role': 'admin',
        'avatar_url': 'https://example.com/avatar.jpg',
        'status': 'online',
        'status_message': 'Working on a project',
        'is_online': true,
      };

      final member = TeamMember.fromJson(json);

      expect(member.id, equals(123));
      expect(member.userId, equals(456));  // userId should come from user_id field
      expect(member.firstName, equals('John'));
      expect(member.lastName, equals('Doe'));
      expect(member.email, equals('john@example.com'));
      expect(member.role, equals('admin'));
      expect(member.avatarUrl, equals('https://example.com/avatar.jpg'));
      expect(member.status, equals('online'));
      expect(member.statusMessage, equals('Working on a project'));
      expect(member.isOnline, isTrue);
    });

    test('fromJson uses user_id for userId when present', () {
      // This is the expected API response format
      final json = {
        'id': 1,  // EntityUser ID
        'user_id': 42,  // Actual User ID for DMs
        'first_name': 'Jane',
        'last_name': 'Smith',
        'email': 'jane@example.com',
      };

      final member = TeamMember.fromJson(json);

      expect(member.id, equals(1), reason: 'id should be EntityUser ID');
      expect(member.userId, equals(42), reason: 'userId should be from user_id field for DMs');
    });

    test('fromJson falls back to id for userId when user_id is missing', () {
      // Legacy API format without user_id
      final json = {
        'id': 99,
        'first_name': 'Legacy',
        'last_name': 'User',
        'email': 'legacy@example.com',
      };

      final member = TeamMember.fromJson(json);

      expect(member.id, equals(99));
      expect(member.userId, equals(99), reason: 'userId should fallback to id when user_id missing');
    });

    test('fromJson handles null user_id by falling back to id', () {
      final json = {
        'id': 50,
        'user_id': null,
        'first_name': 'Test',
        'last_name': 'Null',
        'email': 'test@example.com',
      };

      final member = TeamMember.fromJson(json);

      expect(member.id, equals(50));
      expect(member.userId, equals(50), reason: 'userId should fallback to id when user_id is null');
    });

    test('userId is correct for DM creation with User participant type', () {
      // Simulating what DmListScreen._startDmWithRecipient does
      final json = {
        'id': 10,  // EntityUser.id
        'user_id': 500,  // User.id (what the server expects for DMs)
        'first_name': 'DM',
        'last_name': 'Test',
        'email': 'dm@example.com',
      };

      final member = TeamMember.fromJson(json);

      // When creating a DM, we pass member.userId as participantId
      // The server expects User.id, not EntityUser.id
      final participantType = 'User';
      final participantId = member.userId;  // This is what gets sent to server

      expect(participantType, equals('User'));
      expect(participantId, equals(500), reason: 'DM should use User.id (from user_id), not EntityUser.id');
    });

    test('fromJson handles missing values', () {
      final json = <String, dynamic>{};

      final member = TeamMember.fromJson(json);

      expect(member.id, equals(0));
      expect(member.firstName, equals(''));
      expect(member.lastName, equals(''));
      expect(member.email, equals(''));
      expect(member.role, isNull);
      expect(member.avatarUrl, isNull);
      expect(member.status, equals('offline'));
      expect(member.isOnline, isFalse);
    });

    test('fullName returns combined name', () {
      final member = TeamMember(
        id: 1,
        userId: 100,
        firstName: 'John',
        lastName: 'Doe',
        email: 'john@example.com',
      );
      expect(member.fullName, equals('John Doe'));
    });

    test('fullName handles missing names', () {
      final member = TeamMember(
        id: 1,
        userId: 100,
        firstName: '',
        lastName: '',
        email: 'test@example.com',
      );
      expect(member.fullName, equals(''));
    });

    test('initials returns correct initials', () {
      final member = TeamMember(
        id: 1,
        userId: 100,
        firstName: 'John',
        lastName: 'Doe',
        email: 'john@example.com',
      );
      expect(member.initials, equals('JD'));
    });

    test('initials handles single name', () {
      final member = TeamMember(
        id: 1,
        userId: 100,
        firstName: 'John',
        lastName: '',
        email: 'john@example.com',
      );
      expect(member.initials, equals('J'));
    });
  });

  group('DmThread', () {
    test('fromJson parses complete JSON correctly', () {
      final json = {
        'id': 123,
        'display_name': 'John Doe',
        'participant': {
          'id': 1,
          'participant_type': 'User',
          'participant_id': 2,
          'name': 'John',
        },
        'unread_count': 5,
        'last_activity_at': '2024-01-15T10:30:00.000Z',
        'last_message': 'Hello!',
      };

      final thread = DmThread.fromJson(json);

      expect(thread.id, equals(123));
      expect(thread.displayName, equals('John Doe'));
      expect(thread.otherParticipant, isNotNull);
      expect(thread.otherParticipant?.name, equals('John'));
      expect(thread.unreadCount, equals(5));
      expect(thread.lastActivityAt, equals(DateTime.parse('2024-01-15T10:30:00.000Z')));
      expect(thread.lastMessage, equals('Hello!'));
    });

    test('fromJson handles missing values', () {
      final json = <String, dynamic>{};

      final thread = DmThread.fromJson(json);

      expect(thread.id, equals(0));
      expect(thread.displayName, equals(''));
      expect(thread.otherParticipant, isNull);
      expect(thread.unreadCount, equals(0));
      expect(thread.lastActivityAt, isNull);
      expect(thread.lastMessage, isNull);
    });
  });
}
