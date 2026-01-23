import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/connection.dart';

void main() {
  group('Integration', () {
    test('creates with required values', () {
      final integration = Integration(
        id: '1',
        name: 'Stripe',
        slug: 'stripe',
      );

      expect(integration.id, '1');
      expect(integration.name, 'Stripe');
      expect(integration.slug, 'stripe');
      expect(integration.isActive, true);
      expect(integration.connected, false);
    });

    test('creates with all values', () {
      final integration = Integration(
        id: '2',
        name: 'HubSpot',
        slug: 'hubspot',
        icon: 'hubspot-icon',
        description: 'CRM and marketing automation',
        category: 'CRM',
        authType: 'oauth2',
        isActive: true,
        connected: true,
      );

      expect(integration.id, '2');
      expect(integration.name, 'HubSpot');
      expect(integration.slug, 'hubspot');
      expect(integration.icon, 'hubspot-icon');
      expect(integration.description, 'CRM and marketing automation');
      expect(integration.category, 'CRM');
      expect(integration.authType, 'oauth2');
      expect(integration.isActive, true);
      expect(integration.connected, true);
    });

    test('fromJson parses complete data', () {
      final json = {
        'id': 123,
        'name': 'Mailgun',
        'slug': 'mailgun',
        'icon': 'mail-icon',
        'description': 'Email delivery service',
        'category': 'Email',
        'auth_type': 'api_key',
        'is_active': true,
        'connected': false,
      };

      final integration = Integration.fromJson(json);

      expect(integration.id, '123');
      expect(integration.name, 'Mailgun');
      expect(integration.slug, 'mailgun');
      expect(integration.icon, 'mail-icon');
      expect(integration.description, 'Email delivery service');
      expect(integration.category, 'Email');
      expect(integration.authType, 'api_key');
      expect(integration.isActive, true);
      expect(integration.connected, false);
    });

    test('fromJson handles minimal data', () {
      final json = {
        'id': 1,
      };

      final integration = Integration.fromJson(json);

      expect(integration.id, '1');
      expect(integration.name, '');
      expect(integration.slug, '');
      expect(integration.icon, isNull);
      expect(integration.description, isNull);
      expect(integration.category, isNull);
      expect(integration.authType, isNull);
      expect(integration.isActive, true);
      expect(integration.connected, false);
    });

    test('fromJson handles string id', () {
      final json = {
        'id': 'abc-123',
        'name': 'Test',
        'slug': 'test',
      };

      final integration = Integration.fromJson(json);

      expect(integration.id, 'abc-123');
    });
  });

  group('ConnectionStatus', () {
    test('value getter returns correct strings', () {
      expect(ConnectionStatus.active.value, 'active');
      expect(ConnectionStatus.inactive.value, 'inactive');
      expect(ConnectionStatus.error.value, 'error');
    });

    test('fromString parses valid values', () {
      expect(ConnectionStatusX.fromString('active'), ConnectionStatus.active);
      expect(ConnectionStatusX.fromString('inactive'), ConnectionStatus.inactive);
      expect(ConnectionStatusX.fromString('error'), ConnectionStatus.error);
    });

    test('fromString handles unknown value', () {
      expect(ConnectionStatusX.fromString('unknown'), ConnectionStatus.inactive);
      expect(ConnectionStatusX.fromString(''), ConnectionStatus.inactive);
      expect(ConnectionStatusX.fromString('pending'), ConnectionStatus.inactive);
    });
  });

  group('Connection', () {
    final sampleIntegration = Integration(
      id: '1',
      name: 'Stripe',
      slug: 'stripe',
      category: 'Payments',
    );

    test('creates with required values', () {
      final now = DateTime.now();
      final connection = Connection(
        id: '1',
        name: 'My Stripe Account',
        status: ConnectionStatus.active,
        integration: sampleIntegration,
        createdAt: now,
        updatedAt: now,
      );

      expect(connection.id, '1');
      expect(connection.name, 'My Stripe Account');
      expect(connection.status, ConnectionStatus.active);
      expect(connection.integration.name, 'Stripe');
      expect(connection.lastHealthCheck, isNull);
      expect(connection.createdAt, now);
      expect(connection.updatedAt, now);
    });

    test('creates with all values', () {
      final created = DateTime(2025, 1, 1);
      final updated = DateTime(2025, 1, 15);
      final healthCheck = DateTime(2025, 1, 14);

      final connection = Connection(
        id: '2',
        name: 'Production Stripe',
        status: ConnectionStatus.active,
        integration: sampleIntegration,
        lastHealthCheck: healthCheck,
        createdAt: created,
        updatedAt: updated,
      );

      expect(connection.lastHealthCheck, healthCheck);
    });

    test('fromJson parses complete data', () {
      final json = {
        'id': 100,
        'name': 'My HubSpot',
        'status': 'active',
        'integration': {
          'id': 5,
          'name': 'HubSpot',
          'slug': 'hubspot',
          'category': 'CRM',
        },
        'last_health_check': '2025-01-15T10:30:00Z',
        'created_at': '2025-01-01T00:00:00Z',
        'updated_at': '2025-01-15T10:30:00Z',
      };

      final connection = Connection.fromJson(json);

      expect(connection.id, '100');
      expect(connection.name, 'My HubSpot');
      expect(connection.status, ConnectionStatus.active);
      expect(connection.integration.name, 'HubSpot');
      expect(connection.integration.category, 'CRM');
      expect(connection.lastHealthCheck, isNotNull);
      expect(connection.lastHealthCheck!.year, 2025);
      expect(connection.createdAt.year, 2025);
    });

    test('fromJson handles inactive status', () {
      final json = {
        'id': 1,
        'name': 'Inactive Connection',
        'status': 'inactive',
        'integration': {'id': 1, 'name': 'Test', 'slug': 'test'},
        'created_at': '2025-01-01T00:00:00Z',
        'updated_at': '2025-01-01T00:00:00Z',
      };

      final connection = Connection.fromJson(json);

      expect(connection.status, ConnectionStatus.inactive);
    });

    test('fromJson handles error status', () {
      final json = {
        'id': 1,
        'name': 'Broken Connection',
        'status': 'error',
        'integration': {'id': 1, 'name': 'Test', 'slug': 'test'},
        'created_at': '2025-01-01T00:00:00Z',
        'updated_at': '2025-01-01T00:00:00Z',
      };

      final connection = Connection.fromJson(json);

      expect(connection.status, ConnectionStatus.error);
    });

    test('fromJson handles null health check', () {
      final json = <String, dynamic>{
        'id': 1,
        'name': 'New Connection',
        'status': 'active',
        'integration': <String, dynamic>{'id': 1, 'name': 'Test', 'slug': 'test'},
        'last_health_check': null,
        'created_at': '2025-01-01T00:00:00Z',
        'updated_at': '2025-01-01T00:00:00Z',
      };

      final connection = Connection.fromJson(json);

      expect(connection.lastHealthCheck, isNull);
    });

    test('fromJson handles missing status', () {
      final json = <String, dynamic>{
        'id': 1,
        'name': 'Connection',
        'integration': <String, dynamic>{'id': 1, 'name': 'Test', 'slug': 'test'},
        'created_at': '2025-01-01T00:00:00Z',
        'updated_at': '2025-01-01T00:00:00Z',
      };

      final connection = Connection.fromJson(json);

      expect(connection.status, ConnectionStatus.inactive);
    });

    test('fromJson handles empty integration', () {
      final json = <String, dynamic>{
        'id': 1,
        'name': 'Connection',
        'status': 'active',
        'integration': <String, dynamic>{},
        'created_at': '2025-01-01T00:00:00Z',
        'updated_at': '2025-01-01T00:00:00Z',
      };

      final connection = Connection.fromJson(json);

      expect(connection.integration.name, '');
      expect(connection.integration.slug, '');
    });

    test('creates connections for different integrations', () {
      final stripeIntegration = Integration(
        id: '1',
        name: 'Stripe',
        slug: 'stripe',
        category: 'Payments',
      );

      final hubspotIntegration = Integration(
        id: '2',
        name: 'HubSpot',
        slug: 'hubspot',
        category: 'CRM',
      );

      final mailgunIntegration = Integration(
        id: '3',
        name: 'Mailgun',
        slug: 'mailgun',
        category: 'Email',
      );

      final now = DateTime.now();

      final stripeConnection = Connection(
        id: '1',
        name: 'Stripe Prod',
        status: ConnectionStatus.active,
        integration: stripeIntegration,
        createdAt: now,
        updatedAt: now,
      );

      final hubspotConnection = Connection(
        id: '2',
        name: 'HubSpot Main',
        status: ConnectionStatus.active,
        integration: hubspotIntegration,
        createdAt: now,
        updatedAt: now,
      );

      final mailgunConnection = Connection(
        id: '3',
        name: 'Mailgun Email',
        status: ConnectionStatus.error,
        integration: mailgunIntegration,
        createdAt: now,
        updatedAt: now,
      );

      expect(stripeConnection.integration.category, 'Payments');
      expect(hubspotConnection.integration.category, 'CRM');
      expect(mailgunConnection.status, ConnectionStatus.error);
    });
  });
}
