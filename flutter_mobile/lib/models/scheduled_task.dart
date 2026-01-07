class ScheduledTask {
  final int id;
  final String name;
  final String? description;
  final String taskType;
  final TaskTypeInfo taskTypeInfo;
  final String scheduleType;
  final String status;
  final bool enabled;
  final DateTime? nextRunAt;
  final DateTime? lastRunAt;
  final int runCount;
  final int failureCount;
  final int consecutiveFailures;
  final bool canRun;
  final String? prompt;
  final String? cronExpression;
  final String? runAtTime;
  final int? runOnDay;
  final String? timezone;
  final int? maxRuns;
  final DateTime? expiresAt;
  final Map<String, dynamic>? inputContext;
  final Map<String, dynamic>? outputConfig;
  final String? executionMode;
  final String? agentName;
  final DateTime createdAt;
  final DateTime updatedAt;

  ScheduledTask({
    required this.id,
    required this.name,
    this.description,
    required this.taskType,
    required this.taskTypeInfo,
    required this.scheduleType,
    required this.status,
    required this.enabled,
    this.nextRunAt,
    this.lastRunAt,
    required this.runCount,
    required this.failureCount,
    required this.consecutiveFailures,
    required this.canRun,
    this.prompt,
    this.cronExpression,
    this.runAtTime,
    this.runOnDay,
    this.timezone,
    this.maxRuns,
    this.expiresAt,
    this.inputContext,
    this.outputConfig,
    this.executionMode,
    this.agentName,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ScheduledTask.fromJson(Map<String, dynamic> json) {
    return ScheduledTask(
      id: json['id'] as int,
      name: json['name'] as String? ?? 'Untitled Task',
      description: json['description'] as String?,
      taskType: json['task_type'] as String? ?? 'custom',
      taskTypeInfo: TaskTypeInfo.fromJson(
        json['task_type_info'] as Map<String, dynamic>? ?? {},
      ),
      scheduleType: json['schedule_type'] as String? ?? 'daily',
      status: json['status'] as String? ?? 'active',
      enabled: json['enabled'] as bool? ?? true,
      nextRunAt: json['next_run_at'] != null
          ? DateTime.parse(json['next_run_at'] as String)
          : null,
      lastRunAt: json['last_run_at'] != null
          ? DateTime.parse(json['last_run_at'] as String)
          : null,
      runCount: json['run_count'] as int? ?? 0,
      failureCount: json['failure_count'] as int? ?? 0,
      consecutiveFailures: json['consecutive_failures'] as int? ?? 0,
      canRun: json['can_run'] as bool? ?? false,
      prompt: json['prompt'] as String?,
      cronExpression: json['cron_expression'] as String?,
      runAtTime: json['run_at_time'] as String?,
      runOnDay: json['run_on_day'] as int?,
      timezone: json['timezone'] as String?,
      maxRuns: json['max_runs'] as int?,
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : null,
      inputContext: json['input_context'] as Map<String, dynamic>?,
      outputConfig: json['output_config'] as Map<String, dynamic>?,
      executionMode: json['execution_mode'] as String?,
      agentName: json['agent_name'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'task_type': taskType,
      'schedule_type': scheduleType,
      'status': status,
      'enabled': enabled,
      'next_run_at': nextRunAt?.toIso8601String(),
      'last_run_at': lastRunAt?.toIso8601String(),
      'run_count': runCount,
      'failure_count': failureCount,
      'consecutive_failures': consecutiveFailures,
      'can_run': canRun,
      'prompt': prompt,
      'cron_expression': cronExpression,
      'run_at_time': runAtTime,
      'run_on_day': runOnDay,
      'timezone': timezone,
      'max_runs': maxRuns,
      'expires_at': expiresAt?.toIso8601String(),
      'input_context': inputContext,
      'output_config': outputConfig,
      'execution_mode': executionMode,
      'agent_name': agentName,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  ScheduledTask copyWith({
    int? id,
    String? name,
    String? description,
    String? taskType,
    TaskTypeInfo? taskTypeInfo,
    String? scheduleType,
    String? status,
    bool? enabled,
    DateTime? nextRunAt,
    DateTime? lastRunAt,
    int? runCount,
    int? failureCount,
    int? consecutiveFailures,
    bool? canRun,
    String? prompt,
    String? cronExpression,
    String? runAtTime,
    int? runOnDay,
    String? timezone,
    int? maxRuns,
    DateTime? expiresAt,
    Map<String, dynamic>? inputContext,
    Map<String, dynamic>? outputConfig,
    String? executionMode,
    String? agentName,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ScheduledTask(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      taskType: taskType ?? this.taskType,
      taskTypeInfo: taskTypeInfo ?? this.taskTypeInfo,
      scheduleType: scheduleType ?? this.scheduleType,
      status: status ?? this.status,
      enabled: enabled ?? this.enabled,
      nextRunAt: nextRunAt ?? this.nextRunAt,
      lastRunAt: lastRunAt ?? this.lastRunAt,
      runCount: runCount ?? this.runCount,
      failureCount: failureCount ?? this.failureCount,
      consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
      canRun: canRun ?? this.canRun,
      prompt: prompt ?? this.prompt,
      cronExpression: cronExpression ?? this.cronExpression,
      runAtTime: runAtTime ?? this.runAtTime,
      runOnDay: runOnDay ?? this.runOnDay,
      timezone: timezone ?? this.timezone,
      maxRuns: maxRuns ?? this.maxRuns,
      expiresAt: expiresAt ?? this.expiresAt,
      inputContext: inputContext ?? this.inputContext,
      outputConfig: outputConfig ?? this.outputConfig,
      executionMode: executionMode ?? this.executionMode,
      agentName: agentName ?? this.agentName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Returns display-friendly schedule label
  String get scheduleLabel {
    switch (scheduleType) {
      case 'once':
        return 'One Time';
      case 'daily':
        return 'Daily';
      case 'weekly':
        return 'Weekly';
      case 'monthly':
        return 'Monthly';
      case 'cron':
        return 'Custom Schedule';
      default:
        return scheduleType;
    }
  }

  /// Returns display-friendly status label
  String get statusLabel {
    switch (status) {
      case 'active':
        return 'Active';
      case 'paused':
        return 'Paused';
      case 'completed':
        return 'Completed';
      case 'failed':
        return 'Failed';
      case 'archived':
        return 'Archived';
      default:
        return status;
    }
  }

  /// Returns true if the task has failed multiple times
  bool get hasFailures => consecutiveFailures > 0;
}

class TaskTypeInfo {
  final String name;
  final String description;
  final String icon;

  TaskTypeInfo({
    required this.name,
    required this.description,
    required this.icon,
  });

  factory TaskTypeInfo.fromJson(Map<String, dynamic> json) {
    return TaskTypeInfo(
      name: json['name'] as String? ?? 'Custom Task',
      description: json['description'] as String? ?? '',
      icon: json['icon'] as String? ?? '',
    );
  }
}

class TaskType {
  final String id;
  final String name;
  final String description;
  final String icon;

  TaskType({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
  });

  factory TaskType.fromJson(Map<String, dynamic> json) {
    return TaskType(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      icon: json['icon'] as String? ?? '',
    );
  }
}

class ScheduledTaskCounts {
  final int active;
  final int paused;
  final int completed;
  final int failed;
  final int total;

  ScheduledTaskCounts({
    required this.active,
    required this.paused,
    required this.completed,
    required this.failed,
    required this.total,
  });

  factory ScheduledTaskCounts.fromJson(Map<String, dynamic> json) {
    return ScheduledTaskCounts(
      active: json['active'] as int? ?? 0,
      paused: json['paused'] as int? ?? 0,
      completed: json['completed'] as int? ?? 0,
      failed: json['failed'] as int? ?? 0,
      total: json['total'] as int? ?? 0,
    );
  }
}
