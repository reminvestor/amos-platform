import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/notification.dart';

void main() {
  group('AppNotification', () {
    final createdAt = DateTime(2025, 1, 15, 10, 0);
    final updatedAt = DateTime(2025, 1, 15, 10, 0);

    test('creates with required values', () {
      final notification = AppNotification(
        id: '1',
        notificationType: 'task_completed',
        title: 'Task Completed',
        icon: '✅',
        priority: 'normal',
        read: false,
        timeAgo: '5 minutes ago',
        colorClass: 'success',
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      expect(notification.id, '1');
      expect(notification.notificationType, 'task_completed');
      expect(notification.title, 'Task Completed');
      expect(notification.icon, '✅');
      expect(notification.priority, 'normal');
      expect(notification.read, false);
      expect(notification.timeAgo, '5 minutes ago');
      expect(notification.colorClass, 'success');
      expect(notification.body, isNull);
      expect(notification.readAt, isNull);
      expect(notification.actionUrl, isNull);
      expect(notification.actionType, isNull);
    });

    test('creates with all optional values', () {
      final readAt = DateTime(2025, 1, 15, 11, 0);
      final notification = AppNotification(
        id: '2',
        notificationType: 'action_required',
        title: 'Action Required',
        body: 'Please review the pending approval.',
        icon: '⚠️',
        priority: 'high',
        read: true,
        readAt: readAt,
        actionUrl: '/approvals/123',
        actionType: 'view_approval',
        timeAgo: '1 hour ago',
        colorClass: 'warning',
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      expect(notification.body, 'Please review the pending approval.');
      expect(notification.readAt, readAt);
      expect(notification.actionUrl, '/approvals/123');
      expect(notification.actionType, 'view_approval');
    });

    test('fromJson parses complete data', () {
      final json = {
        'id': 123,
        'notification_type': 'agent_message',
        'title': 'New Agent Message',
        'body': 'Your AI assistant has a message for you.',
        'icon': '🤖',
        'priority': 'normal',
        'read': false,
        'read_at': null,
        'action_url': '/chat/agent',
        'action_type': 'open_chat',
        'time_ago': '2 minutes ago',
        'color_class': 'primary',
        'created_at': '2025-01-15T10:00:00Z',
        'updated_at': '2025-01-15T10:00:00Z',
      };

      final notification = AppNotification.fromJson(json);

      expect(notification.id, '123');
      expect(notification.notificationType, 'agent_message');
      expect(notification.title, 'New Agent Message');
      expect(notification.body, 'Your AI assistant has a message for you.');
      expect(notification.icon, '🤖');
      expect(notification.priority, 'normal');
      expect(notification.read, false);
      expect(notification.actionUrl, '/chat/agent');
      expect(notification.actionType, 'open_chat');
      expect(notification.timeAgo, '2 minutes ago');
      expect(notification.colorClass, 'primary');
    });

    test('fromJson handles minimal data', () {
      final json = {
        'id': 1,
        'created_at': '2025-01-15T10:00:00Z',
        'updated_at': '2025-01-15T10:00:00Z',
      };

      final notification = AppNotification.fromJson(json);

      expect(notification.id, '1');
      expect(notification.notificationType, 'system_alert');
      expect(notification.title, '');
      expect(notification.body, isNull);
      expect(notification.icon, '📬');
      expect(notification.priority, 'normal');
      expect(notification.read, false);
      expect(notification.timeAgo, '');
      expect(notification.colorClass, 'secondary');
    });

    test('fromJson parses read_at when present', () {
      final json = {
        'id': 1,
        'read': true,
        'read_at': '2025-01-15T11:00:00Z',
        'created_at': '2025-01-15T10:00:00Z',
        'updated_at': '2025-01-15T10:00:00Z',
      };

      final notification = AppNotification.fromJson(json);

      expect(notification.read, true);
      expect(notification.readAt, isNotNull);
      expect(notification.readAt!.year, 2025);
      expect(notification.readAt!.hour, 11);
    });

    group('copyWith', () {
      test('copies with no changes', () {
        final original = AppNotification(
          id: '1',
          notificationType: 'task_completed',
          title: 'Original Title',
          icon: '✅',
          priority: 'normal',
          read: false,
          timeAgo: '5m',
          colorClass: 'success',
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        final copy = original.copyWith();

        expect(copy.id, original.id);
        expect(copy.title, original.title);
        expect(copy.read, original.read);
      });

      test('copies with read status changed', () {
        final original = AppNotification(
          id: '1',
          notificationType: 'task_completed',
          title: 'Task Done',
          icon: '✅',
          priority: 'normal',
          read: false,
          timeAgo: '5m',
          colorClass: 'success',
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        final readNotification = original.copyWith(read: true);

        expect(readNotification.read, true);
        expect(readNotification.id, original.id);
        expect(readNotification.title, original.title);
      });

      test('copies with multiple fields changed', () {
        final original = AppNotification(
          id: '1',
          notificationType: 'task_completed',
          title: 'Original',
          icon: '✅',
          priority: 'normal',
          read: false,
          timeAgo: '5m',
          colorClass: 'success',
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        final readAt = DateTime.now();
        final modified = original.copyWith(
          title: 'Modified Title',
          read: true,
          readAt: readAt,
        );

        expect(modified.title, 'Modified Title');
        expect(modified.read, true);
        expect(modified.readAt, readAt);
        expect(modified.id, original.id);
        expect(modified.notificationType, original.notificationType);
      });
    });

    group('displayType', () {
      test('returns correct display name for task_completed', () {
        final notification = AppNotification(
          id: '1',
          notificationType: 'task_completed',
          title: 'Test',
          icon: '✅',
          priority: 'normal',
          read: false,
          timeAgo: '5m',
          colorClass: 'success',
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        expect(notification.displayType, 'Task Completed');
      });

      test('returns correct display name for task_failed', () {
        final notification = AppNotification(
          id: '1',
          notificationType: 'task_failed',
          title: 'Test',
          icon: '❌',
          priority: 'high',
          read: false,
          timeAgo: '5m',
          colorClass: 'danger',
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        expect(notification.displayType, 'Task Failed');
      });

      test('returns correct display name for action_required', () {
        final notification = AppNotification(
          id: '1',
          notificationType: 'action_required',
          title: 'Test',
          icon: '⚠️',
          priority: 'urgent',
          read: false,
          timeAgo: '5m',
          colorClass: 'warning',
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        expect(notification.displayType, 'Action Required');
      });

      test('returns correct display name for daily_digest', () {
        final notification = AppNotification(
          id: '1',
          notificationType: 'daily_digest',
          title: 'Test',
          icon: '📋',
          priority: 'normal',
          read: false,
          timeAgo: '5m',
          colorClass: 'info',
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        expect(notification.displayType, 'Daily Digest');
      });

      test('returns correct display name for weekly_summary', () {
        final notification = AppNotification(
          id: '1',
          notificationType: 'weekly_summary',
          title: 'Test',
          icon: '📊',
          priority: 'normal',
          read: false,
          timeAgo: '5m',
          colorClass: 'info',
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        expect(notification.displayType, 'Weekly Summary');
      });

      test('returns correct display name for agent_message', () {
        final notification = AppNotification(
          id: '1',
          notificationType: 'agent_message',
          title: 'Test',
          icon: '🤖',
          priority: 'normal',
          read: false,
          timeAgo: '5m',
          colorClass: 'primary',
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        expect(notification.displayType, 'Agent Message');
      });

      test('returns correct display name for asset_created', () {
        final notification = AppNotification(
          id: '1',
          notificationType: 'asset_created',
          title: 'Test',
          icon: '📁',
          priority: 'normal',
          read: false,
          timeAgo: '5m',
          colorClass: 'success',
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        expect(notification.displayType, 'Asset Created');
      });

      test('returns correct display name for scheduled_reminder', () {
        final notification = AppNotification(
          id: '1',
          notificationType: 'scheduled_reminder',
          title: 'Test',
          icon: '⏰',
          priority: 'normal',
          read: false,
          timeAgo: '5m',
          colorClass: 'info',
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        expect(notification.displayType, 'Reminder');
      });

      test('returns correct display name for system_alert', () {
        final notification = AppNotification(
          id: '1',
          notificationType: 'system_alert',
          title: 'Test',
          icon: '🔔',
          priority: 'normal',
          read: false,
          timeAgo: '5m',
          colorClass: 'secondary',
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        expect(notification.displayType, 'System Alert');
      });

      test('returns correct display name for collaboration_request', () {
        final notification = AppNotification(
          id: '1',
          notificationType: 'collaboration_request',
          title: 'Test',
          icon: '👥',
          priority: 'normal',
          read: false,
          timeAgo: '5m',
          colorClass: 'primary',
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        expect(notification.displayType, 'Collaboration');
      });

      test('returns correct display name for work_completed', () {
        final notification = AppNotification(
          id: '1',
          notificationType: 'work_completed',
          title: 'Test',
          icon: '✅',
          priority: 'normal',
          read: false,
          timeAgo: '5m',
          colorClass: 'success',
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        expect(notification.displayType, 'Work Completed');
      });

      test('returns Notification for unknown type', () {
        final notification = AppNotification(
          id: '1',
          notificationType: 'unknown_type',
          title: 'Test',
          icon: '📬',
          priority: 'normal',
          read: false,
          timeAgo: '5m',
          colorClass: 'secondary',
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        expect(notification.displayType, 'Notification');
      });
    });

    group('isUrgent', () {
      test('returns true for urgent priority', () {
        final notification = AppNotification(
          id: '1',
          notificationType: 'action_required',
          title: 'Urgent!',
          icon: '🚨',
          priority: 'urgent',
          read: false,
          timeAgo: '1m',
          colorClass: 'danger',
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        expect(notification.isUrgent, true);
      });

      test('returns true for high priority', () {
        final notification = AppNotification(
          id: '1',
          notificationType: 'action_required',
          title: 'High Priority',
          icon: '⚠️',
          priority: 'high',
          read: false,
          timeAgo: '1m',
          colorClass: 'warning',
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        expect(notification.isUrgent, true);
      });

      test('returns false for normal priority', () {
        final notification = AppNotification(
          id: '1',
          notificationType: 'task_completed',
          title: 'Normal',
          icon: '✅',
          priority: 'normal',
          read: false,
          timeAgo: '5m',
          colorClass: 'success',
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        expect(notification.isUrgent, false);
      });

      test('returns false for low priority', () {
        final notification = AppNotification(
          id: '1',
          notificationType: 'daily_digest',
          title: 'Low Priority',
          icon: '📋',
          priority: 'low',
          read: false,
          timeAgo: '1h',
          colorClass: 'info',
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        expect(notification.isUrgent, false);
      });
    });

    test('creates notifications for different scenarios', () {
      // Task completion notification
      final taskComplete = AppNotification(
        id: '1',
        notificationType: 'task_completed',
        title: 'Campaign Sent Successfully',
        body: 'Your email campaign was sent to 1,000 recipients.',
        icon: '✅',
        priority: 'normal',
        read: false,
        timeAgo: '2 minutes ago',
        colorClass: 'success',
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      // Error notification
      final errorNotif = AppNotification(
        id: '2',
        notificationType: 'task_failed',
        title: 'Integration Failed',
        body: 'Could not connect to Stripe API.',
        icon: '❌',
        priority: 'high',
        read: false,
        timeAgo: '5 minutes ago',
        colorClass: 'danger',
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      // Agent message
      final agentMsg = AppNotification(
        id: '3',
        notificationType: 'agent_message',
        title: 'Scout has a question',
        body: 'What target audience would you like for this campaign?',
        icon: '🤖',
        priority: 'normal',
        read: false,
        actionUrl: '/chat',
        actionType: 'open_chat',
        timeAgo: '1 minute ago',
        colorClass: 'primary',
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      expect(taskComplete.colorClass, 'success');
      expect(errorNotif.isUrgent, true);
      expect(agentMsg.actionUrl, '/chat');
    });
  });
}
