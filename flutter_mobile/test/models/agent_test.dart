import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/agent.dart';

void main() {
  group('AgentType', () {
    test('value returns correct string', () {
      expect(AgentType.executor.value, equals('executor'));
      expect(AgentType.planner.value, equals('planner'));
      expect(AgentType.analyst.value, equals('analyst'));
      expect(AgentType.verifier.value, equals('verifier'));
      expect(AgentType.fixer.value, equals('fixer'));
      expect(AgentType.architect.value, equals('architect'));
      expect(AgentType.engineer.value, equals('engineer'));
      expect(AgentType.custom.value, equals('custom'));
    });

    test('displayName returns correct title case', () {
      expect(AgentType.executor.displayName, equals('Executor'));
      expect(AgentType.planner.displayName, equals('Planner'));
      expect(AgentType.analyst.displayName, equals('Analyst'));
      expect(AgentType.verifier.displayName, equals('Verifier'));
      expect(AgentType.fixer.displayName, equals('Fixer'));
      expect(AgentType.architect.displayName, equals('Architect'));
      expect(AgentType.engineer.displayName, equals('Engineer'));
      expect(AgentType.custom.displayName, equals('Custom'));
    });

    test('fromString converts string to enum correctly', () {
      expect(AgentTypeX.fromString('executor'), equals(AgentType.executor));
      expect(AgentTypeX.fromString('planner'), equals(AgentType.planner));
      expect(AgentTypeX.fromString('analyst'), equals(AgentType.analyst));
      expect(AgentTypeX.fromString('verifier'), equals(AgentType.verifier));
      expect(AgentTypeX.fromString('fixer'), equals(AgentType.fixer));
      expect(AgentTypeX.fromString('architect'), equals(AgentType.architect));
      expect(AgentTypeX.fromString('engineer'), equals(AgentType.engineer));
      expect(AgentTypeX.fromString('custom'), equals(AgentType.custom));
    });

    test('fromString is case insensitive', () {
      expect(AgentTypeX.fromString('EXECUTOR'), equals(AgentType.executor));
      expect(AgentTypeX.fromString('Planner'), equals(AgentType.planner));
    });

    test('fromString returns custom for unknown values', () {
      expect(AgentTypeX.fromString('unknown'), equals(AgentType.custom));
      expect(AgentTypeX.fromString(''), equals(AgentType.custom));
    });
  });

  group('AgentFieldOption', () {
    test('fromJson parses correctly', () {
      final json = {
        'label': 'Option A',
        'value': 'option_a',
      };

      final option = AgentFieldOption.fromJson(json);

      expect(option.label, equals('Option A'));
      expect(option.value, equals('option_a'));
    });
  });

  group('AgentField', () {
    test('fromJson parses complete JSON correctly', () {
      final json = {
        'name': 'target_audience',
        'question': 'Who is your target audience?',
        'required': true,
        'type': 'text',
        'examples': ['Young professionals', 'Small business owners'],
        'options': [
          {'label': 'B2B', 'value': 'b2b'},
          {'label': 'B2C', 'value': 'b2c'},
        ],
      };

      final field = AgentField.fromJson(json);

      expect(field.name, equals('target_audience'));
      expect(field.question, equals('Who is your target audience?'));
      expect(field.required, isTrue);
      expect(field.type, equals('text'));
      expect(field.examples, hasLength(2));
      expect(field.examples?.first, equals('Young professionals'));
      expect(field.options, hasLength(2));
      expect(field.options?.first.label, equals('B2B'));
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'name': 'simple_field',
        'question': 'A question?',
      };

      final field = AgentField.fromJson(json);

      expect(field.name, equals('simple_field'));
      expect(field.question, equals('A question?'));
      expect(field.required, isFalse);
      expect(field.type, isNull);
      expect(field.examples, isNull);
      expect(field.options, isNull);
    });
  });

  group('AgentTool', () {
    test('fromJson parses correctly', () {
      final json = {
        'name': 'send_email',
        'required': true,
      };

      final tool = AgentTool.fromJson(json);

      expect(tool.name, equals('send_email'));
      expect(tool.required, isTrue);
    });

    test('fromJson handles missing values', () {
      final json = <String, dynamic>{};

      final tool = AgentTool.fromJson(json);

      expect(tool.name, equals(''));
      expect(tool.required, isFalse);
    });

    test('displayName converts snake_case to Title Case', () {
      final tool = AgentTool(name: 'send_email_campaign', required: false);
      expect(tool.displayName, equals('Send Email Campaign'));
    });

    test('displayName handles single word', () {
      final tool = AgentTool(name: 'search', required: false);
      expect(tool.displayName, equals('Search'));
    });

    test('displayName handles empty name', () {
      final tool = AgentTool(name: '', required: false);
      expect(tool.displayName, equals(''));
    });
  });

  group('Agent', () {
    test('fromJson parses complete JSON correctly', () {
      final json = {
        'id': 1,
        'name': 'Marketing Agent',
        'description': 'Helps with marketing tasks',
        'agent_type': 'executor',
        'interactive': true,
        'icon': 'Target',
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-16T11:00:00.000Z',
        'fields': [
          {'name': 'field1', 'question': 'Question?', 'required': true},
        ],
        'required_context': ['business_profile'],
        'capabilities': ['email', 'social'],
        'tools': [
          {'name': 'send_email', 'required': true},
        ],
      };

      final agent = Agent.fromJson(json);

      expect(agent.id, equals('1'));
      expect(agent.name, equals('Marketing Agent'));
      expect(agent.description, equals('Helps with marketing tasks'));
      expect(agent.agentType, equals(AgentType.executor));
      expect(agent.interactive, isTrue);
      expect(agent.icon, equals('Target'));
      expect(agent.createdAt, equals(DateTime.parse('2024-01-15T10:30:00.000Z')));
      expect(agent.updatedAt, equals(DateTime.parse('2024-01-16T11:00:00.000Z')));
      expect(agent.fields, hasLength(1));
      expect(agent.requiredContext, equals(['business_profile']));
      expect(agent.capabilities, equals(['email', 'social']));
      expect(agent.tools, hasLength(1));
    });

    test('fromJson handles minimal required fields', () {
      final json = {
        'id': '123',
        'created_at': '2024-01-15T10:30:00.000Z',
      };

      final agent = Agent.fromJson(json);

      expect(agent.id, equals('123'));
      expect(agent.name, equals('Unnamed Agent'));
      expect(agent.description, equals(''));
      expect(agent.agentType, equals(AgentType.custom));
      expect(agent.interactive, isFalse);
      expect(agent.icon, equals('Bot'));
      expect(agent.updatedAt, isNull);
      expect(agent.fields, isNull);
      expect(agent.requiredContext, isNull);
      expect(agent.capabilities, isNull);
      expect(agent.tools, isNull);
    });

    test('toJson serializes correctly', () {
      final agent = Agent(
        id: '123',
        name: 'Test Agent',
        description: 'Test description',
        agentType: AgentType.planner,
        interactive: true,
        icon: 'Bot',
        createdAt: DateTime.parse('2024-01-15T10:30:00.000Z'),
        updatedAt: DateTime.parse('2024-01-16T11:00:00.000Z'),
      );

      final json = agent.toJson();

      expect(json['id'], equals('123'));
      expect(json['name'], equals('Test Agent'));
      expect(json['description'], equals('Test description'));
      expect(json['agent_type'], equals('planner'));
      expect(json['interactive'], isTrue);
      expect(json['icon'], equals('Bot'));
      expect(json['created_at'], equals('2024-01-15T10:30:00.000Z'));
      expect(json['updated_at'], equals('2024-01-16T11:00:00.000Z'));
    });

    test('toJson excludes null updatedAt', () {
      final agent = Agent(
        id: '123',
        name: 'Test Agent',
        description: 'Test',
        agentType: AgentType.custom,
        interactive: false,
        icon: 'Bot',
        createdAt: DateTime.now(),
      );

      final json = agent.toJson();

      expect(json.containsKey('updated_at'), isFalse);
    });
  });

  group('AgentExecutionStatus', () {
    test('value returns correct string', () {
      expect(AgentExecutionStatus.pending.value, equals('pending'));
      expect(AgentExecutionStatus.processing.value, equals('processing'));
      expect(AgentExecutionStatus.completed.value, equals('completed'));
      expect(AgentExecutionStatus.failed.value, equals('failed'));
    });

    test('fromString converts string to enum correctly', () {
      expect(AgentExecutionStatusX.fromString('pending'), equals(AgentExecutionStatus.pending));
      expect(AgentExecutionStatusX.fromString('processing'), equals(AgentExecutionStatus.processing));
      expect(AgentExecutionStatusX.fromString('completed'), equals(AgentExecutionStatus.completed));
      expect(AgentExecutionStatusX.fromString('failed'), equals(AgentExecutionStatus.failed));
    });

    test('fromString returns pending for unknown values', () {
      expect(AgentExecutionStatusX.fromString('unknown'), equals(AgentExecutionStatus.pending));
    });
  });

  group('AgentExecution', () {
    test('fromJson parses complete JSON correctly', () {
      final json = {
        'job_id': 'job-123',
        'status': 'completed',
        'result': {'output': 'Success'},
        'error': null,
      };

      final execution = AgentExecution.fromJson(json);

      expect(execution.jobId, equals('job-123'));
      expect(execution.status, equals(AgentExecutionStatus.completed));
      expect(execution.result, equals({'output': 'Success'}));
      expect(execution.error, isNull);
    });

    test('fromJson handles error case', () {
      final json = {
        'job_id': 'job-456',
        'status': 'failed',
        'error': 'Something went wrong',
      };

      final execution = AgentExecution.fromJson(json);

      expect(execution.jobId, equals('job-456'));
      expect(execution.status, equals(AgentExecutionStatus.failed));
      expect(execution.result, isNull);
      expect(execution.error, equals('Something went wrong'));
    });

    test('fromJson handles missing status', () {
      final json = {
        'job_id': 'job-789',
      };

      final execution = AgentExecution.fromJson(json);

      expect(execution.jobId, equals('job-789'));
      expect(execution.status, equals(AgentExecutionStatus.pending));
    });
  });
}
