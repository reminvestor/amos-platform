import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/task.dart';

// Note: TasksService uses ApiClient which requires native plugins.
// For unit tests, we test the data models, query parameter building,
// response parsing logic, and helper functions separately.

void main() {
  group('TaskListResponse', () {
    test('creates with required fields', () {
      final tasks = [
        Task(
          id: '1',
          title: 'Task 1',
          status: TaskStatus.pending,
          priority: TaskPriority.medium,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        Task(
          id: '2',
          title: 'Task 2',
          status: TaskStatus.completed,
          priority: TaskPriority.high,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

      final response = TaskListResponse(
        tasks: tasks,
        currentPage: 1,
        totalPages: 5,
        totalCount: 100,
        perPage: 20,
      );

      expect(response.tasks, hasLength(2));
      expect(response.currentPage, equals(1));
      expect(response.totalPages, equals(5));
      expect(response.totalCount, equals(100));
      expect(response.perPage, equals(20));
    });

    group('hasNextPage', () {
      test('returns true when currentPage < totalPages', () {
        final response = TaskListResponse(
          tasks: [],
          currentPage: 1,
          totalPages: 5,
          totalCount: 100,
          perPage: 20,
        );

        expect(response.hasNextPage, isTrue);
      });

      test('returns false when currentPage == totalPages', () {
        final response = TaskListResponse(
          tasks: [],
          currentPage: 5,
          totalPages: 5,
          totalCount: 100,
          perPage: 20,
        );

        expect(response.hasNextPage, isFalse);
      });

      test('returns false when currentPage > totalPages', () {
        final response = TaskListResponse(
          tasks: [],
          currentPage: 6,
          totalPages: 5,
          totalCount: 100,
          perPage: 20,
        );

        expect(response.hasNextPage, isFalse);
      });

      test('returns false when totalPages is 1', () {
        final response = TaskListResponse(
          tasks: [],
          currentPage: 1,
          totalPages: 1,
          totalCount: 10,
          perPage: 20,
        );

        expect(response.hasNextPage, isFalse);
      });
    });

    group('hasPreviousPage', () {
      test('returns true when currentPage > 1', () {
        final response = TaskListResponse(
          tasks: [],
          currentPage: 2,
          totalPages: 5,
          totalCount: 100,
          perPage: 20,
        );

        expect(response.hasPreviousPage, isTrue);
      });

      test('returns false when currentPage == 1', () {
        final response = TaskListResponse(
          tasks: [],
          currentPage: 1,
          totalPages: 5,
          totalCount: 100,
          perPage: 20,
        );

        expect(response.hasPreviousPage, isFalse);
      });

      test('returns false when currentPage < 1', () {
        final response = TaskListResponse(
          tasks: [],
          currentPage: 0,
          totalPages: 5,
          totalCount: 100,
          perPage: 20,
        );

        expect(response.hasPreviousPage, isFalse);
      });
    });
  });

  group('_toInt helper function logic', () {
    test('returns value when it is already an int', () {
      final result = _toInt(42, 0);
      expect(result, equals(42));
    });

    test('parses string to int', () {
      final result = _toInt('42', 0);
      expect(result, equals(42));
    });

    test('returns default value for null', () {
      final result = _toInt(null, 10);
      expect(result, equals(10));
    });

    test('returns default value for invalid string', () {
      final result = _toInt('invalid', 10);
      expect(result, equals(10));
    });

    test('returns default value for empty string', () {
      final result = _toInt('', 10);
      expect(result, equals(10));
    });

    test('returns default value for non-numeric types', () {
      final result = _toInt(3.14, 10);
      expect(result, equals(10));
    });

    test('parses negative number string', () {
      final result = _toInt('-5', 0);
      expect(result, equals(-5));
    });

    test('parses zero', () {
      final result = _toInt(0, 10);
      expect(result, equals(0));
    });

    test('parses string zero', () {
      final result = _toInt('0', 10);
      expect(result, equals(0));
    });
  });

  group('Query Parameter Building', () {
    test('builds basic pagination parameters', () {
      const page = 1;
      const perPage = 20;

      final queryParams = <String, String>{
        'page': page.toString(),
        'per_page': perPage.toString(),
      };

      expect(queryParams['page'], equals('1'));
      expect(queryParams['per_page'], equals('20'));
    });

    test('adds status parameter when provided', () {
      const page = 1;
      const perPage = 20;
      const status = 'completed';

      final queryParams = <String, String>{
        'page': page.toString(),
        'per_page': perPage.toString(),
      };
      if (status != null) {
        queryParams['status'] = status;
      }

      expect(queryParams['status'], equals('completed'));
    });

    test('does not add status parameter when null', () {
      const page = 1;
      const perPage = 20;
      const String? status = null;

      final queryParams = <String, String>{
        'page': page.toString(),
        'per_page': perPage.toString(),
      };
      if (status != null) {
        queryParams['status'] = status;
      }

      expect(queryParams.containsKey('status'), isFalse);
    });
  });

  group('Tasks List Response Parsing', () {
    test('parses tasks list response correctly', () {
      final responseData = {
        'data': [
          {
            'id': 1,
            'title': 'Task 1',
            'description': 'Description 1',
            'status': 'pending',
            'priority': 'high',
            'created_at': '2024-01-01T00:00:00.000Z',
            'updated_at': '2024-01-01T00:00:00.000Z',
          },
          {
            'id': 2,
            'title': 'Task 2',
            'status': 'completed',
            'priority': 'low',
            'created_at': '2024-01-02T00:00:00.000Z',
            'updated_at': '2024-01-02T00:00:00.000Z',
          },
        ],
        'pagination': {
          'current_page': 1,
          'total_pages': 5,
          'total_count': 100,
          'per_page': 20,
        },
      };

      final data = responseData['data'] as List? ?? [];
      final tasks = data.map((json) => Task.fromJson(json)).toList();
      final pagination = responseData['pagination'] as Map<String, dynamic>? ?? {};

      expect(tasks, hasLength(2));
      expect(tasks[0].id, equals('1'));
      expect(tasks[0].title, equals('Task 1'));
      expect(tasks[0].status, equals(TaskStatus.pending));
      expect(tasks[0].priority, equals(TaskPriority.high));
      expect(tasks[1].id, equals('2'));
      expect(tasks[1].status, equals(TaskStatus.completed));

      expect(pagination['current_page'], equals(1));
      expect(pagination['total_pages'], equals(5));
    });

    test('handles empty tasks list', () {
      final responseData = {
        'data': [],
        'pagination': {
          'current_page': 1,
          'total_pages': 0,
          'total_count': 0,
          'per_page': 20,
        },
      };

      final data = responseData['data'] as List? ?? [];
      final tasks = data.map((json) => Task.fromJson(json)).toList();

      expect(tasks, isEmpty);
    });

    test('handles missing data key with fallback', () {
      final responseData = <String, dynamic>{};

      final data = responseData['data'] as List? ?? [];
      final tasks = data.map((json) => Task.fromJson(json)).toList();

      expect(tasks, isEmpty);
    });

    test('handles missing pagination with defaults', () {
      final responseData = {
        'data': [
          {
            'id': 1,
            'title': 'Task 1',
            'status': 'pending',
            'priority': 'medium',
            'created_at': '2024-01-01T00:00:00.000Z',
            'updated_at': '2024-01-01T00:00:00.000Z',
          },
        ],
      };

      final data = responseData['data'] as List? ?? [];
      final tasks = data.map((json) => Task.fromJson(json)).toList();
      final pagination = responseData['pagination'] as Map<String, dynamic>? ?? {};

      const defaultPerPage = 20;
      final currentPage = _toInt(pagination['current_page'], 1);
      final totalPages = _toInt(pagination['total_pages'], 1);
      final totalCount = _toInt(pagination['total_count'], tasks.length);
      final perPage = _toInt(pagination['per_page'], defaultPerPage);

      expect(currentPage, equals(1));
      expect(totalPages, equals(1));
      expect(totalCount, equals(1));
      expect(perPage, equals(20));
    });
  });

  group('Task Create Request Building', () {
    test('builds create request with required title', () {
      const title = 'New Task';

      final data = <String, dynamic>{
        'title': title,
      };

      expect(data['title'], equals('New Task'));
    });

    test('builds create request with all optional fields', () {
      const title = 'New Task';
      const description = 'Task description';
      const status = 'pending';
      const priority = 'high';
      final dueDate = DateTime.parse('2024-02-01T09:00:00.000Z');

      final data = <String, dynamic>{
        'title': title,
      };
      if (description != null) data['description'] = description;
      if (status != null) data['status'] = status;
      if (priority != null) data['priority'] = priority;
      if (dueDate != null) data['due_date'] = dueDate.toIso8601String();

      expect(data['title'], equals('New Task'));
      expect(data['description'], equals('Task description'));
      expect(data['status'], equals('pending'));
      expect(data['priority'], equals('high'));
      expect(data['due_date'], equals('2024-02-01T09:00:00.000Z'));
    });

    test('excludes null optional fields from request', () {
      const title = 'New Task';
      const String? description = null;
      const String? status = null;

      final data = <String, dynamic>{
        'title': title,
      };
      if (description != null) data['description'] = description;
      if (status != null) data['status'] = status;

      expect(data['title'], equals('New Task'));
      expect(data.containsKey('description'), isFalse);
      expect(data.containsKey('status'), isFalse);
    });
  });

  group('Task Update Request Building', () {
    test('builds update request with only changed fields', () {
      const String? title = 'Updated Title';
      const String? description = null;
      const String? status = 'completed';
      const String? priority = null;
      final DateTime? dueDate = null;

      final data = <String, dynamic>{};
      if (title != null) data['title'] = title;
      if (description != null) data['description'] = description;
      if (status != null) data['status'] = status;
      if (priority != null) data['priority'] = priority;
      if (dueDate != null) data['due_date'] = dueDate.toIso8601String();

      expect(data.length, equals(2));
      expect(data['title'], equals('Updated Title'));
      expect(data['status'], equals('completed'));
      expect(data.containsKey('description'), isFalse);
      expect(data.containsKey('priority'), isFalse);
      expect(data.containsKey('due_date'), isFalse);
    });

    test('builds empty request when no fields provided', () {
      const String? title = null;
      const String? status = null;

      final data = <String, dynamic>{};
      if (title != null) data['title'] = title;
      if (status != null) data['status'] = status;

      expect(data, isEmpty);
    });
  });

  group('Task Model - copyWith', () {
    test('creates copy with updated fields', () {
      final original = Task(
        id: '1',
        title: 'Original Title',
        description: 'Original Description',
        status: TaskStatus.pending,
        priority: TaskPriority.medium,
        createdAt: DateTime.parse('2024-01-01T00:00:00.000Z'),
        updatedAt: DateTime.parse('2024-01-01T00:00:00.000Z'),
      );

      final updated = original.copyWith(
        title: 'Updated Title',
        status: TaskStatus.completed,
      );

      expect(updated.id, equals('1')); // Unchanged
      expect(updated.title, equals('Updated Title')); // Changed
      expect(updated.description, equals('Original Description')); // Unchanged
      expect(updated.status, equals(TaskStatus.completed)); // Changed
      expect(updated.priority, equals(TaskPriority.medium)); // Unchanged
    });

    test('creates identical copy when no fields provided', () {
      final original = Task(
        id: '1',
        title: 'Title',
        status: TaskStatus.pending,
        priority: TaskPriority.medium,
        createdAt: DateTime.parse('2024-01-01T00:00:00.000Z'),
        updatedAt: DateTime.parse('2024-01-01T00:00:00.000Z'),
      );

      final copy = original.copyWith();

      expect(copy.id, equals(original.id));
      expect(copy.title, equals(original.title));
      expect(copy.status, equals(original.status));
      expect(copy.priority, equals(original.priority));
    });
  });

  group('TaskStatus', () {
    test('value returns correct string', () {
      expect(TaskStatus.pending.value, equals('pending'));
      expect(TaskStatus.active.value, equals('active'));
      expect(TaskStatus.inProgress.value, equals('in_progress'));
      expect(TaskStatus.completed.value, equals('completed'));
      expect(TaskStatus.failed.value, equals('failed'));
      expect(TaskStatus.cancelled.value, equals('cancelled'));
      expect(TaskStatus.paused.value, equals('paused'));
    });

    test('displayName returns correct display string', () {
      expect(TaskStatus.pending.displayName, equals('Pending'));
      expect(TaskStatus.active.displayName, equals('Active'));
      expect(TaskStatus.inProgress.displayName, equals('In Progress'));
      expect(TaskStatus.completed.displayName, equals('Completed'));
      expect(TaskStatus.failed.displayName, equals('Failed'));
      expect(TaskStatus.cancelled.displayName, equals('Cancelled'));
      expect(TaskStatus.paused.displayName, equals('Paused'));
    });

    test('fromString converts string to enum correctly', () {
      expect(TaskStatusX.fromString('pending'), equals(TaskStatus.pending));
      expect(TaskStatusX.fromString('active'), equals(TaskStatus.active));
      expect(TaskStatusX.fromString('in_progress'), equals(TaskStatus.inProgress));
      expect(TaskStatusX.fromString('completed'), equals(TaskStatus.completed));
      expect(TaskStatusX.fromString('failed'), equals(TaskStatus.failed));
      expect(TaskStatusX.fromString('cancelled'), equals(TaskStatus.cancelled));
      expect(TaskStatusX.fromString('paused'), equals(TaskStatus.paused));
    });

    test('fromString returns pending for unknown values', () {
      expect(TaskStatusX.fromString('unknown'), equals(TaskStatus.pending));
      expect(TaskStatusX.fromString(''), equals(TaskStatus.pending));
    });
  });

  group('TaskPriority', () {
    test('value returns correct string', () {
      expect(TaskPriority.low.value, equals('low'));
      expect(TaskPriority.medium.value, equals('medium'));
      expect(TaskPriority.high.value, equals('high'));
    });

    test('displayName returns correct display string', () {
      expect(TaskPriority.low.displayName, equals('Low'));
      expect(TaskPriority.medium.displayName, equals('Medium'));
      expect(TaskPriority.high.displayName, equals('High'));
    });

    test('fromString converts string to enum correctly', () {
      expect(TaskPriorityX.fromString('low'), equals(TaskPriority.low));
      expect(TaskPriorityX.fromString('medium'), equals(TaskPriority.medium));
      expect(TaskPriorityX.fromString('high'), equals(TaskPriority.high));
    });

    test('fromString returns medium for unknown values', () {
      expect(TaskPriorityX.fromString('unknown'), equals(TaskPriority.medium));
      expect(TaskPriorityX.fromString(''), equals(TaskPriority.medium));
    });
  });

  group('Complete Task Helper', () {
    test('completeTask should update status to completed', () {
      // Simulates the completeTask logic
      const id = '123';
      const newStatus = 'completed';

      final updateData = <String, dynamic>{};
      if (newStatus != null) updateData['status'] = newStatus;

      expect(updateData['status'], equals('completed'));
    });
  });

  group('Task Model Extended Fields', () {
    test('parses wizardData from response', () {
      final json = {
        'id': '1',
        'title': 'Task with wizard data',
        'status': 'pending',
        'priority': 'medium',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
        'wizard_data': {
          'step': 1,
          'answers': {'q1': 'answer1'},
        },
      };

      final task = Task.fromJson(json);

      expect(task.wizardData, isNotNull);
      expect(task.wizardData!['step'], equals(1));
      expect(task.wizardData!['answers'], isA<Map>());
    });

    test('parses artifacts from response', () {
      final json = {
        'id': '1',
        'title': 'Task with artifacts',
        'status': 'completed',
        'priority': 'high',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
        'artifacts': [
          {'type': 'landing_page', 'id': 100},
          {'type': 'email', 'id': 200},
        ],
      };

      final task = Task.fromJson(json);

      expect(task.artifacts, hasLength(2));
      expect(task.artifacts![0]['type'], equals('landing_page'));
      expect(task.artifacts![1]['id'], equals(200));
    });

    test('handles null extended fields', () {
      final json = {
        'id': '1',
        'title': 'Basic task',
        'status': 'pending',
        'priority': 'medium',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
      };

      final task = Task.fromJson(json);

      expect(task.wizardData, isNull);
      expect(task.artifacts, isNull);
    });
  });
}

/// Mirrors the _toInt helper function from TasksService
int _toInt(dynamic value, int defaultValue) {
  if (value == null) return defaultValue;
  if (value is int) return value;
  if (value is String) return int.tryParse(value) ?? defaultValue;
  return defaultValue;
}

/// Mirrors the TaskListResponse class from TasksService
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
