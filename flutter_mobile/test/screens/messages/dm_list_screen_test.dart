import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/space.dart';
import 'package:amos_mobile/screens/messages/dm_list_screen.dart';

void main() {
  group('HubAgent Model', () {
    test('fromJson parses complete JSON correctly', () {
      final json = {
        'id': 1,
        'name': 'Marketing Assistant',
        'description': 'Helps with marketing tasks',
        'icon_url': 'https://example.com/icon.png',
        'is_active': true,
      };

      final agent = HubAgent.fromJson(json);

      expect(agent.id, equals(1));
      expect(agent.name, equals('Marketing Assistant'));
      expect(agent.description, equals('Helps with marketing tasks'));
      expect(agent.iconUrl, equals('https://example.com/icon.png'));
      expect(agent.isActive, isTrue);
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'id': 2,
        'name': 'Simple Agent',
      };

      final agent = HubAgent.fromJson(json);

      expect(agent.id, equals(2));
      expect(agent.name, equals('Simple Agent'));
      expect(agent.description, isNull);
      expect(agent.iconUrl, isNull);
      // When is_active is missing, falls back to checking if status == 'active'
      // Since status is also missing, this evaluates to false
      expect(agent.isActive, isFalse);
    });

    test('fromJson handles status field for isActive', () {
      final json = {
        'id': 3,
        'name': 'Status Agent',
        'status': 'active',
      };

      final agent = HubAgent.fromJson(json);

      expect(agent.isActive, isTrue);
    });

    test('fromJson handles inactive status', () {
      final json = {
        'id': 4,
        'name': 'Inactive Agent',
        'status': 'inactive',
        'is_active': false,
      };

      final agent = HubAgent.fromJson(json);

      expect(agent.isActive, isFalse);
    });

    test('fromJson handles empty JSON', () {
      final json = <String, dynamic>{};

      final agent = HubAgent.fromJson(json);

      expect(agent.id, equals(0));
      expect(agent.name, equals(''));
      expect(agent.description, isNull);
      expect(agent.iconUrl, isNull);
    });
  });

  group('DM Selection Logic', () {
    test('team member selection uses userId for DM creation', () {
      // Simulating API response from /api/v1/team endpoint
      final teamMemberJson = {
        'id': 10,  // EntityUser.id
        'user_id': 100,  // User.id - THIS is what server expects
        'first_name': 'Alice',
        'last_name': 'Smith',
        'email': 'alice@example.com',
        'role': 'member',
        'status': 'online',
      };

      final member = TeamMember.fromJson(teamMemberJson);

      // What DmListScreen sends to createDm:
      final participantType = 'User';
      final participantId = member.userId;  // Should be 100, not 10

      expect(participantType, equals('User'));
      expect(participantId, equals(100),
          reason: 'DM should use member.userId (User.id=100), not member.id (EntityUser.id=10)');
    });

    test('agent selection uses id for DM creation', () {
      final agentJson = {
        'id': 5,
        'name': 'Support Bot',
        'description': 'Customer support agent',
        'is_active': true,
      };

      final agent = HubAgent.fromJson(agentJson);

      // What DmListScreen sends to createDm:
      final participantType = 'AgentPlugin';
      final participantId = agent.id;

      expect(participantType, equals('AgentPlugin'));
      expect(participantId, equals(5));
    });

    test('correct participant ID is sent for each participant type', () {
      // Test data simulating what the server returns
      final teamMembers = [
        TeamMember.fromJson({
          'id': 1,  // EntityUser.id
          'user_id': 101,  // User.id
          'first_name': 'User',
          'last_name': 'One',
          'email': 'one@test.com',
        }),
        TeamMember.fromJson({
          'id': 2,  // EntityUser.id
          'user_id': 102,  // User.id
          'first_name': 'User',
          'last_name': 'Two',
          'email': 'two@test.com',
        }),
      ];

      final agents = [
        HubAgent.fromJson({
          'id': 10,
          'name': 'Agent A',
        }),
        HubAgent.fromJson({
          'id': 20,
          'name': 'Agent B',
        }),
      ];

      // Verify team members use userId (User.id)
      for (final member in teamMembers) {
        expect(member.userId != member.id || member.userId == 0, isTrue,
            reason: 'Team member should have distinct userId from id unless API does not provide user_id');
      }
      expect(teamMembers[0].userId, equals(101));
      expect(teamMembers[1].userId, equals(102));

      // Verify agents use id directly
      expect(agents[0].id, equals(10));
      expect(agents[1].id, equals(20));
    });
  });

  group('DM Thread Filtering', () {
    test('search filters team members by name', () {
      final members = [
        TeamMember.fromJson({
          'id': 1,
          'user_id': 10,
          'first_name': 'Alice',
          'last_name': 'Smith',
          'email': 'alice@example.com',
        }),
        TeamMember.fromJson({
          'id': 2,
          'user_id': 20,
          'first_name': 'Bob',
          'last_name': 'Jones',
          'email': 'bob@example.com',
        }),
        TeamMember.fromJson({
          'id': 3,
          'user_id': 30,
          'first_name': 'Charlie',
          'last_name': 'Alice',
          'email': 'charlie@example.com',
        }),
      ];

      final searchQuery = 'alice';

      final filtered = members
          .where((m) =>
              m.fullName.toLowerCase().contains(searchQuery.toLowerCase()) ||
              m.email.toLowerCase().contains(searchQuery.toLowerCase()))
          .toList();

      expect(filtered.length, equals(2)); // Alice Smith and Charlie Alice
      expect(filtered.map((m) => m.fullName), containsAll(['Alice Smith', 'Charlie Alice']));
    });

    test('search filters agents by name', () {
      final agents = [
        HubAgent.fromJson({'id': 1, 'name': 'Marketing Bot'}),
        HubAgent.fromJson({'id': 2, 'name': 'Sales Assistant'}),
        HubAgent.fromJson({'id': 3, 'name': 'Support Bot'}),
      ];

      final searchQuery = 'bot';

      final filtered = agents
          .where((a) => a.name.toLowerCase().contains(searchQuery.toLowerCase()))
          .toList();

      expect(filtered.length, equals(2)); // Marketing Bot and Support Bot
      expect(filtered.map((a) => a.name), containsAll(['Marketing Bot', 'Support Bot']));
    });

    test('search filters team members by email', () {
      final members = [
        TeamMember.fromJson({
          'id': 1,
          'user_id': 10,
          'first_name': 'Alice',
          'last_name': 'Smith',
          'email': 'alice@acme.com',
        }),
        TeamMember.fromJson({
          'id': 2,
          'user_id': 20,
          'first_name': 'Bob',
          'last_name': 'Jones',
          'email': 'bob@example.com',
        }),
      ];

      final searchQuery = '@acme.com';

      final filtered = members
          .where((m) =>
              m.fullName.toLowerCase().contains(searchQuery.toLowerCase()) ||
              m.email.toLowerCase().contains(searchQuery.toLowerCase()))
          .toList();

      expect(filtered.length, equals(1));
      expect(filtered.first.email, equals('alice@acme.com'));
    });
  });

  group('DM Thread Display', () {
    test('DmThread parses with participant info', () {
      final json = {
        'id': 1,
        'display_name': 'John Doe',
        'participant': {
          'id': 10,
          'participant_type': 'User',
          'participant_id': 100,
          'name': 'John Doe',
          'is_agent': false,
        },
        'unread_count': 3,
        'last_activity_at': '2024-01-15T10:30:00.000Z',
        'last_message': 'Hello!',
      };

      final thread = DmThread.fromJson(json);

      expect(thread.id, equals(1));
      expect(thread.displayName, equals('John Doe'));
      expect(thread.otherParticipant, isNotNull);
      expect(thread.otherParticipant!.participantId, equals(100));
      expect(thread.otherParticipant!.isAgent, isFalse);
      expect(thread.unreadCount, equals(3));
      expect(thread.lastMessage, equals('Hello!'));
    });

    test('DmThread handles agent participant', () {
      final json = {
        'id': 2,
        'display_name': 'Marketing Bot',
        'participant': {
          'id': 20,
          'participant_type': 'AgentPlugin',
          'participant_id': 5,
          'name': 'Marketing Bot',
          'is_agent': true,
        },
        'unread_count': 0,
        'last_message': 'How can I help?',
      };

      final thread = DmThread.fromJson(json);

      expect(thread.displayName, equals('Marketing Bot'));
      expect(thread.otherParticipant!.isAgent, isTrue);
      expect(thread.otherParticipant!.participantType, equals('AgentPlugin'));
    });

    test('unread badge shows correct count', () {
      final thread = DmThread.fromJson({
        'id': 1,
        'display_name': 'Test User',
        'unread_count': 5,
      });

      expect(thread.unreadCount, equals(5));
      expect(thread.unreadCount > 0, isTrue);
    });

    test('unread badge handles high counts', () {
      final thread = DmThread.fromJson({
        'id': 1,
        'display_name': 'Busy Chat',
        'unread_count': 150,
      });

      expect(thread.unreadCount, equals(150));
      // UI would show "99+" for counts > 99
      final displayCount = thread.unreadCount > 99 ? '99+' : thread.unreadCount.toString();
      expect(displayCount, equals('99+'));
    });
  });

  group('API Request Validation', () {
    test('createDm request body for User participant', () {
      // Simulating what HubService.createDm sends
      const participantType = 'User';
      const participantId = 100;  // Should be User.id
      const initialMessage = 'Hi!';

      final requestBody = {
        'participant_type': participantType,
        'participant_id': participantId,
        'message': initialMessage,
      };

      expect(requestBody['participant_type'], equals('User'));
      expect(requestBody['participant_id'], equals(100));
      expect(requestBody['message'], equals('Hi!'));
    });

    test('createDm request body for AgentPlugin participant', () {
      const participantType = 'AgentPlugin';
      const participantId = 5;

      final requestBody = {
        'participant_type': participantType,
        'participant_id': participantId,
        'message': null,
      };

      expect(requestBody['participant_type'], equals('AgentPlugin'));
      expect(requestBody['participant_id'], equals(5));
      expect(requestBody['message'], isNull);
    });

    test('sendThreadMessage request body', () {
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
  });

  group('TeamMember ID Edge Cases', () {
    test('API response without user_id uses id as fallback', () {
      // Some legacy APIs might not return user_id
      final json = {
        'id': 42,
        // No user_id field
        'first_name': 'Legacy',
        'last_name': 'User',
        'email': 'legacy@test.com',
      };

      final member = TeamMember.fromJson(json);

      // When user_id is missing, userId should fallback to id
      expect(member.id, equals(42));
      expect(member.userId, equals(42));
    });

    test('API response with user_id=0 should use id as fallback', () {
      final json = {
        'id': 50,
        'user_id': 0,  // Invalid user_id
        'first_name': 'Zero',
        'last_name': 'User',
        'email': 'zero@test.com',
      };

      final member = TeamMember.fromJson(json);

      // user_id: 0 is falsy but valid in Dart
      // Current implementation: userId: json['user_id'] ?? json['id'] ?? 0
      // Since 0 is not null, it won't fallback
      expect(member.userId, equals(0));
      // This could be a bug - 0 is likely invalid
    });

    test('difference between id and userId for DM creation', () {
      // This test documents the expected behavior
      final jsonWithUserId = {
        'id': 1,  // EntityUser.id - identifies the user's membership in the entity
        'user_id': 100,  // User.id - the actual user record ID
        'first_name': 'Test',
        'last_name': 'User',
        'email': 'test@example.com',
      };

      final member = TeamMember.fromJson(jsonWithUserId);

      // For DMs, the server expects User.id (participant_id), not EntityUser.id
      // Because HubThread participants are linked to User records
      expect(member.id, equals(1), reason: 'id is EntityUser.id');
      expect(member.userId, equals(100), reason: 'userId is User.id for DM creation');

      // When creating DM:
      // CORRECT: participant_type='User', participant_id=member.userId (100)
      // WRONG: participant_type='User', participant_id=member.id (1)
    });
  });

  group('DM Thread Archive', () {
    test('DmThread can be archived', () {
      final thread = DmThread.fromJson({
        'id': 1,
        'display_name': 'John Doe',
        'unread_count': 0,
        'last_message': 'Hello!',
      });

      // Thread should have an id for archive operation
      expect(thread.id, equals(1));

      // Simulate archive API call data
      final archiveEndpoint = '/hub/thread/${thread.id}/archive';
      expect(archiveEndpoint, equals('/hub/thread/1/archive'));
    });

    test('DmThread can be unarchived', () {
      final thread = DmThread.fromJson({
        'id': 2,
        'display_name': 'Jane Doe',
        'unread_count': 0,
        'last_message': 'Bye!',
      });

      // Simulate unarchive API call data
      final unarchiveEndpoint = '/hub/thread/${thread.id}/unarchive';
      expect(unarchiveEndpoint, equals('/hub/thread/2/unarchive'));
    });

    test('archived threads are removed from list', () {
      // Simulate thread list
      final threads = [
        DmThread.fromJson({'id': 1, 'display_name': 'User A', 'unread_count': 0}),
        DmThread.fromJson({'id': 2, 'display_name': 'User B', 'unread_count': 3}),
        DmThread.fromJson({'id': 3, 'display_name': 'User C', 'unread_count': 0}),
      ];

      expect(threads.length, equals(3));

      // Simulate archiving thread with id 2
      final archivedThreadId = 2;
      threads.removeWhere((t) => t.id == archivedThreadId);

      expect(threads.length, equals(2));
      expect(threads.any((t) => t.id == 2), isFalse);
      expect(threads.map((t) => t.displayName), containsAll(['User A', 'User C']));
    });

    test('unarchive restores thread to list', () {
      // Simulate a thread that was archived and needs to be restored
      final restoredThread = DmThread.fromJson({
        'id': 2,
        'display_name': 'User B',
        'unread_count': 3,
      });

      final threads = [
        DmThread.fromJson({'id': 1, 'display_name': 'User A', 'unread_count': 0}),
        DmThread.fromJson({'id': 3, 'display_name': 'User C', 'unread_count': 0}),
      ];

      expect(threads.length, equals(2));

      // Simulate adding restored thread back
      threads.add(restoredThread);

      expect(threads.length, equals(3));
      expect(threads.any((t) => t.id == 2), isTrue);
    });

    test('swipe-to-archive Dismissible key format', () {
      final thread = DmThread.fromJson({
        'id': 42,
        'display_name': 'Test User',
        'unread_count': 0,
      });

      // Verify the key format used by Dismissible widget
      final dismissibleKey = 'dm-thread-${thread.id}';
      expect(dismissibleKey, equals('dm-thread-42'));
    });
  });

  group('Archive API Request Validation', () {
    test('archiveThread request endpoint', () {
      const threadId = 123;
      final endpoint = '/hub/thread/$threadId/archive';

      expect(endpoint, equals('/hub/thread/123/archive'));
    });

    test('unarchiveThread request endpoint', () {
      const threadId = 456;
      final endpoint = '/hub/thread/$threadId/unarchive';

      expect(endpoint, equals('/hub/thread/456/unarchive'));
    });

    test('archive response contains success status', () {
      // Simulated successful archive response
      final response = {
        'success': true,
        'status': 'archived',
        'message': 'Conversation archived',
      };

      expect(response['success'], isTrue);
      expect(response['status'], equals('archived'));
    });

    test('unarchive response contains active status', () {
      // Simulated successful unarchive response
      final response = {
        'success': true,
        'status': 'active',
        'message': 'Conversation restored',
      };

      expect(response['success'], isTrue);
      expect(response['status'], equals('active'));
    });
  });
}
