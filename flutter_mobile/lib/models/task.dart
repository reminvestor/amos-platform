enum TaskStatus {
  pending,
  inProgress,
  completed,
  cancelled,
}

extension TaskStatusX on TaskStatus {
  String get value {
    switch (this) {
      case TaskStatus.pending:
        return 'pending';
      case TaskStatus.inProgress:
        return 'in_progress';
      case TaskStatus.completed:
        return 'completed';
      case TaskStatus.cancelled:
        return 'cancelled';
    }
  }

  String get displayName {
    switch (this) {
      case TaskStatus.pending:
        return 'Pending';
      case TaskStatus.inProgress:
        return 'In Progress';
      case TaskStatus.completed:
        return 'Completed';
      case TaskStatus.cancelled:
        return 'Cancelled';
    }
  }

  static TaskStatus fromString(String value) {
    switch (value) {
      case 'pending':
        return TaskStatus.pending;
      case 'in_progress':
        return TaskStatus.inProgress;
      case 'completed':
        return TaskStatus.completed;
      case 'cancelled':
        return TaskStatus.cancelled;
      default:
        return TaskStatus.pending;
    }
  }
}

enum TaskPriority {
  low,
  medium,
  high,
}

extension TaskPriorityX on TaskPriority {
  String get value {
    switch (this) {
      case TaskPriority.low:
        return 'low';
      case TaskPriority.medium:
        return 'medium';
      case TaskPriority.high:
        return 'high';
    }
  }

  String get displayName {
    switch (this) {
      case TaskPriority.low:
        return 'Low';
      case TaskPriority.medium:
        return 'Medium';
      case TaskPriority.high:
        return 'High';
    }
  }

  static TaskPriority fromString(String value) {
    switch (value) {
      case 'low':
        return TaskPriority.low;
      case 'medium':
        return TaskPriority.medium;
      case 'high':
        return TaskPriority.high;
      default:
        return TaskPriority.medium;
    }
  }
}

class RelatedEntity {
  final String type;
  final String? id;

  RelatedEntity({
    required this.type,
    this.id,
  });

  factory RelatedEntity.fromJson(Map<String, dynamic> json) {
    return RelatedEntity(
      type: json['type'],
      id: json['id'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      if (id != null) 'id': id,
    };
  }
}

class Task {
  final String id;
  final String entityId;
  final String userId;
  final String title;
  final String? description;
  final TaskStatus status;
  final TaskPriority priority;
  final DateTime? dueDate;
  final String? assignedTo;
  final List<String>? tags;
  final RelatedEntity? relatedEntity;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;

  Task({
    required this.id,
    required this.entityId,
    required this.userId,
    required this.title,
    this.description,
    required this.status,
    required this.priority,
    this.dueDate,
    this.assignedTo,
    this.tags,
    this.relatedEntity,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'],
      entityId: json['entity_id'],
      userId: json['user_id'],
      title: json['title'],
      description: json['description'],
      status: TaskStatusX.fromString(json['status'] ?? 'pending'),
      priority: TaskPriorityX.fromString(json['priority'] ?? 'medium'),
      dueDate:
          json['due_date'] != null ? DateTime.parse(json['due_date']) : null,
      assignedTo: json['assigned_to'],
      tags: json['tags'] != null ? List<String>.from(json['tags']) : null,
      relatedEntity: json['related_entity'] != null
          ? RelatedEntity.fromJson(json['related_entity'])
          : null,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entity_id': entityId,
      'user_id': userId,
      'title': title,
      if (description != null) 'description': description,
      'status': status.value,
      'priority': priority.value,
      if (dueDate != null) 'due_date': dueDate!.toIso8601String(),
      if (assignedTo != null) 'assigned_to': assignedTo,
      if (tags != null) 'tags': tags,
      if (relatedEntity != null) 'related_entity': relatedEntity!.toJson(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      if (completedAt != null) 'completed_at': completedAt!.toIso8601String(),
    };
  }
}
