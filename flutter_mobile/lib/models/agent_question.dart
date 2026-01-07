/// Model for agent input requests (questions from agents)
class AgentQuestion {
  final int id;
  final String question;
  final String agentName;
  final String agentIcon;
  final int priority;
  final DateTime createdAt;
  final Map<String, dynamic>? context;
  final int? executionId;

  AgentQuestion({
    required this.id,
    required this.question,
    required this.agentName,
    required this.agentIcon,
    required this.priority,
    required this.createdAt,
    this.context,
    this.executionId,
  });

  factory AgentQuestion.fromJson(Map<String, dynamic> json) {
    return AgentQuestion(
      id: json['id'] as int,
      question: json['question'] as String,
      agentName: json['agent_name'] as String? ?? 'Agent',
      agentIcon: json['agent_icon'] as String? ?? '🤖',
      priority: json['priority'] as int? ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      context: json['context'] as Map<String, dynamic>?,
      executionId: json['execution_id'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'question': question,
        'agent_name': agentName,
        'agent_icon': agentIcon,
        'priority': priority,
        'created_at': createdAt.toIso8601String(),
        'context': context,
        'execution_id': executionId,
      };

  /// Get relative time string (e.g., "2m ago")
  String get timeAgo {
    final now = DateTime.now();
    final difference = now.difference(createdAt);

    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }
}

/// Model for agent completion notifications
class AgentCompletion {
  final int id;
  final String agentName;
  final String agentIcon;
  final String message;
  final String? workType;
  final int? executionId;
  final DateTime createdAt;

  AgentCompletion({
    required this.id,
    required this.agentName,
    required this.agentIcon,
    required this.message,
    this.workType,
    this.executionId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory AgentCompletion.fromJson(Map<String, dynamic> json) {
    // Handle both string ID (from SSE) and int ID (from polling)
    final rawId = json['id'];
    int id;
    if (rawId is int) {
      id = rawId;
    } else if (rawId is String) {
      // SSE sends string IDs like "completion-123"
      final match = RegExp(r'\d+').firstMatch(rawId);
      id = match != null ? int.parse(match.group(0)!) : DateTime.now().millisecondsSinceEpoch;
    } else {
      id = DateTime.now().millisecondsSinceEpoch;
    }

    return AgentCompletion(
      id: id,
      agentName: json['agent_name'] as String? ?? 'Agent',
      agentIcon: json['agent_icon'] as String? ?? '✅',
      message: json['message'] as String? ?? 'Task completed',
      workType: json['work_type'] as String?,
      executionId: json['execution_id'] as int?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }
}
