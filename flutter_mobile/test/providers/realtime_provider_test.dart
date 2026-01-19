import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/space.dart';
import 'package:amos_mobile/services/action_cable_service.dart';
import 'package:amos_mobile/providers/realtime_provider.dart';

void main() {
  group('RealtimeState', () {
    test('default state has correct initial values', () {
      const state = RealtimeState();

      expect(state.isConnected, isFalse);
      expect(state.unreadTeamMessages, equals(0));
      expect(state.recentMessages, isEmpty);
      expect(state.recentJobNotifications, isEmpty);
    });

    test('copyWith updates isConnected', () {
      const original = RealtimeState();

      final updated = original.copyWith(isConnected: true);

      expect(updated.isConnected, isTrue);
      expect(updated.unreadTeamMessages, equals(0));
      expect(updated.recentMessages, isEmpty);
      expect(updated.recentJobNotifications, isEmpty);
    });

    test('copyWith updates unreadTeamMessages', () {
      const original = RealtimeState();

      final updated = original.copyWith(unreadTeamMessages: 5);

      expect(updated.isConnected, isFalse);
      expect(updated.unreadTeamMessages, equals(5));
    });

    test('copyWith updates recentMessages', () {
      const original = RealtimeState();

      final message = HubMessage(
        id: 1,
        content: 'Test message',
        senderId: 1,
        senderType: 'User',
        senderName: 'Test User',
        createdAt: DateTime(2024, 1, 1),
      );

      final updated = original.copyWith(recentMessages: [message]);

      expect(updated.recentMessages.length, equals(1));
      expect(updated.recentMessages.first.content, equals('Test message'));
    });

    test('copyWith updates recentJobNotifications', () {
      const original = RealtimeState();

      final notification = JobNotification(
        type: 'job_completed',
        jobType: 'export',
        message: 'Export completed',
        status: 'completed',
      );

      final updated = original.copyWith(recentJobNotifications: [notification]);

      expect(updated.recentJobNotifications.length, equals(1));
      expect(updated.recentJobNotifications.first.message, equals('Export completed'));
    });

    test('copyWith preserves unspecified values', () {
      final message = HubMessage(
        id: 1,
        content: 'Test message',
        senderId: 1,
        senderType: 'User',
        senderName: 'Test User',
        createdAt: DateTime(2024, 1, 1),
      );

      final original = RealtimeState(
        isConnected: true,
        unreadTeamMessages: 3,
        recentMessages: [message],
      );

      final updated = original.copyWith(unreadTeamMessages: 5);

      expect(updated.isConnected, isTrue);
      expect(updated.unreadTeamMessages, equals(5));
      expect(updated.recentMessages.length, equals(1));
    });

    test('copyWith with all null values returns equivalent state', () {
      final message = HubMessage(
        id: 1,
        content: 'Test message',
        senderId: 1,
        senderType: 'User',
        senderName: 'Test User',
        createdAt: DateTime(2024, 1, 1),
      );

      final original = RealtimeState(
        isConnected: true,
        unreadTeamMessages: 3,
        recentMessages: [message],
      );

      final updated = original.copyWith();

      expect(updated.isConnected, equals(original.isConnected));
      expect(updated.unreadTeamMessages, equals(original.unreadTeamMessages));
      expect(updated.recentMessages, equals(original.recentMessages));
      expect(updated.recentJobNotifications, equals(original.recentJobNotifications));
    });
  });

  group('HubMessage', () {
    test('fromJson parses message correctly', () {
      final json = {
        'id': 1,
        'content': 'Hello world',
        'message_type': 'text',
        'sender_id': 42,
        'sender_type': 'User',
        'sender_name': 'John Doe',
        'created_at': '2024-01-15T10:30:00Z',
        'edited': false,
        'thread_id': 5,
        'channel_id': 2,
      };

      final message = HubMessage.fromJson(json);

      expect(message.id, equals(1));
      expect(message.content, equals('Hello world'));
      expect(message.messageType, equals('text'));
      expect(message.senderId, equals(42));
      expect(message.senderType, equals('User'));
      expect(message.senderName, equals('John Doe'));
      expect(message.edited, isFalse);
      expect(message.threadId, equals(5));
      expect(message.channelId, equals(2));
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'id': 1,
        'content': 'Test',
        'sender_id': 1,
        'sender_type': 'User',
        'sender_name': 'Test',
        'created_at': '2024-01-15T10:30:00Z',
      };

      final message = HubMessage.fromJson(json);

      expect(message.messageType, equals('text'));
      expect(message.edited, isFalse);
      expect(message.reactions, isNull);
      expect(message.replyToId, isNull);
      expect(message.attachments, isNull);
      expect(message.threadId, isNull);
      expect(message.channelId, isNull);
    });

    test('isFromUser returns true for User sender type', () {
      final message = HubMessage(
        id: 1,
        content: 'Test',
        senderId: 1,
        senderType: 'User',
        senderName: 'Test User',
        createdAt: DateTime.now(),
      );

      expect(message.isFromUser, isTrue);
      expect(message.isFromAgent, isFalse);
    });

    test('isFromAgent returns true for AgentPlugin sender type', () {
      final message = HubMessage(
        id: 1,
        content: 'Test',
        senderId: 1,
        senderType: 'AgentPlugin',
        senderName: 'Test Agent',
        createdAt: DateTime.now(),
      );

      expect(message.isFromAgent, isTrue);
      expect(message.isFromUser, isFalse);
    });

    test('isGif returns true for gif message type', () {
      final message = HubMessage(
        id: 1,
        content: 'https://giphy.com/test.gif',
        messageType: 'gif',
        senderId: 1,
        senderType: 'User',
        senderName: 'Test',
        createdAt: DateTime.now(),
      );

      expect(message.isGif, isTrue);
    });

    test('hasAttachments returns true when attachments exist', () {
      final message = HubMessage(
        id: 1,
        content: 'Test',
        senderId: 1,
        senderType: 'User',
        senderName: 'Test',
        createdAt: DateTime.now(),
        attachments: [
          {'filename': 'doc.pdf', 'url': 'https://example.com/doc.pdf'}
        ],
      );

      expect(message.hasAttachments, isTrue);
    });

    test('hasAttachments returns false for empty attachments', () {
      final message = HubMessage(
        id: 1,
        content: 'Test',
        senderId: 1,
        senderType: 'User',
        senderName: 'Test',
        createdAt: DateTime.now(),
        attachments: [],
      );

      expect(message.hasAttachments, isFalse);
    });

    test('hasAttachments returns false when attachments is null', () {
      final message = HubMessage(
        id: 1,
        content: 'Test',
        senderId: 1,
        senderType: 'User',
        senderName: 'Test',
        createdAt: DateTime.now(),
      );

      expect(message.hasAttachments, isFalse);
    });

    test('toJson serializes message correctly', () {
      final createdAt = DateTime(2024, 1, 15, 10, 30, 0);
      final message = HubMessage(
        id: 1,
        content: 'Hello',
        messageType: 'text',
        senderId: 42,
        senderType: 'User',
        senderName: 'John',
        createdAt: createdAt,
        edited: true,
        threadId: 5,
        channelId: 2,
      );

      final json = message.toJson();

      expect(json['id'], equals(1));
      expect(json['content'], equals('Hello'));
      expect(json['message_type'], equals('text'));
      expect(json['sender_id'], equals(42));
      expect(json['sender_type'], equals('User'));
      expect(json['sender_name'], equals('John'));
      expect(json['edited'], isTrue);
      expect(json['thread_id'], equals(5));
      expect(json['channel_id'], equals(2));
    });
  });

  group('TeamChannel', () {
    test('fromJson parses channel correctly', () {
      final json = {
        'id': 1,
        'name': 'General',
        'description': 'General discussion',
        'channel_type': 'general',
        'icon': 'hash',
        'is_private': false,
        'member_count': 10,
        'agent_count': 2,
        'unread': 5,
        'main_thread_id': 42,
      };

      final channel = TeamChannel.fromJson(json);

      expect(channel.id, equals(1));
      expect(channel.name, equals('General'));
      expect(channel.description, equals('General discussion'));
      expect(channel.channelType, equals('general'));
      expect(channel.isPrivate, isFalse);
      expect(channel.memberCount, equals(10));
      expect(channel.agentCount, equals(2));
      expect(channel.unreadCount, equals(5));
      expect(channel.mainThreadId, equals(42));
    });

    test('displayIcon returns hash for general channel', () {
      final channel = TeamChannel(
        id: 1,
        name: 'General',
        channelType: 'general',
      );

      expect(channel.displayIcon, equals('#'));
    });

    test('displayIcon returns lock emoji for private channel', () {
      final channel = TeamChannel(
        id: 1,
        name: 'Private',
        isPrivate: true,
      );

      expect(channel.displayIcon, equals('\u{1F512}')); // Lock emoji
    });

    test('displayIcon returns megaphone for announcements', () {
      final channel = TeamChannel(
        id: 1,
        name: 'Announcements',
        channelType: 'announcements',
      );

      expect(channel.displayIcon, equals('\u{1F4E2}')); // Megaphone emoji
    });

    test('displayIcon handles hash icon name', () {
      final channel = TeamChannel(
        id: 1,
        name: 'Test',
        icon: 'hash',
      );

      expect(channel.displayIcon, equals('#'));
    });

    test('displayIcon handles lock icon name', () {
      final channel = TeamChannel(
        id: 1,
        name: 'Test',
        icon: 'lock',
      );

      expect(channel.displayIcon, equals('\u{1F512}'));
    });
  });

  group('HubThread', () {
    test('fromJson parses thread correctly', () {
      final json = {
        'id': 1,
        'thread_type': 'dm',
        'subject': 'Quick question',
        'display_name': 'John Doe',
        'status': 'active',
        'message_count': 15,
        'unread_count': 3,
      };

      final thread = HubThread.fromJson(json);

      expect(thread.id, equals(1));
      expect(thread.threadType, equals('dm'));
      expect(thread.subject, equals('Quick question'));
      expect(thread.displayName, equals('John Doe'));
      expect(thread.status, equals('active'));
      expect(thread.messageCount, equals(15));
      expect(thread.unreadCount, equals(3));
    });

    test('isDm returns true for dm thread type', () {
      final thread = HubThread(
        id: 1,
        threadType: 'dm',
        displayName: 'Test',
      );

      expect(thread.isDm, isTrue);
      expect(thread.isChannel, isFalse);
      expect(thread.isWorkStream, isFalse);
    });

    test('isChannel returns true for channel thread type', () {
      final thread = HubThread(
        id: 1,
        threadType: 'channel',
        displayName: 'Test',
      );

      expect(thread.isChannel, isTrue);
      expect(thread.isDm, isFalse);
    });

    test('isWorkStream returns true for work_stream thread type', () {
      final thread = HubThread(
        id: 1,
        threadType: 'work_stream',
        displayName: 'Test',
      );

      expect(thread.isWorkStream, isTrue);
      expect(thread.isDm, isFalse);
      expect(thread.isChannel, isFalse);
    });
  });

  group('TeamMember', () {
    test('fromJson parses member correctly', () {
      final json = {
        'id': 1,
        'first_name': 'John',
        'last_name': 'Doe',
        'email': 'john@example.com',
        'role': 'admin',
        'avatar_url': 'https://example.com/avatar.jpg',
        'status': 'online',
        'status_message': 'Working remotely',
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
      expect(member.statusMessage, equals('Working remotely'));
      expect(member.isOnline, isTrue);
    });

    test('fullName combines first and last name', () {
      final member = TeamMember(
        id: 1,
        firstName: 'John',
        lastName: 'Doe',
        email: 'john@example.com',
      );

      expect(member.fullName, equals('John Doe'));
    });

    test('fullName handles empty last name', () {
      final member = TeamMember(
        id: 1,
        firstName: 'John',
        lastName: '',
        email: 'john@example.com',
      );

      expect(member.fullName, equals('John'));
    });

    test('initials returns first letters of first and last name', () {
      final member = TeamMember(
        id: 1,
        firstName: 'John',
        lastName: 'Doe',
        email: 'john@example.com',
      );

      expect(member.initials, equals('JD'));
    });

    test('initials handles empty names', () {
      final member = TeamMember(
        id: 1,
        firstName: '',
        lastName: '',
        email: 'test@example.com',
      );

      expect(member.initials, equals(''));
    });
  });

  group('HubParticipant', () {
    test('fromJson parses participant correctly', () {
      final json = {
        'id': 1,
        'participant_type': 'User',
        'participant_id': 42,
        'name': 'John Doe',
        'role': 'member',
        'is_agent': false,
      };

      final participant = HubParticipant.fromJson(json);

      expect(participant.id, equals(1));
      expect(participant.participantType, equals('User'));
      expect(participant.participantId, equals(42));
      expect(participant.name, equals('John Doe'));
      expect(participant.role, equals('member'));
      expect(participant.isAgent, isFalse);
    });

    test('fromJson detects agent from participant_type', () {
      final json = {
        'id': 1,
        'participant_type': 'AgentPlugin',
        'participant_id': 5,
        'name': 'AI Assistant',
      };

      final participant = HubParticipant.fromJson(json);

      expect(participant.isAgent, isTrue);
    });
  });

  group('DmThread', () {
    test('fromJson parses dm thread correctly', () {
      final json = {
        'id': 1,
        'display_name': 'John Doe',
        'unread_count': 3,
        'last_activity_at': '2024-01-15T10:30:00Z',
        'last_message': 'Hey, how are you?',
        'participant': {
          'id': 42,
          'participant_type': 'User',
          'participant_id': 42,
          'name': 'John Doe',
        },
      };

      final dmThread = DmThread.fromJson(json);

      expect(dmThread.id, equals(1));
      expect(dmThread.displayName, equals('John Doe'));
      expect(dmThread.unreadCount, equals(3));
      expect(dmThread.lastMessage, equals('Hey, how are you?'));
      expect(dmThread.otherParticipant, isNotNull);
      expect(dmThread.otherParticipant!.name, equals('John Doe'));
    });

    test('fromJson handles missing participant', () {
      final json = {
        'id': 1,
        'display_name': 'Unknown',
      };

      final dmThread = DmThread.fromJson(json);

      expect(dmThread.otherParticipant, isNull);
    });
  });
}
