import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:amos_mobile/models/connection.dart';

// Note: ConnectionsService uses ApiClient which requires native plugins.
// For unit tests, we test the data models, query parameter building,
// and response parsing logic separately.

void main() {
  group('Integration Model', () {
    test('parses from JSON correctly', () {
      final json = {
        'id': 1,
        'name': 'Stripe',
        'slug': 'stripe',
        'icon': 'credit-card',
        'description': 'Payment processing platform',
        'category': 'payments',
        'auth_type': 'oauth2',
        'is_active': true,
        'connected': true,
      };

      final integration = Integration.fromJson(json);

      expect(integration.id, equals('1'));
      expect(integration.name, equals('Stripe'));
      expect(integration.slug, equals('stripe'));
      expect(integration.icon, equals('credit-card'));
      expect(integration.description, equals('Payment processing platform'));
      expect(integration.category, equals('payments'));
      expect(integration.authType, equals('oauth2'));
      expect(integration.isActive, isTrue);
      expect(integration.connected, isTrue);
    });

    test('handles missing optional fields', () {
      final json = {
        'id': 2,
        'name': 'HubSpot',
        'slug': 'hubspot',
      };

      final integration = Integration.fromJson(json);

      expect(integration.id, equals('2'));
      expect(integration.name, equals('HubSpot'));
      expect(integration.slug, equals('hubspot'));
      expect(integration.icon, isNull);
      expect(integration.description, isNull);
      expect(integration.category, isNull);
      expect(integration.authType, isNull);
      expect(integration.isActive, isTrue); // default
      expect(integration.connected, isFalse); // default
    });

    test('handles numeric id conversion', () {
      final json = {
        'id': 123,
        'name': 'Test',
        'slug': 'test',
      };

      final integration = Integration.fromJson(json);

      expect(integration.id, equals('123'));
    });
  });

  group('ConnectionStatus Enum', () {
    test('fromString returns correct status', () {
      expect(ConnectionStatusX.fromString('active'), equals(ConnectionStatus.active));
      expect(ConnectionStatusX.fromString('inactive'), equals(ConnectionStatus.inactive));
      expect(ConnectionStatusX.fromString('error'), equals(ConnectionStatus.error));
    });

    test('fromString returns inactive for unknown values', () {
      expect(ConnectionStatusX.fromString('unknown'), equals(ConnectionStatus.inactive));
      expect(ConnectionStatusX.fromString(''), equals(ConnectionStatus.inactive));
    });

    test('value extension returns correct string', () {
      expect(ConnectionStatus.active.value, equals('active'));
      expect(ConnectionStatus.inactive.value, equals('inactive'));
      expect(ConnectionStatus.error.value, equals('error'));
    });
  });

  group('Connection Model', () {
    test('parses from JSON correctly', () {
      final json = {
        'id': 1,
        'name': 'My Stripe Account',
        'status': 'active',
        'integration': {
          'id': 10,
          'name': 'Stripe',
          'slug': 'stripe',
          'icon': 'credit-card',
          'description': 'Payment processing',
          'category': 'payments',
          'auth_type': 'api_key',
          'is_active': true,
          'connected': true,
        },
        'last_health_check': '2024-01-15T10:30:00.000Z',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-15T10:30:00.000Z',
      };

      final connection = Connection.fromJson(json);

      expect(connection.id, equals('1'));
      expect(connection.name, equals('My Stripe Account'));
      expect(connection.status, equals(ConnectionStatus.active));
      expect(connection.integration.name, equals('Stripe'));
      expect(connection.integration.slug, equals('stripe'));
      expect(connection.lastHealthCheck, equals(DateTime.parse('2024-01-15T10:30:00.000Z')));
      expect(connection.createdAt, equals(DateTime.parse('2024-01-01T00:00:00.000Z')));
      expect(connection.updatedAt, equals(DateTime.parse('2024-01-15T10:30:00.000Z')));
    });

    test('handles missing last_health_check', () {
      final json = {
        'id': 2,
        'name': 'My HubSpot',
        'status': 'inactive',
        'integration': {
          'id': 20,
          'name': 'HubSpot',
          'slug': 'hubspot',
        },
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
      };

      final connection = Connection.fromJson(json);

      expect(connection.id, equals('2'));
      expect(connection.lastHealthCheck, isNull);
      expect(connection.status, equals(ConnectionStatus.inactive));
    });

    test('handles error status', () {
      final json = {
        'id': 3,
        'name': 'Failed Connection',
        'status': 'error',
        'integration': {
          'id': 30,
          'name': 'Mailgun',
          'slug': 'mailgun',
        },
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
      };

      final connection = Connection.fromJson(json);

      expect(connection.status, equals(ConnectionStatus.error));
    });

    test('handles empty integration object', () {
      final json = <String, dynamic>{
        'id': 4,
        'name': 'No Integration',
        'status': 'inactive',
        'integration': <String, dynamic>{},
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
      };

      final connection = Connection.fromJson(json);

      expect(connection.integration.name, equals(''));
      expect(connection.integration.slug, equals(''));
    });
  });

  group('Connections List Response Parsing', () {
    test('parses connections list response correctly', () {
      final responseData = {
        'data': [
          {
            'id': 1,
            'name': 'Stripe Connection',
            'status': 'active',
            'integration': {
              'id': 1,
              'name': 'Stripe',
              'slug': 'stripe',
            },
            'created_at': '2024-01-01T00:00:00.000Z',
            'updated_at': '2024-01-01T00:00:00.000Z',
          },
          {
            'id': 2,
            'name': 'HubSpot Connection',
            'status': 'inactive',
            'integration': {
              'id': 2,
              'name': 'HubSpot',
              'slug': 'hubspot',
            },
            'created_at': '2024-01-02T00:00:00.000Z',
            'updated_at': '2024-01-02T00:00:00.000Z',
          },
        ],
      };

      final connectionsList = responseData['data'] as List? ?? [];
      final connections = connectionsList.map((json) => Connection.fromJson(json)).toList();

      expect(connections, hasLength(2));
      expect(connections[0].id, equals('1'));
      expect(connections[0].name, equals('Stripe Connection'));
      expect(connections[0].status, equals(ConnectionStatus.active));
      expect(connections[1].id, equals('2'));
      expect(connections[1].name, equals('HubSpot Connection'));
      expect(connections[1].status, equals(ConnectionStatus.inactive));
    });

    test('handles empty connections list', () {
      final responseData = {'data': []};

      final connectionsList = responseData['data'] as List? ?? [];
      final connections = connectionsList.map((json) => Connection.fromJson(json)).toList();

      expect(connections, isEmpty);
    });

    test('handles missing data key with fallback', () {
      final responseData = <String, dynamic>{};

      final connectionsList = responseData['data'] as List? ?? [];
      final connections = connectionsList.map((json) => Connection.fromJson(json)).toList();

      expect(connections, isEmpty);
    });
  });

  group('Available Integrations Response Parsing', () {
    test('parses available integrations list', () {
      final responseData = {
        'data': [
          {
            'id': 1,
            'name': 'Stripe',
            'slug': 'stripe',
            'icon': 'credit-card',
            'description': 'Payment processing',
            'category': 'payments',
            'auth_type': 'api_key',
            'is_active': true,
            'connected': false,
          },
          {
            'id': 2,
            'name': 'HubSpot',
            'slug': 'hubspot',
            'icon': 'hubspot',
            'description': 'CRM platform',
            'category': 'crm',
            'auth_type': 'oauth2',
            'is_active': true,
            'connected': true,
          },
        ],
      };

      final integrationsList = responseData['data'] as List? ?? [];
      final integrations = integrationsList.map((json) => Integration.fromJson(json)).toList();

      expect(integrations, hasLength(2));
      expect(integrations[0].name, equals('Stripe'));
      expect(integrations[0].connected, isFalse);
      expect(integrations[1].name, equals('HubSpot'));
      expect(integrations[1].connected, isTrue);
    });
  });

  group('Test Connection Response Parsing', () {
    test('parses successful test response', () {
      final response = {
        'success': true,
        'message': 'Connection is healthy',
        'status': 'active',
      };

      final result = {
        'success': response['success'] ?? false,
        'message': response['message'] ?? '',
        'status': response['status'] ?? 'unknown',
      };

      expect(result['success'], isTrue);
      expect(result['message'], equals('Connection is healthy'));
      expect(result['status'], equals('active'));
    });

    test('parses failed test response', () {
      final response = {
        'success': false,
        'message': 'API key invalid',
        'status': 'error',
      };

      final result = {
        'success': response['success'] ?? false,
        'message': response['message'] ?? '',
        'status': response['status'] ?? 'unknown',
      };

      expect(result['success'], isFalse);
      expect(result['message'], equals('API key invalid'));
      expect(result['status'], equals('error'));
    });

    test('handles missing fields in test response', () {
      final response = <String, dynamic>{};

      final result = {
        'success': response['success'] ?? false,
        'message': response['message'] ?? '',
        'status': response['status'] ?? 'unknown',
      };

      expect(result['success'], isFalse);
      expect(result['message'], equals(''));
      expect(result['status'], equals('unknown'));
    });
  });

  group('Dio HTTP Client Tests', () {
    late Dio dio;
    late DioAdapter dioAdapter;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
      dioAdapter = DioAdapter(dio: dio);
    });

    test('GET /api/v1/connections returns connections list', () async {
      dioAdapter.onGet(
        '/api/v1/connections',
        (server) => server.reply(200, {
          'data': [
            {
              'id': 1,
              'name': 'Test Connection',
              'status': 'active',
              'integration': {
                'id': 1,
                'name': 'Stripe',
                'slug': 'stripe',
              },
              'created_at': '2024-01-01T00:00:00.000Z',
              'updated_at': '2024-01-01T00:00:00.000Z',
            },
          ],
        }),
      );

      final response = await dio.get('/api/v1/connections');

      expect(response.statusCode, equals(200));
      expect(response.data['data'], hasLength(1));

      final connections = (response.data['data'] as List)
          .map((json) => Connection.fromJson(json))
          .toList();
      expect(connections[0].name, equals('Test Connection'));
    });

    test('GET /api/v1/connections/:id returns single connection', () async {
      dioAdapter.onGet(
        '/api/v1/connections/1',
        (server) => server.reply(200, {
          'id': 1,
          'name': 'Stripe Production',
          'status': 'active',
          'integration': {
            'id': 1,
            'name': 'Stripe',
            'slug': 'stripe',
          },
          'last_health_check': '2024-01-15T10:30:00.000Z',
          'created_at': '2024-01-01T00:00:00.000Z',
          'updated_at': '2024-01-15T10:30:00.000Z',
        }),
      );

      final response = await dio.get('/api/v1/connections/1');

      expect(response.statusCode, equals(200));
      final connection = Connection.fromJson(response.data);
      expect(connection.name, equals('Stripe Production'));
      expect(connection.status, equals(ConnectionStatus.active));
    });

    test('POST /api/v1/connections/:id/test tests connection', () async {
      dioAdapter.onPost(
        '/api/v1/connections/1/test',
        (server) => server.reply(200, {
          'success': true,
          'message': 'Connection is healthy',
          'status': 'active',
        }),
      );

      final response = await dio.post('/api/v1/connections/1/test');

      expect(response.statusCode, equals(200));
      expect(response.data['success'], isTrue);
      expect(response.data['message'], equals('Connection is healthy'));
    });

    test('DELETE /api/v1/connections/:id deletes connection', () async {
      dioAdapter.onDelete(
        '/api/v1/connections/1',
        (server) => server.reply(204, null),
      );

      final response = await dio.delete('/api/v1/connections/1');

      expect(response.statusCode, equals(204));
    });

    test('GET /api/v1/connections/available returns integrations', () async {
      dioAdapter.onGet(
        '/api/v1/connections/available',
        (server) => server.reply(200, {
          'data': [
            {
              'id': 1,
              'name': 'Stripe',
              'slug': 'stripe',
              'icon': 'credit-card',
              'category': 'payments',
              'connected': false,
            },
          ],
        }),
      );

      final response = await dio.get('/api/v1/connections/available');

      expect(response.statusCode, equals(200));
      final integrations = (response.data['data'] as List)
          .map((json) => Integration.fromJson(json))
          .toList();
      expect(integrations[0].name, equals('Stripe'));
      expect(integrations[0].connected, isFalse);
    });

    test('handles 401 unauthorized error', () async {
      dioAdapter.onGet(
        '/api/v1/connections',
        (server) => server.reply(401, {'error': 'Unauthorized'}),
      );

      expect(
        () => dio.get('/api/v1/connections'),
        throwsA(isA<DioException>()),
      );
    });

    test('handles 404 not found error', () async {
      dioAdapter.onGet(
        '/api/v1/connections/999',
        (server) => server.reply(404, {'error': 'Connection not found'}),
      );

      expect(
        () => dio.get('/api/v1/connections/999'),
        throwsA(isA<DioException>()),
      );
    });
  });
}
