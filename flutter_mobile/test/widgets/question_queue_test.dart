import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/agent_question.dart';
import 'package:amos_mobile/services/questions_service.dart';

void main() {
  Widget createTestWidget(Widget child) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(body: child),
    );
  }

  group('AgentQuestion model', () {
    test('fromJson parses correctly', () {
      final json = {
        'id': 1,
        'question': 'What is the target audience?',
        'agent_name': 'Marketing Agent',
        'agent_icon': '📊',
        'priority': 5,
        'created_at': '2024-01-15T10:30:00Z',
        'execution_id': 123,
        'context': {'campaign_id': 456},
      };

      final question = AgentQuestion.fromJson(json);
      expect(question.id, equals(1));
      expect(question.question, equals('What is the target audience?'));
      expect(question.agentName, equals('Marketing Agent'));
      expect(question.agentIcon, equals('📊'));
      expect(question.priority, equals(5));
      expect(question.executionId, equals(123));
      expect(question.context, isNotNull);
      expect(question.context!['campaign_id'], equals(456));
    });

    test('fromJson uses defaults for missing optional fields', () {
      final json = {
        'id': 2,
        'question': 'Simple question',
      };

      final question = AgentQuestion.fromJson(json);
      expect(question.id, equals(2));
      expect(question.question, equals('Simple question'));
      expect(question.agentName, equals('Agent'));
      expect(question.agentIcon, equals('🤖'));
      expect(question.priority, equals(0));
      expect(question.executionId, isNull);
      expect(question.context, isNull);
    });

    test('toJson returns correct map', () {
      final question = AgentQuestion(
        id: 1,
        question: 'Test question?',
        agentName: 'Test Agent',
        agentIcon: '🧪',
        priority: 3,
        createdAt: DateTime.parse('2024-01-15T10:30:00Z'),
      );

      final json = question.toJson();
      expect(json['id'], equals(1));
      expect(json['question'], equals('Test question?'));
      expect(json['agent_name'], equals('Test Agent'));
      expect(json['agent_icon'], equals('🧪'));
      expect(json['priority'], equals(3));
    });

    test('timeAgo returns "Just now" for recent questions', () {
      final question = AgentQuestion(
        id: 1,
        question: 'Test?',
        agentName: 'Agent',
        agentIcon: '🤖',
        priority: 0,
        createdAt: DateTime.now().subtract(const Duration(seconds: 30)),
      );

      expect(question.timeAgo, equals('Just now'));
    });

    test('timeAgo returns minutes ago for older questions', () {
      final question = AgentQuestion(
        id: 1,
        question: 'Test?',
        agentName: 'Agent',
        agentIcon: '🤖',
        priority: 0,
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );

      expect(question.timeAgo, equals('5m ago'));
    });

    test('timeAgo returns hours ago for old questions', () {
      final question = AgentQuestion(
        id: 1,
        question: 'Test?',
        agentName: 'Agent',
        agentIcon: '🤖',
        priority: 0,
        createdAt: DateTime.now().subtract(const Duration(hours: 3)),
      );

      expect(question.timeAgo, equals('3h ago'));
    });

    test('timeAgo returns days ago for very old questions', () {
      final question = AgentQuestion(
        id: 1,
        question: 'Test?',
        agentName: 'Agent',
        agentIcon: '🤖',
        priority: 0,
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
      );

      expect(question.timeAgo, equals('2d ago'));
    });
  });

  group('AgentCompletion model', () {
    test('fromJson parses integer id correctly', () {
      final json = {
        'id': 123,
        'agent_name': 'Campaign Agent',
        'agent_icon': '✅',
        'message': 'Campaign created successfully',
        'work_type': 'campaign',
        'execution_id': 456,
        'created_at': '2024-01-15T12:00:00Z',
      };

      final completion = AgentCompletion.fromJson(json);
      expect(completion.id, equals(123));
      expect(completion.agentName, equals('Campaign Agent'));
      expect(completion.agentIcon, equals('✅'));
      expect(completion.message, equals('Campaign created successfully'));
      expect(completion.workType, equals('campaign'));
      expect(completion.executionId, equals(456));
    });

    test('fromJson parses string id from SSE', () {
      final json = {
        'id': 'completion-789',
        'agent_name': 'Test Agent',
        'message': 'Task done',
      };

      final completion = AgentCompletion.fromJson(json);
      expect(completion.id, equals(789));
      expect(completion.agentName, equals('Test Agent'));
    });

    test('fromJson uses defaults for missing fields', () {
      final json = <String, dynamic>{};

      final completion = AgentCompletion.fromJson(json);
      expect(completion.agentName, equals('Agent'));
      expect(completion.agentIcon, equals('✅'));
      expect(completion.message, equals('Task completed'));
    });
  });

  group('QuestionsResponse', () {
    test('creates correctly with questions and completions', () {
      final questions = [
        AgentQuestion(
          id: 1,
          question: 'Q1?',
          agentName: 'Agent',
          agentIcon: '🤖',
          priority: 0,
          createdAt: DateTime.now(),
        ),
      ];

      final completions = [
        AgentCompletion(
          id: 1,
          agentName: 'Agent',
          agentIcon: '✅',
          message: 'Done',
        ),
      ];

      final response = QuestionsResponse(
        questions: questions,
        completions: completions,
      );

      expect(response.questions.length, equals(1));
      expect(response.completions.length, equals(1));
    });

    test('creates correctly with empty lists', () {
      final response = QuestionsResponse(
        questions: [],
        completions: [],
      );

      expect(response.questions, isEmpty);
      expect(response.completions, isEmpty);
    });
  });

  // Note: QuestionQueueWidget tests are limited because the widget
  // depends on API calls through QuestionsService. The widget also
  // has complex state management with polling timers.
  //
  // The tests above comprehensively cover the data models used by
  // the QuestionQueueWidget. For full widget testing, consider:
  // 1. Using dependency injection to allow mocking QuestionsService
  // 2. Using mockito or mocktail for service mocking
  // 3. Testing UI state changes with mock data

  group('Question queue visual elements', () {
    testWidgets('uses correct icons for UI elements', (tester) async {
      // Verify that the icons used in question queue exist
      await tester.pumpWidget(createTestWidget(
        Column(
          children: [
            Icon(LucideIcons.messageSquare),  // Used in badge
            Icon(LucideIcons.x),               // Used for close button
            Icon(LucideIcons.skipForward),     // Used for skip button
            Icon(LucideIcons.send),            // Used for send button
            Icon(LucideIcons.circleCheck),     // Used for completions
            Icon(LucideIcons.inbox),           // Used for inbox navigation
          ],
        ),
      ));

      expect(find.byIcon(LucideIcons.messageSquare), findsOneWidget);
      expect(find.byIcon(LucideIcons.x), findsOneWidget);
      expect(find.byIcon(LucideIcons.skipForward), findsOneWidget);
      expect(find.byIcon(LucideIcons.send), findsOneWidget);
      expect(find.byIcon(LucideIcons.circleCheck), findsOneWidget);
      expect(find.byIcon(LucideIcons.inbox), findsOneWidget);
    });

    testWidgets('theme colors are accessible', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              // Verify theme extension colors work
              expect(context.primaryColor, isNotNull);
              expect(context.surfaceColor, isNotNull);
              expect(context.textSecondary, isNotNull);
              expect(context.textTertiary, isNotNull);
              return const SizedBox();
            },
          ),
        ),
      );
    });
  });
}
