import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/contact_group.dart';

void main() {
  group('ContactGroup', () {
    test('fromJson parses complete JSON correctly', () {
      final json = {
        'id': 1,
        'name': 'VIP Customers',
        'description': 'Our most valuable customers',
        'contacts_count': 150,
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-16T11:00:00.000Z',
      };

      final group = ContactGroup.fromJson(json);

      expect(group.id, equals('1'));
      expect(group.name, equals('VIP Customers'));
      expect(group.description, equals('Our most valuable customers'));
      expect(group.contactsCount, equals(150));
      expect(group.createdAt, equals(DateTime.parse('2024-01-15T10:30:00.000Z')));
      expect(group.updatedAt, equals(DateTime.parse('2024-01-16T11:00:00.000Z')));
    });

    test('fromJson handles string id', () {
      final json = {
        'id': '123',
        'name': 'Test Group',
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-16T11:00:00.000Z',
      };

      final group = ContactGroup.fromJson(json);

      expect(group.id, equals('123'));
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'id': 1,
        'name': 'Simple Group',
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-16T11:00:00.000Z',
      };

      final group = ContactGroup.fromJson(json);

      expect(group.name, equals('Simple Group'));
      expect(group.description, isNull);
      expect(group.contactsCount, equals(0));
    });

    test('fromJson handles missing name with default', () {
      final json = {
        'id': 1,
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-16T11:00:00.000Z',
      };

      final group = ContactGroup.fromJson(json);

      expect(group.name, equals(''));
    });

    test('toJson serializes correctly', () {
      final group = ContactGroup(
        id: '123',
        name: 'Test Group',
        description: 'A test group',
        contactsCount: 50,
        createdAt: DateTime.parse('2024-01-15T10:30:00.000Z'),
        updatedAt: DateTime.parse('2024-01-16T11:00:00.000Z'),
      );

      final json = group.toJson();

      expect(json['id'], equals('123'));
      expect(json['name'], equals('Test Group'));
      expect(json['description'], equals('A test group'));
      expect(json['contacts_count'], equals(50));
      expect(json['created_at'], equals('2024-01-15T10:30:00.000Z'));
      expect(json['updated_at'], equals('2024-01-16T11:00:00.000Z'));
    });

    test('toJson excludes null description', () {
      final group = ContactGroup(
        id: '123',
        name: 'Test Group',
        createdAt: DateTime.parse('2024-01-15T10:30:00.000Z'),
        updatedAt: DateTime.parse('2024-01-16T11:00:00.000Z'),
      );

      final json = group.toJson();

      expect(json.containsKey('description'), isFalse);
    });

    test('default contactsCount is 0', () {
      final group = ContactGroup(
        id: '123',
        name: 'Test Group',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(group.contactsCount, equals(0));
    });
  });
}
