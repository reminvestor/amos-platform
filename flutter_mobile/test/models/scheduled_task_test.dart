import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/scheduled_task.dart';

void main() {
  group('TaskTypeInfo', () {
    test('fromJson parses correctly', () {
      final json = {
        'name': 'Daily Report',
        'description': 'Generate daily analytics report',
        'icon': '📊',
      };

      final info = TaskTypeInfo.fromJson(json);

      expect(info.name, equals('Daily Report'));
      expect(info.description, equals('Generate daily analytics report'));
      expect(info.icon, equals('📊'));
    });

    test('fromJson handles missing values with defaults', () {
      final json = <String, dynamic>{};

      final info = TaskTypeInfo.fromJson(json);

      expect(info.name, equals('Custom Task'));
      expect(info.description, equals(''));
      expect(info.icon, equals(''));
    });
  });

  group('TaskType', () {
    test('fromJson parses correctly', () {
      final json = {
        'id': 'daily_report',
        'name': 'Daily Report',
        'description': 'Generate daily analytics report',
        'icon': '📊',
      };

      final taskType = TaskType.fromJson(json);

      expect(taskType.id, equals('daily_report'));
      expect(taskType.name, equals('Daily Report'));
      expect(taskType.description, equals('Generate daily analytics report'));
      expect(taskType.icon, equals('📊'));
    });

    test('fromJson handles missing optional values', () {
      final json = {
        'id': 'custom',
        'name': 'Custom',
      };

      final taskType = TaskType.fromJson(json);

      expect(taskType.description, equals(''));
      expect(taskType.icon, equals(''));
    });
  });

  group('ScheduledTask', () {
    test('fromJson parses complete JSON correctly', () {
      final json = {
        'id': 1,
        'name': 'Daily Analytics Report',
        'description': 'Generate and send daily analytics',
        'task_type': 'daily_report',
        'task_type_info': {
          'name': 'Daily Report',
          'description': 'Analytics report',
          'icon': '📊',
        },
        'schedule_type': 'daily',
        'status': 'active',
        'enabled': true,
        'next_run_at': '2024-01-16T09:00:00.000Z',
        'last_run_at': '2024-01-15T09:00:00.000Z',
        'run_count': 10,
        'failure_count': 1,
        'consecutive_failures': 0,
        'can_run': true,
        'prompt': 'Generate report',
        'cron_expression': '0 9 * * *',
        'run_at_time': '09:00',
        'run_on_day': 1,
        'timezone': 'America/New_York',
        'max_runs': 100,
        'expires_at': '2024-12-31T23:59:59.000Z',
        'input_context': {'format': 'pdf'},
        'output_config': {'email': true},
        'execution_mode': 'async',
        'agent_name': 'Analytics Agent',
        'created_at': '2024-01-01T10:30:00.000Z',
        'updated_at': '2024-01-15T11:00:00.000Z',
      };

      final task = ScheduledTask.fromJson(json);

      expect(task.id, equals(1));
      expect(task.name, equals('Daily Analytics Report'));
      expect(task.description, equals('Generate and send daily analytics'));
      expect(task.taskType, equals('daily_report'));
      expect(task.taskTypeInfo.name, equals('Daily Report'));
      expect(task.scheduleType, equals('daily'));
      expect(task.status, equals('active'));
      expect(task.enabled, isTrue);
      expect(task.nextRunAt, equals(DateTime.parse('2024-01-16T09:00:00.000Z')));
      expect(task.lastRunAt, equals(DateTime.parse('2024-01-15T09:00:00.000Z')));
      expect(task.runCount, equals(10));
      expect(task.failureCount, equals(1));
      expect(task.consecutiveFailures, equals(0));
      expect(task.canRun, isTrue);
      expect(task.cronExpression, equals('0 9 * * *'));
      expect(task.agentName, equals('Analytics Agent'));
    });

    test('fromJson handles minimal required fields with defaults', () {
      final json = {
        'id': 1,
        'created_at': '2024-01-01T10:30:00.000Z',
        'updated_at': '2024-01-15T11:00:00.000Z',
      };

      final task = ScheduledTask.fromJson(json);

      expect(task.id, equals(1));
      expect(task.name, equals('Untitled Task'));
      expect(task.taskType, equals('custom'));
      expect(task.scheduleType, equals('daily'));
      expect(task.status, equals('active'));
      expect(task.enabled, isTrue);
      expect(task.runCount, equals(0));
      expect(task.failureCount, equals(0));
      expect(task.consecutiveFailures, equals(0));
      expect(task.canRun, isFalse);
    });

    test('toJson serializes correctly', () {
      final task = ScheduledTask(
        id: 1,
        name: 'Test Task',
        taskType: 'custom',
        taskTypeInfo: TaskTypeInfo(
          name: 'Custom',
          description: 'Custom task',
          icon: '✅',
        ),
        scheduleType: 'weekly',
        status: 'active',
        enabled: true,
        runCount: 5,
        failureCount: 0,
        consecutiveFailures: 0,
        canRun: true,
        createdAt: DateTime.parse('2024-01-01T10:30:00.000Z'),
        updatedAt: DateTime.parse('2024-01-15T11:00:00.000Z'),
      );

      final json = task.toJson();

      expect(json['id'], equals(1));
      expect(json['name'], equals('Test Task'));
      expect(json['task_type'], equals('custom'));
      expect(json['schedule_type'], equals('weekly'));
      expect(json['status'], equals('active'));
      expect(json['enabled'], isTrue);
      expect(json['run_count'], equals(5));
    });

    test('copyWith creates new task with updated values', () {
      final original = ScheduledTask(
        id: 1,
        name: 'Original',
        taskType: 'custom',
        taskTypeInfo: TaskTypeInfo(name: 'Custom', description: '', icon: ''),
        scheduleType: 'daily',
        status: 'active',
        enabled: true,
        runCount: 0,
        failureCount: 0,
        consecutiveFailures: 0,
        canRun: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final modified = original.copyWith(
        name: 'Modified',
        status: 'paused',
        enabled: false,
      );

      expect(modified.id, equals(1));
      expect(modified.name, equals('Modified'));
      expect(modified.status, equals('paused'));
      expect(modified.enabled, isFalse);
      expect(original.name, equals('Original'));
      expect(original.status, equals('active'));
    });

    test('scheduleLabel returns correct labels for all types', () {
      final testCases = {
        'once': 'One Time',
        'daily': 'Daily',
        'weekly': 'Weekly',
        'monthly': 'Monthly',
        'cron': 'Custom Schedule',
        'unknown': 'unknown',
      };

      for (final entry in testCases.entries) {
        final task = ScheduledTask(
          id: 1,
          name: 'Test',
          taskType: 'custom',
          taskTypeInfo: TaskTypeInfo(name: 'Custom', description: '', icon: ''),
          scheduleType: entry.key,
          status: 'active',
          enabled: true,
          runCount: 0,
          failureCount: 0,
          consecutiveFailures: 0,
          canRun: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        expect(task.scheduleLabel, equals(entry.value),
            reason: 'Expected ${entry.key} to have label ${entry.value}');
      }
    });

    test('statusLabel returns correct labels for all statuses', () {
      final testCases = {
        'active': 'Active',
        'paused': 'Paused',
        'completed': 'Completed',
        'failed': 'Failed',
        'archived': 'Archived',
        'unknown': 'unknown',
      };

      for (final entry in testCases.entries) {
        final task = ScheduledTask(
          id: 1,
          name: 'Test',
          taskType: 'custom',
          taskTypeInfo: TaskTypeInfo(name: 'Custom', description: '', icon: ''),
          scheduleType: 'daily',
          status: entry.key,
          enabled: true,
          runCount: 0,
          failureCount: 0,
          consecutiveFailures: 0,
          canRun: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        expect(task.statusLabel, equals(entry.value),
            reason: 'Expected ${entry.key} to have label ${entry.value}');
      }
    });

    test('hasFailures returns true when consecutiveFailures > 0', () {
      final task = ScheduledTask(
        id: 1,
        name: 'Test',
        taskType: 'custom',
        taskTypeInfo: TaskTypeInfo(name: 'Custom', description: '', icon: ''),
        scheduleType: 'daily',
        status: 'active',
        enabled: true,
        runCount: 5,
        failureCount: 2,
        consecutiveFailures: 1,
        canRun: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(task.hasFailures, isTrue);
    });

    test('hasFailures returns false when consecutiveFailures is 0', () {
      final task = ScheduledTask(
        id: 1,
        name: 'Test',
        taskType: 'custom',
        taskTypeInfo: TaskTypeInfo(name: 'Custom', description: '', icon: ''),
        scheduleType: 'daily',
        status: 'active',
        enabled: true,
        runCount: 5,
        failureCount: 2,
        consecutiveFailures: 0,
        canRun: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(task.hasFailures, isFalse);
    });
  });

  group('ScheduledTaskCounts', () {
    test('fromJson parses correctly', () {
      final json = {
        'active': 10,
        'paused': 3,
        'completed': 25,
        'failed': 2,
        'total': 40,
      };

      final counts = ScheduledTaskCounts.fromJson(json);

      expect(counts.active, equals(10));
      expect(counts.paused, equals(3));
      expect(counts.completed, equals(25));
      expect(counts.failed, equals(2));
      expect(counts.total, equals(40));
    });

    test('fromJson handles missing values with defaults', () {
      final json = <String, dynamic>{};

      final counts = ScheduledTaskCounts.fromJson(json);

      expect(counts.active, equals(0));
      expect(counts.paused, equals(0));
      expect(counts.completed, equals(0));
      expect(counts.failed, equals(0));
      expect(counts.total, equals(0));
    });
  });
}
