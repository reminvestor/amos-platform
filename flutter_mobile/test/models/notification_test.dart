import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/notification.dart';

void main() {
  group('AppNotification', () {
    test('fromJson parses complete JSON correctly', () {
      final json = {
        'id': 1,
        'notification_type': 'task_completed',
        'title': 'Task Completed',
        'body': 'Your task has been completed successfully',
        'icon': '✅',
        'priority': 'normal',
        'read': false,
        'read_at': null,
        'action_url': '/tasks/123',
        'action_type': 'navigate',
        'time_ago': '5 minutes ago',
        'color_class': 'success',
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-16T11:00:00.000Z',
      };

      final notification = AppNotification.fromJson(json);

      expect(notification.id, equals('1'));
      expect(notification.notificationType, equals('task_completed'));
      expect(notification.title, equals('Task Completed'));
      expect(notification.body, equals('Your task has been completed successfully'));
      expect(notification.icon, equals('✅'));
      expect(notification.priority, equals('normal'));
      expect(notification.read, isFalse);
      expect(notification.readAt, isNull);
      expect(notification.actionUrl, equals('/tasks/123'));
      expect(notification.actionType, equals('navigate'));
      expect(notification.timeAgo, equals('5 minutes ago'));
      expect(notification.colorClass, equals('success'));
    });

    test('fromJson handles minimal required fields with defaults', () {
      final json = {
        'id': '123',
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-16T11:00:00.000Z',
      };

      final notification = AppNotification.fromJson(json);

      expect(notification.id, equals('123'));
      expect(notification.notificationType, equals('system_alert'));
      expect(notification.title, equals(''));
      expect(notification.body, isNull);
      expect(notification.icon, equals('📬'));
      expect(notification.priority, equals('normal'));
      expect(notification.read, isFalse);
      expect(notification.timeAgo, equals(''));
      expect(notification.colorClass, equals('secondary'));
    });

    test('fromJson parses read_at correctly', () {
      final json = {
        'id': '123',
        'read': true,
        'read_at': '2024-01-15T12:00:00.000Z',
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-16T11:00:00.000Z',
      };

      final notification = AppNotification.fromJson(json);

      expect(notification.read, isTrue);
      expect(notification.readAt, equals(DateTime.parse('2024-01-15T12:00:00.000Z')));
    });

    test('displayType returns correct display name for all types', () {
      final testCases = {
        'task_completed': 'Task Completed',
        'task_failed': 'Task Failed',
        'action_required': 'Action Required',
        'daily_digest': 'Daily Digest',
        'weekly_summary': 'Weekly Summary',
        'agent_message': 'Agent Message',
        'asset_created': 'Asset Created',
        'scheduled_reminder': 'Reminder',
        'system_alert': 'System Alert',
        'collaboration_request': 'Collaboration',
        'work_completed': 'Work Completed',
        'unknown_type': 'Notification',
      };

      for (final entry in testCases.entries) {
        final notification = AppNotification(
          id: '123',
          notificationType: entry.key,
          title: 'Test',
          icon: '📬',
          priority: 'normal',
          read: false,
          timeAgo: '',
          colorClass: 'secondary',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        expect(notification.displayType, equals(entry.value),
            reason: 'Expected ${entry.key} to display as ${entry.value}');
      }
    });

    test('isUrgent returns true for urgent priority', () {
      final notification = AppNotification(
        id: '123',
        notificationType: 'system_alert',
        title: 'Urgent Alert',
        icon: '🚨',
        priority: 'urgent',
        read: false,
        timeAgo: '',
        colorClass: 'danger',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(notification.isUrgent, isTrue);
    });

    test('isUrgent returns true for high priority', () {
      final notification = AppNotification(
        id: '123',
        notificationType: 'action_required',
        title: 'High Priority',
        icon: '⚠️',
        priority: 'high',
        read: false,
        timeAgo: '',
        colorClass: 'warning',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(notification.isUrgent, isTrue);
    });

    test('isUrgent returns false for normal priority', () {
      final notification = AppNotification(
        id: '123',
        notificationType: 'task_completed',
        title: 'Normal',
        icon: '✅',
        priority: 'normal',
        read: false,
        timeAgo: '',
        colorClass: 'success',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(notification.isUrgent, isFalse);
    });

    test('isUrgent returns false for low priority', () {
      final notification = AppNotification(
        id: '123',
        notificationType: 'daily_digest',
        title: 'Low Priority',
        icon: '📊',
        priority: 'low',
        read: false,
        timeAgo: '',
        colorClass: 'info',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(notification.isUrgent, isFalse);
    });

    test('copyWith creates new notification with updated values', () {
      final original = AppNotification(
        id: '123',
        notificationType: 'task_completed',
        title: 'Original Title',
        body: 'Original body',
        icon: '✅',
        priority: 'normal',
        read: false,
        timeAgo: '5 min ago',
        colorClass: 'success',
        createdAt: DateTime.parse('2024-01-15T10:30:00.000Z'),
        updatedAt: DateTime.parse('2024-01-16T11:00:00.000Z'),
      );

      final modified = original.copyWith(
        title: 'Modified Title',
        read: true,
        readAt: DateTime.parse('2024-01-15T12:00:00.000Z'),
      );

      expect(modified.id, equals('123'));
      expect(modified.title, equals('Modified Title'));
      expect(modified.read, isTrue);
      expect(modified.readAt, equals(DateTime.parse('2024-01-15T12:00:00.000Z')));
      expect(modified.body, equals('Original body'));
      expect(modified.notificationType, equals('task_completed'));
      expect(original.title, equals('Original Title'));
      expect(original.read, isFalse);
    });

    test('copyWith preserves unmodified values', () {
      final original = AppNotification(
        id: '123',
        notificationType: 'agent_message',
        title: 'Test',
        body: 'Body text',
        icon: '🤖',
        priority: 'normal',
        read: false,
        actionUrl: '/agents/123',
        actionType: 'navigate',
        timeAgo: '1 hour ago',
        colorClass: 'primary',
        createdAt: DateTime.parse('2024-01-15T10:30:00.000Z'),
        updatedAt: DateTime.parse('2024-01-16T11:00:00.000Z'),
      );

      final modified = original.copyWith(read: true);

      expect(modified.notificationType, equals('agent_message'));
      expect(modified.title, equals('Test'));
      expect(modified.body, equals('Body text'));
      expect(modified.icon, equals('🤖'));
      expect(modified.actionUrl, equals('/agents/123'));
      expect(modified.actionType, equals('navigate'));
      expect(modified.timeAgo, equals('1 hour ago'));
      expect(modified.colorClass, equals('primary'));
    });
  });
}
