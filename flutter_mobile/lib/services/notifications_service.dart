import 'package:amos_mobile/models/notification.dart';
import 'package:amos_mobile/services/api_client.dart';

class NotificationsService {
  final ApiClient _api = ApiClient();

  /// Get paginated list of notifications
  Future<NotificationListResponse> getNotifications({
    bool unreadOnly = false,
    int page = 1,
    int perPage = 20,
  }) async {
    final queryParams = <String, String>{
      'page': page.toString(),
      'per_page': perPage.toString(),
    };
    if (unreadOnly) {
      queryParams['unread_only'] = 'true';
    }

    final response = await _api.get(
      '/api/v1/notifications',
      queryParameters: queryParams,
    );

    final notifications = (response['data'] as List)
        .map((json) => AppNotification.fromJson(json))
        .toList();

    final pagination = response['pagination'] ?? {};

    return NotificationListResponse(
      notifications: notifications,
      currentPage: _toInt(pagination['current_page'], 1),
      totalPages: _toInt(pagination['total_pages'], 1),
      totalCount: _toInt(pagination['total_count'], notifications.length),
      perPage: _toInt(pagination['per_page'], perPage),
      unreadCount: _toInt(response['unread_count'], 0),
    );
  }

  /// Get unread count only (lightweight)
  Future<UnreadCountResponse> getUnreadCount() async {
    final response = await _api.get('/api/v1/notifications/unread_count');
    return UnreadCountResponse(
      unreadCount: _toInt(response['unread_count'], 0),
      urgentCount: _toInt(response['urgent_count'], 0),
    );
  }

  /// Safely convert a dynamic value to int
  int _toInt(dynamic value, int defaultValue) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  /// Get a single notification
  Future<AppNotification> getNotification(String id) async {
    final response = await _api.get('/api/v1/notifications/$id');
    return AppNotification.fromJson(response);
  }

  /// Mark a notification as read
  Future<AppNotification> markAsRead(String id) async {
    final response = await _api.post('/api/v1/notifications/$id/mark_read');
    return AppNotification.fromJson(response);
  }

  /// Mark all notifications as read
  Future<void> markAllAsRead() async {
    await _api.post('/api/v1/notifications/mark_all_read');
  }

  /// Dismiss a notification
  Future<void> dismiss(String id) async {
    await _api.post('/api/v1/notifications/$id/dismiss');
  }
}

class NotificationListResponse {
  final List<AppNotification> notifications;
  final int currentPage;
  final int totalPages;
  final int totalCount;
  final int perPage;
  final int unreadCount;

  NotificationListResponse({
    required this.notifications,
    required this.currentPage,
    required this.totalPages,
    required this.totalCount,
    required this.perPage,
    required this.unreadCount,
  });
}

class UnreadCountResponse {
  final int unreadCount;
  final int urgentCount;

  UnreadCountResponse({
    required this.unreadCount,
    required this.urgentCount,
  });

  bool get hasUnread => unreadCount > 0;
  bool get hasUrgent => urgentCount > 0;
}
