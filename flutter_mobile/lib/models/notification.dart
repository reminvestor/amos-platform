/// Notification model matching the UserNotification backend model
class AppNotification {
  final String id;
  final String notificationType;
  final String title;
  final String? body;
  final String icon;
  final String priority;
  final bool read;
  final DateTime? readAt;
  final String? actionUrl;
  final String? actionType;
  final String timeAgo;
  final String colorClass;
  final DateTime createdAt;
  final DateTime updatedAt;

  AppNotification({
    required this.id,
    required this.notificationType,
    required this.title,
    this.body,
    required this.icon,
    required this.priority,
    required this.read,
    this.readAt,
    this.actionUrl,
    this.actionType,
    required this.timeAgo,
    required this.colorClass,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'].toString(),
      notificationType: json['notification_type'] ?? 'system_alert',
      title: json['title'] ?? '',
      body: json['body'],
      icon: json['icon'] ?? '📬',
      priority: json['priority'] ?? 'normal',
      read: json['read'] ?? false,
      readAt: json['read_at'] != null ? DateTime.parse(json['read_at']) : null,
      actionUrl: json['action_url'],
      actionType: json['action_type'],
      timeAgo: json['time_ago'] ?? '',
      colorClass: json['color_class'] ?? 'secondary',
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  AppNotification copyWith({
    String? id,
    String? notificationType,
    String? title,
    String? body,
    String? icon,
    String? priority,
    bool? read,
    DateTime? readAt,
    String? actionUrl,
    String? actionType,
    String? timeAgo,
    String? colorClass,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AppNotification(
      id: id ?? this.id,
      notificationType: notificationType ?? this.notificationType,
      title: title ?? this.title,
      body: body ?? this.body,
      icon: icon ?? this.icon,
      priority: priority ?? this.priority,
      read: read ?? this.read,
      readAt: readAt ?? this.readAt,
      actionUrl: actionUrl ?? this.actionUrl,
      actionType: actionType ?? this.actionType,
      timeAgo: timeAgo ?? this.timeAgo,
      colorClass: colorClass ?? this.colorClass,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Get display name for notification type
  String get displayType {
    switch (notificationType) {
      case 'task_completed':
        return 'Task Completed';
      case 'task_failed':
        return 'Task Failed';
      case 'action_required':
        return 'Action Required';
      case 'daily_digest':
        return 'Daily Digest';
      case 'weekly_summary':
        return 'Weekly Summary';
      case 'agent_message':
        return 'Agent Message';
      case 'asset_created':
        return 'Asset Created';
      case 'scheduled_reminder':
        return 'Reminder';
      case 'system_alert':
        return 'System Alert';
      case 'collaboration_request':
        return 'Collaboration';
      case 'work_completed':
        return 'Work Completed';
      default:
        return 'Notification';
    }
  }

  /// Check if this is an urgent notification
  bool get isUrgent => priority == 'urgent' || priority == 'high';
}
