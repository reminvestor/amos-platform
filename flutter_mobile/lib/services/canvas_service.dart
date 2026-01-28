import 'package:amos_mobile/services/api_client.dart';
import 'package:amos_mobile/utils/logger.dart';

/// Service for loading canvas content from the server.
/// Handles fetching rendered HTML for WebView-based canvases.
class CanvasService {
  final ApiClient _api = ApiClient();

  /// Fetch rendered canvas HTML from the server
  /// Returns the HTML content for WebView rendering
  Future<CanvasContent> loadCanvas({
    required String canvasType,
    Map<String, dynamic>? canvasData,
  }) async {
    try {
      AppLogger.info('Loading canvas: $canvasType');

      final response = await _api.post(
        '/scout/load_canvas',
        data: {
          'canvas_type': canvasType,
          'canvas_data': canvasData ?? {},
        },
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final canvas = response.data['canvas'];
        return CanvasContent(
          type: canvas['type'] ?? canvasType,
          title: canvas['title'] ?? 'Canvas',
          html: canvas['content'] ?? '',
          data: canvas['data'] ?? {},
        );
      } else {
        throw Exception(response.data['error'] ?? 'Failed to load canvas');
      }
    } catch (e, stackTrace) {
      AppLogger.error('Failed to load canvas: $canvasType', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Fetch data for a specific resource (for native Flutter rendering)
  Future<Map<String, dynamic>> fetchResourceData({
    required String resourceType,
    required String resourceId,
  }) async {
    try {
      final endpoint = _getResourceEndpoint(resourceType, resourceId);
      final response = await _api.get(endpoint);

      if (response.statusCode == 200) {
        return response.data is Map<String, dynamic>
            ? response.data
            : {'data': response.data};
      } else {
        throw Exception('Failed to fetch $resourceType: $resourceId');
      }
    } catch (e, stackTrace) {
      AppLogger.error('Failed to fetch resource: $resourceType/$resourceId', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Fetch a list of resources (for list canvases)
  Future<List<Map<String, dynamic>>> fetchResourceList({
    required String resourceType,
    Map<String, dynamic>? filters,
    int? page,
    int? perPage,
  }) async {
    try {
      final endpoint = _getResourceListEndpoint(resourceType);
      final queryParams = <String, dynamic>{
        if (page != null) 'page': page,
        if (perPage != null) 'per_page': perPage,
        ...?filters,
      };

      final response = await _api.get(endpoint, queryParameters: queryParams);

      if (response.statusCode == 200) {
        final data = response.data;
        if (data is List) {
          return data.cast<Map<String, dynamic>>();
        } else if (data is Map && data['data'] is List) {
          return (data['data'] as List).cast<Map<String, dynamic>>();
        } else if (data is Map && data[resourceType] is List) {
          return (data[resourceType] as List).cast<Map<String, dynamic>>();
        }
        return [];
      } else {
        throw Exception('Failed to fetch $resourceType list');
      }
    } catch (e, stackTrace) {
      AppLogger.error('Failed to fetch resource list: $resourceType', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  String _getResourceEndpoint(String resourceType, String resourceId) {
    switch (resourceType) {
      case 'landing_page':
        return '/api/v1/landing_pages/$resourceId';
      case 'campaign':
        return '/api/v1/campaigns/$resourceId';
      case 'contact':
        return '/api/v1/contacts/$resourceId';
      case 'task':
        return '/api/v1/tasks/$resourceId';
      default:
        return '/api/v1/$resourceType/$resourceId';
    }
  }

  String _getResourceListEndpoint(String resourceType) {
    switch (resourceType) {
      case 'landing_pages':
        return '/api/v1/landing_pages';
      case 'campaigns':
        return '/api/v1/campaigns';
      case 'contacts':
        return '/api/v1/contacts';
      case 'tasks':
        return '/api/v1/tasks';
      default:
        return '/api/v1/$resourceType';
    }
  }
}

/// Represents rendered canvas content from the server
class CanvasContent {
  final String type;
  final String title;
  final String html;
  final Map<String, dynamic> data;

  const CanvasContent({
    required this.type,
    required this.title,
    required this.html,
    this.data = const {},
  });
}
