import 'package:amos_mobile/models/landing_page.dart';
import 'package:amos_mobile/services/api_client.dart';
import 'package:amos_mobile/utils/logger.dart';

class LandingPagesService {
  final ApiClient _api = ApiClient();

  /// Fetch all landing pages with optional filtering
  Future<List<LandingPage>> getLandingPages({
    String? search,
    String? status,
    int page = 1,
    int perPage = 20,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'page': page,
        'per_page': perPage,
      };
      if (search != null && search.isNotEmpty) {
        queryParams['search'] = search;
      }
      if (status != null && status.isNotEmpty) {
        queryParams['status'] = status;
      }

      final response = await _api.get('/api/v1/landing_pages', queryParameters: queryParams);
      final pagesList = response['data'] as List? ?? [];
      AppLogger.info('Loaded ${pagesList.length} landing pages');
      return pagesList.map((json) => LandingPage.fromJson(json)).toList();
    } catch (e, stackTrace) {
      AppLogger.error('Failed to load landing pages', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Fetch single landing page details
  Future<LandingPage> getLandingPage(String id) async {
    try {
      final response = await _api.get('/api/v1/landing_pages/$id');
      return LandingPage.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to load landing page $id', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Create a new landing page
  Future<LandingPage> createLandingPage({
    required String title,
    required String slug,
    String? content,
    String status = 'draft',
    String? metaTitle,
    String? metaDescription,
  }) async {
    try {
      final response = await _api.post('/api/v1/landing_pages', data: {
        'title': title,
        'slug': slug,
        if (content != null) 'content': content,
        'status': status,
        if (metaTitle != null) 'meta_title': metaTitle,
        if (metaDescription != null) 'meta_description': metaDescription,
      });
      return LandingPage.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to create landing page', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Update a landing page
  Future<LandingPage> updateLandingPage(String id, Map<String, dynamic> data) async {
    try {
      final response = await _api.patch('/api/v1/landing_pages/$id', data: data);
      return LandingPage.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to update landing page $id', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Delete a landing page
  Future<void> deleteLandingPage(String id) async {
    try {
      await _api.delete('/api/v1/landing_pages/$id');
    } catch (e, stackTrace) {
      AppLogger.error('Failed to delete landing page $id', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Publish a landing page
  Future<LandingPage> publishLandingPage(String id) async {
    try {
      final response = await _api.post('/api/v1/landing_pages/$id/publish');
      return LandingPage.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to publish landing page $id', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Unpublish a landing page
  Future<LandingPage> unpublishLandingPage(String id) async {
    try {
      final response = await _api.post('/api/v1/landing_pages/$id/unpublish');
      return LandingPage.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to unpublish landing page $id', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }
}
