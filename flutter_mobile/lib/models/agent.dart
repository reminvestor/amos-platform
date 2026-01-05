enum AgentType {
  executor,
  planner,
  analyst,
  verifier,
  fixer,
  architect,
  engineer,
  custom,
}

extension AgentTypeX on AgentType {
  String get value {
    switch (this) {
      case AgentType.executor:
        return 'executor';
      case AgentType.planner:
        return 'planner';
      case AgentType.analyst:
        return 'analyst';
      case AgentType.verifier:
        return 'verifier';
      case AgentType.fixer:
        return 'fixer';
      case AgentType.architect:
        return 'architect';
      case AgentType.engineer:
        return 'engineer';
      case AgentType.custom:
        return 'custom';
    }
  }

  String get displayName {
    switch (this) {
      case AgentType.executor:
        return 'Executor';
      case AgentType.planner:
        return 'Planner';
      case AgentType.analyst:
        return 'Analyst';
      case AgentType.verifier:
        return 'Verifier';
      case AgentType.fixer:
        return 'Fixer';
      case AgentType.architect:
        return 'Architect';
      case AgentType.engineer:
        return 'Engineer';
      case AgentType.custom:
        return 'Custom';
    }
  }

  static AgentType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'executor':
        return AgentType.executor;
      case 'planner':
        return AgentType.planner;
      case 'analyst':
        return AgentType.analyst;
      case 'verifier':
        return AgentType.verifier;
      case 'fixer':
        return AgentType.fixer;
      case 'architect':
        return AgentType.architect;
      case 'engineer':
        return AgentType.engineer;
      case 'custom':
        return AgentType.custom;
      default:
        return AgentType.custom;
    }
  }
}

class AgentFieldOption {
  final String label;
  final String value;

  AgentFieldOption({
    required this.label,
    required this.value,
  });

  factory AgentFieldOption.fromJson(Map<String, dynamic> json) {
    return AgentFieldOption(
      label: json['label'],
      value: json['value'],
    );
  }
}

class AgentField {
  final String name;
  final String question;
  final bool required;
  final String? type;
  final List<String>? examples;
  final List<AgentFieldOption>? options;

  AgentField({
    required this.name,
    required this.question,
    required this.required,
    this.type,
    this.examples,
    this.options,
  });

  factory AgentField.fromJson(Map<String, dynamic> json) {
    return AgentField(
      name: json['name'],
      question: json['question'],
      required: json['required'] ?? false,
      type: json['type'],
      examples:
          json['examples'] != null ? List<String>.from(json['examples']) : null,
      options: json['options'] != null
          ? (json['options'] as List)
              .map((o) => AgentFieldOption.fromJson(o))
              .toList()
          : null,
    );
  }
}

class AgentTool {
  final String name;
  final bool required;

  AgentTool({
    required this.name,
    required this.required,
  });

  factory AgentTool.fromJson(Map<String, dynamic> json) {
    return AgentTool(
      name: json['name'] ?? '',
      required: json['required'] ?? false,
    );
  }

  /// Returns a human-readable display name from the tool name
  String get displayName {
    // Convert snake_case to Title Case
    return name
        .split('_')
        .map((word) => word.isNotEmpty
            ? '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}'
            : '')
        .join(' ');
  }
}

class Agent {
  final String id;
  final String name;
  final String description;
  final AgentType agentType;
  final bool interactive;
  final String icon;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<AgentField>? fields;
  final List<String>? requiredContext;
  final List<String>? capabilities;
  final List<AgentTool>? tools;

  Agent({
    required this.id,
    required this.name,
    required this.description,
    required this.agentType,
    required this.interactive,
    required this.icon,
    required this.createdAt,
    this.updatedAt,
    this.fields,
    this.requiredContext,
    this.capabilities,
    this.tools,
  });

  factory Agent.fromJson(Map<String, dynamic> json) {
    return Agent(
      id: json['id'].toString(),
      name: json['name'] ?? 'Unnamed Agent',
      description: json['description'] ?? '',
      agentType: AgentTypeX.fromString(json['agent_type'] ?? 'custom'),
      interactive: json['interactive'] ?? false,
      icon: json['icon'] ?? 'Bot',
      createdAt: DateTime.parse(json['created_at']),
      updatedAt:
          json['updated_at'] != null ? DateTime.parse(json['updated_at']) : null,
      fields: json['fields'] != null
          ? (json['fields'] as List).map((f) => AgentField.fromJson(f)).toList()
          : null,
      requiredContext: json['required_context'] != null
          ? List<String>.from(json['required_context'])
          : null,
      capabilities: json['capabilities'] != null
          ? List<String>.from(json['capabilities'])
          : null,
      tools: json['tools'] != null
          ? (json['tools'] as List).map((t) => AgentTool.fromJson(t)).toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'agent_type': agentType.value,
      'interactive': interactive,
      'icon': icon,
      'created_at': createdAt.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }
}

enum AgentExecutionStatus {
  pending,
  processing,
  completed,
  failed,
}

extension AgentExecutionStatusX on AgentExecutionStatus {
  String get value {
    switch (this) {
      case AgentExecutionStatus.pending:
        return 'pending';
      case AgentExecutionStatus.processing:
        return 'processing';
      case AgentExecutionStatus.completed:
        return 'completed';
      case AgentExecutionStatus.failed:
        return 'failed';
    }
  }

  static AgentExecutionStatus fromString(String value) {
    switch (value) {
      case 'pending':
        return AgentExecutionStatus.pending;
      case 'processing':
        return AgentExecutionStatus.processing;
      case 'completed':
        return AgentExecutionStatus.completed;
      case 'failed':
        return AgentExecutionStatus.failed;
      default:
        return AgentExecutionStatus.pending;
    }
  }
}

class AgentExecution {
  final String jobId;
  final AgentExecutionStatus status;
  final Map<String, dynamic>? result;
  final String? error;

  AgentExecution({
    required this.jobId,
    required this.status,
    this.result,
    this.error,
  });

  factory AgentExecution.fromJson(Map<String, dynamic> json) {
    return AgentExecution(
      jobId: json['job_id'],
      status: AgentExecutionStatusX.fromString(json['status'] ?? 'pending'),
      result: json['result'],
      error: json['error'],
    );
  }
}
