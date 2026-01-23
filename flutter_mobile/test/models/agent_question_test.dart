import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/agent_question.dart';

void main() {
  group('AgentQuestion', () {
    test('fromJson parses complete JSON correctly', () {
      final json = {
        'id': 1,
        'question': 'What is the target audience?',
        'agent_name': 'Marketing Agent',
        'agent_icon': '🎯',
        'priority': 2,
        'created_at': '2024-01-15T10:30:00.000Z',
        'context': {'campaign_id': 123},
        'execution_id': 456,
      };

      final question = AgentQuestion.fromJson(json);

      expect(question.id, equals(1));
      expect(question.question, equals('What is the target audience?'));
      expect(question.agentName, equals('Marketing Agent'));
      expect(question.agentIcon, equals('🎯'));
      expect(question.priority, equals(2));
      expect(question.createdAt, equals(DateTime.parse('2024-01-15T10:30:00.000Z')));
      expect(question.context, equals({'campaign_id': 123}));
      expect(question.executionId, equals(456));
    });

    test('fromJson handles minimal required fields with defaults', () {
      final json = {
        'id': 1,
        'question': 'What is your name?',
      };

      final question = AgentQuestion.fromJson(json);

      expect(question.id, equals(1));
      expect(question.question, equals('What is your name?'));
      expect(question.agentName, equals('Agent'));
      expect(question.agentIcon, equals('🤖'));
      expect(question.priority, equals(0));
      expect(question.context, isNull);
      expect(question.executionId, isNull);
    });

    test('toJson serializes correctly', () {
      final question = AgentQuestion(
        id: 1,
        question: 'Test question',
        agentName: 'Test Agent',
        agentIcon: '🤖',
        priority: 1,
        createdAt: DateTime.parse('2024-01-15T10:30:00.000Z'),
        context: {'key': 'value'},
        executionId: 123,
      );

      final json = question.toJson();

      expect(json['id'], equals(1));
      expect(json['question'], equals('Test question'));
      expect(json['agent_name'], equals('Test Agent'));
      expect(json['agent_icon'], equals('🤖'));
      expect(json['priority'], equals(1));
      expect(json['created_at'], equals('2024-01-15T10:30:00.000Z'));
      expect(json['context'], equals({'key': 'value'}));
      expect(json['execution_id'], equals(123));
    });

    test('timeAgo returns "Just now" for recent questions', () {
      final question = AgentQuestion(
        id: 1,
        question: 'Test',
        agentName: 'Agent',
        agentIcon: '🤖',
        priority: 0,
        createdAt: DateTime.now().subtract(const Duration(seconds: 30)),
      );

      expect(question.timeAgo, equals('Just now'));
    });

    test('timeAgo returns minutes for questions within an hour', () {
      final question = AgentQuestion(
        id: 1,
        question: 'Test',
        agentName: 'Agent',
        agentIcon: '🤖',
        priority: 0,
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );

      expect(question.timeAgo, equals('5m ago'));
    });

    test('timeAgo returns hours for questions within a day', () {
      final question = AgentQuestion(
        id: 1,
        question: 'Test',
        agentName: 'Agent',
        agentIcon: '🤖',
        priority: 0,
        createdAt: DateTime.now().subtract(const Duration(hours: 3)),
      );

      expect(question.timeAgo, equals('3h ago'));
    });

    test('timeAgo returns days for older questions', () {
      final question = AgentQuestion(
        id: 1,
        question: 'Test',
        agentName: 'Agent',
        agentIcon: '🤖',
        priority: 0,
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
      );

      expect(question.timeAgo, equals('2d ago'));
    });
  });

  group('AgentCompletion', () {
    test('fromJson parses complete JSON correctly', () {
      final json = {
        'id': 1,
        'agent_name': 'Email Agent',
        'agent_icon': '📧',
        'message': 'Email campaign sent successfully',
        'work_type': 'email_sent',
        'execution_id': 123,
        'created_at': '2024-01-15T10:30:00.000Z',
      };

      final completion = AgentCompletion.fromJson(json);

      expect(completion.id, equals(1));
      expect(completion.agentName, equals('Email Agent'));
      expect(completion.agentIcon, equals('📧'));
      expect(completion.message, equals('Email campaign sent successfully'));
      expect(completion.workType, equals('email_sent'));
      expect(completion.executionId, equals(123));
    });

    test('fromJson handles minimal required fields with defaults', () {
      final json = <String, dynamic>{
        'id': 1,
      };

      final completion = AgentCompletion.fromJson(json);

      expect(completion.id, equals(1));
      expect(completion.agentName, equals('Agent'));
      expect(completion.agentIcon, equals('✅'));
      expect(completion.message, equals('Task completed'));
      expect(completion.workType, isNull);
      expect(completion.executionId, isNull);
    });

    test('fromJson handles string ID from SSE', () {
      final json = {
        'id': 'completion-456',
        'message': 'Done',
      };

      final completion = AgentCompletion.fromJson(json);

      expect(completion.id, equals(456));
    });

    test('fromJson handles string ID without number', () {
      final json = {
        'id': 'no-number-here',
        'message': 'Done',
      };

      final completion = AgentCompletion.fromJson(json);

      // Should fallback to current timestamp
      expect(completion.id, isA<int>());
      expect(completion.id, greaterThan(0));
    });

    test('fromJson handles null ID', () {
      final json = {
        'id': null,
        'message': 'Done',
      };

      final completion = AgentCompletion.fromJson(json);

      // Should fallback to current timestamp
      expect(completion.id, isA<int>());
      expect(completion.id, greaterThan(0));
    });
  });
}
