class EmailTemplate {
  final String id;
  final String name;
  final String subject;
  final String body;
  final String? description;
  final int campaignsCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  EmailTemplate({
    required this.id,
    required this.name,
    required this.subject,
    required this.body,
    this.description,
    this.campaignsCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory EmailTemplate.fromJson(Map<String, dynamic> json) {
    return EmailTemplate(
      id: json['id'].toString(),
      name: json['name'] ?? '',
      subject: json['subject'] ?? '',
      body: json['body'] ?? '',
      description: json['description'],
      campaignsCount: json['campaigns_count'] ?? 0,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'subject': subject,
      'body': body,
      if (description != null) 'description': description,
      'campaigns_count': campaignsCount,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Get a preview of the body content (first 100 chars)
  String get bodyPreview {
    final stripped = body
        .replaceAll(RegExp(r'<[^>]*>'), '') // Remove HTML tags
        .replaceAll(RegExp(r'\s+'), ' ') // Normalize whitespace
        .trim();
    if (stripped.length <= 100) return stripped;
    return '${stripped.substring(0, 100)}...';
  }
}
