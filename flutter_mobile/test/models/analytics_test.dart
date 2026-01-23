import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/analytics.dart';

void main() {
  group('AnalyticsSummary', () {
    test('creates with default values', () {
      final summary = AnalyticsSummary();

      expect(summary.totalCampaigns, equals(0));
      expect(summary.activeCampaigns, equals(0));
      expect(summary.totalContacts, equals(0));
      expect(summary.activeContacts, equals(0));
      expect(summary.totalLandingPages, equals(0));
      expect(summary.publishedLandingPages, equals(0));
    });

    test('fromJson parses correctly', () {
      final json = {
        'total_campaigns': 10,
        'active_campaigns': 5,
        'total_contacts': 1000,
        'active_contacts': 800,
        'total_landing_pages': 20,
        'published_landing_pages': 15,
      };

      final summary = AnalyticsSummary.fromJson(json);

      expect(summary.totalCampaigns, equals(10));
      expect(summary.activeCampaigns, equals(5));
      expect(summary.totalContacts, equals(1000));
      expect(summary.activeContacts, equals(800));
      expect(summary.totalLandingPages, equals(20));
      expect(summary.publishedLandingPages, equals(15));
    });

    test('fromJson handles missing values', () {
      final json = <String, dynamic>{};
      final summary = AnalyticsSummary.fromJson(json);

      expect(summary.totalCampaigns, equals(0));
      expect(summary.totalContacts, equals(0));
    });
  });

  group('CampaignStats', () {
    test('creates with default values', () {
      final stats = CampaignStats();

      expect(stats.totalSent, equals(0));
      expect(stats.avgOpenRate, equals(0));
      expect(stats.avgClickRate, equals(0));
      expect(stats.avgBounceRate, equals(0));
    });

    test('fromJson parses correctly', () {
      final json = {
        'total_sent': 5000,
        'avg_open_rate': 45.5,
        'avg_click_rate': 12.3,
        'avg_bounce_rate': 2.1,
      };

      final stats = CampaignStats.fromJson(json);

      expect(stats.totalSent, equals(5000));
      expect(stats.avgOpenRate, equals(45.5));
      expect(stats.avgClickRate, equals(12.3));
      expect(stats.avgBounceRate, equals(2.1));
    });

    test('fromJson handles int values for rates', () {
      final json = {
        'total_sent': 1000,
        'avg_open_rate': 45,
        'avg_click_rate': 12,
        'avg_bounce_rate': 2,
      };

      final stats = CampaignStats.fromJson(json);

      expect(stats.avgOpenRate, equals(45.0));
      expect(stats.avgClickRate, equals(12.0));
      expect(stats.avgBounceRate, equals(2.0));
    });
  });

  group('LandingPageStats', () {
    test('creates with default values', () {
      final stats = LandingPageStats();

      expect(stats.totalViews, equals(0));
      expect(stats.totalSubmissions, equals(0));
      expect(stats.conversionRate, equals(0));
    });

    test('fromJson parses correctly', () {
      final json = {
        'total_views': 10000,
        'total_submissions': 500,
        'conversion_rate': 5.0,
      };

      final stats = LandingPageStats.fromJson(json);

      expect(stats.totalViews, equals(10000));
      expect(stats.totalSubmissions, equals(500));
      expect(stats.conversionRate, equals(5.0));
    });
  });

  group('RecentActivity', () {
    test('fromJson parses correctly', () {
      final json = {
        'type': 'campaign_sent',
        'title': 'Campaign Sent',
        'description': 'Newsletter campaign sent to 500 recipients',
        'timestamp': '2024-01-15T10:30:00.000Z',
      };

      final activity = RecentActivity.fromJson(json);

      expect(activity.type, equals('campaign_sent'));
      expect(activity.title, equals('Campaign Sent'));
      expect(activity.description, equals('Newsletter campaign sent to 500 recipients'));
      expect(activity.timestamp, equals(DateTime.parse('2024-01-15T10:30:00.000Z')));
    });

    test('fromJson handles missing values', () {
      final json = {
        'timestamp': '2024-01-15T10:30:00.000Z',
      };

      final activity = RecentActivity.fromJson(json);

      expect(activity.type, equals(''));
      expect(activity.title, equals(''));
      expect(activity.description, equals(''));
    });
  });

  group('AnalyticsDashboard', () {
    test('fromJson parses complete JSON correctly', () {
      final json = {
        'summary': {
          'total_campaigns': 10,
          'active_campaigns': 5,
        },
        'campaigns': {
          'total_sent': 5000,
          'avg_open_rate': 45.5,
        },
        'landing_pages': {
          'total_views': 10000,
          'total_submissions': 500,
        },
        'recent_activity': [
          {
            'type': 'campaign_sent',
            'title': 'Campaign Sent',
            'description': 'Description',
            'timestamp': '2024-01-15T10:30:00.000Z',
          },
        ],
      };

      final dashboard = AnalyticsDashboard.fromJson(json);

      expect(dashboard.summary.totalCampaigns, equals(10));
      expect(dashboard.campaigns.totalSent, equals(5000));
      expect(dashboard.landingPages.totalViews, equals(10000));
      expect(dashboard.recentActivity.length, equals(1));
      expect(dashboard.recentActivity.first.type, equals('campaign_sent'));
    });

    test('fromJson handles missing sections', () {
      final json = <String, dynamic>{};

      final dashboard = AnalyticsDashboard.fromJson(json);

      expect(dashboard.summary.totalCampaigns, equals(0));
      expect(dashboard.campaigns.totalSent, equals(0));
      expect(dashboard.landingPages.totalViews, equals(0));
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
  });
}
