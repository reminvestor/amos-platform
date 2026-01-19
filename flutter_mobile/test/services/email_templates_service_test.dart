import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:amos_mobile/models/email_template.dart';

// Note: EmailTemplatesService uses ApiClient which requires native plugins.
// For unit tests, we test the data models, query parameter building,
// and response parsing logic separately.

void main() {
  group('EmailTemplate Model', () {
    test('parses from JSON correctly', () {
      final json = {
        'id': 1,
        'name': 'Welcome Email',
        'subject': 'Welcome to Our Platform!',
        'body': '<html><body><h1>Welcome!</h1><p>Thank you for joining us.</p></body></html>',
        'description': 'Sent to new users upon registration',
        'campaigns_count': 5,
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-15T10:30:00.000Z',
      };

      final template = EmailTemplate.fromJson(json);

      expect(template.id, equals('1'));
      expect(template.name, equals('Welcome Email'));
      expect(template.subject, equals('Welcome to Our Platform!'));
      expect(template.body, contains('<h1>Welcome!</h1>'));
      expect(template.description, equals('Sent to new users upon registration'));
      expect(template.campaignsCount, equals(5));
      expect(template.createdAt, equals(DateTime.parse('2024-01-01T00:00:00.000Z')));
      expect(template.updatedAt, equals(DateTime.parse('2024-01-15T10:30:00.000Z')));
    });

    test('handles missing optional fields', () {
      final json = {
        'id': 2,
        'name': 'Simple Template',
        'subject': 'Subject Line',
        'body': '<p>Body content</p>',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
      };

      final template = EmailTemplate.fromJson(json);

      expect(template.id, equals('2'));
      expect(template.name, equals('Simple Template'));
      expect(template.description, isNull);
      expect(template.campaignsCount, equals(0)); // default
    });

    test('handles null name, subject, and body with defaults', () {
      final json = {
        'id': 3,
        'name': null,
        'subject': null,
        'body': null,
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
      };

      final template = EmailTemplate.fromJson(json);

      expect(template.name, equals(''));
      expect(template.subject, equals(''));
      expect(template.body, equals(''));
    });

    test('handles numeric id conversion', () {
      final json = {
        'id': 456,
        'name': 'Test',
        'subject': 'Test Subject',
        'body': 'Test Body',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
      };

      final template = EmailTemplate.fromJson(json);

      expect(template.id, equals('456'));
    });
  });

  group('EmailTemplate toJson', () {
    test('converts to JSON correctly with all fields', () {
      final template = EmailTemplate(
        id: '1',
        name: 'Newsletter Template',
        subject: 'Monthly Newsletter',
        body: '<html>Newsletter content</html>',
        description: 'Monthly newsletter for subscribers',
        campaignsCount: 12,
        createdAt: DateTime.parse('2024-01-01T00:00:00.000Z'),
        updatedAt: DateTime.parse('2024-01-15T10:30:00.000Z'),
      );

      final json = template.toJson();

      expect(json['id'], equals('1'));
      expect(json['name'], equals('Newsletter Template'));
      expect(json['subject'], equals('Monthly Newsletter'));
      expect(json['body'], equals('<html>Newsletter content</html>'));
      expect(json['description'], equals('Monthly newsletter for subscribers'));
      expect(json['campaigns_count'], equals(12));
      expect(json['created_at'], equals('2024-01-01T00:00:00.000Z'));
      expect(json['updated_at'], equals('2024-01-15T10:30:00.000Z'));
    });

    test('omits null description', () {
      final template = EmailTemplate(
        id: '2',
        name: 'Simple',
        subject: 'Simple Subject',
        body: 'Simple body',
        createdAt: DateTime.parse('2024-01-01T00:00:00.000Z'),
        updatedAt: DateTime.parse('2024-01-01T00:00:00.000Z'),
      );

      final json = template.toJson();

      expect(json.containsKey('description'), isFalse);
    });
  });

  group('EmailTemplate bodyPreview', () {
    test('returns full text for short body', () {
      final template = EmailTemplate(
        id: '1',
        name: 'Test',
        subject: 'Test',
        body: '<p>Short content</p>',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(template.bodyPreview, equals('Short content'));
    });

    test('strips HTML tags from body', () {
      final template = EmailTemplate(
        id: '2',
        name: 'Test',
        subject: 'Test',
        body: '<html><body><h1>Title</h1><p>Content with <strong>bold</strong> text</p></body></html>',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(template.bodyPreview, contains('Title'));
      expect(template.bodyPreview, contains('Content with'));
      expect(template.bodyPreview, contains('bold'));
      expect(template.bodyPreview, isNot(contains('<')));
      expect(template.bodyPreview, isNot(contains('>')));
    });

    test('truncates long body to 100 characters', () {
      final longContent = 'A' * 150;
      final template = EmailTemplate(
        id: '3',
        name: 'Test',
        subject: 'Test',
        body: '<p>$longContent</p>',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(template.bodyPreview.length, equals(103)); // 100 chars + '...'
      expect(template.bodyPreview, endsWith('...'));
    });

    test('normalizes whitespace in preview', () {
      final template = EmailTemplate(
        id: '4',
        name: 'Test',
        subject: 'Test',
        body: '<p>Content   with\n\n  extra   whitespace</p>',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(template.bodyPreview, equals('Content with extra whitespace'));
    });

    test('trims whitespace from preview', () {
      final template = EmailTemplate(
        id: '5',
        name: 'Test',
        subject: 'Test',
        body: '  <p>  Padded content  </p>  ',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(template.bodyPreview, equals('Padded content'));
    });
  });

  group('Query Parameter Building', () {
    test('builds empty query params by default', () {
      final queryParams = <String, dynamic>{};

      expect(queryParams, isEmpty);
    });

    test('adds search parameter when provided', () {
      const search = 'welcome';

      final queryParams = <String, dynamic>{};
      if (search.isNotEmpty) {
        queryParams['search'] = search;
      }

      expect(queryParams['search'], equals('welcome'));
    });

    test('does not add search parameter when empty', () {
      const search = '';

      final queryParams = <String, dynamic>{};
      if (search.isNotEmpty) {
        queryParams['search'] = search;
      }

      expect(queryParams.containsKey('search'), isFalse);
    });

    test('handles null search parameter', () {
      const String? search = null;

      final queryParams = <String, dynamic>{};
      if (search != null && search.isNotEmpty) {
        queryParams['search'] = search;
      }

      expect(queryParams.containsKey('search'), isFalse);
    });
  });

  group('Email Templates List Response Parsing', () {
    test('parses email templates list response correctly', () {
      final responseData = {
        'data': [
          {
            'id': 1,
            'name': 'Welcome Email',
            'subject': 'Welcome!',
            'body': '<p>Welcome to our platform</p>',
            'campaigns_count': 5,
            'created_at': '2024-01-01T00:00:00.000Z',
            'updated_at': '2024-01-01T00:00:00.000Z',
          },
          {
            'id': 2,
            'name': 'Newsletter',
            'subject': 'Monthly Update',
            'body': '<p>This month\'s news</p>',
            'campaigns_count': 12,
            'created_at': '2024-01-02T00:00:00.000Z',
            'updated_at': '2024-01-02T00:00:00.000Z',
          },
        ],
      };

      final templatesList = responseData['data'] as List? ?? [];
      final templates = templatesList.map((json) => EmailTemplate.fromJson(json)).toList();

      expect(templates, hasLength(2));
      expect(templates[0].id, equals('1'));
      expect(templates[0].name, equals('Welcome Email'));
      expect(templates[0].campaignsCount, equals(5));
      expect(templates[1].id, equals('2'));
      expect(templates[1].name, equals('Newsletter'));
      expect(templates[1].campaignsCount, equals(12));
    });

    test('handles empty templates list', () {
      final responseData = {'data': []};

      final templatesList = responseData['data'] as List? ?? [];
      final templates = templatesList.map((json) => EmailTemplate.fromJson(json)).toList();

      expect(templates, isEmpty);
    });

    test('handles missing data key with fallback', () {
      final responseData = <String, dynamic>{};

      final templatesList = responseData['data'] as List? ?? [];
      final templates = templatesList.map((json) => EmailTemplate.fromJson(json)).toList();

      expect(templates, isEmpty);
    });

    test('handles null data key with fallback', () {
      final responseData = {'data': null};

      final templatesList = responseData['data'] as List? ?? [];
      final templates = templatesList.map((json) => EmailTemplate.fromJson(json)).toList();

      expect(templates, isEmpty);
    });
  });

  group('Create Email Template Request Building', () {
    test('builds create request with required fields', () {
      const name = 'New Template';
      const subject = 'New Subject';
      const body = '<p>Email body</p>';

      final data = {
        'name': name,
        'subject': subject,
        'body': body,
      };

      expect(data['name'], equals('New Template'));
      expect(data['subject'], equals('New Subject'));
      expect(data['body'], equals('<p>Email body</p>'));
    });
  });

  group('Update Email Template Request Building', () {
    test('builds update request with only changed fields', () {
      const String? name = 'Updated Name';
      const String? subject = null;
      const String? body = '<p>Updated body</p>';

      final data = <String, dynamic>{};
      if (name != null) data['name'] = name;
      if (subject != null) data['subject'] = subject;
      if (body != null) data['body'] = body;

      expect(data.length, equals(2));
      expect(data['name'], equals('Updated Name'));
      expect(data['body'], equals('<p>Updated body</p>'));
      expect(data.containsKey('subject'), isFalse);
    });

    test('builds empty request when no fields provided', () {
      const String? name = null;
      const String? subject = null;
      const String? body = null;

      final data = <String, dynamic>{};
      if (name != null) data['name'] = name;
      if (subject != null) data['subject'] = subject;
      if (body != null) data['body'] = body;

      expect(data, isEmpty);
    });
  });

  group('Duplicate Template Logic', () {
    test('creates copy name correctly', () {
      final template = EmailTemplate(
        id: '1',
        name: 'Original Template',
        subject: 'Original Subject',
        body: '<p>Original body</p>',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final copyName = '${template.name} (Copy)';

      expect(copyName, equals('Original Template (Copy)'));
    });

    test('preserves subject and body in duplicate', () {
      final template = EmailTemplate(
        id: '1',
        name: 'Template',
        subject: 'Important Subject',
        body: '<html><body><h1>Hello</h1></body></html>',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final duplicateData = {
        'name': '${template.name} (Copy)',
        'subject': template.subject,
        'body': template.body,
      };

      expect(duplicateData['name'], equals('Template (Copy)'));
      expect(duplicateData['subject'], equals('Important Subject'));
      expect(duplicateData['body'], equals('<html><body><h1>Hello</h1></body></html>'));
    });
  });

  group('Dio HTTP Client Tests', () {
    late Dio dio;
    late DioAdapter dioAdapter;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
      dioAdapter = DioAdapter(dio: dio);
    });

    test('GET /api/v1/email_templates returns templates list', () async {
      dioAdapter.onGet(
        '/api/v1/email_templates',
        (server) => server.reply(200, {
          'data': [
            {
              'id': 1,
              'name': 'Test Template',
              'subject': 'Test Subject',
              'body': '<p>Test body</p>',
              'campaigns_count': 3,
              'created_at': '2024-01-01T00:00:00.000Z',
              'updated_at': '2024-01-01T00:00:00.000Z',
            },
          ],
        }),
      );

      final response = await dio.get('/api/v1/email_templates');

      expect(response.statusCode, equals(200));
      expect(response.data['data'], hasLength(1));

      final templates = (response.data['data'] as List)
          .map((json) => EmailTemplate.fromJson(json))
          .toList();
      expect(templates[0].name, equals('Test Template'));
    });

    test('GET /api/v1/email_templates with search parameter', () async {
      dioAdapter.onGet(
        '/api/v1/email_templates',
        (server) => server.reply(200, {
          'data': [
            {
              'id': 1,
              'name': 'Welcome Email',
              'subject': 'Welcome!',
              'body': '<p>Welcome</p>',
              'created_at': '2024-01-01T00:00:00.000Z',
              'updated_at': '2024-01-01T00:00:00.000Z',
            },
          ],
        }),
        queryParameters: {'search': 'welcome'},
      );

      final response = await dio.get('/api/v1/email_templates', queryParameters: {'search': 'welcome'});

      expect(response.statusCode, equals(200));
    });

    test('GET /api/v1/email_templates/:id returns single template', () async {
      dioAdapter.onGet(
        '/api/v1/email_templates/1',
        (server) => server.reply(200, {
          'id': 1,
          'name': 'Detailed Template',
          'subject': 'Detailed Subject',
          'body': '<html><body>Full content</body></html>',
          'description': 'A detailed description',
          'campaigns_count': 10,
          'created_at': '2024-01-01T00:00:00.000Z',
          'updated_at': '2024-01-15T10:30:00.000Z',
        }),
      );

      final response = await dio.get('/api/v1/email_templates/1');

      expect(response.statusCode, equals(200));
      final template = EmailTemplate.fromJson(response.data);
      expect(template.name, equals('Detailed Template'));
      expect(template.description, equals('A detailed description'));
    });

    test('POST /api/v1/email_templates creates template', () async {
      dioAdapter.onPost(
        '/api/v1/email_templates',
        (server) => server.reply(201, {
          'id': 1,
          'name': 'New Template',
          'subject': 'New Subject',
          'body': '<p>New body</p>',
          'campaigns_count': 0,
          'created_at': '2024-01-01T00:00:00.000Z',
          'updated_at': '2024-01-01T00:00:00.000Z',
        }),
        data: {
          'name': 'New Template',
          'subject': 'New Subject',
          'body': '<p>New body</p>',
        },
      );

      final response = await dio.post('/api/v1/email_templates', data: {
        'name': 'New Template',
        'subject': 'New Subject',
        'body': '<p>New body</p>',
      });

      expect(response.statusCode, equals(201));
      final template = EmailTemplate.fromJson(response.data);
      expect(template.name, equals('New Template'));
      expect(template.campaignsCount, equals(0));
    });

    test('PATCH /api/v1/email_templates/:id updates template', () async {
      dioAdapter.onPatch(
        '/api/v1/email_templates/1',
        (server) => server.reply(200, {
          'id': 1,
          'name': 'Updated Template',
          'subject': 'Updated Subject',
          'body': '<p>Updated body</p>',
          'created_at': '2024-01-01T00:00:00.000Z',
          'updated_at': '2024-01-15T10:30:00.000Z',
        }),
        data: {
          'name': 'Updated Template',
        },
      );

      final response = await dio.patch('/api/v1/email_templates/1', data: {
        'name': 'Updated Template',
      });

      expect(response.statusCode, equals(200));
      final template = EmailTemplate.fromJson(response.data);
      expect(template.name, equals('Updated Template'));
    });

    test('DELETE /api/v1/email_templates/:id deletes template', () async {
      dioAdapter.onDelete(
        '/api/v1/email_templates/1',
        (server) => server.reply(204, null),
      );

      final response = await dio.delete('/api/v1/email_templates/1');

      expect(response.statusCode, equals(204));
    });

    test('handles 401 unauthorized error', () async {
      dioAdapter.onGet(
        '/api/v1/email_templates',
        (server) => server.reply(401, {'error': 'Unauthorized'}),
      );

      expect(
        () => dio.get('/api/v1/email_templates'),
        throwsA(isA<DioException>()),
      );
    });

    test('handles 404 not found error', () async {
      dioAdapter.onGet(
        '/api/v1/email_templates/999',
        (server) => server.reply(404, {'error': 'Email template not found'}),
      );

      expect(
        () => dio.get('/api/v1/email_templates/999'),
        throwsA(isA<DioException>()),
      );
    });

    test('handles 422 validation error on create', () async {
      dioAdapter.onPost(
        '/api/v1/email_templates',
        (server) => server.reply(422, {
          'errors': {
            'name': ['can\'t be blank'],
            'subject': ['can\'t be blank'],
          },
        }),
        data: {
          'name': '',
          'subject': '',
          'body': '',
        },
      );

      expect(
        () => dio.post('/api/v1/email_templates', data: {
          'name': '',
          'subject': '',
          'body': '',
        }),
        throwsA(isA<DioException>()),
      );
    });

    test('handles 500 server error', () async {
      dioAdapter.onGet(
        '/api/v1/email_templates',
        (server) => server.reply(500, {'error': 'Internal server error'}),
      );

      expect(
        () => dio.get('/api/v1/email_templates'),
        throwsA(isA<DioException>()),
      );
    });
  });
}
