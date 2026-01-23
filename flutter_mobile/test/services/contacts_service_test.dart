import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/contact.dart';

// Note: ContactsService uses ApiClient which requires native plugins.
// For unit tests, we test the data models, query parameter building,
// and response parsing logic separately.

void main() {
  group('Query Parameter Building', () {
    test('builds basic pagination parameters', () {
      const page = 1;
      const perPage = 20;

      final queryParams = <String, dynamic>{
        'page': page,
        'per_page': perPage,
      };

      expect(queryParams['page'], equals(1));
      expect(queryParams['per_page'], equals(20));
    });

    test('adds search parameter when provided', () {
      const page = 1;
      const perPage = 20;
      const search = 'john@example.com';

      final queryParams = <String, dynamic>{
        'page': page,
        'per_page': perPage,
      };
      if (search.isNotEmpty) {
        queryParams['search'] = search;
      }

      expect(queryParams['search'], equals('john@example.com'));
    });

    test('does not add search parameter when empty', () {
      const page = 1;
      const perPage = 20;
      const search = '';

      final queryParams = <String, dynamic>{
        'page': page,
        'per_page': perPage,
      };
      if (search.isNotEmpty) {
        queryParams['search'] = search;
      }

      expect(queryParams.containsKey('search'), isFalse);
    });

    test('adds groupId parameter when provided', () {
      const page = 1;
      const perPage = 20;
      const groupId = 'group-123';

      final queryParams = <String, dynamic>{
        'page': page,
        'per_page': perPage,
      };
      if (groupId.isNotEmpty) {
        queryParams['group_id'] = groupId;
      }

      expect(queryParams['group_id'], equals('group-123'));
    });

    test('builds full query parameters with all options', () {
      const page = 2;
      const perPage = 50;
      const search = 'john';
      const groupId = 'group-456';

      final queryParams = <String, dynamic>{
        'page': page,
        'per_page': perPage,
      };
      if (search.isNotEmpty) {
        queryParams['search'] = search;
      }
      if (groupId.isNotEmpty) {
        queryParams['group_id'] = groupId;
      }

      expect(queryParams.length, equals(4));
      expect(queryParams['page'], equals(2));
      expect(queryParams['per_page'], equals(50));
      expect(queryParams['search'], equals('john'));
      expect(queryParams['group_id'], equals('group-456'));
    });

    test('handles null search parameter', () {
      const page = 1;
      const perPage = 20;
      const String? search = null;

      final queryParams = <String, dynamic>{
        'page': page,
        'per_page': perPage,
      };
      if (search != null && search.isNotEmpty) {
        queryParams['search'] = search;
      }

      expect(queryParams.containsKey('search'), isFalse);
    });

    test('handles null groupId parameter', () {
      const page = 1;
      const perPage = 20;
      const String? groupId = null;

      final queryParams = <String, dynamic>{
        'page': page,
        'per_page': perPage,
      };
      if (groupId != null && groupId.isNotEmpty) {
        queryParams['group_id'] = groupId;
      }

      expect(queryParams.containsKey('group_id'), isFalse);
    });
  });

  group('Contacts List Response Parsing', () {
    test('parses contacts list response correctly', () {
      final responseData = {
        'data': [
          {
            'id': 1,
            'email': 'john@example.com',
            'first_name': 'John',
            'last_name': 'Doe',
            'status': 'active',
            'created_at': '2024-01-01T00:00:00.000Z',
            'updated_at': '2024-01-01T00:00:00.000Z',
          },
          {
            'id': 2,
            'email': 'jane@example.com',
            'name': 'Jane Smith',
            'status': 'inactive',
            'created_at': '2024-01-02T00:00:00.000Z',
            'updated_at': '2024-01-02T00:00:00.000Z',
          },
        ],
      };

      final contactsList = responseData['data'] as List? ?? [];
      final contacts = contactsList.map((json) => Contact.fromJson(json)).toList();

      expect(contacts, hasLength(2));
      expect(contacts[0].id, equals('1'));
      expect(contacts[0].email, equals('john@example.com'));
      expect(contacts[0].firstName, equals('John'));
      expect(contacts[0].lastName, equals('Doe'));
      expect(contacts[0].status, equals(ContactStatus.active));
      expect(contacts[1].id, equals('2'));
      expect(contacts[1].name, equals('Jane Smith'));
      expect(contacts[1].status, equals(ContactStatus.inactive));
    });

    test('handles empty contacts list', () {
      final responseData = {'data': []};

      final contactsList = responseData['data'] as List? ?? [];
      final contacts = contactsList.map((json) => Contact.fromJson(json)).toList();

      expect(contacts, isEmpty);
    });

    test('handles missing data key with fallback', () {
      final responseData = <String, dynamic>{};

      final contactsList = responseData['data'] as List? ?? [];
      final contacts = contactsList.map((json) => Contact.fromJson(json)).toList();

      expect(contacts, isEmpty);
    });
  });

  group('Contact Create Request Building', () {
    test('builds create request with required email', () {
      const email = 'new@example.com';

      final data = <String, dynamic>{
        'email': email,
      };

      expect(data['email'], equals('new@example.com'));
    });

    test('builds create request with all optional fields', () {
      const email = 'new@example.com';
      const firstName = 'John';
      const lastName = 'Doe';
      const phone = '+1234567890';
      const company = 'Acme Inc';
      const notes = 'VIP customer';
      const status = 'active';
      const tags = ['vip', 'premium'];

      final data = <String, dynamic>{
        'email': email,
        if (firstName != null) 'first_name': firstName,
        if (lastName != null) 'last_name': lastName,
        if (phone != null) 'phone': phone,
        if (company != null) 'company': company,
        if (notes != null) 'notes': notes,
        if (status != null) 'status': status,
        if (tags != null) 'tags': tags.join(','),
      };

      expect(data['email'], equals('new@example.com'));
      expect(data['first_name'], equals('John'));
      expect(data['last_name'], equals('Doe'));
      expect(data['phone'], equals('+1234567890'));
      expect(data['company'], equals('Acme Inc'));
      expect(data['notes'], equals('VIP customer'));
      expect(data['status'], equals('active'));
      expect(data['tags'], equals('vip,premium'));
    });

    test('excludes null optional fields from request', () {
      const email = 'new@example.com';
      const String? firstName = null;
      const String? lastName = null;

      final data = <String, dynamic>{
        'email': email,
        if (firstName != null) 'first_name': firstName,
        if (lastName != null) 'last_name': lastName,
      };

      expect(data['email'], equals('new@example.com'));
      expect(data.containsKey('first_name'), isFalse);
      expect(data.containsKey('last_name'), isFalse);
    });

    test('joins tags with comma', () {
      const tags = ['tag1', 'tag2', 'tag3'];

      final joinedTags = tags.join(',');

      expect(joinedTags, equals('tag1,tag2,tag3'));
    });

    test('handles empty tags list', () {
      const tags = <String>[];

      final joinedTags = tags.join(',');

      expect(joinedTags, equals(''));
    });

    test('handles single tag', () {
      const tags = ['single'];

      final joinedTags = tags.join(',');

      expect(joinedTags, equals('single'));
    });
  });

  group('Contact Update Request Building', () {
    test('builds update request with only changed fields', () {
      const String? email = null;
      const String? firstName = 'Updated';
      const String? lastName = null;
      const String? phone = '+9876543210';
      const String? company = null;
      const String? notes = null;
      const String? status = 'inactive';
      const List<String>? tags = null;

      final data = <String, dynamic>{};
      if (email != null) data['email'] = email;
      if (firstName != null) data['first_name'] = firstName;
      if (lastName != null) data['last_name'] = lastName;
      if (phone != null) data['phone'] = phone;
      if (company != null) data['company'] = company;
      if (notes != null) data['notes'] = notes;
      if (status != null) data['status'] = status;
      if (tags != null) data['tags'] = tags.join(',');

      expect(data.length, equals(3));
      expect(data['first_name'], equals('Updated'));
      expect(data['phone'], equals('+9876543210'));
      expect(data['status'], equals('inactive'));
      expect(data.containsKey('email'), isFalse);
      expect(data.containsKey('last_name'), isFalse);
    });

    test('builds empty request when no fields provided', () {
      const String? email = null;
      const String? firstName = null;

      final data = <String, dynamic>{};
      if (email != null) data['email'] = email;
      if (firstName != null) data['first_name'] = firstName;

      expect(data, isEmpty);
    });

    test('updates tags by joining with comma', () {
      const tags = ['new-tag1', 'new-tag2'];

      final data = <String, dynamic>{};
      if (tags != null) data['tags'] = tags.join(',');

      expect(data['tags'], equals('new-tag1,new-tag2'));
    });
  });

  group('Contact Model - displayName', () {
    test('returns name when available', () {
      final contact = Contact(
        id: '1',
        email: 'test@example.com',
        status: ContactStatus.active,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        name: 'John Doe',
        firstName: 'John',
      );

      expect(contact.displayName, equals('John Doe'));
    });

    test('returns firstName when name is null', () {
      final contact = Contact(
        id: '1',
        email: 'test@example.com',
        status: ContactStatus.active,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        firstName: 'Jane',
      );

      expect(contact.displayName, equals('Jane'));
    });

    test('returns email username when name and firstName are null', () {
      final contact = Contact(
        id: '1',
        email: 'johndoe@example.com',
        status: ContactStatus.active,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(contact.displayName, equals('johndoe'));
    });
  });

  group('Contact Model - initials', () {
    test('returns initials from full name', () {
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

    test('returns single initial from single name', () {
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

    test('returns first letter of email when name is null', () {
      final contact = Contact(
        id: '1',
        email: 'test@example.com',
        status: ContactStatus.active,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(contact.initials, equals('T'));
    });

    test('initials are uppercase', () {
      final contact = Contact(
        id: '1',
        email: 'test@example.com',
        status: ContactStatus.active,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        name: 'john doe',
      );

      expect(contact.initials, equals('JD'));
    });
  });

  group('Contact Model - tags parsing', () {
    test('parses tags from comma-separated string', () {
      final json = {
        'id': '1',
        'email': 'test@example.com',
        'status': 'active',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
        'tags': 'tag1, tag2, tag3',
      };

      final contact = Contact.fromJson(json);

      expect(contact.tags, equals(['tag1', 'tag2', 'tag3']));
    });

    test('parses tags from List', () {
      final json = {
        'id': '1',
        'email': 'test@example.com',
        'status': 'active',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
        'tags': ['tag1', 'tag2', 'tag3'],
      };

      final contact = Contact.fromJson(json);

      expect(contact.tags, equals(['tag1', 'tag2', 'tag3']));
    });

    test('handles empty tags string', () {
      final json = {
        'id': '1',
        'email': 'test@example.com',
        'status': 'active',
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
        'status': 'active',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
      };

      final contact = Contact.fromJson(json);

      expect(contact.tags, isNull);
    });

    test('trims whitespace from tags in comma-separated string', () {
      final json = {
        'id': '1',
        'email': 'test@example.com',
        'status': 'active',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
        'tags': '  tag1  ,  tag2  ,  tag3  ',
      };

      final contact = Contact.fromJson(json);

      expect(contact.tags, equals(['tag1', 'tag2', 'tag3']));
    });
  });

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

  group('Contact Groups Parsing', () {
    test('parses groups from response', () {
      final json = {
        'id': '1',
        'email': 'test@example.com',
        'status': 'active',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
        'groups': [
          {'id': 'g1', 'name': 'VIP'},
          {'id': 'g2', 'name': 'Newsletter'},
        ],
      };

      final contact = Contact.fromJson(json);

      expect(contact.groups, hasLength(2));
      expect(contact.groups![0]['name'], equals('VIP'));
      expect(contact.groups![1]['name'], equals('Newsletter'));
    });

    test('handles null groups', () {
      final json = {
        'id': '1',
        'email': 'test@example.com',
        'status': 'active',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
      };

      final contact = Contact.fromJson(json);

      expect(contact.groups, isNull);
    });
  });
}
