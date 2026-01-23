import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/task.dart';

void main() {
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

    test('displayName returns human-readable name', () {
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

    test('displayName returns human-readable name', () {
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

  group('Task', () {
    test('fromJson parses complete JSON correctly', () {
      final json = {
        'id': 1,
        'title': 'Test Task',
        'description': 'Task description',
        'status': 'in_progress',
        'priority': 'high',
        'due_date': '2024-01-20T09:00:00.000Z',
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-16T11:00:00.000Z',
        'wizard_data': {'step': 'complete'},
        'artifacts': [
          {'type': 'file', 'name': 'report.pdf'}
        ],
      };

      final task = Task.fromJson(json);

      expect(task.id, equals('1'));
      expect(task.title, equals('Test Task'));
      expect(task.description, equals('Task description'));
      expect(task.status, equals(TaskStatus.inProgress));
      expect(task.priority, equals(TaskPriority.high));
      expect(task.dueDate, equals(DateTime.parse('2024-01-20T09:00:00.000Z')));
      expect(task.createdAt, equals(DateTime.parse('2024-01-15T10:30:00.000Z')));
      expect(task.updatedAt, equals(DateTime.parse('2024-01-16T11:00:00.000Z')));
      expect(task.wizardData, equals({'step': 'complete'}));
      expect(task.artifacts, isNotNull);
      expect(task.artifacts!.length, equals(1));
    });

    test('fromJson handles minimal required fields', () {
      final json = {
        'id': '123',
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-16T11:00:00.000Z',
      };

      final task = Task.fromJson(json);

      expect(task.id, equals('123'));
      expect(task.title, equals('Untitled Task'));
      expect(task.description, isNull);
      expect(task.status, equals(TaskStatus.pending));
      expect(task.priority, equals(TaskPriority.medium));
      expect(task.dueDate, isNull);
      expect(task.wizardData, isNull);
      expect(task.artifacts, isNull);
    });

    test('toJson serializes correctly', () {
      final task = Task(
        id: '123',
        title: 'Test Task',
        description: 'Task description',
        status: TaskStatus.inProgress,
        priority: TaskPriority.high,
        dueDate: DateTime.parse('2024-01-20T09:00:00.000Z'),
        createdAt: DateTime.parse('2024-01-15T10:30:00.000Z'),
        updatedAt: DateTime.parse('2024-01-16T11:00:00.000Z'),
      );

      final json = task.toJson();

      expect(json['id'], equals('123'));
      expect(json['title'], equals('Test Task'));
      expect(json['description'], equals('Task description'));
      expect(json['status'], equals('in_progress'));
      expect(json['priority'], equals('high'));
      expect(json['due_date'], equals('2024-01-20T09:00:00.000Z'));
    });

    test('toJson excludes null optional fields', () {
      final task = Task(
        id: '123',
        title: 'Test Task',
        status: TaskStatus.pending,
        priority: TaskPriority.medium,
        createdAt: DateTime.parse('2024-01-15T10:30:00.000Z'),
        updatedAt: DateTime.parse('2024-01-16T11:00:00.000Z'),
      );

      final json = task.toJson();

      expect(json.containsKey('description'), isFalse);
      expect(json.containsKey('due_date'), isFalse);
    });

    test('copyWith creates new task with updated values', () {
      final original = Task(
        id: '123',
        title: 'Original Title',
        status: TaskStatus.pending,
        priority: TaskPriority.medium,
        createdAt: DateTime.parse('2024-01-15T10:30:00.000Z'),
        updatedAt: DateTime.parse('2024-01-16T11:00:00.000Z'),
      );

      final modified = original.copyWith(
        title: 'Modified Title',
        status: TaskStatus.completed,
        priority: TaskPriority.high,
      );

      expect(modified.id, equals('123'));
      expect(modified.title, equals('Modified Title'));
      expect(modified.status, equals(TaskStatus.completed));
      expect(modified.priority, equals(TaskPriority.high));
      expect(original.title, equals('Original Title'));
      expect(original.status, equals(TaskStatus.pending));
    });

    test('copyWith preserves unmodified values', () {
      final original = Task(
        id: '123',
        title: 'Test Task',
        description: 'Description',
        status: TaskStatus.pending,
        priority: TaskPriority.medium,
        dueDate: DateTime.parse('2024-01-20T09:00:00.000Z'),
        createdAt: DateTime.parse('2024-01-15T10:30:00.000Z'),
        updatedAt: DateTime.parse('2024-01-16T11:00:00.000Z'),
        wizardData: {'key': 'value'},
      );

      final modified = original.copyWith(title: 'New Title');

      expect(modified.title, equals('New Title'));
      expect(modified.description, equals('Description'));
      expect(modified.status, equals(TaskStatus.pending));
      expect(modified.priority, equals(TaskPriority.medium));
      expect(modified.dueDate, equals(original.dueDate));
      expect(modified.wizardData, equals({'key': 'value'}));
    });
  });
}
