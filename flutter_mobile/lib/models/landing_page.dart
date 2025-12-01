enum LandingPageStatus {
  draft,
  published,
}

extension LandingPageStatusX on LandingPageStatus {
  String get value {
    switch (this) {
      case LandingPageStatus.draft:
        return 'draft';
      case LandingPageStatus.published:
        return 'published';
    }
  }

  static LandingPageStatus fromString(String value) {
    switch (value) {
      case 'draft':
        return LandingPageStatus.draft;
      case 'published':
        return LandingPageStatus.published;
      default:
        return LandingPageStatus.draft;
    }
  }
}

class LandingPage {
  final String id;
  final String entityId;
  final String title;
  final String slug;
  final LandingPageStatus status;
  final String htmlContent;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int? submissionCount;
  final int? viewCount;
  final DateTime? publishedAt;

  LandingPage({
    required this.id,
    required this.entityId,
    required this.title,
    required this.slug,
    required this.status,
    required this.htmlContent,
    required this.createdAt,
    required this.updatedAt,
    this.submissionCount,
    this.viewCount,
    this.publishedAt,
  });

  factory LandingPage.fromJson(Map<String, dynamic> json) {
    return LandingPage(
      id: json['id'],
      entityId: json['entity_id'],
      title: json['title'] ?? '',
      slug: json['slug'] ?? '',
      status: LandingPageStatusX.fromString(json['status'] ?? 'draft'),
      htmlContent: json['html_content'] ?? '',
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      submissionCount: json['submission_count'],
      viewCount: json['view_count'],
      publishedAt: json['published_at'] != null
          ? DateTime.parse(json['published_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entity_id': entityId,
      'title': title,
      'slug': slug,
      'status': status.value,
      'html_content': htmlContent,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      if (submissionCount != null) 'submission_count': submissionCount,
      if (viewCount != null) 'view_count': viewCount,
      if (publishedAt != null) 'published_at': publishedAt!.toIso8601String(),
    };
  }
}

class LandingPageSubmission {
  final String id;
  final String landingPageId;
  final String email;
  final Map<String, dynamic>? data;
  final String? ipAddress;
  final String? userAgent;
  final DateTime createdAt;

  LandingPageSubmission({
    required this.id,
    required this.landingPageId,
    required this.email,
    this.data,
    this.ipAddress,
    this.userAgent,
    required this.createdAt,
  });

  factory LandingPageSubmission.fromJson(Map<String, dynamic> json) {
    return LandingPageSubmission(
      id: json['id'],
      landingPageId: json['landing_page_id'],
      email: json['email'],
      data: json['data'],
      ipAddress: json['ip_address'],
      userAgent: json['user_agent'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}
