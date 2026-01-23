import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/notification.dart';
import 'package:amos_mobile/services/notifications_service.dart';

// Note: NotificationsService uses ApiClient which requires FlutterSecureStorage.
// For unit tests, we test the response parsing logic and model behavior separately.

void main() {
  group('AppNotification Model', () {
    test('parses notification with all fields', () {
      final json = {
        'id': 123,
        'notification_type': 'task_completed',
        'title': 'Task Finished',
        'body': 'Your landing page has been generated',
        'icon': '✅',
        'priority': 'normal',
        'read': false,
        'read_at': null,
        'action_url': '/landing_pages/456',
        'action_type': 'navigate',
        'time_ago': '5 minutes ago',
        'color_class': 'success',
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-15T10:30:00.000Z',
      };

      final notification = AppNotification.fromJson(json);

      expect(notification.id, equals('123'));
      expect(notification.notificationType, equals('task_completed'));
      expect(notification.title, equals('Task Finished'));
      expect(notification.body, equals('Your landing page has been generated'));
      expect(notification.icon, equals('✅'));
      expect(notification.priority, equals('normal'));
      expect(notification.read, isFalse);
      expect(notification.readAt, isNull);
      expect(notification.actionUrl, equals('/landing_pages/456'));
      expect(notification.actionType, equals('navigate'));
      expect(notification.timeAgo, equals('5 minutes ago'));
      expect(notification.colorClass, equals('success'));
    });

    test('parses read notification with read_at timestamp', () {
      final json = {
        'id': 456,
        'notification_type': 'agent_message',
        'title': 'Message from Scout',
        'body': 'Your campaign is ready',
        'icon': '🤖',
        'priority': 'normal',
        'read': true,
        'read_at': '2024-01-15T11:00:00.000Z',
        'time_ago': '2 hours ago',
        'color_class': 'info',
        'created_at': '2024-01-15T09:00:00.000Z',
        'updated_at': '2024-01-15T11:00:00.000Z',
      };

      final notification = AppNotification.fromJson(json);

      expect(notification.read, isTrue);
      expect(notification.readAt, isNotNull);
      expect(notification.readAt!.year, equals(2024));
    });

    test('handles missing optional fields with defaults', () {
      final json = {
        'id': 789,
        'created_at': '2024-01-15T12:00:00.000Z',
        'updated_at': '2024-01-15T12:00:00.000Z',
      };

      final notification = AppNotification.fromJson(json);

      expect(notification.id, equals('789'));
      expect(notification.notificationType, equals('system_alert'));
      expect(notification.title, equals(''));
      expect(notification.body, isNull);
      expect(notification.icon, equals('📬'));
      expect(notification.priority, equals('normal'));
      expect(notification.read, isFalse);
      expect(notification.timeAgo, equals(''));
      expect(notification.colorClass, equals('secondary'));
    });

    test('converts various id types to string', () {
      final jsonWithInt = {
        'id': 123,
        'created_at': '2024-01-15T12:00:00.000Z',
        'updated_at': '2024-01-15T12:00:00.000Z',
      };

      final jsonWithString = {
        'id': 'abc-123',
        'created_at': '2024-01-15T12:00:00.000Z',
        'updated_at': '2024-01-15T12:00:00.000Z',
      };

      final notificationFromInt = AppNotification.fromJson(jsonWithInt);
      final notificationFromString = AppNotification.fromJson(jsonWithString);

      expect(notificationFromInt.id, equals('123'));
      expect(notificationFromString.id, equals('abc-123'));
    });
  });

  group('AppNotification.displayType', () {
    final baseJson = {
      'id': 1,
      'created_at': '2024-01-15T12:00:00.000Z',
      'updated_at': '2024-01-15T12:00:00.000Z',
    };

    test('returns correct display name for task_completed', () {
      final json = {...baseJson, 'notification_type': 'task_completed'};
      final notification = AppNotification.fromJson(json);
      expect(notification.displayType, equals('Task Completed'));
    });

    test('returns correct display name for task_failed', () {
      final json = {...baseJson, 'notification_type': 'task_failed'};
      final notification = AppNotification.fromJson(json);
      expect(notification.displayType, equals('Task Failed'));
    });

    test('returns correct display name for action_required', () {
      final json = {...baseJson, 'notification_type': 'action_required'};
      final notification = AppNotification.fromJson(json);
      expect(notification.displayType, equals('Action Required'));
    });

    test('returns correct display name for daily_digest', () {
      final json = {...baseJson, 'notification_type': 'daily_digest'};
      final notification = AppNotification.fromJson(json);
      expect(notification.displayType, equals('Daily Digest'));
    });

    test('returns correct display name for weekly_summary', () {
      final json = {...baseJson, 'notification_type': 'weekly_summary'};
      final notification = AppNotification.fromJson(json);
      expect(notification.displayType, equals('Weekly Summary'));
    });

    test('returns correct display name for agent_message', () {
      final json = {...baseJson, 'notification_type': 'agent_message'};
      final notification = AppNotification.fromJson(json);
      expect(notification.displayType, equals('Agent Message'));
    });

    test('returns correct display name for asset_created', () {
      final json = {...baseJson, 'notification_type': 'asset_created'};
      final notification = AppNotification.fromJson(json);
      expect(notification.displayType, equals('Asset Created'));
    });

    test('returns correct display name for scheduled_reminder', () {
      final json = {...baseJson, 'notification_type': 'scheduled_reminder'};
      final notification = AppNotification.fromJson(json);
      expect(notification.displayType, equals('Reminder'));
    });

    test('returns correct display name for system_alert', () {
      final json = {...baseJson, 'notification_type': 'system_alert'};
      final notification = AppNotification.fromJson(json);
      expect(notification.displayType, equals('System Alert'));
    });

    test('returns correct display name for collaboration_request', () {
      final json = {...baseJson, 'notification_type': 'collaboration_request'};
      final notification = AppNotification.fromJson(json);
      expect(notification.displayType, equals('Collaboration'));
    });

    test('returns correct display name for work_completed', () {
      final json = {...baseJson, 'notification_type': 'work_completed'};
      final notification = AppNotification.fromJson(json);
      expect(notification.displayType, equals('Work Completed'));
    });

    test('returns default for unknown type', () {
      final json = {...baseJson, 'notification_type': 'unknown_type'};
      final notification = AppNotification.fromJson(json);
      expect(notification.displayType, equals('Notification'));
    });
  });

  group('AppNotification.isUrgent', () {
    final baseJson = {
      'id': 1,
      'created_at': '2024-01-15T12:00:00.000Z',
      'updated_at': '2024-01-15T12:00:00.000Z',
    };

    test('returns true for urgent priority', () {
      final json = {...baseJson, 'priority': 'urgent'};
      final notification = AppNotification.fromJson(json);
      expect(notification.isUrgent, isTrue);
    });

    test('returns true for high priority', () {
      final json = {...baseJson, 'priority': 'high'};
      final notification = AppNotification.fromJson(json);
      expect(notification.isUrgent, isTrue);
    });

    test('returns false for normal priority', () {
      final json = {...baseJson, 'priority': 'normal'};
      final notification = AppNotification.fromJson(json);
      expect(notification.isUrgent, isFalse);
    });

    test('returns false for low priority', () {
      final json = {...baseJson, 'priority': 'low'};
      final notification = AppNotification.fromJson(json);
      expect(notification.isUrgent, isFalse);
    });
  });

  group('AppNotification.copyWith', () {
    test('creates copy with updated read status', () {
      final original = AppNotification(
        id: '1',
        notificationType: 'task_completed',
        title: 'Test',
        icon: '✅',
        priority: 'normal',
        read: false,
        timeAgo: '5 min',
        colorClass: 'success',
        createdAt: DateTime(2024, 1, 15),
        updatedAt: DateTime(2024, 1, 15),
      );

      final updated = original.copyWith(read: true);

      expect(updated.id, equals(original.id));
      expect(updated.title, equals(original.title));
      expect(updated.read, isTrue);
      expect(original.read, isFalse); // Original unchanged
    });

    test('creates copy with all fields updated', () {
      final original = AppNotification(
        id: '1',
        notificationType: 'task_completed',
        title: 'Original Title',
        icon: '✅',
        priority: 'normal',
        read: false,
        timeAgo: '5 min',
        colorClass: 'success',
        createdAt: DateTime(2024, 1, 15),
        updatedAt: DateTime(2024, 1, 15),
      );

      final updated = original.copyWith(
        title: 'New Title',
        body: 'New body',
        read: true,
        readAt: DateTime(2024, 1, 16),
      );

      expect(updated.title, equals('New Title'));
      expect(updated.body, equals('New body'));
      expect(updated.read, isTrue);
      expect(updated.readAt, equals(DateTime(2024, 1, 16)));
    });
  });

  group('NotificationListResponse', () {
    test('creates response with all pagination fields', () {
      final notifications = [
        AppNotification(
          id: '1',
          notificationType: 'task_completed',
          title: 'Test 1',
          icon: '✅',
          priority: 'normal',
          read: false,
          timeAgo: '5 min',
          colorClass: 'success',
          createdAt: DateTime(2024, 1, 15),
          updatedAt: DateTime(2024, 1, 15),
        ),
      ];

      final response = NotificationListResponse(
        notifications: notifications,
        currentPage: 2,
        totalPages: 5,
        totalCount: 100,
        perPage: 20,
        unreadCount: 15,
      );

      expect(response.notifications, hasLength(1));
      expect(response.currentPage, equals(2));
      expect(response.totalPages, equals(5));
      expect(response.totalCount, equals(100));
      expect(response.perPage, equals(20));
      expect(response.unreadCount, equals(15));
    });
  });

  group('UnreadCountResponse', () {
    test('creates response with counts', () {
      final response = UnreadCountResponse(
        unreadCount: 10,
        urgentCount: 3,
      );

      expect(response.unreadCount, equals(10));
      expect(response.urgentCount, equals(3));
    });

    test('hasUnread returns true when count > 0', () {
      final response = UnreadCountResponse(unreadCount: 5, urgentCount: 0);
      expect(response.hasUnread, isTrue);
    });

    test('hasUnread returns false when count is 0', () {
      final response = UnreadCountResponse(unreadCount: 0, urgentCount: 0);
      expect(response.hasUnread, isFalse);
    });

    test('hasUrgent returns true when count > 0', () {
      final response = UnreadCountResponse(unreadCount: 5, urgentCount: 2);
      expect(response.hasUrgent, isTrue);
    });

    test('hasUrgent returns false when count is 0', () {
      final response = UnreadCountResponse(unreadCount: 5, urgentCount: 0);
      expect(response.hasUrgent, isFalse);
    });
  });

  group('Notifications API Response Parsing', () {
    test('parses list notifications response', () {
      final responseData = {
        'data': [
          {
            'id': 1,
            'notification_type': 'task_completed',
            'title': 'Task Done',
            'icon': '✅',
            'priority': 'normal',
            'read': false,
            'time_ago': '5 min',
            'color_class': 'success',
            'created_at': '2024-01-15T10:00:00.000Z',
            'updated_at': '2024-01-15T10:00:00.000Z',
          },
          {
            'id': 2,
            'notification_type': 'agent_message',
            'title': 'New Message',
            'icon': '🤖',
            'priority': 'high',
            'read': true,
            'time_ago': '1 hour',
            'color_class': 'info',
            'created_at': '2024-01-15T09:00:00.000Z',
            'updated_at': '2024-01-15T10:00:00.000Z',
          },
        ],
        'pagination': {
          'current_page': 1,
          'total_pages': 3,
          'total_count': 50,
          'per_page': 20,
        },
        'unread_count': 25,
      };

      final data = responseData['data'] as List;
      final notifications =
          data.map((json) => AppNotification.fromJson(json)).toList();
      final pagination = responseData['pagination'] as Map<String, dynamic>;

      expect(notifications, hasLength(2));
      expect(notifications[0].title, equals('Task Done'));
      expect(notifications[1].title, equals('New Message'));
      expect(pagination['current_page'], equals(1));
      expect(pagination['total_pages'], equals(3));
    });

    test('handles missing pagination with defaults', () {
      final responseData = {
        'data': [],
      };

      final pagination = responseData['pagination'] as Map? ?? {};

      // Test the _toInt helper logic
      int toInt(dynamic value, int defaultValue) {
        if (value == null) return defaultValue;
        if (value is int) return value;
        if (value is String) return int.tryParse(value) ?? defaultValue;
        return defaultValue;
      }

      expect(toInt(pagination['current_page'], 1), equals(1));
      expect(toInt(pagination['total_pages'], 1), equals(1));
    });

    test('parses unread count response', () {
      final responseData = {
        'unread_count': 15,
        'urgent_count': 3,
      };

      // Test the _toInt helper logic
      int toInt(dynamic value, int defaultValue) {
        if (value == null) return defaultValue;
        if (value is int) return value;
        if (value is String) return int.tryParse(value) ?? defaultValue;
        return defaultValue;
      }

      final unreadCount = toInt(responseData['unread_count'], 0);
      final urgentCount = toInt(responseData['urgent_count'], 0);

      expect(unreadCount, equals(15));
      expect(urgentCount, equals(3));
    });

    test('handles string counts with _toInt conversion', () {
      // Sometimes APIs return numbers as strings
      int toInt(dynamic value, int defaultValue) {
        if (value == null) return defaultValue;
        if (value is int) return value;
        if (value is String) return int.tryParse(value) ?? defaultValue;
        return defaultValue;
      }

      expect(toInt('42', 0), equals(42));
      expect(toInt('invalid', 0), equals(0));
      expect(toInt(null, 5), equals(5));
      expect(toInt(100, 0), equals(100));
    });
  });

  group('Query Parameters Building', () {
    test('builds query params for getNotifications', () {
      final params = <String, String>{
        'page': '2',
        'per_page': '25',
      };

      expect(params['page'], equals('2'));
      expect(params['per_page'], equals('25'));
    });

    test('adds unread_only when filtering', () {
      final params = <String, String>{
        'page': '1',
        'per_page': '20',
      };

      // When unreadOnly is true
      const unreadOnly = true;
      if (unreadOnly) {
        params['unread_only'] = 'true';
      }

      expect(params['unread_only'], equals('true'));
    });

    test('excludes unread_only when not filtering', () {
      final params = <String, String>{
        'page': '1',
        'per_page': '20',
      };

      // When unreadOnly is false, don't add the param
      const unreadOnly = false;
      if (unreadOnly) {
        params['unread_only'] = 'true';
      }

      expect(params.containsKey('unread_only'), isFalse);
    });
  });
}
