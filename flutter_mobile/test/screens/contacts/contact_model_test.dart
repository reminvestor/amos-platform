import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/contact.dart';

// Note: These tests focus on the Contact model and ContactStatus enum
// used by the contact screens. Widget tests are avoided due to async initState complexity.

void main() {
  group('ContactStatus Enum', () {
    test('value property returns correct string for each status', () {
      expect(ContactStatus.active.value, equals('active'));
      expect(ContactStatus.inactive.value, equals('inactive'));
      expect(ContactStatus.unsubscribed.value, equals('unsubscribed'));
    });

    test('fromString converts valid string to enum correctly', () {
      expect(ContactStatusX.fromString('active'), equals(ContactStatus.active));
      expect(ContactStatusX.fromString('inactive'), equals(ContactStatus.inactive));
      expect(ContactStatusX.fromString('unsubscribed'), equals(ContactStatus.unsubscribed));
    });

    test('fromString returns active as default for unknown values', () {
      expect(ContactStatusX.fromString('unknown'), equals(ContactStatus.active));
      expect(ContactStatusX.fromString(''), equals(ContactStatus.active));
      expect(ContactStatusX.fromString('ACTIVE'), equals(ContactStatus.active)); // case sensitive
      expect(ContactStatusX.fromString('deleted'), equals(ContactStatus.active));
    });

    test('enum values length is correct', () {
      expect(ContactStatus.values.length, equals(3));
    });
  });

  group('Contact Model - fromJson', () {
    test('parses complete JSON with all fields correctly', () {
      final json = {
        'id': 42,
        'entity_id': 'entity-123',
        'email': 'john.doe@example.com',
        'status': 'active',
        'metadata': {'source': 'import', 'campaign': 'newsletter'},
        'created_at': '2024-06-15T09:30:00.000Z',
        'updated_at': '2024-06-20T14:45:00.000Z',
        'name': 'John Doe',
        'first_name': 'John',
        'last_name': 'Doe',
        'phone': '+1-555-123-4567',
        'company': 'Acme Corporation',
        'tags': ['customer', 'premium', 'newsletter'],
        'groups': [
          {'id': 'group-1', 'name': 'Premium Customers'},
          {'id': 'group-2', 'name': 'Newsletter Subscribers'},
        ],
      };

      final contact = Contact.fromJson(json);

      expect(contact.id, equals('42'));
      expect(contact.entityId, equals('entity-123'));
      expect(contact.email, equals('john.doe@example.com'));
      expect(contact.status, equals(ContactStatus.active));
      expect(contact.metadata, equals({'source': 'import', 'campaign': 'newsletter'}));
      expect(contact.createdAt, equals(DateTime.parse('2024-06-15T09:30:00.000Z')));
      expect(contact.updatedAt, equals(DateTime.parse('2024-06-20T14:45:00.000Z')));
      expect(contact.name, equals('John Doe'));
      expect(contact.firstName, equals('John'));
      expect(contact.lastName, equals('Doe'));
      expect(contact.phone, equals('+1-555-123-4567'));
      expect(contact.company, equals('Acme Corporation'));
      expect(contact.tags, equals(['customer', 'premium', 'newsletter']));
      expect(contact.groups, isNotNull);
      expect(contact.groups!.length, equals(2));
    });

    test('converts integer id to string', () {
      final json = {
        'id': 12345,
        'email': 'test@example.com',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
      };

      final contact = Contact.fromJson(json);
      expect(contact.id, equals('12345'));
    });

    test('handles string id directly', () {
      final json = {
        'id': 'uuid-contact-123',
        'email': 'test@example.com',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
      };

      final contact = Contact.fromJson(json);
      expect(contact.id, equals('uuid-contact-123'));
    });

    test('parses tags as List correctly', () {
      final json = {
        'id': '1',
        'email': 'test@example.com',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
        'tags': ['tag1', 'tag2', 'tag3'],
      };

      final contact = Contact.fromJson(json);
      expect(contact.tags, equals(['tag1', 'tag2', 'tag3']));
    });

    test('parses tags as comma-separated string correctly', () {
      final json = {
        'id': '1',
        'email': 'test@example.com',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
        'tags': 'customer, vip, newsletter',
      };

      final contact = Contact.fromJson(json);
      expect(contact.tags, equals(['customer', 'vip', 'newsletter']));
    });

    test('handles tags string with extra whitespace', () {
      final json = {
        'id': '1',
        'email': 'test@example.com',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
        'tags': '  premium  ,   vip   ,  loyal  ',
      };

      final contact = Contact.fromJson(json);
      expect(contact.tags, equals(['premium', 'vip', 'loyal']));
    });

    test('handles empty tags string', () {
      final json = {
        'id': '1',
        'email': 'test@example.com',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
        'tags': '',
      };

      final contact = Contact.fromJson(json);
      expect(contact.tags, isEmpty);
    });

    test('handles null tags', () {
      final json = {
        'id': '1',
        'email': 'test@example.com',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
        'tags': null,
      };

      final contact = Contact.fromJson(json);
      expect(contact.tags, isNull);
    });

    test('handles minimal required fields', () {
      final json = {
        'id': '1',
        'email': 'minimal@example.com',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
      };

      final contact = Contact.fromJson(json);

      expect(contact.id, equals('1'));
      expect(contact.email, equals('minimal@example.com'));
      expect(contact.status, equals(ContactStatus.active)); // default
      expect(contact.entityId, isNull);
      expect(contact.name, isNull);
      expect(contact.firstName, isNull);
      expect(contact.lastName, isNull);
      expect(contact.phone, isNull);
      expect(contact.company, isNull);
      expect(contact.tags, isNull);
      expect(contact.groups, isNull);
      expect(contact.metadata, isNull);
    });

    test('handles missing email with empty string default', () {
      final json = {
        'id': '1',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
      };

      final contact = Contact.fromJson(json);
      expect(contact.email, equals(''));
    });

    test('parses inactive status correctly', () {
      final json = {
        'id': '1',
        'email': 'test@example.com',
        'status': 'inactive',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
      };

      final contact = Contact.fromJson(json);
      expect(contact.status, equals(ContactStatus.inactive));
    });

    test('parses unsubscribed status correctly', () {
      final json = {
        'id': '1',
        'email': 'test@example.com',
        'status': 'unsubscribed',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
      };

      final contact = Contact.fromJson(json);
      expect(contact.status, equals(ContactStatus.unsubscribed));
    });
  });

  group('Contact Model - displayName', () {
    test('returns name when available', () {
      final contact = Contact(
        id: '1',
        email: 'john@example.com',
        status: ContactStatus.active,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        name: 'John Smith',
        firstName: 'John',
      );

      expect(contact.displayName, equals('John Smith'));
    });

    test('returns firstName when name is null', () {
      final contact = Contact(
        id: '1',
        email: 'john@example.com',
        status: ContactStatus.active,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        firstName: 'John',
      );

      expect(contact.displayName, equals('John'));
    });

    test('returns email prefix when both name and firstName are null', () {
      final contact = Contact(
        id: '1',
        email: 'johnsmith@example.com',
        status: ContactStatus.active,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(contact.displayName, equals('johnsmith'));
    });

    test('handles email with subdomain prefix', () {
      final contact = Contact(
        id: '1',
        email: 'user.name@subdomain.example.com',
        status: ContactStatus.active,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(contact.displayName, equals('user.name'));
    });

    test('prefers name over firstName even when both are present', () {
      final contact = Contact(
        id: '1',
        email: 'test@example.com',
        status: ContactStatus.active,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        name: 'Full Name Here',
        firstName: 'First',
      );

      expect(contact.displayName, equals('Full Name Here'));
    });
  });

  group('Contact Model - initials', () {
    test('returns two letters for full name with two parts', () {
      final contact = Contact(
        id: '1',
        email: 'test@example.com',
        status: ContactStatus.active,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        name: 'John Doe',
      );

      expect(contact.initials, equals('JD'));
    });

    test('returns two letters for full name with multiple parts (first and last)', () {
      final contact = Contact(
        id: '1',
        email: 'test@example.com',
        status: ContactStatus.active,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        name: 'John Michael Doe',
      );

      expect(contact.initials, equals('JD'));
    });

    test('returns single letter for single word name', () {
      final contact = Contact(
        id: '1',
        email: 'test@example.com',
        status: ContactStatus.active,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        name: 'John',
      );

      expect(contact.initials, equals('J'));
    });

    test('returns email first letter when name is null', () {
      final contact = Contact(
        id: '1',
        email: 'test@example.com',
        status: ContactStatus.active,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(contact.initials, equals('T'));
    });

    test('returns email first letter when name is empty', () {
      final contact = Contact(
        id: '1',
        email: 'alice@example.com',
        status: ContactStatus.active,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        name: '',
      );

      expect(contact.initials, equals('A'));
    });

    test('initials are uppercase', () {
      final contact = Contact(
        id: '1',
        email: 'test@example.com',
        status: ContactStatus.active,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        name: 'alice wonderland',
      );

      expect(contact.initials, equals('AW'));
    });

    test('handles name with lowercase letters', () {
      final contact = Contact(
        id: '1',
        email: 'test@example.com',
        status: ContactStatus.active,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        name: 'bob smith',
      );

      expect(contact.initials, equals('BS'));
    });
  });

  group('Contact Model - toJson', () {
    test('serializes all required fields correctly', () {
      final createdAt = DateTime.parse('2024-06-15T09:30:00.000Z');
      final updatedAt = DateTime.parse('2024-06-20T14:45:00.000Z');

      final contact = Contact(
        id: '123',
        email: 'test@example.com',
        status: ContactStatus.active,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      final json = contact.toJson();

      expect(json['id'], equals('123'));
      expect(json['email'], equals('test@example.com'));
      expect(json['status'], equals('active'));
      expect(json['created_at'], equals('2024-06-15T09:30:00.000Z'));
      expect(json['updated_at'], equals('2024-06-20T14:45:00.000Z'));
    });

    test('serializes optional fields when present', () {
      final contact = Contact(
        id: '123',
        entityId: 'entity-456',
        email: 'test@example.com',
        status: ContactStatus.inactive,
        metadata: {'source': 'import'},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        name: 'Test User',
        company: 'Test Corp',
      );

      final json = contact.toJson();

      expect(json['entity_id'], equals('entity-456'));
      expect(json['status'], equals('inactive'));
      expect(json['metadata'], equals({'source': 'import'}));
      expect(json['name'], equals('Test User'));
      expect(json['company'], equals('Test Corp'));
    });

    test('excludes null optional fields except entity_id', () {
      final contact = Contact(
        id: '123',
        email: 'test@example.com',
        status: ContactStatus.active,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final json = contact.toJson();

      // entity_id is always included (even when null)
      expect(json.containsKey('entity_id'), isTrue);
      expect(json['entity_id'], isNull);
      // These optional fields are excluded when null
      expect(json.containsKey('metadata'), isFalse);
      expect(json.containsKey('name'), isFalse);
      expect(json.containsKey('company'), isFalse);
    });

    test('serializes unsubscribed status correctly', () {
      final contact = Contact(
        id: '123',
        email: 'test@example.com',
        status: ContactStatus.unsubscribed,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final json = contact.toJson();
      expect(json['status'], equals('unsubscribed'));
    });
  });

  group('Contact Model - roundtrip', () {
    test('fromJson and toJson are consistent for basic fields', () {
      final originalJson = {
        'id': '123',
        'entity_id': '456',
        'email': 'roundtrip@example.com',
        'status': 'inactive',
        'metadata': {'key': 'value'},
        'created_at': '2024-06-15T09:30:00.000Z',
        'updated_at': '2024-06-20T14:45:00.000Z',
        'name': 'Roundtrip Test',
        'company': 'Test Company',
      };

      final contact = Contact.fromJson(originalJson);
      final resultJson = contact.toJson();

      expect(resultJson['id'], equals(originalJson['id']));
      expect(resultJson['entity_id'], equals(originalJson['entity_id']));
      expect(resultJson['email'], equals(originalJson['email']));
      expect(resultJson['status'], equals(originalJson['status']));
      expect(resultJson['metadata'], equals(originalJson['metadata']));
      expect(resultJson['name'], equals(originalJson['name']));
      expect(resultJson['company'], equals(originalJson['company']));
    });
  });

  group('Contact List Screen Data Patterns', () {
    test('status filter values used in contact list screen', () {
      // These are typical filter options for contact list screens
      const statusFilters = ['all', 'active', 'inactive', 'unsubscribed'];
      expect(statusFilters.length, equals(4));
      expect(statusFilters, contains('all'));
      expect(statusFilters, contains('active'));
    });

    test('contacts can be sorted by display name', () {
      final contacts = [
        Contact(
          id: '1',
          email: 'zoe@example.com',
          status: ContactStatus.active,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          name: 'Zoe Adams',
        ),
        Contact(
          id: '2',
          email: 'alice@example.com',
          status: ContactStatus.active,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          name: 'Alice Brown',
        ),
        Contact(
          id: '3',
          email: 'bob@example.com',
          status: ContactStatus.active,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          name: 'Bob Clark',
        ),
      ];

      contacts.sort((a, b) => a.displayName.compareTo(b.displayName));

      expect(contacts[0].displayName, equals('Alice Brown'));
      expect(contacts[1].displayName, equals('Bob Clark'));
      expect(contacts[2].displayName, equals('Zoe Adams'));
    });

    test('contacts can be filtered by status', () {
      final contacts = [
        Contact(
          id: '1',
          email: 'active1@example.com',
          status: ContactStatus.active,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        Contact(
          id: '2',
          email: 'inactive@example.com',
          status: ContactStatus.inactive,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        Contact(
          id: '3',
          email: 'active2@example.com',
          status: ContactStatus.active,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

      final activeContacts =
          contacts.where((c) => c.status == ContactStatus.active).toList();

      expect(activeContacts.length, equals(2));
      expect(activeContacts.every((c) => c.status == ContactStatus.active), isTrue);
    });
  });
}
