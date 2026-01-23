import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/work_item.dart';

void main() {
  group('WorkItem', () {
    test('fromJson parses complete JSON correctly', () {
      final json = {
        'id': 1,
        'work_type': 'task_completed',
        'title': 'Email Campaign Completed',
        'summary': 'Campaign sent to 500 recipients',
        'details': 'Full details here',
        'icon': '📧',
        'category': 'marketing',
        'priority': 'high',
        'read': true,
        'starred': true,
        'archived': false,
        'requires_action': true,
        'action_type': 'review',
        'action_due_at': '2024-01-20T09:00:00.000Z',
        'agent_name': 'Marketing Agent',
        'time_ago': '5 minutes ago',
        'asset_type': 'campaign',
        'asset_id': 123,
        'asset_data': {'name': 'Test Campaign'},
        'metadata': {'source': 'api'},
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-16T11:00:00.000Z',
      };

      final item = WorkItem.fromJson(json);

      expect(item.id, equals(1));
      expect(item.workType, equals('task_completed'));
      expect(item.title, equals('Email Campaign Completed'));
      expect(item.summary, equals('Campaign sent to 500 recipients'));
      expect(item.details, equals('Full details here'));
      expect(item.icon, equals('📧'));
      expect(item.category, equals('marketing'));
      expect(item.priority, equals('high'));
      expect(item.read, isTrue);
      expect(item.starred, isTrue);
      expect(item.archived, isFalse);
      expect(item.requiresAction, isTrue);
      expect(item.actionType, equals('review'));
      expect(item.actionDueAt, equals(DateTime.parse('2024-01-20T09:00:00.000Z')));
      expect(item.agentName, equals('Marketing Agent'));
      expect(item.assetType, equals('campaign'));
      expect(item.assetId, equals(123));
    });

    test('fromJson handles minimal required fields with defaults', () {
      final json = {
        'id': 1,
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-16T11:00:00.000Z',
      };

      final item = WorkItem.fromJson(json);

      expect(item.id, equals(1));
      expect(item.workType, equals('task_completed'));
      expect(item.title, equals('Untitled'));
      expect(item.icon, equals(''));
      expect(item.category, equals('general'));
      expect(item.priority, equals('normal'));
      expect(item.read, isFalse);
      expect(item.starred, isFalse);
      expect(item.archived, isFalse);
      expect(item.requiresAction, isFalse);
    });

    test('toJson serializes correctly', () {
      final item = WorkItem(
        id: 1,
        workType: 'email_sent',
        title: 'Test Item',
        summary: 'Summary',
        icon: '📧',
        category: 'email',
        priority: 'high',
        read: true,
        starred: false,
        archived: false,
        requiresAction: false,
        createdAt: DateTime.parse('2024-01-15T10:30:00.000Z'),
        updatedAt: DateTime.parse('2024-01-16T11:00:00.000Z'),
      );

      final json = item.toJson();

      expect(json['id'], equals(1));
      expect(json['work_type'], equals('email_sent'));
      expect(json['title'], equals('Test Item'));
      expect(json['summary'], equals('Summary'));
      expect(json['priority'], equals('high'));
      expect(json['read'], isTrue);
    });

    test('copyWith creates new item with updated values', () {
      final original = WorkItem(
        id: 1,
        workType: 'task_completed',
        title: 'Original Title',
        icon: '✅',
        category: 'general',
        priority: 'normal',
        read: false,
        starred: false,
        archived: false,
        requiresAction: false,
        createdAt: DateTime.parse('2024-01-15T10:30:00.000Z'),
        updatedAt: DateTime.parse('2024-01-16T11:00:00.000Z'),
      );

      final modified = original.copyWith(
        title: 'Modified Title',
        read: true,
        starred: true,
      );

      expect(modified.id, equals(1));
      expect(modified.title, equals('Modified Title'));
      expect(modified.read, isTrue);
      expect(modified.starred, isTrue);
      expect(original.title, equals('Original Title'));
      expect(original.read, isFalse);
    });

    test('workTypeLabel returns correct labels for all types', () {
      final testCases = {
        'task_completed': 'Task Completed',
        'scheduled_task_completed': 'Scheduled Task',
        'asset_created': 'Asset Created',
        'report_generated': 'Report Generated',
        'email_sent': 'Email Sent',
        'email_drafted': 'Email Drafted',
        'research_completed': 'Research Completed',
        'integration_synced': 'Integration Synced',
        'agent_created': 'Agent Created',
        'tool_created': 'Tool Created',
        'landing_page_created': 'Landing Page Created',
        'campaign_created': 'Campaign Created',
        'analysis_completed': 'Analysis Completed',
        'visualization_created': 'Visualization Created',
        'action_required': 'Action Required',
      };

      for (final entry in testCases.entries) {
        final item = WorkItem(
          id: 1,
          workType: entry.key,
          title: 'Test',
          icon: '✅',
          category: 'general',
          priority: 'normal',
          read: false,
          starred: false,
          archived: false,
          requiresAction: false,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        expect(item.workTypeLabel, equals(entry.value),
            reason: 'Expected ${entry.key} to have label ${entry.value}');
      }
    });

    test('workTypeLabel handles unknown types with underscore replacement', () {
      final item = WorkItem(
        id: 1,
        workType: 'custom_work_type',
        title: 'Test',
        icon: '✅',
        category: 'general',
        priority: 'normal',
        read: false,
        starred: false,
        archived: false,
        requiresAction: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(item.workTypeLabel, equals('custom work type'));
    });

    test('isHighPriority returns true for high priority', () {
      final item = WorkItem(
        id: 1,
        workType: 'task_completed',
        title: 'Test',
        icon: '✅',
        category: 'general',
        priority: 'high',
        read: false,
        starred: false,
        archived: false,
        requiresAction: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(item.isHighPriority, isTrue);
    });

    test('isHighPriority returns true for urgent priority', () {
      final item = WorkItem(
        id: 1,
        workType: 'action_required',
        title: 'Test',
        icon: '⚠️',
        category: 'general',
        priority: 'urgent',
        read: false,
        starred: false,
        archived: false,
        requiresAction: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(item.isHighPriority, isTrue);
    });

    test('isHighPriority returns false for normal priority', () {
      final item = WorkItem(
        id: 1,
        workType: 'task_completed',
        title: 'Test',
        icon: '✅',
        category: 'general',
        priority: 'normal',
        read: false,
        starred: false,
        archived: false,
        requiresAction: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(item.isHighPriority, isFalse);
    });

    test('isHighPriority returns false for low priority', () {
      final item = WorkItem(
        id: 1,
        workType: 'task_completed',
        title: 'Test',
        icon: '✅',
        category: 'general',
        priority: 'low',
        read: false,
        starred: false,
        archived: false,
        requiresAction: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(item.isHighPriority, isFalse);
    });
  });

  group('WorkItemCounts', () {
    test('fromJson parses correctly', () {
      final json = {
        'unread': 10,
        'starred': 5,
        'action_required': 3,
        'total': 50,
      };

      final counts = WorkItemCounts.fromJson(json);

      expect(counts.unread, equals(10));
      expect(counts.starred, equals(5));
      expect(counts.actionRequired, equals(3));
      expect(counts.total, equals(50));
    });

    test('fromJson handles missing values with defaults', () {
      final json = <String, dynamic>{};

      final counts = WorkItemCounts.fromJson(json);

      expect(counts.unread, equals(0));
      expect(counts.starred, equals(0));
      expect(counts.actionRequired, equals(0));
      expect(counts.total, equals(0));
    });
  });
}
