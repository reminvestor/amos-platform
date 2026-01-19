import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/scheduled_task.dart';

// Note: TaskDetailScreen requires GoRouter context and API calls.
// These tests focus on the data models used by the screen instead.

void main() {
  group('TaskDetailScreen Data Models', () {
    test('ScheduledTask can be created with all fields', () {
      final task = ScheduledTask(
        id: 1,
        name: 'Test Task',
        description: 'A test task',
        taskType: 'custom',
        taskTypeInfo: TaskTypeInfo(
          name: 'Custom',
          description: 'Custom task type',
          icon: '✅',
        ),
        scheduleType: 'daily',
        status: 'active',
        enabled: true,
        runCount: 5,
        failureCount: 1,
        consecutiveFailures: 0,
        canRun: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        nextRunAt: DateTime.now().add(const Duration(hours: 1)),
        lastRunAt: DateTime.now().subtract(const Duration(hours: 1)),
        cronExpression: '0 9 * * *',
        runAtTime: '09:00',
        timezone: 'America/New_York',
        prompt: 'Run the task',
        agentName: 'Test Agent',
      );

      expect(task.id, equals(1));
      expect(task.name, equals('Test Task'));
      expect(task.description, equals('A test task'));
      expect(task.taskType, equals('custom'));
      expect(task.scheduleType, equals('daily'));
      expect(task.status, equals('active'));
      expect(task.enabled, isTrue);
      expect(task.runCount, equals(5));
      expect(task.cronExpression, equals('0 9 * * *'));
      expect(task.agentName, equals('Test Agent'));
    });

    test('ScheduledTask copyWith creates new instance with updated values', () {
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

      final updated = original.copyWith(
        name: 'Updated',
        status: 'paused',
        enabled: false,
      );

      expect(updated.name, equals('Updated'));
      expect(updated.status, equals('paused'));
      expect(updated.enabled, isFalse);
      expect(updated.id, equals(original.id));
    });

    test('ScheduledTask toJson serializes correctly', () {
      final task = ScheduledTask(
        id: 1,
        name: 'Test',
        taskType: 'custom',
        taskTypeInfo: TaskTypeInfo(name: 'Custom', description: '', icon: ''),
        scheduleType: 'weekly',
        status: 'active',
        enabled: true,
        runCount: 10,
        failureCount: 2,
        consecutiveFailures: 0,
        canRun: true,
        createdAt: DateTime.parse('2024-01-15T10:30:00.000Z'),
        updatedAt: DateTime.parse('2024-01-16T11:00:00.000Z'),
      );

      final json = task.toJson();
      expect(json['id'], equals(1));
      expect(json['name'], equals('Test'));
      expect(json['task_type'], equals('custom'));
      expect(json['schedule_type'], equals('weekly'));
      expect(json['enabled'], isTrue);
    });

    test('ScheduledTask schedule types have correct labels', () {
      final scheduleTypes = {
        'once': 'One Time',
        'daily': 'Daily',
        'weekly': 'Weekly',
        'monthly': 'Monthly',
        'cron': 'Custom Schedule',
      };

      for (final entry in scheduleTypes.entries) {
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
        expect(task.scheduleLabel, equals(entry.value));
      }
    });
  });
}
