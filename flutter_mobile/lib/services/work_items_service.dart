import 'package:amos_mobile/models/work_item.dart';
import 'package:amos_mobile/services/api_client.dart';
import 'package:amos_mobile/utils/logger.dart';

class WorkItemsService {
  final ApiClient _apiClient = ApiClient.instance;

  /// Get list of work items (inbox) with optional filtering
  Future<WorkItemsResponse> getWorkItems({
    String? filter, // 'unread', 'starred', 'action_required', 'archived'
    String? workType,
    String? priority,
    int page = 1,
    int perPage = 20,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'page': page,
        'per_page': perPage,
      };

      if (filter != null) queryParams['filter'] = filter;
      if (workType != null) queryParams['work_type'] = workType;
      if (priority != null) queryParams['priority'] = priority;

      final response = await _apiClient.get(
        '/api/v1/work_items',
        queryParameters: queryParams,
      );

      final List<dynamic> data = response['data'] ?? [];
      final workItems = data.map((json) => WorkItem.fromJson(json)).toList();

      final pagination = response['pagination'] ?? {};
      final counts = response['counts'] ?? {};

      return WorkItemsResponse(
        workItems: workItems,
        currentPage: _toInt(pagination['current_page'], 1),
        totalPages: _toInt(pagination['total_pages'], 1),
        totalCount: _toInt(pagination['total_count'], 0),
        perPage: _toInt(pagination['per_page'], perPage),
        counts: WorkItemCounts.fromJson(counts),
      );
    } catch (e, stackTrace) {
      AppLogger.error('Failed to fetch work items', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Get a single work item by ID
  Future<WorkItem> getWorkItem(int id) async {
    try {
      final response = await _apiClient.get('/api/v1/work_items/$id');
      return WorkItem.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to fetch work item $id', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Mark a work item as read
  Future<WorkItem> markAsRead(int id) async {
    try {
      final response = await _apiClient.post('/api/v1/work_items/$id/mark_read');
      return WorkItem.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to mark work item $id as read', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Mark all work items as read
  Future<void> markAllAsRead() async {
    try {
      await _apiClient.post('/api/v1/work_items/mark_all_read');
    } catch (e, stackTrace) {
      AppLogger.error('Failed to mark all work items as read', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Toggle starred status of a work item
  Future<WorkItem> toggleStarred(int id) async {
    try {
      final response = await _apiClient.post('/api/v1/work_items/$id/toggle_starred');
      return WorkItem.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to toggle starred for work item $id', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Archive a work item
  Future<WorkItem> archive(int id) async {
    try {
      final response = await _apiClient.post('/api/v1/work_items/$id/archive');
      return WorkItem.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to archive work item $id', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Unarchive a work item
  Future<WorkItem> unarchive(int id) async {
    try {
      final response = await _apiClient.post('/api/v1/work_items/$id/unarchive');
      return WorkItem.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to unarchive work item $id', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Helper to safely convert dynamic to int
  int _toInt(dynamic value, int defaultValue) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? defaultValue;
    return defaultValue;
  }
}

class WorkItemsResponse {
  final List<WorkItem> workItems;
  final int currentPage;
  final int totalPages;
  final int totalCount;
  final int perPage;
  final WorkItemCounts counts;

  WorkItemsResponse({
    required this.workItems,
    required this.currentPage,
    required this.totalPages,
    required this.totalCount,
    required this.perPage,
    required this.counts,
  });

  bool get hasMore => currentPage < totalPages;
}
