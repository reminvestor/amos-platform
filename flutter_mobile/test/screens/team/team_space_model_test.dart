import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/space.dart';

void main() {
  group('Space', () {
    test('creates with required values', () {
      final space = Space(
        slug: 'custom',
        name: 'Custom Space',
      );

      expect(space.slug, 'custom');
      expect(space.name, 'Custom Space');
      expect(space.description, isNull);
      expect(space.icon, isNull);
      expect(space.enabled, true);
      expect(space.displayOrder, 0);
    });

    test('creates with all values', () {
      final space = Space(
        slug: 'team',
        name: 'Team Space',
        description: 'Collaborate with your team',
        icon: '👥',
        enabled: true,
        displayOrder: 2,
      );

      expect(space.description, 'Collaborate with your team');
      expect(space.icon, '👥');
      expect(space.enabled, true);
      expect(space.displayOrder, 2);
    });

    test('fromJson parses complete data', () {
      final json = {
        'slug': 'workspace',
        'name': 'My Workspace',
        'description': 'A custom workspace',
        'icon': '💼',
        'enabled': true,
        'display_order': 1,
      };

      final space = Space.fromJson(json);

      expect(space.slug, 'workspace');
      expect(space.name, 'My Workspace');
      expect(space.description, 'A custom workspace');
      expect(space.icon, '💼');
      expect(space.enabled, true);
      expect(space.displayOrder, 1);
    });

    test('fromJson handles minimal data', () {
      final json = <String, dynamic>{};
      final space = Space.fromJson(json);

      expect(space.slug, '');
      expect(space.name, '');
      expect(space.enabled, true);
      expect(space.displayOrder, 0);
    });

    test('toJson serializes all fields', () {
      final space = Space(
        slug: 'test',
        name: 'Test Space',
        description: 'Test description',
        icon: '🧪',
        enabled: false,
        displayOrder: 5,
      );

      final json = space.toJson();

      expect(json['slug'], 'test');
      expect(json['name'], 'Test Space');
      expect(json['description'], 'Test description');
      expect(json['icon'], '🧪');
      expect(json['enabled'], false);
      expect(json['display_order'], 5);
    });

    group('type checks', () {
      test('isPersonal returns true for personal space', () {
        final space = Space(slug: 'personal', name: 'Personal');
        expect(space.isPersonal, true);
        expect(space.isWork, false);
        expect(space.isTeam, false);
      });

      test('isWork returns true for work space', () {
        final space = Space(slug: 'work', name: 'Work');
        expect(space.isPersonal, false);
        expect(space.isWork, true);
        expect(space.isTeam, false);
      });

      test('isTeam returns true for team space', () {
        final space = Space(slug: 'team', name: 'Team');
        expect(space.isPersonal, false);
        expect(space.isWork, false);
        expect(space.isTeam, true);
      });

      test('all type checks return false for unknown space', () {
        final space = Space(slug: 'custom', name: 'Custom');
        expect(space.isPersonal, false);
        expect(space.isWork, false);
        expect(space.isTeam, false);
      });
    });

    group('predefined spaces', () {
      test('personal space has correct values', () {
        expect(Space.personal.slug, 'personal');
        expect(Space.personal.name, 'Personal');
        expect(Space.personal.icon, '👤');
        expect(Space.personal.displayOrder, 0);
      });

      test('work space has correct values', () {
        expect(Space.work.slug, 'work');
        expect(Space.work.name, 'Workspace');
        expect(Space.work.icon, '💼');
        expect(Space.work.displayOrder, 1);
      });

      test('team space has correct values', () {
        expect(Space.team.slug, 'team');
        expect(Space.team.name, 'Team Space');
        expect(Space.team.icon, '👥');
        expect(Space.team.displayOrder, 2);
      });

      test('all spaces list contains all predefined spaces', () {
        expect(Space.all.length, 3);
        expect(Space.all[0], Space.personal);
        expect(Space.all[1], Space.work);
        expect(Space.all[2], Space.team);
      });
    });
  });

  group('TeamChannel', () {
    test('creates with required values', () {
      final channel = TeamChannel(
        id: 1,
        name: 'general',
      );

      expect(channel.id, 1);
      expect(channel.name, 'general');
      expect(channel.description, isNull);
      expect(channel.channelType, 'general');
      expect(channel.icon, isNull);
      expect(channel.isPrivate, false);
      expect(channel.memberCount, 0);
      expect(channel.agentCount, 0);
      expect(channel.unreadCount, 0);
      expect(channel.lastActivityAt, isNull);
      expect(channel.mainThreadId, isNull);
    });

    test('creates with all values', () {
      final lastActivity = DateTime(2025, 1, 15, 10, 0);
      final channel = TeamChannel(
        id: 2,
        name: 'engineering',
        description: 'Engineering team discussions',
        channelType: 'department',
        icon: '💻',
        isPrivate: true,
        memberCount: 15,
        agentCount: 2,
        unreadCount: 5,
        lastActivityAt: lastActivity,
        mainThreadId: 100,
      );

      expect(channel.description, 'Engineering team discussions');
      expect(channel.channelType, 'department');
      expect(channel.icon, '💻');
      expect(channel.isPrivate, true);
      expect(channel.memberCount, 15);
      expect(channel.agentCount, 2);
      expect(channel.unreadCount, 5);
      expect(channel.lastActivityAt, lastActivity);
      expect(channel.mainThreadId, 100);
    });

    test('fromJson parses complete data', () {
      final json = {
        'id': 123,
        'name': 'marketing',
        'description': 'Marketing team',
        'channel_type': 'team',
        'icon': '📢',
        'is_private': false,
        'member_count': 10,
        'agent_count': 1,
        'unread': 3,
        'last_activity_at': '2025-01-15T10:00:00Z',
        'main_thread_id': 50,
      };

      final channel = TeamChannel.fromJson(json);

      expect(channel.id, 123);
      expect(channel.name, 'marketing');
      expect(channel.description, 'Marketing team');
      expect(channel.channelType, 'team');
      expect(channel.icon, '📢');
      expect(channel.isPrivate, false);
      expect(channel.memberCount, 10);
      expect(channel.agentCount, 1);
      expect(channel.unreadCount, 3);
      expect(channel.lastActivityAt, isNotNull);
      expect(channel.mainThreadId, 50);
    });

    test('fromJson handles unread_count alias', () {
      final json = {
        'id': 1,
        'name': 'test',
        'unread_count': 7,
      };

      final channel = TeamChannel.fromJson(json);
      expect(channel.unreadCount, 7);
    });

    test('fromJson handles minimal data', () {
      final json = <String, dynamic>{};
      final channel = TeamChannel.fromJson(json);

      expect(channel.id, 0);
      expect(channel.name, '');
      expect(channel.channelType, 'general');
    });

    test('toJson serializes all fields', () {
      final lastActivity = DateTime.parse('2025-01-15T10:00:00Z');
      final channel = TeamChannel(
        id: 1,
        name: 'test',
        description: 'Test channel',
        channelType: 'custom',
        icon: '🔧',
        isPrivate: true,
        memberCount: 5,
        agentCount: 1,
        unreadCount: 2,
        lastActivityAt: lastActivity,
      );

      final json = channel.toJson();

      expect(json['id'], 1);
      expect(json['name'], 'test');
      expect(json['description'], 'Test channel');
      expect(json['channel_type'], 'custom');
      expect(json['icon'], '🔧');
      expect(json['is_private'], true);
      expect(json['member_count'], 5);
      expect(json['agent_count'], 1);
      expect(json['unread'], 2);
    });

    group('displayIcon', () {
      test('returns # for general channel without icon', () {
        final channel = TeamChannel(id: 1, name: 'general', channelType: 'general');
        expect(channel.displayIcon, '#');
      });

      test('returns lock emoji for private channel without icon', () {
        final channel = TeamChannel(id: 1, name: 'private', isPrivate: true);
        expect(channel.displayIcon, '🔒');
      });

      test('returns megaphone for announcements channel', () {
        final channel = TeamChannel(id: 1, name: 'announcements', channelType: 'announcements');
        expect(channel.displayIcon, '📢');
      });

      test('returns headphones for support channel', () {
        final channel = TeamChannel(id: 1, name: 'support', channelType: 'support');
        expect(channel.displayIcon, '🎧');
      });

      test('returns # for hash icon name', () {
        final channel = TeamChannel(id: 1, name: 'test', icon: 'hash');
        expect(channel.displayIcon, '#');
      });

      test('returns lock for lock icon name', () {
        final channel = TeamChannel(id: 1, name: 'test', icon: 'lock');
        expect(channel.displayIcon, '🔒');
      });

      test('returns megaphone for megaphone icon name', () {
        final channel = TeamChannel(id: 1, name: 'test', icon: 'megaphone');
        expect(channel.displayIcon, '📢');
      });

      test('returns emoji directly if set', () {
        final channel = TeamChannel(id: 1, name: 'test', icon: '🚀');
        expect(channel.displayIcon, '🚀');
      });

      test('returns star for star icon name', () {
        final channel = TeamChannel(id: 1, name: 'test', icon: 'star');
        expect(channel.displayIcon, '⭐');
      });

      test('returns heart for heart icon name', () {
        final channel = TeamChannel(id: 1, name: 'test', icon: 'heart');
        expect(channel.displayIcon, '❤️');
      });

      test('returns message circle for message-circle icon name', () {
        final channel = TeamChannel(id: 1, name: 'test', icon: 'message-circle');
        expect(channel.displayIcon, '💬');
      });

      test('returns users for users icon name', () {
        final channel = TeamChannel(id: 1, name: 'test', icon: 'users');
        expect(channel.displayIcon, '👥');
      });
    });
  });

  group('HubThread', () {
    test('creates with required values', () {
      final thread = HubThread(
        id: 1,
        threadType: 'dm',
        displayName: 'John Doe',
      );

      expect(thread.id, 1);
      expect(thread.threadType, 'dm');
      expect(thread.displayName, 'John Doe');
      expect(thread.status, 'active');
      expect(thread.messageCount, 0);
      expect(thread.unreadCount, 0);
      expect(thread.participants, isEmpty);
    });

    test('fromJson parses complete data', () {
      final json = {
        'id': 123,
        'thread_type': 'channel',
        'subject': 'Project Discussion',
        'display_name': '#engineering',
        'status': 'active',
        'last_activity_at': '2025-01-15T10:00:00Z',
        'message_count': 100,
        'unread_count': 5,
        'participants': [
          {'id': 1, 'participant_type': 'User', 'participant_id': 1, 'name': 'John'},
        ],
      };

      final thread = HubThread.fromJson(json);

      expect(thread.id, 123);
      expect(thread.threadType, 'channel');
      expect(thread.subject, 'Project Discussion');
      expect(thread.displayName, '#engineering');
      expect(thread.messageCount, 100);
      expect(thread.unreadCount, 5);
      expect(thread.participants.length, 1);
    });

    group('type checks', () {
      test('isDm returns true for dm thread', () {
        final thread = HubThread(id: 1, threadType: 'dm', displayName: 'Test');
        expect(thread.isDm, true);
        expect(thread.isChannel, false);
        expect(thread.isWorkStream, false);
      });

      test('isChannel returns true for channel thread', () {
        final thread = HubThread(id: 1, threadType: 'channel', displayName: 'Test');
        expect(thread.isDm, false);
        expect(thread.isChannel, true);
        expect(thread.isWorkStream, false);
      });

      test('isWorkStream returns true for work_stream thread', () {
        final thread = HubThread(id: 1, threadType: 'work_stream', displayName: 'Test');
        expect(thread.isDm, false);
        expect(thread.isChannel, false);
        expect(thread.isWorkStream, true);
      });
    });
  });

  group('HubParticipant', () {
    test('creates with required values', () {
      final participant = HubParticipant(
        id: 1,
        participantType: 'User',
        participantId: 100,
      );

      expect(participant.id, 1);
      expect(participant.participantType, 'User');
      expect(participant.participantId, 100);
      expect(participant.name, isNull);
      expect(participant.role, 'member');
      expect(participant.isAgent, false);
    });

    test('fromJson parses complete data', () {
      final json = {
        'id': 1,
        'participant_type': 'AgentPlugin',
        'participant_id': 50,
        'name': 'Scout',
        'role': 'assistant',
        'is_agent': true,
      };

      final participant = HubParticipant.fromJson(json);

      expect(participant.participantType, 'AgentPlugin');
      expect(participant.name, 'Scout');
      expect(participant.role, 'assistant');
      expect(participant.isAgent, true);
    });

    test('fromJson infers isAgent from participant_type', () {
      final json = {
        'id': 1,
        'participant_type': 'AgentPlugin',
        'participant_id': 50,
      };

      final participant = HubParticipant.fromJson(json);
      expect(participant.isAgent, true);
    });
  });

  group('HubMessage', () {
    test('creates with required values', () {
      final message = HubMessage(
        id: 1,
        content: 'Hello world',
        senderId: 100,
        senderType: 'User',
        senderName: 'John',
        createdAt: DateTime(2025, 1, 15, 10, 0),
      );

      expect(message.id, 1);
      expect(message.content, 'Hello world');
      expect(message.messageType, 'text');
      expect(message.senderId, 100);
      expect(message.senderType, 'User');
      expect(message.senderName, 'John');
      expect(message.edited, false);
    });

    test('fromJson parses complete data', () {
      final json = {
        'id': 123,
        'content': 'Test message',
        'message_type': 'text',
        'sender_id': 1,
        'sender_type': 'User',
        'sender_name': 'Jane',
        'created_at': '2025-01-15T10:00:00Z',
        'edited': true,
        'reactions': {'👍': 3},
        'reply_to_id': 100,
        'attachments': [{'name': 'file.pdf'}],
        'thread_id': 50,
        'channel_id': 25,
      };

      final message = HubMessage.fromJson(json);

      expect(message.id, 123);
      expect(message.content, 'Test message');
      expect(message.edited, true);
      expect(message.reactions, isNotNull);
      expect(message.replyToId, 100);
      expect(message.attachments, isNotNull);
      expect(message.threadId, 50);
      expect(message.channelId, 25);
    });

    test('toJson serializes all fields', () {
      final message = HubMessage(
        id: 1,
        content: 'Test',
        senderId: 1,
        senderType: 'User',
        senderName: 'Test User',
        createdAt: DateTime.parse('2025-01-15T10:00:00Z'),
      );

      final json = message.toJson();

      expect(json['id'], 1);
      expect(json['content'], 'Test');
      expect(json['sender_id'], 1);
      expect(json['sender_type'], 'User');
      expect(json['sender_name'], 'Test User');
    });

    group('type checks', () {
      test('isFromUser returns true for User sender', () {
        final message = HubMessage(
          id: 1,
          content: 'Test',
          senderId: 1,
          senderType: 'User',
          senderName: 'John',
          createdAt: DateTime.now(),
        );

        expect(message.isFromUser, true);
        expect(message.isFromAgent, false);
      });

      test('isFromAgent returns true for AgentPlugin sender', () {
        final message = HubMessage(
          id: 1,
          content: 'Test',
          senderId: 1,
          senderType: 'AgentPlugin',
          senderName: 'Scout',
          createdAt: DateTime.now(),
        );

        expect(message.isFromUser, false);
        expect(message.isFromAgent, true);
      });

      test('isGif returns true for gif message type', () {
        final message = HubMessage(
          id: 1,
          content: 'gif_url',
          messageType: 'gif',
          senderId: 1,
          senderType: 'User',
          senderName: 'John',
          createdAt: DateTime.now(),
        );

        expect(message.isGif, true);
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

        expect(message.hasAttachments, true);
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

        expect(message.hasAttachments, false);
      });
    });
  });

  group('TeamMember', () {
    test('creates with required values', () {
      final member = TeamMember(
        id: 1,
        firstName: 'John',
        lastName: 'Doe',
        email: 'john.doe@example.com',
      );

      expect(member.id, 1);
      expect(member.firstName, 'John');
      expect(member.lastName, 'Doe');
      expect(member.email, 'john.doe@example.com');
      expect(member.status, 'offline');
      expect(member.isOnline, false);
    });

    test('fromJson parses complete data', () {
      final json = {
        'id': 123,
        'first_name': 'Jane',
        'last_name': 'Smith',
        'email': 'jane@example.com',
        'role': 'admin',
        'avatar_url': 'https://example.com/avatar.png',
        'status': 'online',
        'status_message': 'Working on project',
        'is_online': true,
      };

      final member = TeamMember.fromJson(json);

      expect(member.id, 123);
      expect(member.firstName, 'Jane');
      expect(member.lastName, 'Smith');
      expect(member.role, 'admin');
      expect(member.avatarUrl, 'https://example.com/avatar.png');
      expect(member.status, 'online');
      expect(member.statusMessage, 'Working on project');
      expect(member.isOnline, true);
    });

    test('fullName combines first and last name', () {
      final member = TeamMember(
        id: 1,
        firstName: 'John',
        lastName: 'Doe',
        email: 'john@example.com',
      );

      expect(member.fullName, 'John Doe');
    });

    test('fullName trims whitespace', () {
      final member = TeamMember(
        id: 1,
        firstName: '  John  ',
        lastName: '  Doe  ',
        email: 'john@example.com',
      );

      // fullName is '$firstName $lastName'.trim() = '  John     Doe  '.trim() = 'John     Doe'
      expect(member.fullName, '  John     Doe  '.trim());
    });

    test('initials returns uppercase first letters', () {
      final member = TeamMember(
        id: 1,
        firstName: 'john',
        lastName: 'doe',
        email: 'john@example.com',
      );

      expect(member.initials, 'JD');
    });

    test('initials handles empty names', () {
      final member = TeamMember(
        id: 1,
        firstName: '',
        lastName: '',
        email: 'test@example.com',
      );

      expect(member.initials, '');
    });

    test('initials handles single name', () {
      final member = TeamMember(
        id: 1,
        firstName: 'John',
        lastName: '',
        email: 'test@example.com',
      );

      expect(member.initials, 'J');
    });
  });

  group('DmThread', () {
    test('creates with required values', () {
      final dm = DmThread(
        id: 1,
        displayName: 'John Doe',
      );

      expect(dm.id, 1);
      expect(dm.displayName, 'John Doe');
      expect(dm.otherParticipant, isNull);
      expect(dm.unreadCount, 0);
      expect(dm.lastActivityAt, isNull);
      expect(dm.lastMessage, isNull);
    });

    test('fromJson parses complete data', () {
      final json = {
        'id': 123,
        'display_name': 'Scout',
        'participant': {
          'id': 1,
          'participant_type': 'AgentPlugin',
          'participant_id': 50,
          'name': 'Scout',
          'is_agent': true,
        },
        'unread_count': 3,
        'last_activity_at': '2025-01-15T10:00:00Z',
        'last_message': 'Hello, how can I help?',
      };

      final dm = DmThread.fromJson(json);

      expect(dm.id, 123);
      expect(dm.displayName, 'Scout');
      expect(dm.otherParticipant, isNotNull);
      expect(dm.otherParticipant!.isAgent, true);
      expect(dm.unreadCount, 3);
      expect(dm.lastActivityAt, isNotNull);
      expect(dm.lastMessage, 'Hello, how can I help?');
    });

    test('fromJson handles minimal data', () {
      final json = <String, dynamic>{};
      final dm = DmThread.fromJson(json);

      expect(dm.id, 0);
      expect(dm.displayName, '');
      expect(dm.unreadCount, 0);
    });
  });
}
