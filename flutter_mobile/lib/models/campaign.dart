class MailgunStats {
  final int delivered;
  final int failed;
  final int bounced;
  final int unsubscribed;
  final int complained;
  final int opened;
  final int clicked;

  MailgunStats({
    this.delivered = 0,
    this.failed = 0,
    this.bounced = 0,
    this.unsubscribed = 0,
    this.complained = 0,
    this.opened = 0,
    this.clicked = 0,
  });

  factory MailgunStats.fromJson(Map<String, dynamic> json) {
    return MailgunStats(
      delivered: json['delivered'] ?? 0,
      failed: json['failed'] ?? 0,
      bounced: json['bounced'] ?? 0,
      unsubscribed: json['unsubscribed'] ?? 0,
      complained: json['complained'] ?? 0,
      opened: json['opened'] ?? 0,
      clicked: json['clicked'] ?? 0,
    );
  }
}

enum CampaignStatus {
  draft,
  scheduled,
  inProgress,
  completed,
  paused,
  stopped,
}

extension CampaignStatusX on CampaignStatus {
  String get value {
    switch (this) {
      case CampaignStatus.draft:
        return 'draft';
      case CampaignStatus.scheduled:
        return 'scheduled';
      case CampaignStatus.inProgress:
        return 'in_progress';
      case CampaignStatus.completed:
        return 'completed';
      case CampaignStatus.paused:
        return 'paused';
      case CampaignStatus.stopped:
        return 'stopped';
    }
  }

  static CampaignStatus fromString(String value) {
    switch (value) {
      case 'draft':
        return CampaignStatus.draft;
      case 'scheduled':
        return CampaignStatus.scheduled;
      case 'in_progress':
        return CampaignStatus.inProgress;
      case 'completed':
        return CampaignStatus.completed;
      case 'paused':
        return CampaignStatus.paused;
      case 'stopped':
        return CampaignStatus.stopped;
      default:
        return CampaignStatus.draft;
    }
  }
}

class Campaign {
  final String id;
  final String entityId;
  final String userId;
  final String name;
  final String subject;
  final CampaignStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? scheduledAt;
  final int? contactCount;
  final double? openRate;
  final double? clickRate;
  final double? bounceRate;
  final MailgunStats? mailgunStats;

  Campaign({
    required this.id,
    required this.entityId,
    required this.userId,
    required this.name,
    required this.subject,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.scheduledAt,
    this.contactCount,
    this.openRate,
    this.clickRate,
    this.bounceRate,
    this.mailgunStats,
  });

  factory Campaign.fromJson(Map<String, dynamic> json) {
    return Campaign(
      id: json['id'],
      entityId: json['entity_id'],
      userId: json['user_id'],
      name: json['name'] ?? '',
      subject: json['subject'] ?? '',
      status: CampaignStatusX.fromString(json['status'] ?? 'draft'),
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      scheduledAt: json['scheduled_at'] != null
          ? DateTime.parse(json['scheduled_at'])
          : null,
      contactCount: json['contact_count'],
      openRate: json['open_rate']?.toDouble(),
      clickRate: json['click_rate']?.toDouble(),
      bounceRate: json['bounce_rate']?.toDouble(),
      mailgunStats: json['mailgun_stats'] != null
          ? MailgunStats.fromJson(json['mailgun_stats'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entity_id': entityId,
      'user_id': userId,
      'name': name,
      'subject': subject,
      'status': status.value,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      if (scheduledAt != null) 'scheduled_at': scheduledAt!.toIso8601String(),
      if (contactCount != null) 'contact_count': contactCount,
      if (openRate != null) 'open_rate': openRate,
      if (clickRate != null) 'click_rate': clickRate,
      if (bounceRate != null) 'bounce_rate': bounceRate,
    };
  }
}
