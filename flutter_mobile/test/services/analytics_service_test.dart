import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/analytics.dart';

// Note: AnalyticsService uses ApiClient which requires FlutterSecureStorage.
// For unit tests, we test the response parsing logic and model behavior separately.

void main() {
  group('AnalyticsSummary Model', () {
    test('parses full summary response', () {
      final json = {
        'total_campaigns': 25,
        'active_campaigns': 5,
        'total_contacts': 1500,
        'active_contacts': 1200,
        'total_landing_pages': 12,
        'published_landing_pages': 8,
      };

      final summary = AnalyticsSummary.fromJson(json);

      expect(summary.totalCampaigns, equals(25));
      expect(summary.activeCampaigns, equals(5));
      expect(summary.totalContacts, equals(1500));
      expect(summary.activeContacts, equals(1200));
      expect(summary.totalLandingPages, equals(12));
      expect(summary.publishedLandingPages, equals(8));
    });

    test('handles missing fields with defaults', () {
      final json = <String, dynamic>{};

      final summary = AnalyticsSummary.fromJson(json);

      expect(summary.totalCampaigns, equals(0));
      expect(summary.activeCampaigns, equals(0));
      expect(summary.totalContacts, equals(0));
      expect(summary.activeContacts, equals(0));
      expect(summary.totalLandingPages, equals(0));
      expect(summary.publishedLandingPages, equals(0));
    });

    test('handles null values gracefully', () {
      final json = {
        'total_campaigns': null,
        'total_contacts': null,
      };

      final summary = AnalyticsSummary.fromJson(json);

      expect(summary.totalCampaigns, equals(0));
      expect(summary.totalContacts, equals(0));
    });
  });

  group('CampaignStats Model', () {
    test('parses full campaign stats', () {
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

    test('converts int rates to double', () {
      final json = {
        'total_sent': 1000,
        'avg_open_rate': 50, // int instead of double
        'avg_click_rate': 15,
        'avg_bounce_rate': 3,
      };

      final stats = CampaignStats.fromJson(json);

      expect(stats.avgOpenRate, isA<double>());
      expect(stats.avgOpenRate, equals(50.0));
      expect(stats.avgClickRate, equals(15.0));
      expect(stats.avgBounceRate, equals(3.0));
    });

    test('handles missing fields with defaults', () {
      final json = <String, dynamic>{};

      final stats = CampaignStats.fromJson(json);

      expect(stats.totalSent, equals(0));
      expect(stats.avgOpenRate, equals(0.0));
      expect(stats.avgClickRate, equals(0.0));
      expect(stats.avgBounceRate, equals(0.0));
    });
  });

  group('LandingPageStats Model', () {
    test('parses full landing page stats', () {
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

    test('converts int rate to double', () {
      final json = {
        'total_views': 1000,
        'total_submissions': 50,
        'conversion_rate': 5, // int instead of double
      };

      final stats = LandingPageStats.fromJson(json);

      expect(stats.conversionRate, isA<double>());
      expect(stats.conversionRate, equals(5.0));
    });

    test('handles missing fields with defaults', () {
      final json = <String, dynamic>{};

      final stats = LandingPageStats.fromJson(json);

      expect(stats.totalViews, equals(0));
      expect(stats.totalSubmissions, equals(0));
      expect(stats.conversionRate, equals(0.0));
    });
  });

  group('RecentActivity Model', () {
    test('parses full activity', () {
      final json = {
        'type': 'campaign_sent',
        'title': 'Newsletter Q1',
        'description': 'Sent to 1000 contacts',
        'timestamp': '2024-01-15T10:30:00.000Z',
      };

      final activity = RecentActivity.fromJson(json);

      expect(activity.type, equals('campaign_sent'));
      expect(activity.title, equals('Newsletter Q1'));
      expect(activity.description, equals('Sent to 1000 contacts'));
      expect(activity.timestamp.year, equals(2024));
      expect(activity.timestamp.month, equals(1));
      expect(activity.timestamp.day, equals(15));
    });

    test('handles missing type with empty string', () {
      final json = {
        'title': 'Test',
        'description': 'Test desc',
        'timestamp': '2024-01-15T10:00:00.000Z',
      };

      final activity = RecentActivity.fromJson(json);

      expect(activity.type, equals(''));
    });
  });

  group('AnalyticsDashboard Model', () {
    test('parses full dashboard response', () {
      final json = {
        'summary': {
          'total_campaigns': 25,
          'active_campaigns': 5,
          'total_contacts': 1500,
          'active_contacts': 1200,
          'total_landing_pages': 12,
          'published_landing_pages': 8,
        },
        'campaigns': {
          'total_sent': 5000,
          'avg_open_rate': 45.5,
          'avg_click_rate': 12.3,
          'avg_bounce_rate': 2.1,
        },
        'landing_pages': {
          'total_views': 10000,
          'total_submissions': 500,
          'conversion_rate': 5.0,
        },
        'recent_activity': [
          {
            'type': 'campaign_sent',
            'title': 'Newsletter',
            'description': 'Sent successfully',
            'timestamp': '2024-01-15T10:00:00.000Z',
          },
          {
            'type': 'landing_page_created',
            'title': 'Product Launch',
            'description': 'New landing page',
            'timestamp': '2024-01-14T15:00:00.000Z',
          },
        ],
      };

      final dashboard = AnalyticsDashboard.fromJson(json);

      expect(dashboard.summary.totalCampaigns, equals(25));
      expect(dashboard.campaigns.totalSent, equals(5000));
      expect(dashboard.landingPages.totalViews, equals(10000));
      expect(dashboard.recentActivity, hasLength(2));
      expect(dashboard.recentActivity[0].type, equals('campaign_sent'));
    });

    test('handles missing nested objects with defaults', () {
      final json = <String, dynamic>{};

      final dashboard = AnalyticsDashboard.fromJson(json);

      expect(dashboard.summary.totalCampaigns, equals(0));
      expect(dashboard.campaigns.totalSent, equals(0));
      expect(dashboard.landingPages.totalViews, equals(0));
      expect(dashboard.recentActivity, isEmpty);
    });

    test('handles null recent_activity', () {
      final json = <String, dynamic>{
        'summary': <String, dynamic>{},
        'campaigns': <String, dynamic>{},
        'landing_pages': <String, dynamic>{},
        'recent_activity': null,
      };

      final dashboard = AnalyticsDashboard.fromJson(json);

      expect(dashboard.recentActivity, isEmpty);
    });

    test('handles empty recent_activity list', () {
      final json = <String, dynamic>{
        'summary': <String, dynamic>{},
        'campaigns': <String, dynamic>{},
        'landing_pages': <String, dynamic>{},
        'recent_activity': <dynamic>[],
      };

      final dashboard = AnalyticsDashboard.fromJson(json);

      expect(dashboard.recentActivity, isEmpty);
    });
  });

  group('Campaign Analytics Response Parsing', () {
    test('parses campaign analytics list', () {
      final responseData = {
        'data': [
          {
            'id': 1,
            'name': 'Newsletter Q1',
            'sent_count': 1000,
            'open_count': 450,
            'click_count': 120,
            'open_rate': 45.0,
            'click_rate': 12.0,
            'created_at': '2024-01-01',
          },
          {
            'id': 2,
            'name': 'Product Launch',
            'sent_count': 500,
            'open_count': 300,
            'click_count': 100,
            'open_rate': 60.0,
            'click_rate': 20.0,
            'created_at': '2024-01-10',
          },
        ],
      };

      final data = responseData['data'] as List? ?? [];
      final campaigns = data.cast<Map<String, dynamic>>();

      expect(campaigns, hasLength(2));
      expect(campaigns[0]['name'], equals('Newsletter Q1'));
      expect(campaigns[0]['open_rate'], equals(45.0));
      expect(campaigns[1]['name'], equals('Product Launch'));
      expect(campaigns[1]['click_rate'], equals(20.0));
    });

    test('handles empty data list', () {
      final responseData = {'data': []};

      final data = responseData['data'] as List? ?? [];

      expect(data, isEmpty);
    });

    test('handles missing data key', () {
      final responseData = <String, dynamic>{};

      final data = responseData['data'] as List? ?? [];

      expect(data, isEmpty);
    });
  });

  group('Landing Page Analytics Response Parsing', () {
    test('parses landing page analytics list', () {
      final responseData = {
        'data': [
          {
            'id': 1,
            'title': 'Product Launch Page',
            'views': 5000,
            'unique_visitors': 3500,
            'conversions': 250,
            'conversion_rate': 7.14,
            'created_at': '2024-01-05',
          },
          {
            'id': 2,
            'title': 'Webinar Signup',
            'views': 2000,
            'unique_visitors': 1800,
            'conversions': 180,
            'conversion_rate': 10.0,
            'created_at': '2024-01-12',
          },
        ],
      };

      final data = responseData['data'] as List? ?? [];
      final landingPages = data.cast<Map<String, dynamic>>();

      expect(landingPages, hasLength(2));
      expect(landingPages[0]['title'], equals('Product Launch Page'));
      expect(landingPages[0]['views'], equals(5000));
      expect(landingPages[1]['conversion_rate'], equals(10.0));
    });

    test('calculates derived metrics from raw data', () {
      final pageData = {
        'views': 1000,
        'unique_visitors': 800,
        'conversions': 50,
      };

      // Calculate conversion rate
      final views = pageData['views'] as int;
      final conversions = pageData['conversions'] as int;
      final conversionRate = views > 0 ? (conversions / views) * 100 : 0.0;

      expect(conversionRate, equals(5.0));
    });
  });

  group('Query Parameters Building', () {
    test('builds limit query parameter', () {
      const limit = 25;
      final params = {'limit': limit};

      expect(params['limit'], equals(25));
    });

    test('uses default limit when not specified', () {
      const defaultLimit = 10;
      final limit = null;
      final effectiveLimit = limit ?? defaultLimit;

      expect(effectiveLimit, equals(10));
    });
  });
}
