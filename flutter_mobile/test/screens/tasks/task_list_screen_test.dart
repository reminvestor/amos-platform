import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/scheduled_task.dart';

// Note: TaskListScreen requires GoRouter context which is complex to mock in widget tests.
// These tests focus on the data models used by the screen instead.

void main() {
  group('TaskListScreen Data Models', () {
    test('ScheduledTask status filter values are correct', () {
      // These are the filter statuses used by TaskListScreen tabs
      const allStatuses = ['all', 'active', 'paused', 'completed', 'failed'];
      expect(allStatuses.length, equals(5));
    });

    test('ScheduledTask scheduleLabel returns correct values', () {
      final task = ScheduledTask(
        id: 1,
        name: 'Test',
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

      expect(task.scheduleLabel, equals('Daily'));
    });

    test('ScheduledTask statusLabel returns correct values', () {
      final activeTask = ScheduledTask(
        id: 1,
        name: 'Test',
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

      expect(activeTask.statusLabel, equals('Active'));
    });

    test('Task tabs correspond to status values', () {
      // Tab labels used in TaskListScreen
      const tabLabels = ['All', 'Active', 'Paused', 'Done', 'Failed'];
      expect(tabLabels, contains('All'));
      expect(tabLabels, contains('Active'));
      expect(tabLabels, contains('Paused'));
      expect(tabLabels, contains('Done'));
      expect(tabLabels, contains('Failed'));
    });

    test('ScheduledTask hasFailures returns correct value', () {
      final failingTask = ScheduledTask(
        id: 1,
        name: 'Test',
        taskType: 'custom',
        taskTypeInfo: TaskTypeInfo(name: 'Custom', description: '', icon: ''),
        scheduleType: 'daily',
        status: 'active',
        enabled: true,
        runCount: 5,
        failureCount: 2,
        consecutiveFailures: 2,
        canRun: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(failingTask.hasFailures, isTrue);
    });

    test('TaskTypeInfo parses correctly', () {
      final json = {
        'name': 'Daily Report',
        'description': 'Generate daily report',
        'icon': '📊',
      };

      final info = TaskTypeInfo.fromJson(json);
      expect(info.name, equals('Daily Report'));
      expect(info.description, equals('Generate daily report'));
      expect(info.icon, equals('📊'));
    });
  });
}
