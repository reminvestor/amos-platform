class AnalyticsSummary {
  final int totalCampaigns;
  final int activeCampaigns;
  final int totalContacts;
  final int activeContacts;
  final int totalLandingPages;
  final int publishedLandingPages;

  AnalyticsSummary({
    this.totalCampaigns = 0,
    this.activeCampaigns = 0,
    this.totalContacts = 0,
    this.activeContacts = 0,
    this.totalLandingPages = 0,
    this.publishedLandingPages = 0,
  });

  factory AnalyticsSummary.fromJson(Map<String, dynamic> json) {
    return AnalyticsSummary(
      totalCampaigns: json['total_campaigns'] ?? 0,
      activeCampaigns: json['active_campaigns'] ?? 0,
      totalContacts: json['total_contacts'] ?? 0,
      activeContacts: json['active_contacts'] ?? 0,
      totalLandingPages: json['total_landing_pages'] ?? 0,
      publishedLandingPages: json['published_landing_pages'] ?? 0,
    );
  }
}

class CampaignStats {
  final int totalSent;
  final double avgOpenRate;
  final double avgClickRate;
  final double avgBounceRate;

  CampaignStats({
    this.totalSent = 0,
    this.avgOpenRate = 0,
    this.avgClickRate = 0,
    this.avgBounceRate = 0,
  });

  factory CampaignStats.fromJson(Map<String, dynamic> json) {
    return CampaignStats(
      totalSent: json['total_sent'] ?? 0,
      avgOpenRate: (json['avg_open_rate'] ?? 0).toDouble(),
      avgClickRate: (json['avg_click_rate'] ?? 0).toDouble(),
      avgBounceRate: (json['avg_bounce_rate'] ?? 0).toDouble(),
    );
  }
}

class LandingPageStats {
  final int totalViews;
  final int totalSubmissions;
  final double conversionRate;

  LandingPageStats({
    this.totalViews = 0,
    this.totalSubmissions = 0,
    this.conversionRate = 0,
  });

  factory LandingPageStats.fromJson(Map<String, dynamic> json) {
    return LandingPageStats(
      totalViews: json['total_views'] ?? 0,
      totalSubmissions: json['total_submissions'] ?? 0,
      conversionRate: (json['conversion_rate'] ?? 0).toDouble(),
    );
  }
}

class RecentActivity {
  final String type;
  final String title;
  final String description;
  final DateTime timestamp;

  RecentActivity({
    required this.type,
    required this.title,
    required this.description,
    required this.timestamp,
  });

  factory RecentActivity.fromJson(Map<String, dynamic> json) {
    return RecentActivity(
      type: json['type'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}

class AnalyticsDashboard {
  final AnalyticsSummary summary;
  final CampaignStats campaigns;
  final LandingPageStats landingPages;
  final List<RecentActivity> recentActivity;

  AnalyticsDashboard({
    required this.summary,
    required this.campaigns,
    required this.landingPages,
    required this.recentActivity,
  });

  factory AnalyticsDashboard.fromJson(Map<String, dynamic> json) {
    return AnalyticsDashboard(
      summary: AnalyticsSummary.fromJson(json['summary'] ?? {}),
      campaigns: CampaignStats.fromJson(json['campaigns'] ?? {}),
      landingPages: LandingPageStats.fromJson(json['landing_pages'] ?? {}),
      recentActivity: (json['recent_activity'] as List<dynamic>?)
              ?.map((a) => RecentActivity.fromJson(a))
              .toList() ??
          [],
    );
  }
}
