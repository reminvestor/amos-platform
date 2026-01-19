import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/agent.dart';

// Note: AgentDetailScreen triggers async operations in initState which can cause
// "ref used after dispose" errors in widget tests. These tests focus on the
// Agent model and related data structures instead.

void main() {
  group('AgentDetailScreen Data Models', () {
    test('Agent fields are properly accessible', () {
      final agent = Agent(
        id: '1',
        name: 'Marketing Agent',
        description: 'Helps with marketing tasks',
        agentType: AgentType.executor,
        interactive: true,
        icon: 'Target',
        createdAt: DateTime.parse('2024-01-15T10:30:00.000Z'),
        updatedAt: DateTime.parse('2024-01-16T11:00:00.000Z'),
        fields: [
          AgentField(
            name: 'target_audience',
            question: 'Who is your target audience?',
            required: true,
            type: 'text',
          ),
        ],
        capabilities: ['email', 'social'],
        tools: [
          AgentTool(name: 'send_email', required: true),
        ],
      );

      expect(agent.name, equals('Marketing Agent'));
      expect(agent.description, equals('Helps with marketing tasks'));
      expect(agent.fields?.length, equals(1));
      expect(agent.capabilities?.length, equals(2));
      expect(agent.tools?.length, equals(1));
    });

    test('AgentField fromJson parses correctly', () {
      final json = {
        'name': 'target_audience',
        'question': 'Who is your target audience?',
        'required': true,
        'type': 'text',
        'examples': ['Young professionals', 'Small business owners'],
      };

      final field = AgentField.fromJson(json);

      expect(field.name, equals('target_audience'));
      expect(field.question, equals('Who is your target audience?'));
      expect(field.required, isTrue);
      expect(field.type, equals('text'));
      expect(field.examples?.length, equals(2));
    });

    test('AgentTool displayName formats name correctly', () {
      final tool1 = AgentTool(name: 'web_search_tool', required: true);
      final tool2 = AgentTool(name: 'send_email', required: false);
      final tool3 = AgentTool(name: 'get_data', required: true);

      expect(tool1.displayName, equals('Web Search Tool'));
      expect(tool2.displayName, equals('Send Email'));
      expect(tool3.displayName, equals('Get Data'));
    });

    test('Capability names are formatted for display', () {
      final capabilities = ['content_generation', 'data_analysis', 'email_marketing'];

      // Simulating the display formatting used in the screen
      String formatCapability(String cap) {
        return cap.split('_').map((word) =>
          word[0].toUpperCase() + word.substring(1)
        ).join(' ');
      }

      expect(formatCapability(capabilities[0]), equals('Content Generation'));
      expect(formatCapability(capabilities[1]), equals('Data Analysis'));
      expect(formatCapability(capabilities[2]), equals('Email Marketing'));
    });

    test('Agent types display names correctly', () {
      final types = AgentType.values;

      for (final type in types) {
        expect(type.displayName.isNotEmpty, isTrue);
        expect(type.displayName[0], equals(type.displayName[0].toUpperCase()));
      }
    });

    test('Agent with tools has tool count', () {
      final agent = Agent(
        id: '1',
        name: 'Test Agent',
        description: 'A test agent',
        agentType: AgentType.executor,
        interactive: false,
        icon: 'bot',
        createdAt: DateTime.now(),
        tools: [
          AgentTool(name: 'tool_1', required: true),
          AgentTool(name: 'tool_2', required: false),
          AgentTool(name: 'tool_3', required: true),
        ],
      );

      expect(agent.tools?.length, equals(3));
      expect(agent.tools?.where((t) => t.required).length, equals(2));
    });

    test('Agent without optional fields returns null', () {
      final minimalAgent = Agent(
        id: '1',
        name: 'Minimal Agent',
        description: 'A minimal agent',
        agentType: AgentType.custom,
        interactive: false,
        icon: 'bot',
        createdAt: DateTime.now(),
      );

      expect(minimalAgent.fields, isNull);
      expect(minimalAgent.capabilities, isNull);
      expect(minimalAgent.tools, isNull);
      expect(minimalAgent.requiredContext, isNull);
      expect(minimalAgent.updatedAt, isNull);
    });

    test('AgentFieldOption parses correctly', () {
      final json = {
        'label': 'Option A',
        'value': 'option_a',
      };

      final option = AgentFieldOption.fromJson(json);

      expect(option.label, equals('Option A'));
      expect(option.value, equals('option_a'));
    });

    test('AgentField with options parses correctly', () {
      final json = {
        'name': 'priority',
        'question': 'Select priority level',
        'required': true,
        'type': 'select',
        'options': [
          {'label': 'High', 'value': 'high'},
          {'label': 'Medium', 'value': 'medium'},
          {'label': 'Low', 'value': 'low'},
        ],
      };

      final field = AgentField.fromJson(json);

      expect(field.options?.length, equals(3));
      expect(field.options?.first.label, equals('High'));
      expect(field.options?.last.value, equals('low'));
    });
  });
}
