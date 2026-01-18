import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/connection.dart';

void main() {
  group('Integration', () {
    test('fromJson parses complete JSON correctly', () {
      final json = {
        'id': 1,
        'name': 'Stripe',
        'slug': 'stripe',
        'icon': 'stripe-icon',
        'description': 'Payment processing',
        'category': 'payments',
        'auth_type': 'api_key',
        'is_active': true,
        'connected': true,
      };

      final integration = Integration.fromJson(json);

      expect(integration.id, equals('1'));
      expect(integration.name, equals('Stripe'));
      expect(integration.slug, equals('stripe'));
      expect(integration.icon, equals('stripe-icon'));
      expect(integration.description, equals('Payment processing'));
      expect(integration.category, equals('payments'));
      expect(integration.authType, equals('api_key'));
      expect(integration.isActive, isTrue);
      expect(integration.connected, isTrue);
    });

    test('fromJson handles minimal required fields with defaults', () {
      final json = {
        'id': '123',
      };

      final integration = Integration.fromJson(json);

      expect(integration.id, equals('123'));
      expect(integration.name, equals(''));
      expect(integration.slug, equals(''));
      expect(integration.icon, isNull);
      expect(integration.description, isNull);
      expect(integration.category, isNull);
      expect(integration.authType, isNull);
      expect(integration.isActive, isTrue);
      expect(integration.connected, isFalse);
    });
  });

  group('ConnectionStatus', () {
    test('value returns correct string', () {
      expect(ConnectionStatus.active.value, equals('active'));
      expect(ConnectionStatus.inactive.value, equals('inactive'));
      expect(ConnectionStatus.error.value, equals('error'));
    });

    test('fromString converts string to enum correctly', () {
      expect(ConnectionStatusX.fromString('active'), equals(ConnectionStatus.active));
      expect(ConnectionStatusX.fromString('inactive'), equals(ConnectionStatus.inactive));
      expect(ConnectionStatusX.fromString('error'), equals(ConnectionStatus.error));
    });

    test('fromString returns inactive for unknown values', () {
      expect(ConnectionStatusX.fromString('unknown'), equals(ConnectionStatus.inactive));
      expect(ConnectionStatusX.fromString(''), equals(ConnectionStatus.inactive));
    });
  });

  group('Connection', () {
    test('fromJson parses complete JSON correctly', () {
      final json = {
        'id': 1,
        'name': 'My Stripe Connection',
        'status': 'active',
        'integration': {
          'id': '100',
          'name': 'Stripe',
          'slug': 'stripe',
          'category': 'payments',
        },
        'last_health_check': '2024-01-15T12:00:00.000Z',
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-16T11:00:00.000Z',
      };

      final connection = Connection.fromJson(json);

      expect(connection.id, equals('1'));
      expect(connection.name, equals('My Stripe Connection'));
      expect(connection.status, equals(ConnectionStatus.active));
      expect(connection.integration.name, equals('Stripe'));
      expect(connection.integration.slug, equals('stripe'));
      expect(connection.lastHealthCheck, equals(DateTime.parse('2024-01-15T12:00:00.000Z')));
      expect(connection.createdAt, equals(DateTime.parse('2024-01-15T10:30:00.000Z')));
      expect(connection.updatedAt, equals(DateTime.parse('2024-01-16T11:00:00.000Z')));
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'id': '123',
        'name': 'Test Connection',
        'integration': {'id': '1', 'name': 'Test', 'slug': 'test'},
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-16T11:00:00.000Z',
      };

      final connection = Connection.fromJson(json);

      expect(connection.id, equals('123'));
      expect(connection.status, equals(ConnectionStatus.inactive));
      expect(connection.lastHealthCheck, isNull);
    });

    test('fromJson handles missing integration with empty object', () {
      final json = {
        'id': '123',
        'name': 'Test Connection',
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-16T11:00:00.000Z',
      };

      final connection = Connection.fromJson(json);

      expect(connection.integration.name, equals(''));
      expect(connection.integration.slug, equals(''));
    });

    test('fromJson handles error status', () {
      final json = {
        'id': '123',
        'name': 'Broken Connection',
        'status': 'error',
        'integration': {'id': '1', 'name': 'Test', 'slug': 'test'},
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-16T11:00:00.000Z',
      };

      final connection = Connection.fromJson(json);

      expect(connection.status, equals(ConnectionStatus.error));
    });
  });
}
