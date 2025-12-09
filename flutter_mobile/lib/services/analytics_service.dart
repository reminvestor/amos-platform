import 'package:amos_mobile/models/analytics.dart';
import 'package:amos_mobile/services/api_client.dart';
import 'package:amos_mobile/utils/logger.dart';

class AnalyticsService {
  final ApiClient _api = ApiClient();

  /// Fetch the analytics dashboard data
  Future<AnalyticsDashboard> getDashboard() async {
    try {
      final response = await _api.get('/api/v1/analytics/dashboard');
      AppLogger.info('Loaded analytics dashboard');
      return AnalyticsDashboard.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to load analytics dashboard', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Fetch campaign analytics
  Future<List<Map<String, dynamic>>> getCampaignAnalytics({int limit = 10}) async {
    try {
      final response = await _api.get('/api/v1/analytics/campaigns', queryParameters: {
        'limit': limit,
      });
      final data = response['data'] as List? ?? [];
      AppLogger.info('Loaded ${data.length} campaign analytics');
      return data.cast<Map<String, dynamic>>();
    } catch (e, stackTrace) {
      AppLogger.error('Failed to load campaign analytics', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Fetch landing page analytics
  Future<List<Map<String, dynamic>>> getLandingPageAnalytics({int limit = 10}) async {
    try {
      final response = await _api.get('/api/v1/analytics/landing_pages', queryParameters: {
        'limit': limit,
      });
      final data = response['data'] as List? ?? [];
      AppLogger.info('Loaded ${data.length} landing page analytics');
      return data.cast<Map<String, dynamic>>();
    } catch (e, stackTrace) {
      AppLogger.error('Failed to load landing page analytics', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }
}
