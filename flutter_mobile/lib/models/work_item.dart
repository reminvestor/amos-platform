class WorkItem {
  final int id;
  final String workType;
  final String title;
  final String? summary;
  final String? details;
  final String icon;
  final String category;
  final String priority;
  final bool read;
  final bool starred;
  final bool archived;
  final bool requiresAction;
  final String? actionType;
  final DateTime? actionDueAt;
  final String? agentName;
  final String? timeAgo;
  final String? assetType;
  final int? assetId;
  final Map<String, dynamic>? assetData;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  WorkItem({
    required this.id,
    required this.workType,
    required this.title,
    this.summary,
    this.details,
    required this.icon,
    required this.category,
    required this.priority,
    required this.read,
    required this.starred,
    required this.archived,
    required this.requiresAction,
    this.actionType,
    this.actionDueAt,
    this.agentName,
    this.timeAgo,
    this.assetType,
    this.assetId,
    this.assetData,
    this.metadata,
    required this.createdAt,
    required this.updatedAt,
  });

  factory WorkItem.fromJson(Map<String, dynamic> json) {
    return WorkItem(
      id: json['id'] as int,
      workType: json['work_type'] as String? ?? 'task_completed',
      title: json['title'] as String? ?? 'Untitled',
      summary: json['summary'] as String?,
      details: json['details'] as String?,
      icon: json['icon'] as String? ?? '',
      category: json['category'] as String? ?? 'general',
      priority: json['priority'] as String? ?? 'normal',
      read: json['read'] as bool? ?? false,
      starred: json['starred'] as bool? ?? false,
      archived: json['archived'] as bool? ?? false,
      requiresAction: json['requires_action'] as bool? ?? false,
      actionType: json['action_type'] as String?,
      actionDueAt: json['action_due_at'] != null
          ? DateTime.parse(json['action_due_at'] as String)
          : null,
      agentName: json['agent_name'] as String?,
      timeAgo: json['time_ago'] as String?,
      assetType: json['asset_type'] as String?,
      assetId: json['asset_id'] as int?,
      assetData: json['asset_data'] as Map<String, dynamic>?,
      metadata: json['metadata'] as Map<String, dynamic>?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'work_type': workType,
      'title': title,
      'summary': summary,
      'details': details,
      'icon': icon,
      'category': category,
      'priority': priority,
      'read': read,
      'starred': starred,
      'archived': archived,
      'requires_action': requiresAction,
      'action_type': actionType,
      'action_due_at': actionDueAt?.toIso8601String(),
      'agent_name': agentName,
      'time_ago': timeAgo,
      'asset_type': assetType,
      'asset_id': assetId,
      'asset_data': assetData,
      'metadata': metadata,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  WorkItem copyWith({
    int? id,
    String? workType,
    String? title,
    String? summary,
    String? details,
    String? icon,
    String? category,
    String? priority,
    bool? read,
    bool? starred,
    bool? archived,
    bool? requiresAction,
    String? actionType,
    DateTime? actionDueAt,
    String? agentName,
    String? timeAgo,
    String? assetType,
    int? assetId,
    Map<String, dynamic>? assetData,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return WorkItem(
      id: id ?? this.id,
      workType: workType ?? this.workType,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      details: details ?? this.details,
      icon: icon ?? this.icon,
      category: category ?? this.category,
      priority: priority ?? this.priority,
      read: read ?? this.read,
      starred: starred ?? this.starred,
      archived: archived ?? this.archived,
      requiresAction: requiresAction ?? this.requiresAction,
      actionType: actionType ?? this.actionType,
      actionDueAt: actionDueAt ?? this.actionDueAt,
      agentName: agentName ?? this.agentName,
      timeAgo: timeAgo ?? this.timeAgo,
      assetType: assetType ?? this.assetType,
      assetId: assetId ?? this.assetId,
      assetData: assetData ?? this.assetData,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Returns display-friendly work type label
  String get workTypeLabel {
    switch (workType) {
      case 'task_completed':
        return 'Task Completed';
      case 'scheduled_task_completed':
        return 'Scheduled Task';
      case 'asset_created':
        return 'Asset Created';
      case 'report_generated':
        return 'Report Generated';
      case 'email_sent':
        return 'Email Sent';
      case 'email_drafted':
        return 'Email Drafted';
      case 'research_completed':
        return 'Research Completed';
      case 'integration_synced':
        return 'Integration Synced';
      case 'agent_created':
        return 'Agent Created';
      case 'tool_created':
        return 'Tool Created';
      case 'landing_page_created':
        return 'Landing Page Created';
      case 'campaign_created':
        return 'Campaign Created';
      case 'analysis_completed':
        return 'Analysis Completed';
      case 'visualization_created':
        return 'Visualization Created';
      case 'action_required':
        return 'Action Required';
      default:
        return workType.replaceAll('_', ' ');
    }
  }

  /// Returns true if this is a high-priority or urgent item
  bool get isHighPriority => priority == 'high' || priority == 'urgent';
}

class WorkItemCounts {
  final int unread;
  final int starred;
  final int actionRequired;
  final int total;

  WorkItemCounts({
    required this.unread,
    required this.starred,
    required this.actionRequired,
    required this.total,
  });

  factory WorkItemCounts.fromJson(Map<String, dynamic> json) {
    return WorkItemCounts(
      unread: json['unread'] as int? ?? 0,
      starred: json['starred'] as int? ?? 0,
      actionRequired: json['action_required'] as int? ?? 0,
      total: json['total'] as int? ?? 0,
    );
  }
}
