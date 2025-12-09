import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:amos_mobile/models/agent.dart';

// Note: AgentsService uses FlutterSecureStorage which requires native plugins.
// For unit tests, we test the API response parsing logic separately.

void main() {
  group('Agents API Response Parsing', () {
    test('parses agents list response correctly', () {
      // This is the format returned by GET /api/v1/agents
      final responseData = {
        'agents': [
          {
            'id': 1,
            'name': 'Landing Page Generator',
            'description': 'Creates high-converting landing pages',
            'agent_type': 'executor',
            'interactive': true,
            'icon': 'LayoutGrid',
            'created_at': '2024-01-01T00:00:00.000Z',
          },
          {
            'id': 2,
            'name': 'Email Writer',
            'description': 'Crafts professional email campaigns',
            'agent_type': 'executor',
            'interactive': true,
            'icon': 'Mail',
            'created_at': '2024-01-02T00:00:00.000Z',
          },
        ],
      };

      final agentsList = responseData['agents'] as List;
      final agents = agentsList.map((json) => Agent.fromJson(json)).toList();

      expect(agents, hasLength(2));
      expect(agents[0].id, equals('1'));
      expect(agents[0].name, equals('Landing Page Generator'));
      expect(agents[0].agentType, equals(AgentType.executor));
      expect(agents[1].id, equals('2'));
      expect(agents[1].name, equals('Email Writer'));
    });

    test('handles empty agents list', () {
      final responseData = {'agents': []};

      final agentsList = responseData['agents'] as List;
      final agents = agentsList.map((json) => Agent.fromJson(json)).toList();

      expect(agents, isEmpty);
    });

    test('handles missing agents key with fallback', () {
      final responseData = <String, dynamic>{};

      final agentsList = responseData['agents'] as List? ?? [];
      final agents = agentsList.map((json) => Agent.fromJson(json)).toList();

      expect(agents, isEmpty);
    });
  });

  group('Agent Detail Response Parsing', () {
    test('parses single agent response', () {
      final responseData = {
        'id': 1,
        'name': 'Landing Page Generator',
        'description': 'Creates high-converting landing pages with AI',
        'agent_type': 'content_generator',
        'interactive': true,
        'icon': 'LayoutGrid',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-15T12:00:00.000Z',
        'capabilities': ['generate_content', 'optimize_seo'],
        'fields': [
          {
            'name': 'product_name',
            'question': 'What is your product name?',
            'required': true,
            'type': 'text',
          },
          {
            'name': 'target_audience',
            'question': 'Who is your target audience?',
            'required': true,
            'type': 'text',
            'examples': ['Small business owners', 'Enterprise teams'],
          },
        ],
      };

      final agent = Agent.fromJson(responseData);

      expect(agent.id, equals('1'));
      expect(agent.name, equals('Landing Page Generator'));
      expect(agent.capabilities, equals(['generate_content', 'optimize_seo']));
      expect(agent.fields, hasLength(2));
      expect(agent.fields![0].name, equals('product_name'));
      expect(agent.fields![0].required, isTrue);
      expect(agent.fields![1].examples, contains('Small business owners'));
    });
  });

  group('Agent Execution Response Parsing', () {
    test('parses execution start response', () {
      final responseData = {
        'job_id': 'exec_abc123',
        'status': 'pending',
        'message': 'Agent execution queued',
      };

      final execution = AgentExecution.fromJson(responseData);

      expect(execution.jobId, equals('exec_abc123'));
      expect(execution.status, equals(AgentExecutionStatus.pending));
    });

    test('parses execution result response', () {
      final responseData = {
        'job_id': 'exec_abc123',
        'status': 'completed',
        'result': {
          'landing_page_id': 456,
          'preview_url': 'https://example.com/preview/456',
          'content': '<html>...</html>',
        },
      };

      final execution = AgentExecution.fromJson(responseData);

      expect(execution.status, equals(AgentExecutionStatus.completed));
      expect(execution.result, isNotNull);
      expect(execution.result!['landing_page_id'], equals(456));
    });

    test('parses execution error response', () {
      final responseData = {
        'job_id': 'exec_def456',
        'status': 'failed',
        'error': 'Insufficient context provided',
      };

      final execution = AgentExecution.fromJson(responseData);

      expect(execution.status, equals(AgentExecutionStatus.failed));
      expect(execution.error, equals('Insufficient context provided'));
    });
  });

  group('Dio HTTP Client Tests', () {
    late Dio dio;
    late DioAdapter dioAdapter;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'http://192.168.4.182:3000'));
      dioAdapter = DioAdapter(dio: dio);
    });

    test('GET /api/v1/agents returns agents list', () async {
      dioAdapter.onGet(
        '/api/v1/agents',
        (server) => server.reply(200, {
          'agents': [
            {
              'id': 1,
              'name': 'Test Agent',
              'description': 'Test description',
              'agent_type': 'custom',
              'interactive': false,
              'icon': 'Bot',
              'created_at': '2024-01-01T00:00:00.000Z',
            },
          ],
        }),
      );

      final response = await dio.get('/api/v1/agents');

      expect(response.statusCode, equals(200));
      expect(response.data['agents'], hasLength(1));

      final agents = (response.data['agents'] as List)
          .map((json) => Agent.fromJson(json))
          .toList();
      expect(agents[0].name, equals('Test Agent'));
    });

    test('GET /api/v1/agents/:id returns single agent', () async {
      dioAdapter.onGet(
        '/api/v1/agents/1',
        (server) => server.reply(200, {
          'id': 1,
          'name': 'Test Agent',
          'description': 'Detailed description',
          'agent_type': 'content_generator',
          'interactive': true,
          'icon': 'Sparkles',
          'created_at': '2024-01-01T00:00:00.000Z',
          'fields': [
            {
              'name': 'topic',
              'question': 'What topic?',
              'required': true,
            },
          ],
        }),
      );

      final response = await dio.get('/api/v1/agents/1');

      expect(response.statusCode, equals(200));
      final agent = Agent.fromJson(response.data);
      expect(agent.name, equals('Test Agent'));
      expect(agent.fields, hasLength(1));
    });

    test('POST /api/v1/agents/:id/execute starts execution', () async {
      dioAdapter.onPost(
        '/api/v1/agents/1/execute',
        (server) => server.reply(202, {
          'job_id': 'exec_123',
          'status': 'pending',
          'message': 'Agent execution started',
        }),
        data: {'task': 'Create a landing page for my SaaS product'},
      );

      final response = await dio.post(
        '/api/v1/agents/1/execute',
        data: {'task': 'Create a landing page for my SaaS product'},
      );

      expect(response.statusCode, equals(202));
      expect(response.data['job_id'], equals('exec_123'));
      expect(response.data['status'], equals('pending'));
    });

    test('handles 401 unauthorized error', () async {
      dioAdapter.onGet(
        '/api/v1/agents',
        (server) => server.reply(401, {'error': 'Unauthorized'}),
      );

      expect(
        () => dio.get('/api/v1/agents'),
        throwsA(isA<DioException>()),
      );
    });

    test('handles 500 server error', () async {
      dioAdapter.onGet(
        '/api/v1/agents',
        (server) => server.reply(500, {'error': 'Internal server error'}),
      );

      expect(
        () => dio.get('/api/v1/agents'),
        throwsA(isA<DioException>()),
      );
    });

    test('handles network timeout', () async {
      dioAdapter.onGet(
        '/api/v1/agents',
        (server) => server.throws(
          0,
          DioException(
            requestOptions: RequestOptions(path: '/api/v1/agents'),
            type: DioExceptionType.connectionTimeout,
          ),
        ),
      );

      expect(
        () => dio.get('/api/v1/agents'),
        throwsA(isA<DioException>()),
      );
    });
  });
}
