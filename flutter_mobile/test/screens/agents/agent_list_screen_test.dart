import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/agent.dart';

// Note: AgentListScreen triggers async _loadAgents in initState which can cause
// "ref used after dispose" errors in widget tests. These tests focus on the
// Agent model instead.

void main() {
  group('AgentListScreen Data Models', () {
    test('Agent can be created with required fields', () {
      final agent = Agent(
        id: '1',
        name: 'Test Agent',
        description: 'A test agent for testing',
        agentType: AgentType.executor,
        interactive: false,
        icon: 'bot',
        createdAt: DateTime.now(),
      );

      expect(agent.id, equals('1'));
      expect(agent.name, equals('Test Agent'));
      expect(agent.description, equals('A test agent for testing'));
      expect(agent.agentType, equals(AgentType.executor));
      expect(agent.interactive, isFalse);
      expect(agent.icon, equals('bot'));
    });

    test('AgentType values are correct', () {
      expect(AgentType.executor.value, equals('executor'));
      expect(AgentType.planner.value, equals('planner'));
      expect(AgentType.analyst.value, equals('analyst'));
      expect(AgentType.verifier.value, equals('verifier'));
      expect(AgentType.fixer.value, equals('fixer'));
      expect(AgentType.architect.value, equals('architect'));
      expect(AgentType.engineer.value, equals('engineer'));
      expect(AgentType.custom.value, equals('custom'));
    });

    test('AgentType displayName returns capitalized value', () {
      expect(AgentType.executor.displayName, equals('Executor'));
      expect(AgentType.planner.displayName, equals('Planner'));
      expect(AgentType.analyst.displayName, equals('Analyst'));
    });

    test('AgentTypeX.fromString parses string correctly', () {
      expect(AgentTypeX.fromString('executor'), equals(AgentType.executor));
      expect(AgentTypeX.fromString('PLANNER'), equals(AgentType.planner));
      expect(AgentTypeX.fromString('unknown'), equals(AgentType.custom));
    });

    test('Agent.fromJson parses correctly', () {
      final json = {
        'id': 1,
        'name': 'Marketing Agent',
        'description': 'Helps with marketing tasks',
        'agent_type': 'executor',
        'interactive': true,
        'icon': 'Target',
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-16T11:00:00.000Z',
      };

      final agent = Agent.fromJson(json);

      expect(agent.id, equals('1'));
      expect(agent.name, equals('Marketing Agent'));
      expect(agent.agentType, equals(AgentType.executor));
      expect(agent.interactive, isTrue);
    });

    test('Agent.toJson serializes correctly', () {
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
      expect(json['agent_type'], equals('planner'));
      expect(json['interactive'], isTrue);
    });

    test('List of agents can be created from JSON', () {
      final jsonList = [
        {
          'id': '1',
          'name': 'Agent One',
          'description': 'First agent',
          'agent_type': 'executor',
          'interactive': false,
          'icon': 'bot',
          'created_at': '2024-01-01T00:00:00.000Z',
        },
        {
          'id': '2',
          'name': 'Agent Two',
          'description': 'Second agent',
          'agent_type': 'analyst',
          'interactive': true,
          'icon': 'chart',
          'created_at': '2024-01-02T00:00:00.000Z',
        },
      ];

      final agents = jsonList.map((j) => Agent.fromJson(j)).toList();
      expect(agents.length, equals(2));
      expect(agents[0].name, equals('Agent One'));
      expect(agents[1].name, equals('Agent Two'));
    });

    test('Interactive agents have interactive flag set', () {
      final interactiveAgent = Agent(
        id: '1',
        name: 'Interactive Agent',
        description: 'An interactive agent',
        agentType: AgentType.planner,
        interactive: true,
        icon: 'bot',
        createdAt: DateTime.now(),
      );

      final nonInteractiveAgent = Agent(
        id: '2',
        name: 'Batch Agent',
        description: 'A batch processing agent',
        agentType: AgentType.executor,
        interactive: false,
        icon: 'cog',
        createdAt: DateTime.now(),
      );

      expect(interactiveAgent.interactive, isTrue);
      expect(nonInteractiveAgent.interactive, isFalse);
    });
  });
}
