import 'package:amos_mobile/models/scheduled_task.dart';
import 'package:amos_mobile/services/api_client.dart';
import 'package:amos_mobile/utils/logger.dart';

class ScheduledTasksService {
  final ApiClient _apiClient = ApiClient.instance;

  /// Get list of scheduled tasks with optional filtering
  Future<ScheduledTasksResponse> getScheduledTasks({
    String? status, // 'active', 'paused', 'completed', 'failed', 'archived'
    String? taskType,
    int page = 1,
    int perPage = 20,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'page': page,
        'per_page': perPage,
      };

      if (status != null) queryParams['status'] = status;
      if (taskType != null) queryParams['task_type'] = taskType;

      final response = await _apiClient.get(
        '/api/v1/scheduled_tasks',
        queryParameters: queryParams,
      );

      final List<dynamic> data = response['data'] ?? [];
      final tasks = data.map((json) => ScheduledTask.fromJson(json)).toList();

      final pagination = response['pagination'] ?? {};
      final counts = response['counts'] ?? {};

      return ScheduledTasksResponse(
        tasks: tasks,
        currentPage: _toInt(pagination['current_page'], 1),
        totalPages: _toInt(pagination['total_pages'], 1),
        totalCount: _toInt(pagination['total_count'], 0),
        perPage: _toInt(pagination['per_page'], perPage),
        counts: ScheduledTaskCounts.fromJson(counts),
      );
    } catch (e, stackTrace) {
      AppLogger.error('Failed to fetch scheduled tasks', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Get a single scheduled task by ID
  Future<ScheduledTask> getScheduledTask(int id) async {
    try {
      final response = await _apiClient.get('/api/v1/scheduled_tasks/$id');
      return ScheduledTask.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to fetch scheduled task $id', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Get available task types
  Future<List<TaskType>> getTaskTypes() async {
    try {
      final response = await _apiClient.get('/api/v1/scheduled_tasks/task_types');
      final List<dynamic> data = response['data'] ?? [];
      return data.map((json) => TaskType.fromJson(json)).toList();
    } catch (e, stackTrace) {
      AppLogger.error('Failed to fetch task types', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Create a new scheduled task
  Future<ScheduledTask> createScheduledTask({
    required String name,
    String? description,
    required String taskType,
    required String prompt,
    required String scheduleType,
    String? cronExpression,
    String? runAtTime,
    int? runOnDay,
    String? timezone,
    int? maxRuns,
    DateTime? expiresAt,
  }) async {
    try {
      final data = <String, dynamic>{
        'name': name,
        'task_type': taskType,
        'prompt': prompt,
        'schedule_type': scheduleType,
      };

      if (description != null) data['description'] = description;
      if (cronExpression != null) data['cron_expression'] = cronExpression;
      if (runAtTime != null) data['run_at_time'] = runAtTime;
      if (runOnDay != null) data['run_on_day'] = runOnDay;
      if (timezone != null) data['timezone'] = timezone;
      if (maxRuns != null) data['max_runs'] = maxRuns;
      if (expiresAt != null) data['expires_at'] = expiresAt.toIso8601String();

      final response = await _apiClient.post('/api/v1/scheduled_tasks', data: data);
      return ScheduledTask.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to create scheduled task', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Update an existing scheduled task
  Future<ScheduledTask> updateScheduledTask(int id, Map<String, dynamic> updates) async {
    try {
      final response = await _apiClient.patch('/api/v1/scheduled_tasks/$id', data: updates);
      return ScheduledTask.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to update scheduled task $id', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Delete (archive) a scheduled task
  Future<void> deleteScheduledTask(int id) async {
    try {
      await _apiClient.delete('/api/v1/scheduled_tasks/$id');
    } catch (e, stackTrace) {
      AppLogger.error('Failed to delete scheduled task $id', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Pause a scheduled task
  Future<ScheduledTask> pauseTask(int id) async {
    try {
      final response = await _apiClient.post('/api/v1/scheduled_tasks/$id/pause');
      return ScheduledTask.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to pause scheduled task $id', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Resume a scheduled task
  Future<ScheduledTask> resumeTask(int id) async {
    try {
      final response = await _apiClient.post('/api/v1/scheduled_tasks/$id/resume');
      return ScheduledTask.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to resume scheduled task $id', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Run a task immediately
  Future<void> runNow(int id) async {
    try {
      await _apiClient.post('/api/v1/scheduled_tasks/$id/run_now');
    } catch (e, stackTrace) {
      AppLogger.error('Failed to run scheduled task $id', error: e, stackTrace: stackTrace);
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

class ScheduledTasksResponse {
  final List<ScheduledTask> tasks;
  final int currentPage;
  final int totalPages;
  final int totalCount;
  final int perPage;
  final ScheduledTaskCounts counts;

  ScheduledTasksResponse({
    required this.tasks,
    required this.currentPage,
    required this.totalPages,
    required this.totalCount,
    required this.perPage,
    required this.counts,
  });

  bool get hasMore => currentPage < totalPages;
}
