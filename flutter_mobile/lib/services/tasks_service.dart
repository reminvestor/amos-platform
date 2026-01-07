import 'package:amos_mobile/models/task.dart';
import 'package:amos_mobile/services/api_client.dart';
import 'package:amos_mobile/utils/logger.dart';

class TasksService {
  final ApiClient _api = ApiClient();

  /// Get list of tasks with optional status filter and pagination
  Future<TaskListResponse> getTasks({
    String? status,
    int page = 1,
    int perPage = 20,
  }) async {
    AppLogger.info('TasksService: Fetching tasks (page: $page, status: $status)');

    final queryParams = <String, String>{
      'page': page.toString(),
      'per_page': perPage.toString(),
    };
    if (status != null) {
      queryParams['status'] = status;
    }

    final response = await _api.get(
      '/api/v1/tasks',
      queryParameters: queryParams,
    );

    final List<dynamic> data = response['data'] ?? [];
    final tasks = data.map((json) => Task.fromJson(json)).toList();

    final pagination = response['pagination'] ?? {};

    AppLogger.info('TasksService: Loaded ${tasks.length} tasks');

    return TaskListResponse(
      tasks: tasks,
      currentPage: _toInt(pagination['current_page'], 1),
      totalPages: _toInt(pagination['total_pages'], 1),
      totalCount: _toInt(pagination['total_count'], tasks.length),
      perPage: _toInt(pagination['per_page'], perPage),
    );
  }

  /// Get a single task by ID
  Future<Task> getTask(String id) async {
    AppLogger.info('TasksService: Fetching task $id');

    final response = await _api.get('/api/v1/tasks/$id');
    return Task.fromJson(response);
  }

  /// Create a new task
  Future<Task> createTask({
    required String title,
    String? description,
    String? status,
    String? priority,
    DateTime? dueDate,
  }) async {
    AppLogger.info('TasksService: Creating task "$title"');

    final data = <String, dynamic>{
      'title': title,
    };
    if (description != null) data['description'] = description;
    if (status != null) data['status'] = status;
    if (priority != null) data['priority'] = priority;
    if (dueDate != null) data['due_date'] = dueDate.toIso8601String();

    final response = await _api.post('/api/v1/tasks', data: data);
    return Task.fromJson(response);
  }

  /// Update an existing task
  Future<Task> updateTask(
    String id, {
    String? title,
    String? description,
    String? status,
    String? priority,
    DateTime? dueDate,
  }) async {
    AppLogger.info('TasksService: Updating task $id');

    final data = <String, dynamic>{};
    if (title != null) data['title'] = title;
    if (description != null) data['description'] = description;
    if (status != null) data['status'] = status;
    if (priority != null) data['priority'] = priority;
    if (dueDate != null) data['due_date'] = dueDate.toIso8601String();

    final response = await _api.patch('/api/v1/tasks/$id', data: data);
    return Task.fromJson(response);
  }

  /// Delete a task
  Future<void> deleteTask(String id) async {
    AppLogger.info('TasksService: Deleting task $id');
    await _api.delete('/api/v1/tasks/$id');
  }

  /// Mark a task as complete
  Future<Task> completeTask(String id) async {
    return updateTask(id, status: 'completed');
  }

  /// Safely convert a dynamic value to int
  int _toInt(dynamic value, int defaultValue) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? defaultValue;
    return defaultValue;
  }
}

class TaskListResponse {
  final List<Task> tasks;
  final int currentPage;
  final int totalPages;
  final int totalCount;
  final int perPage;

  TaskListResponse({
    required this.tasks,
    required this.currentPage,
    required this.totalPages,
    required this.totalCount,
    required this.perPage,
  });

  bool get hasNextPage => currentPage < totalPages;
  bool get hasPreviousPage => currentPage > 1;
}
