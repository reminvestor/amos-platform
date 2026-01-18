import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/contact.dart';

void main() {
  group('ContactStatus', () {
    test('value returns correct string', () {
      expect(ContactStatus.active.value, equals('active'));
      expect(ContactStatus.inactive.value, equals('inactive'));
      expect(ContactStatus.unsubscribed.value, equals('unsubscribed'));
    });

    test('fromString converts string to enum correctly', () {
      expect(ContactStatusX.fromString('active'), equals(ContactStatus.active));
      expect(ContactStatusX.fromString('inactive'), equals(ContactStatus.inactive));
      expect(ContactStatusX.fromString('unsubscribed'), equals(ContactStatus.unsubscribed));
    });

    test('fromString returns active for unknown values', () {
      expect(ContactStatusX.fromString('unknown'), equals(ContactStatus.active));
      expect(ContactStatusX.fromString(''), equals(ContactStatus.active));
    });
  });

  group('Contact', () {
    test('fromJson parses complete JSON correctly', () {
      final json = {
        'id': 1,
        'entity_id': '123',
        'email': 'test@example.com',
        'status': 'active',
        'metadata': {'source': 'api'},
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-16T11:00:00.000Z',
        'name': 'John Doe',
        'first_name': 'John',
        'last_name': 'Doe',
        'phone': '+1234567890',
        'company': 'ACME Inc',
        'tags': ['customer', 'vip'],
        'groups': [
          {'id': '1', 'name': 'VIP Customers'}
        ],
      };

      final contact = Contact.fromJson(json);

      expect(contact.id, equals('1'));
      expect(contact.entityId, equals('123'));
      expect(contact.email, equals('test@example.com'));
      expect(contact.status, equals(ContactStatus.active));
      expect(contact.metadata, equals({'source': 'api'}));
      expect(contact.createdAt, equals(DateTime.parse('2024-01-15T10:30:00.000Z')));
      expect(contact.name, equals('John Doe'));
      expect(contact.firstName, equals('John'));
      expect(contact.lastName, equals('Doe'));
      expect(contact.phone, equals('+1234567890'));
      expect(contact.company, equals('ACME Inc'));
      expect(contact.tags, equals(['customer', 'vip']));
      expect(contact.groups, isNotNull);
      expect(contact.groups!.length, equals(1));
    });

    test('fromJson handles tags as comma-separated string', () {
      final json = {
        'id': '123',
        'email': 'test@example.com',
        'status': 'active',
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-16T11:00:00.000Z',
        'tags': 'customer, vip, premium',
      };

      final contact = Contact.fromJson(json);

      expect(contact.tags, equals(['customer', 'vip', 'premium']));
    });

    test('fromJson handles empty tags string', () {
      final json = {
        'id': '123',
        'email': 'test@example.com',
        'status': 'active',
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-16T11:00:00.000Z',
        'tags': '',
      };

      final contact = Contact.fromJson(json);

      expect(contact.tags, isEmpty);
    });

    test('fromJson handles minimal required fields', () {
      final json = {
        'id': '123',
        'email': 'test@example.com',
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-16T11:00:00.000Z',
      };

      final contact = Contact.fromJson(json);

      expect(contact.id, equals('123'));
      expect(contact.email, equals('test@example.com'));
      expect(contact.status, equals(ContactStatus.active));
      expect(contact.name, isNull);
      expect(contact.tags, isNull);
      expect(contact.groups, isNull);
    });

    test('displayName returns name when available', () {
      final contact = Contact(
        id: '123',
        email: 'test@example.com',
        status: ContactStatus.active,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        name: 'John Doe',
        firstName: 'John',
      );

      expect(contact.displayName, equals('John Doe'));
    });

    test('displayName returns firstName when name is null', () {
      final contact = Contact(
        id: '123',
        email: 'test@example.com',
        status: ContactStatus.active,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        firstName: 'John',
      );

      expect(contact.displayName, equals('John'));
    });

    test('displayName returns email prefix when name and firstName are null', () {
      final contact = Contact(
        id: '123',
        email: 'johndoe@example.com',
        status: ContactStatus.active,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(contact.displayName, equals('johndoe'));
    });

    test('initials returns two letters for full name', () {
      final contact = Contact(
        id: '123',
        email: 'test@example.com',
        status: ContactStatus.active,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        name: 'John Doe',
      );

      expect(contact.initials, equals('JD'));
    });

    test('initials returns single letter for single name', () {
      final contact = Contact(
        id: '123',
        email: 'test@example.com',
        status: ContactStatus.active,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        name: 'John',
      );

      expect(contact.initials, equals('J'));
    });

    test('initials returns email first letter when name is null', () {
      final contact = Contact(
        id: '123',
        email: 'test@example.com',
        status: ContactStatus.active,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(contact.initials, equals('T'));
    });

    test('toJson serializes correctly', () {
      final contact = Contact(
        id: '123',
        entityId: '456',
        email: 'test@example.com',
        status: ContactStatus.active,
        metadata: {'source': 'api'},
        createdAt: DateTime.parse('2024-01-15T10:30:00.000Z'),
        updatedAt: DateTime.parse('2024-01-16T11:00:00.000Z'),
        name: 'John Doe',
        company: 'ACME Inc',
      );

      final json = contact.toJson();

      expect(json['id'], equals('123'));
      expect(json['entity_id'], equals('456'));
      expect(json['email'], equals('test@example.com'));
      expect(json['status'], equals('active'));
      expect(json['metadata'], equals({'source': 'api'}));
      expect(json['name'], equals('John Doe'));
      expect(json['company'], equals('ACME Inc'));
    });

    test('toJson excludes null optional fields', () {
      final contact = Contact(
        id: '123',
        email: 'test@example.com',
        status: ContactStatus.active,
        createdAt: DateTime.parse('2024-01-15T10:30:00.000Z'),
        updatedAt: DateTime.parse('2024-01-16T11:00:00.000Z'),
      );

      final json = contact.toJson();

      expect(json.containsKey('metadata'), isFalse);
      expect(json.containsKey('name'), isFalse);
      expect(json.containsKey('company'), isFalse);
    });
  });

  group('ContactGroup', () {
    test('fromJson parses complete JSON correctly', () {
      final json = {
        'id': '123',
        'entity_id': '456',
        'name': 'VIP Customers',
        'description': 'Our most valued customers',
        'contact_count': 150,
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-16T11:00:00.000Z',
      };

      final group = ContactGroup.fromJson(json);

      expect(group.id, equals('123'));
      expect(group.entityId, equals('456'));
      expect(group.name, equals('VIP Customers'));
      expect(group.description, equals('Our most valued customers'));
      expect(group.contactCount, equals(150));
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'id': '123',
        'entity_id': '456',
        'name': 'Test Group',
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-16T11:00:00.000Z',
      };

      final group = ContactGroup.fromJson(json);

      expect(group.description, isNull);
      expect(group.contactCount, isNull);
    });

    test('toJson serializes correctly', () {
      final group = ContactGroup(
        id: '123',
        entityId: '456',
        name: 'VIP Customers',
        description: 'Our most valued customers',
        contactCount: 150,
        createdAt: DateTime.parse('2024-01-15T10:30:00.000Z'),
        updatedAt: DateTime.parse('2024-01-16T11:00:00.000Z'),
      );

      final json = group.toJson();

      expect(json['id'], equals('123'));
      expect(json['entity_id'], equals('456'));
      expect(json['name'], equals('VIP Customers'));
      expect(json['description'], equals('Our most valued customers'));
      expect(json['contact_count'], equals(150));
    });

    test('toJson excludes null optional fields', () {
      final group = ContactGroup(
        id: '123',
        entityId: '456',
        name: 'Test Group',
        createdAt: DateTime.parse('2024-01-15T10:30:00.000Z'),
        updatedAt: DateTime.parse('2024-01-16T11:00:00.000Z'),
      );

      final json = group.toJson();

      expect(json.containsKey('description'), isFalse);
      expect(json.containsKey('contact_count'), isFalse);
    });
  });
}
