import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/agent.dart';

void main() {
  group('AgentType', () {
    test('fromString converts string to enum correctly', () {
      expect(AgentTypeX.fromString('content_generator'),
          equals(AgentType.contentGenerator));
      expect(AgentTypeX.fromString('data_processor'),
          equals(AgentType.dataProcessor));
      expect(AgentTypeX.fromString('api_integration'),
          equals(AgentType.apiIntegration));
      expect(AgentTypeX.fromString('workflow_automation'),
          equals(AgentType.workflowAutomation));
      expect(AgentTypeX.fromString('custom'), equals(AgentType.custom));
    });

    test('fromString returns custom for unknown values', () {
      expect(AgentTypeX.fromString('unknown'), equals(AgentType.custom));
      expect(AgentTypeX.fromString(''), equals(AgentType.custom));
    });

    test('value returns correct string', () {
      expect(AgentType.contentGenerator.value, equals('content_generator'));
      expect(AgentType.dataProcessor.value, equals('data_processor'));
      expect(AgentType.apiIntegration.value, equals('api_integration'));
      expect(AgentType.workflowAutomation.value, equals('workflow_automation'));
      expect(AgentType.custom.value, equals('custom'));
    });

    test('displayName returns human-readable name', () {
      expect(AgentType.contentGenerator.displayName, equals('Content Generator'));
      expect(AgentType.dataProcessor.displayName, equals('Data Processor'));
      expect(AgentType.apiIntegration.displayName, equals('API Integration'));
      expect(
          AgentType.workflowAutomation.displayName, equals('Workflow Automation'));
      expect(AgentType.custom.displayName, equals('Custom'));
    });
  });

  group('Agent', () {
    test('fromJson parses complete JSON correctly', () {
      final json = {
        'id': '123',
        'name': 'Test Agent',
        'description': 'A test agent',
        'agent_type': 'content_generator',
        'interactive': true,
        'icon': 'Sparkles',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-02T00:00:00.000Z',
        'capabilities': ['generate_text', 'summarize'],
        'required_context': ['brand_info'],
      };

      final agent = Agent.fromJson(json);

      expect(agent.id, equals('123'));
      expect(agent.name, equals('Test Agent'));
      expect(agent.description, equals('A test agent'));
      expect(agent.agentType, equals(AgentType.contentGenerator));
      expect(agent.interactive, isTrue);
      expect(agent.icon, equals('Sparkles'));
      expect(agent.createdAt, equals(DateTime.parse('2024-01-01T00:00:00.000Z')));
      expect(agent.updatedAt, equals(DateTime.parse('2024-01-02T00:00:00.000Z')));
      expect(agent.capabilities, equals(['generate_text', 'summarize']));
      expect(agent.requiredContext, equals(['brand_info']));
    });

    test('fromJson handles numeric id', () {
      final json = {
        'id': 456,
        'name': 'Agent',
        'description': '',
        'created_at': '2024-01-01T00:00:00.000Z',
      };

      final agent = Agent.fromJson(json);
      expect(agent.id, equals('456'));
    });

    test('fromJson uses default values for missing fields', () {
      final json = {
        'id': '789',
        'created_at': '2024-01-01T00:00:00.000Z',
      };

      final agent = Agent.fromJson(json);

      expect(agent.name, equals('Unnamed Agent'));
      expect(agent.description, equals(''));
      expect(agent.agentType, equals(AgentType.custom));
      expect(agent.interactive, isFalse);
      expect(agent.icon, equals('Bot'));
      expect(agent.updatedAt, isNull);
      expect(agent.capabilities, isNull);
      expect(agent.requiredContext, isNull);
    });

    test('toJson serializes agent correctly', () {
      final agent = Agent(
        id: '123',
        name: 'Test Agent',
        description: 'A test agent',
        agentType: AgentType.contentGenerator,
        interactive: true,
        icon: 'Sparkles',
        createdAt: DateTime.parse('2024-01-01T00:00:00.000Z'),
        updatedAt: DateTime.parse('2024-01-02T00:00:00.000Z'),
      );

      final json = agent.toJson();

      expect(json['id'], equals('123'));
      expect(json['name'], equals('Test Agent'));
      expect(json['description'], equals('A test agent'));
      expect(json['agent_type'], equals('content_generator'));
      expect(json['interactive'], isTrue);
      expect(json['icon'], equals('Sparkles'));
      expect(json.containsKey('created_at'), isTrue);
      expect(json.containsKey('updated_at'), isTrue);
    });

    test('toJson excludes null updatedAt', () {
      final agent = Agent(
        id: '123',
        name: 'Test Agent',
        description: 'A test agent',
        agentType: AgentType.custom,
        interactive: false,
        icon: 'Bot',
        createdAt: DateTime.parse('2024-01-01T00:00:00.000Z'),
      );

      final json = agent.toJson();
      expect(json.containsKey('updated_at'), isFalse);
    });
  });

  group('AgentField', () {
    test('fromJson parses field with options', () {
      final json = {
        'name': 'tone',
        'question': 'What tone would you like?',
        'required': true,
        'type': 'select',
        'options': [
          {'label': 'Professional', 'value': 'professional'},
          {'label': 'Casual', 'value': 'casual'},
        ],
      };

      final field = AgentField.fromJson(json);

      expect(field.name, equals('tone'));
      expect(field.question, equals('What tone would you like?'));
      expect(field.required, isTrue);
      expect(field.type, equals('select'));
      expect(field.options, hasLength(2));
      expect(field.options![0].label, equals('Professional'));
      expect(field.options![0].value, equals('professional'));
    });

    test('fromJson parses field with examples', () {
      final json = {
        'name': 'topic',
        'question': 'What topic?',
        'required': false,
        'examples': ['AI', 'Marketing', 'Sales'],
      };

      final field = AgentField.fromJson(json);

      expect(field.examples, equals(['AI', 'Marketing', 'Sales']));
      expect(field.required, isFalse);
    });
  });

  group('AgentExecution', () {
    test('fromJson parses execution status correctly', () {
      final json = {
        'job_id': 'job_123',
        'status': 'processing',
        'result': null,
        'error': null,
      };

      final execution = AgentExecution.fromJson(json);

      expect(execution.jobId, equals('job_123'));
      expect(execution.status, equals(AgentExecutionStatus.processing));
      expect(execution.result, isNull);
      expect(execution.error, isNull);
    });

    test('fromJson parses completed execution with result', () {
      final json = {
        'job_id': 'job_456',
        'status': 'completed',
        'result': {'output': 'Generated content here'},
      };

      final execution = AgentExecution.fromJson(json);

      expect(execution.status, equals(AgentExecutionStatus.completed));
      expect(execution.result, isNotNull);
      expect(execution.result!['output'], equals('Generated content here'));
    });

    test('fromJson parses failed execution with error', () {
      final json = {
        'job_id': 'job_789',
        'status': 'failed',
        'error': 'Something went wrong',
      };

      final execution = AgentExecution.fromJson(json);

      expect(execution.status, equals(AgentExecutionStatus.failed));
      expect(execution.error, equals('Something went wrong'));
    });
  });

  group('AgentExecutionStatus', () {
    test('fromString converts string to enum correctly', () {
      expect(AgentExecutionStatusX.fromString('pending'),
          equals(AgentExecutionStatus.pending));
      expect(AgentExecutionStatusX.fromString('processing'),
          equals(AgentExecutionStatus.processing));
      expect(AgentExecutionStatusX.fromString('completed'),
          equals(AgentExecutionStatus.completed));
      expect(AgentExecutionStatusX.fromString('failed'),
          equals(AgentExecutionStatus.failed));
    });

    test('fromString returns pending for unknown values', () {
      expect(AgentExecutionStatusX.fromString('unknown'),
          equals(AgentExecutionStatus.pending));
    });
  });
}
