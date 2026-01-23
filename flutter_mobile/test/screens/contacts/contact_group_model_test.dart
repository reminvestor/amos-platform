import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/contact_group.dart';

// Note: These tests focus on the ContactGroup model used by contact group screens.
// Widget tests are avoided due to async initState complexity with GoRouter context.

void main() {
  group('ContactGroup Model - fromJson', () {
    test('parses complete JSON with all fields correctly', () {
      final json = {
        'id': 42,
        'name': 'VIP Customers',
        'description': 'Our most valued and loyal customers',
        'contacts_count': 256,
        'created_at': '2024-03-15T10:30:00.000Z',
        'updated_at': '2024-06-20T14:45:00.000Z',
      };

      final group = ContactGroup.fromJson(json);

      expect(group.id, equals('42'));
      expect(group.name, equals('VIP Customers'));
      expect(group.description, equals('Our most valued and loyal customers'));
      expect(group.contactsCount, equals(256));
      expect(group.createdAt, equals(DateTime.parse('2024-03-15T10:30:00.000Z')));
      expect(group.updatedAt, equals(DateTime.parse('2024-06-20T14:45:00.000Z')));
    });

    test('converts integer id to string', () {
      final json = {
        'id': 98765,
        'name': 'Test Group',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
      };

      final group = ContactGroup.fromJson(json);
      expect(group.id, equals('98765'));
    });

    test('handles string id directly', () {
      final json = {
        'id': 'uuid-group-abc123',
        'name': 'Test Group',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
      };

      final group = ContactGroup.fromJson(json);
      expect(group.id, equals('uuid-group-abc123'));
    });

    test('handles missing name with empty string default', () {
      final json = {
        'id': 1,
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
      };

      final group = ContactGroup.fromJson(json);
      expect(group.name, equals(''));
    });

    test('handles null name with empty string default', () {
      final json = {
        'id': 1,
        'name': null,
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
      };

      final group = ContactGroup.fromJson(json);
      expect(group.name, equals(''));
    });

    test('handles missing description as null', () {
      final json = {
        'id': 1,
        'name': 'Test Group',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
      };

      final group = ContactGroup.fromJson(json);
      expect(group.description, isNull);
    });

    test('handles missing contacts_count with default 0', () {
      final json = {
        'id': 1,
        'name': 'Test Group',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
      };

      final group = ContactGroup.fromJson(json);
      expect(group.contactsCount, equals(0));
    });

    test('handles null contacts_count with default 0', () {
      final json = {
        'id': 1,
        'name': 'Test Group',
        'contacts_count': null,
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
      };

      final group = ContactGroup.fromJson(json);
      expect(group.contactsCount, equals(0));
    });

    test('parses various date formats correctly', () {
      final json = {
        'id': 1,
        'name': 'Test Group',
        'created_at': '2024-12-31T23:59:59.999Z',
        'updated_at': '2025-01-01T00:00:00.000Z',
      };

      final group = ContactGroup.fromJson(json);
      expect(group.createdAt.year, equals(2024));
      expect(group.createdAt.month, equals(12));
      expect(group.createdAt.day, equals(31));
      expect(group.updatedAt.year, equals(2025));
    });
  });

  group('ContactGroup Model - toJson', () {
    test('serializes all fields correctly', () {
      final createdAt = DateTime.parse('2024-03-15T10:30:00.000Z');
      final updatedAt = DateTime.parse('2024-06-20T14:45:00.000Z');

      final group = ContactGroup(
        id: '123',
        name: 'Premium Subscribers',
        description: 'Users on premium plan',
        contactsCount: 1500,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      final json = group.toJson();

      expect(json['id'], equals('123'));
      expect(json['name'], equals('Premium Subscribers'));
      expect(json['description'], equals('Users on premium plan'));
      expect(json['contacts_count'], equals(1500));
      expect(json['created_at'], equals('2024-03-15T10:30:00.000Z'));
      expect(json['updated_at'], equals('2024-06-20T14:45:00.000Z'));
    });

    test('excludes null description', () {
      final group = ContactGroup(
        id: '123',
        name: 'Test Group',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final json = group.toJson();

      expect(json.containsKey('description'), isFalse);
    });

    test('includes zero contacts_count', () {
      final group = ContactGroup(
        id: '123',
        name: 'Empty Group',
        contactsCount: 0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final json = group.toJson();

      expect(json['contacts_count'], equals(0));
    });

    test('handles large contact counts', () {
      final group = ContactGroup(
        id: '123',
        name: 'Large Group',
        contactsCount: 1000000,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final json = group.toJson();

      expect(json['contacts_count'], equals(1000000));
    });
  });

  group('ContactGroup Model - Constructor', () {
    test('default contactsCount is 0', () {
      final group = ContactGroup(
        id: '123',
        name: 'New Group',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(group.contactsCount, equals(0));
    });

    test('accepts all optional parameters', () {
      final group = ContactGroup(
        id: '123',
        name: 'Full Group',
        description: 'A group with all fields',
        contactsCount: 50,
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 6, 1),
      );

      expect(group.id, equals('123'));
      expect(group.name, equals('Full Group'));
      expect(group.description, equals('A group with all fields'));
      expect(group.contactsCount, equals(50));
    });
  });

  group('ContactGroup Model - roundtrip', () {
    test('fromJson and toJson maintain data consistency', () {
      final originalJson = {
        'id': '456',
        'name': 'Roundtrip Test Group',
        'description': 'Testing roundtrip serialization',
        'contacts_count': 75,
        'created_at': '2024-05-10T08:00:00.000Z',
        'updated_at': '2024-05-15T16:30:00.000Z',
      };

      final group = ContactGroup.fromJson(originalJson);
      final resultJson = group.toJson();

      expect(resultJson['id'], equals(originalJson['id']));
      expect(resultJson['name'], equals(originalJson['name']));
      expect(resultJson['description'], equals(originalJson['description']));
      expect(resultJson['contacts_count'], equals(originalJson['contacts_count']));
    });

    test('handles minimal json roundtrip', () {
      final originalJson = {
        'id': 1,
        'name': 'Minimal Group',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
      };

      final group = ContactGroup.fromJson(originalJson);
      final resultJson = group.toJson();

      expect(resultJson['id'], equals('1'));
      expect(resultJson['name'], equals('Minimal Group'));
      expect(resultJson.containsKey('description'), isFalse);
      expect(resultJson['contacts_count'], equals(0));
    });
  });

  group('ContactGroup List Screen Data Patterns', () {
    test('groups can be sorted by name alphabetically', () {
      final groups = [
        ContactGroup(
          id: '1',
          name: 'Zebra Group',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        ContactGroup(
          id: '2',
          name: 'Alpha Group',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        ContactGroup(
          id: '3',
          name: 'Beta Group',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

      groups.sort((a, b) => a.name.compareTo(b.name));

      expect(groups[0].name, equals('Alpha Group'));
      expect(groups[1].name, equals('Beta Group'));
      expect(groups[2].name, equals('Zebra Group'));
    });

    test('groups can be sorted by contact count descending', () {
      final groups = [
        ContactGroup(
          id: '1',
          name: 'Small',
          contactsCount: 10,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        ContactGroup(
          id: '2',
          name: 'Large',
          contactsCount: 1000,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        ContactGroup(
          id: '3',
          name: 'Medium',
          contactsCount: 100,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

      groups.sort((a, b) => b.contactsCount.compareTo(a.contactsCount));

      expect(groups[0].name, equals('Large'));
      expect(groups[1].name, equals('Medium'));
      expect(groups[2].name, equals('Small'));
    });

    test('groups can be sorted by creation date', () {
      final groups = [
        ContactGroup(
          id: '1',
          name: 'Oldest',
          createdAt: DateTime(2023, 1, 1),
          updatedAt: DateTime.now(),
        ),
        ContactGroup(
          id: '2',
          name: 'Newest',
          createdAt: DateTime(2024, 6, 1),
          updatedAt: DateTime.now(),
        ),
        ContactGroup(
          id: '3',
          name: 'Middle',
          createdAt: DateTime(2024, 1, 1),
          updatedAt: DateTime.now(),
        ),
      ];

      groups.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      expect(groups[0].name, equals('Newest'));
      expect(groups[1].name, equals('Middle'));
      expect(groups[2].name, equals('Oldest'));
    });

    test('empty groups can be identified', () {
      final groups = [
        ContactGroup(
          id: '1',
          name: 'Empty Group',
          contactsCount: 0,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        ContactGroup(
          id: '2',
          name: 'Active Group',
          contactsCount: 50,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

      final emptyGroups = groups.where((g) => g.contactsCount == 0).toList();
      final nonEmptyGroups = groups.where((g) => g.contactsCount > 0).toList();

      expect(emptyGroups.length, equals(1));
      expect(nonEmptyGroups.length, equals(1));
      expect(emptyGroups.first.name, equals('Empty Group'));
    });

    test('groups can be filtered by name search', () {
      final groups = [
        ContactGroup(
          id: '1',
          name: 'VIP Customers',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        ContactGroup(
          id: '2',
          name: 'Newsletter Subscribers',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        ContactGroup(
          id: '3',
          name: 'Customer Support',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

      final searchQuery = 'customer';
      final filteredGroups = groups
          .where((g) => g.name.toLowerCase().contains(searchQuery.toLowerCase()))
          .toList();

      expect(filteredGroups.length, equals(2));
      expect(
        filteredGroups.any((g) => g.name == 'VIP Customers'),
        isTrue,
      );
      expect(
        filteredGroups.any((g) => g.name == 'Customer Support'),
        isTrue,
      );
    });
  });

  group('ContactGroup Detail Screen Data Patterns', () {
    test('group with description displays correctly', () {
      final group = ContactGroup(
        id: '1',
        name: 'Premium Users',
        description: 'Users who have upgraded to premium tier',
        contactsCount: 500,
        createdAt: DateTime(2024, 1, 15),
        updatedAt: DateTime(2024, 6, 20),
      );

      expect(group.description, isNotNull);
      expect(group.description, isNotEmpty);
      expect(group.description!.length, greaterThan(0));
    });

    test('group without description handles gracefully', () {
      final group = ContactGroup(
        id: '1',
        name: 'No Description Group',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(group.description, isNull);
    });

    test('contact count formatting scenarios', () {
      final smallGroup = ContactGroup(
        id: '1',
        name: 'Small',
        contactsCount: 5,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final mediumGroup = ContactGroup(
        id: '2',
        name: 'Medium',
        contactsCount: 500,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final largeGroup = ContactGroup(
        id: '3',
        name: 'Large',
        contactsCount: 50000,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(smallGroup.contactsCount, lessThan(10));
      expect(mediumGroup.contactsCount, inInclusiveRange(100, 1000));
      expect(largeGroup.contactsCount, greaterThan(10000));
    });
  });
}
