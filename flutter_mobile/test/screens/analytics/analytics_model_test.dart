import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/analytics.dart';

void main() {
  group('AnalyticsSummary', () {
    test('creates with default values', () {
      final summary = AnalyticsSummary();

      expect(summary.totalCampaigns, 0);
      expect(summary.activeCampaigns, 0);
      expect(summary.totalContacts, 0);
      expect(summary.activeContacts, 0);
      expect(summary.totalLandingPages, 0);
      expect(summary.publishedLandingPages, 0);
    });

    test('creates with custom values', () {
      final summary = AnalyticsSummary(
        totalCampaigns: 10,
        activeCampaigns: 3,
        totalContacts: 1000,
        activeContacts: 800,
        totalLandingPages: 5,
        publishedLandingPages: 3,
      );

      expect(summary.totalCampaigns, 10);
      expect(summary.activeCampaigns, 3);
      expect(summary.totalContacts, 1000);
      expect(summary.activeContacts, 800);
      expect(summary.totalLandingPages, 5);
      expect(summary.publishedLandingPages, 3);
    });

    test('fromJson parses complete data', () {
      final json = {
        'total_campaigns': 15,
        'active_campaigns': 5,
        'total_contacts': 2000,
        'active_contacts': 1500,
        'total_landing_pages': 8,
        'published_landing_pages': 6,
      };

      final summary = AnalyticsSummary.fromJson(json);

      expect(summary.totalCampaigns, 15);
      expect(summary.activeCampaigns, 5);
      expect(summary.totalContacts, 2000);
      expect(summary.activeContacts, 1500);
      expect(summary.totalLandingPages, 8);
      expect(summary.publishedLandingPages, 6);
    });

    test('fromJson handles empty json', () {
      final summary = AnalyticsSummary.fromJson({});

      expect(summary.totalCampaigns, 0);
      expect(summary.activeCampaigns, 0);
      expect(summary.totalContacts, 0);
      expect(summary.activeContacts, 0);
      expect(summary.totalLandingPages, 0);
      expect(summary.publishedLandingPages, 0);
    });

    test('fromJson handles null values', () {
      final json = {
        'total_campaigns': null,
        'active_campaigns': null,
      };

      final summary = AnalyticsSummary.fromJson(json);

      expect(summary.totalCampaigns, 0);
      expect(summary.activeCampaigns, 0);
    });
  });

  group('CampaignStats', () {
    test('creates with default values', () {
      final stats = CampaignStats();

      expect(stats.totalSent, 0);
      expect(stats.avgOpenRate, 0);
      expect(stats.avgClickRate, 0);
      expect(stats.avgBounceRate, 0);
    });

    test('creates with custom values', () {
      final stats = CampaignStats(
        totalSent: 5000,
        avgOpenRate: 25.5,
        avgClickRate: 3.2,
        avgBounceRate: 1.1,
      );

      expect(stats.totalSent, 5000);
      expect(stats.avgOpenRate, 25.5);
      expect(stats.avgClickRate, 3.2);
      expect(stats.avgBounceRate, 1.1);
    });

    test('fromJson parses complete data', () {
      final json = {
        'total_sent': 10000,
        'avg_open_rate': 30.5,
        'avg_click_rate': 5.2,
        'avg_bounce_rate': 0.8,
      };

      final stats = CampaignStats.fromJson(json);

      expect(stats.totalSent, 10000);
      expect(stats.avgOpenRate, 30.5);
      expect(stats.avgClickRate, 5.2);
      expect(stats.avgBounceRate, 0.8);
    });

    test('fromJson handles empty json', () {
      final stats = CampaignStats.fromJson({});

      expect(stats.totalSent, 0);
      expect(stats.avgOpenRate, 0.0);
      expect(stats.avgClickRate, 0.0);
      expect(stats.avgBounceRate, 0.0);
    });

    test('fromJson converts int rates to double', () {
      final json = {
        'total_sent': 100,
        'avg_open_rate': 25,
        'avg_click_rate': 3,
        'avg_bounce_rate': 1,
      };

      final stats = CampaignStats.fromJson(json);

      expect(stats.avgOpenRate, isA<double>());
      expect(stats.avgOpenRate, 25.0);
      expect(stats.avgClickRate, isA<double>());
      expect(stats.avgBounceRate, isA<double>());
    });
  });

  group('LandingPageStats', () {
    test('creates with default values', () {
      final stats = LandingPageStats();

      expect(stats.totalViews, 0);
      expect(stats.totalSubmissions, 0);
      expect(stats.conversionRate, 0);
    });

    test('creates with custom values', () {
      final stats = LandingPageStats(
        totalViews: 50000,
        totalSubmissions: 2500,
        conversionRate: 5.0,
      );

      expect(stats.totalViews, 50000);
      expect(stats.totalSubmissions, 2500);
      expect(stats.conversionRate, 5.0);
    });

    test('fromJson parses complete data', () {
      final json = {
        'total_views': 100000,
        'total_submissions': 8000,
        'conversion_rate': 8.0,
      };

      final stats = LandingPageStats.fromJson(json);

      expect(stats.totalViews, 100000);
      expect(stats.totalSubmissions, 8000);
      expect(stats.conversionRate, 8.0);
    });

    test('fromJson handles empty json', () {
      final stats = LandingPageStats.fromJson({});

      expect(stats.totalViews, 0);
      expect(stats.totalSubmissions, 0);
      expect(stats.conversionRate, 0.0);
    });

    test('fromJson converts int conversion rate to double', () {
      final json = {
        'total_views': 1000,
        'total_submissions': 50,
        'conversion_rate': 5,
      };

      final stats = LandingPageStats.fromJson(json);

      expect(stats.conversionRate, isA<double>());
      expect(stats.conversionRate, 5.0);
    });
  });

  group('RecentActivity', () {
    test('creates with required values', () {
      final timestamp = DateTime(2025, 1, 15, 10, 30);
      final activity = RecentActivity(
        type: 'campaign',
        title: 'Newsletter Sent',
        description: 'Monthly newsletter was sent to 500 subscribers',
        timestamp: timestamp,
      );

      expect(activity.type, 'campaign');
      expect(activity.title, 'Newsletter Sent');
      expect(activity.description, 'Monthly newsletter was sent to 500 subscribers');
      expect(activity.timestamp, timestamp);
    });

    test('fromJson parses complete data', () {
      final json = {
        'type': 'landing_page',
        'title': 'Landing Page Published',
        'description': 'Product launch page is now live',
        'timestamp': '2025-01-15T14:30:00Z',
      };

      final activity = RecentActivity.fromJson(json);

      expect(activity.type, 'landing_page');
      expect(activity.title, 'Landing Page Published');
      expect(activity.description, 'Product launch page is now live');
      expect(activity.timestamp.year, 2025);
      expect(activity.timestamp.month, 1);
      expect(activity.timestamp.day, 15);
    });

    test('fromJson handles missing string values', () {
      final json = {
        'timestamp': '2025-01-15T14:30:00Z',
      };

      final activity = RecentActivity.fromJson(json);

      expect(activity.type, '');
      expect(activity.title, '');
      expect(activity.description, '');
    });

    test('creates activity with contact type', () {
      final activity = RecentActivity(
        type: 'contact',
        title: 'New Contact Added',
        description: 'john.doe@example.com was added',
        timestamp: DateTime.now(),
      );

      expect(activity.type, 'contact');
    });
  });

  group('AnalyticsDashboard', () {
    test('creates with required values', () {
      final dashboard = AnalyticsDashboard(
        summary: AnalyticsSummary(),
        campaigns: CampaignStats(),
        landingPages: LandingPageStats(),
        recentActivity: [],
      );

      expect(dashboard.summary, isA<AnalyticsSummary>());
      expect(dashboard.campaigns, isA<CampaignStats>());
      expect(dashboard.landingPages, isA<LandingPageStats>());
      expect(dashboard.recentActivity, isEmpty);
    });

    test('fromJson parses complete data', () {
      final json = {
        'summary': {
          'total_campaigns': 10,
          'active_campaigns': 2,
          'total_contacts': 500,
          'active_contacts': 400,
          'total_landing_pages': 3,
          'published_landing_pages': 2,
        },
        'campaigns': {
          'total_sent': 5000,
          'avg_open_rate': 28.5,
          'avg_click_rate': 4.2,
          'avg_bounce_rate': 0.5,
        },
        'landing_pages': {
          'total_views': 25000,
          'total_submissions': 1250,
          'conversion_rate': 5.0,
        },
        'recent_activity': [
          {
            'type': 'campaign',
            'title': 'Campaign Sent',
            'description': 'Welcome email campaign',
            'timestamp': '2025-01-15T10:00:00Z',
          },
          {
            'type': 'landing_page',
            'title': 'Page Created',
            'description': 'New product page',
            'timestamp': '2025-01-14T15:30:00Z',
          },
        ],
      };

      final dashboard = AnalyticsDashboard.fromJson(json);

      expect(dashboard.summary.totalCampaigns, 10);
      expect(dashboard.summary.activeCampaigns, 2);
      expect(dashboard.campaigns.totalSent, 5000);
      expect(dashboard.campaigns.avgOpenRate, 28.5);
      expect(dashboard.landingPages.totalViews, 25000);
      expect(dashboard.landingPages.conversionRate, 5.0);
      expect(dashboard.recentActivity.length, 2);
      expect(dashboard.recentActivity[0].type, 'campaign');
      expect(dashboard.recentActivity[1].type, 'landing_page');
    });

    test('fromJson handles empty json', () {
      final dashboard = AnalyticsDashboard.fromJson({});

      expect(dashboard.summary.totalCampaigns, 0);
      expect(dashboard.campaigns.totalSent, 0);
      expect(dashboard.landingPages.totalViews, 0);
      expect(dashboard.recentActivity, isEmpty);
    });

    test('fromJson handles null recent_activity', () {
      final json = <String, dynamic>{
        'summary': <String, dynamic>{},
        'campaigns': <String, dynamic>{},
        'landing_pages': <String, dynamic>{},
        'recent_activity': null,
      };

      final dashboard = AnalyticsDashboard.fromJson(json);

      expect(dashboard.recentActivity, isEmpty);
    });

    test('fromJson handles missing nested objects', () {
      final json = {
        'recent_activity': [],
      };

      final dashboard = AnalyticsDashboard.fromJson(json);

      expect(dashboard.summary, isA<AnalyticsSummary>());
      expect(dashboard.campaigns, isA<CampaignStats>());
      expect(dashboard.landingPages, isA<LandingPageStats>());
    });

    test('creates dashboard with multiple activities', () {
      final activities = [
        RecentActivity(
          type: 'campaign',
          title: 'Activity 1',
          description: 'Desc 1',
          timestamp: DateTime(2025, 1, 15),
        ),
        RecentActivity(
          type: 'contact',
          title: 'Activity 2',
          description: 'Desc 2',
          timestamp: DateTime(2025, 1, 14),
        ),
        RecentActivity(
          type: 'landing_page',
          title: 'Activity 3',
          description: 'Desc 3',
          timestamp: DateTime(2025, 1, 13),
        ),
      ];

      final dashboard = AnalyticsDashboard(
        summary: AnalyticsSummary(totalCampaigns: 5),
        campaigns: CampaignStats(totalSent: 1000),
        landingPages: LandingPageStats(totalViews: 5000),
        recentActivity: activities,
      );

      expect(dashboard.recentActivity.length, 3);
      expect(dashboard.recentActivity[0].title, 'Activity 1');
      expect(dashboard.recentActivity[2].title, 'Activity 3');
    });
  });
}
