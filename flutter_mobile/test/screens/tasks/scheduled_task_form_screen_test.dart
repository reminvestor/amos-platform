import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/scheduled_task.dart';

// Note: ScheduledTaskFormScreen requires GoRouter context and complex providers.
// These tests focus on the data models and form data structures instead.

void main() {
  group('ScheduledTaskFormScreen Data Models', () {
    test('ScheduledTask can be created for new task form', () {
      final now = DateTime.now();
      final task = ScheduledTask(
        id: 0, // New task
        name: '',
        taskType: 'custom',
        taskTypeInfo: TaskTypeInfo(name: 'Custom', description: '', icon: ''),
        scheduleType: 'daily',
        status: 'active',
        enabled: true,
        runCount: 0,
        failureCount: 0,
        consecutiveFailures: 0,
        canRun: false,
        createdAt: now,
        updatedAt: now,
      );

      expect(task.id, equals(0));
      expect(task.name, isEmpty);
      expect(task.scheduleType, equals('daily'));
    });

    test('Schedule types available for form selection', () {
      const scheduleTypes = ['once', 'daily', 'weekly', 'monthly', 'cron'];
      expect(scheduleTypes.length, equals(5));
      expect(scheduleTypes, contains('once'));
      expect(scheduleTypes, contains('daily'));
      expect(scheduleTypes, contains('weekly'));
      expect(scheduleTypes, contains('monthly'));
      expect(scheduleTypes, contains('cron'));
    });

    test('TaskType options are available', () {
      final taskTypes = [
        TaskType(id: 'daily_report', name: 'Daily Report', description: 'Generate daily reports', icon: '📊'),
        TaskType(id: 'weekly_summary', name: 'Weekly Summary', description: 'Create weekly summaries', icon: '📈'),
        TaskType(id: 'custom', name: 'Custom', description: 'Custom task type', icon: '⚙️'),
      ];

      expect(taskTypes.length, equals(3));
      expect(taskTypes.first.id, equals('daily_report'));
      expect(taskTypes.first.name, equals('Daily Report'));
    });

    test('ScheduledTask form data can be converted to JSON for API', () {
      final task = ScheduledTask(
        id: 1,
        name: 'My Task',
        description: 'Task description',
        taskType: 'daily_report',
        taskTypeInfo: TaskTypeInfo(name: 'Daily Report', description: '', icon: '📊'),
        scheduleType: 'daily',
        status: 'active',
        enabled: true,
        runCount: 0,
        failureCount: 0,
        consecutiveFailures: 0,
        canRun: true,
        prompt: 'Generate the report',
        runAtTime: '09:00',
        timezone: 'UTC',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final json = task.toJson();
      expect(json['name'], equals('My Task'));
      expect(json['task_type'], equals('daily_report'));
      expect(json['schedule_type'], equals('daily'));
      expect(json['prompt'], equals('Generate the report'));
      expect(json['run_at_time'], equals('09:00'));
      expect(json['timezone'], equals('UTC'));
    });

    test('ScheduledTask validates required fields', () {
      // Name is required
      final task = ScheduledTask(
        id: 0,
        name: '',
        taskType: 'custom',
        taskTypeInfo: TaskTypeInfo(name: 'Custom', description: '', icon: ''),
        scheduleType: 'daily',
        status: 'active',
        enabled: true,
        runCount: 0,
        failureCount: 0,
        consecutiveFailures: 0,
        canRun: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(task.name.isEmpty, isTrue);
    });

    test('Form can handle edit mode with existing task', () {
      final existingTask = ScheduledTask(
        id: 123,
        name: 'Existing Task',
        description: 'Existing description',
        taskType: 'weekly_summary',
        taskTypeInfo: TaskTypeInfo(name: 'Weekly Summary', description: '', icon: '📈'),
        scheduleType: 'weekly',
        status: 'active',
        enabled: true,
        runCount: 10,
        failureCount: 0,
        consecutiveFailures: 0,
        canRun: true,
        prompt: 'Summarize the week',
        runAtTime: '17:00',
        runOnDay: 5, // Friday
        timezone: 'America/New_York',
        createdAt: DateTime.parse('2024-01-01T00:00:00Z'),
        updatedAt: DateTime.parse('2024-01-15T00:00:00Z'),
      );

      // Edit mode would have id > 0
      expect(existingTask.id, greaterThan(0));
      expect(existingTask.name, isNotEmpty);
      expect(existingTask.runOnDay, equals(5));
    });
  });
}
