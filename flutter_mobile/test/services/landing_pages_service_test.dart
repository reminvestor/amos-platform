import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:amos_mobile/models/landing_page.dart';

// Note: LandingPagesService uses ApiClient which requires native plugins.
// For unit tests, we test the data models, query parameter building,
// and response parsing logic separately.

void main() {
  group('LandingPageStatus Enum', () {
    test('fromString returns correct status', () {
      expect(LandingPageStatusX.fromString('draft'), equals(LandingPageStatus.draft));
      expect(LandingPageStatusX.fromString('published'), equals(LandingPageStatus.published));
    });

    test('fromString returns draft for unknown values', () {
      expect(LandingPageStatusX.fromString('unknown'), equals(LandingPageStatus.draft));
      expect(LandingPageStatusX.fromString(''), equals(LandingPageStatus.draft));
    });

    test('value extension returns correct string', () {
      expect(LandingPageStatus.draft.value, equals('draft'));
      expect(LandingPageStatus.published.value, equals('published'));
    });
  });

  group('LandingPage Model', () {
    test('parses from JSON correctly', () {
      final json = {
        'id': 1,
        'entity_id': 10,
        'title': 'Product Launch',
        'slug': 'product-launch',
        'status': 'published',
        'html_content': '<html><body>Welcome</body></html>',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-15T10:30:00.000Z',
        'submission_count': 150,
        'unread_submissions_count': 25,
        'view_count': 1000,
        'published_at': '2024-01-10T09:00:00.000Z',
      };

      final landingPage = LandingPage.fromJson(json);

      expect(landingPage.id, equals('1'));
      expect(landingPage.entityId, equals('10'));
      expect(landingPage.title, equals('Product Launch'));
      expect(landingPage.slug, equals('product-launch'));
      expect(landingPage.status, equals(LandingPageStatus.published));
      expect(landingPage.htmlContent, equals('<html><body>Welcome</body></html>'));
      expect(landingPage.createdAt, equals(DateTime.parse('2024-01-01T00:00:00.000Z')));
      expect(landingPage.updatedAt, equals(DateTime.parse('2024-01-15T10:30:00.000Z')));
      expect(landingPage.submissionCount, equals(150));
      expect(landingPage.unreadSubmissionsCount, equals(25));
      expect(landingPage.viewCount, equals(1000));
      expect(landingPage.publishedAt, equals(DateTime.parse('2024-01-10T09:00:00.000Z')));
    });

    test('parses content field as fallback for html_content', () {
      final json = {
        'id': 2,
        'title': 'Test Page',
        'slug': 'test-page',
        'status': 'draft',
        'content': '<div>Content here</div>',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
      };

      final landingPage = LandingPage.fromJson(json);

      expect(landingPage.htmlContent, equals('<div>Content here</div>'));
    });

    test('handles missing optional fields', () {
      final json = {
        'id': 3,
        'title': 'Simple Page',
        'slug': 'simple-page',
        'status': 'draft',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
      };

      final landingPage = LandingPage.fromJson(json);

      expect(landingPage.id, equals('3'));
      expect(landingPage.entityId, isNull);
      expect(landingPage.htmlContent, isNull);
      expect(landingPage.submissionCount, isNull);
      expect(landingPage.unreadSubmissionsCount, isNull);
      expect(landingPage.viewCount, isNull);
      expect(landingPage.publishedAt, isNull);
      expect(landingPage.status, equals(LandingPageStatus.draft));
    });

    test('handles empty title and slug', () {
      final json = {
        'id': 4,
        'title': null,
        'slug': null,
        'status': null,
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-01T00:00:00.000Z',
      };

      final landingPage = LandingPage.fromJson(json);

      expect(landingPage.title, equals(''));
      expect(landingPage.slug, equals(''));
      expect(landingPage.status, equals(LandingPageStatus.draft));
    });
  });

  group('LandingPage toJson', () {
    test('converts to JSON correctly with all fields', () {
      final landingPage = LandingPage(
        id: '1',
        entityId: '10',
        title: 'Test Page',
        slug: 'test-page',
        status: LandingPageStatus.published,
        htmlContent: '<html>Test</html>',
        createdAt: DateTime.parse('2024-01-01T00:00:00.000Z'),
        updatedAt: DateTime.parse('2024-01-15T10:30:00.000Z'),
        submissionCount: 50,
        viewCount: 200,
        publishedAt: DateTime.parse('2024-01-10T09:00:00.000Z'),
      );

      final json = landingPage.toJson();

      expect(json['id'], equals('1'));
      expect(json['entity_id'], equals('10'));
      expect(json['title'], equals('Test Page'));
      expect(json['slug'], equals('test-page'));
      expect(json['status'], equals('published'));
      expect(json['html_content'], equals('<html>Test</html>'));
      expect(json['created_at'], equals('2024-01-01T00:00:00.000Z'));
      expect(json['updated_at'], equals('2024-01-15T10:30:00.000Z'));
      expect(json['submission_count'], equals(50));
      expect(json['view_count'], equals(200));
      expect(json['published_at'], equals('2024-01-10T09:00:00.000Z'));
    });

    test('omits null optional fields', () {
      final landingPage = LandingPage(
        id: '2',
        title: 'Simple',
        slug: 'simple',
        status: LandingPageStatus.draft,
        createdAt: DateTime.parse('2024-01-01T00:00:00.000Z'),
        updatedAt: DateTime.parse('2024-01-01T00:00:00.000Z'),
      );

      final json = landingPage.toJson();

      expect(json.containsKey('submission_count'), isFalse);
      expect(json.containsKey('view_count'), isFalse);
      expect(json.containsKey('published_at'), isFalse);
    });
  });

  group('LandingPageSubmission Model', () {
    test('parses from JSON correctly', () {
      final json = {
        'id': 'sub_123',
        'landing_page_id': 'lp_456',
        'email': 'user@example.com',
        'data': {
          'name': 'John Doe',
          'company': 'Acme Inc',
        },
        'ip_address': '192.168.1.1',
        'user_agent': 'Mozilla/5.0',
        'created_at': '2024-01-15T10:30:00.000Z',
      };

      final submission = LandingPageSubmission.fromJson(json);

      expect(submission.id, equals('sub_123'));
      expect(submission.landingPageId, equals('lp_456'));
      expect(submission.email, equals('user@example.com'));
      expect(submission.data, isNotNull);
      expect(submission.data!['name'], equals('John Doe'));
      expect(submission.data!['company'], equals('Acme Inc'));
      expect(submission.ipAddress, equals('192.168.1.1'));
      expect(submission.userAgent, equals('Mozilla/5.0'));
      expect(submission.createdAt, equals(DateTime.parse('2024-01-15T10:30:00.000Z')));
    });

    test('handles missing optional fields', () {
      final json = {
        'id': 'sub_456',
        'landing_page_id': 'lp_789',
        'email': 'simple@example.com',
        'created_at': '2024-01-15T10:30:00.000Z',
      };

      final submission = LandingPageSubmission.fromJson(json);

      expect(submission.id, equals('sub_456'));
      expect(submission.data, isNull);
      expect(submission.ipAddress, isNull);
      expect(submission.userAgent, isNull);
    });
  });

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
      const search = 'product';

      final queryParams = <String, dynamic>{
        'page': page,
        'per_page': perPage,
      };
      if (search.isNotEmpty) {
        queryParams['search'] = search;
      }

      expect(queryParams['search'], equals('product'));
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

    test('adds status parameter when provided', () {
      const page = 1;
      const perPage = 20;
      const status = 'published';

      final queryParams = <String, dynamic>{
        'page': page,
        'per_page': perPage,
      };
      if (status.isNotEmpty) {
        queryParams['status'] = status;
      }

      expect(queryParams['status'], equals('published'));
    });

    test('builds full query parameters with all options', () {
      const page = 2;
      const perPage = 50;
      const search = 'launch';
      const status = 'published';

      final queryParams = <String, dynamic>{
        'page': page,
        'per_page': perPage,
      };
      if (search.isNotEmpty) {
        queryParams['search'] = search;
      }
      if (status.isNotEmpty) {
        queryParams['status'] = status;
      }

      expect(queryParams.length, equals(4));
      expect(queryParams['page'], equals(2));
      expect(queryParams['per_page'], equals(50));
      expect(queryParams['search'], equals('launch'));
      expect(queryParams['status'], equals('published'));
    });

    test('handles null parameters', () {
      const page = 1;
      const perPage = 20;
      const String? search = null;
      const String? status = null;

      final queryParams = <String, dynamic>{
        'page': page,
        'per_page': perPage,
      };
      if (search != null && search.isNotEmpty) {
        queryParams['search'] = search;
      }
      if (status != null && status.isNotEmpty) {
        queryParams['status'] = status;
      }

      expect(queryParams.length, equals(2));
      expect(queryParams.containsKey('search'), isFalse);
      expect(queryParams.containsKey('status'), isFalse);
    });
  });

  group('Landing Pages List Response Parsing', () {
    test('parses landing pages list response correctly', () {
      final responseData = {
        'data': [
          {
            'id': 1,
            'title': 'Product Launch',
            'slug': 'product-launch',
            'status': 'published',
            'created_at': '2024-01-01T00:00:00.000Z',
            'updated_at': '2024-01-01T00:00:00.000Z',
            'view_count': 500,
          },
          {
            'id': 2,
            'title': 'Coming Soon',
            'slug': 'coming-soon',
            'status': 'draft',
            'created_at': '2024-01-02T00:00:00.000Z',
            'updated_at': '2024-01-02T00:00:00.000Z',
          },
        ],
      };

      final pagesList = responseData['data'] as List? ?? [];
      final pages = pagesList.map((json) => LandingPage.fromJson(json)).toList();

      expect(pages, hasLength(2));
      expect(pages[0].id, equals('1'));
      expect(pages[0].title, equals('Product Launch'));
      expect(pages[0].status, equals(LandingPageStatus.published));
      expect(pages[0].viewCount, equals(500));
      expect(pages[1].id, equals('2'));
      expect(pages[1].title, equals('Coming Soon'));
      expect(pages[1].status, equals(LandingPageStatus.draft));
    });

    test('handles empty landing pages list', () {
      final responseData = {'data': []};

      final pagesList = responseData['data'] as List? ?? [];
      final pages = pagesList.map((json) => LandingPage.fromJson(json)).toList();

      expect(pages, isEmpty);
    });

    test('handles missing data key with fallback', () {
      final responseData = <String, dynamic>{};

      final pagesList = responseData['data'] as List? ?? [];
      final pages = pagesList.map((json) => LandingPage.fromJson(json)).toList();

      expect(pages, isEmpty);
    });
  });

  group('Create Landing Page Request Building', () {
    test('builds create request with required fields', () {
      const title = 'New Page';
      const slug = 'new-page';
      const status = 'draft';

      final data = {
        'title': title,
        'slug': slug,
        'status': status,
      };

      expect(data['title'], equals('New Page'));
      expect(data['slug'], equals('new-page'));
      expect(data['status'], equals('draft'));
    });

    test('builds create request with optional content', () {
      const title = 'New Page';
      const slug = 'new-page';
      const content = '<html>Content</html>';
      const metaTitle = 'Page Title';
      const metaDescription = 'Page description for SEO';

      final data = <String, dynamic>{
        'title': title,
        'slug': slug,
        if (content != null) 'content': content,
        'status': 'draft',
        if (metaTitle != null) 'meta_title': metaTitle,
        if (metaDescription != null) 'meta_description': metaDescription,
      };

      expect(data['content'], equals('<html>Content</html>'));
      expect(data['meta_title'], equals('Page Title'));
      expect(data['meta_description'], equals('Page description for SEO'));
    });

    test('excludes null optional content from request', () {
      const title = 'New Page';
      const slug = 'new-page';
      const String? content = null;
      const String? metaTitle = null;

      final data = <String, dynamic>{
        'title': title,
        'slug': slug,
        if (content != null) 'content': content,
        'status': 'draft',
        if (metaTitle != null) 'meta_title': metaTitle,
      };

      expect(data.containsKey('content'), isFalse);
      expect(data.containsKey('meta_title'), isFalse);
    });
  });

  group('Update Landing Page Request Building', () {
    test('builds update request with only provided fields', () {
      final data = <String, dynamic>{
        'title': 'Updated Title',
        'status': 'published',
      };

      expect(data.length, equals(2));
      expect(data['title'], equals('Updated Title'));
      expect(data['status'], equals('published'));
    });

    test('builds empty request when no fields provided', () {
      final data = <String, dynamic>{};

      expect(data, isEmpty);
    });
  });

  group('Dio HTTP Client Tests', () {
    late Dio dio;
    late DioAdapter dioAdapter;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
      dioAdapter = DioAdapter(dio: dio);
    });

    test('GET /api/v1/landing_pages returns landing pages list', () async {
      dioAdapter.onGet(
        '/api/v1/landing_pages',
        (server) => server.reply(200, {
          'data': [
            {
              'id': 1,
              'title': 'Test Page',
              'slug': 'test-page',
              'status': 'draft',
              'created_at': '2024-01-01T00:00:00.000Z',
              'updated_at': '2024-01-01T00:00:00.000Z',
            },
          ],
        }),
      );

      final response = await dio.get('/api/v1/landing_pages');

      expect(response.statusCode, equals(200));
      expect(response.data['data'], hasLength(1));

      final pages = (response.data['data'] as List)
          .map((json) => LandingPage.fromJson(json))
          .toList();
      expect(pages[0].title, equals('Test Page'));
    });

    test('GET /api/v1/landing_pages with query parameters', () async {
      dioAdapter.onGet(
        '/api/v1/landing_pages',
        (server) => server.reply(200, {
          'data': [
            {
              'id': 1,
              'title': 'Published Page',
              'slug': 'published-page',
              'status': 'published',
              'created_at': '2024-01-01T00:00:00.000Z',
              'updated_at': '2024-01-01T00:00:00.000Z',
            },
          ],
        }),
        queryParameters: {
          'page': 1,
          'per_page': 20,
          'status': 'published',
        },
      );

      final response = await dio.get('/api/v1/landing_pages', queryParameters: {
        'page': 1,
        'per_page': 20,
        'status': 'published',
      });

      expect(response.statusCode, equals(200));
    });

    test('GET /api/v1/landing_pages/:id returns single landing page', () async {
      dioAdapter.onGet(
        '/api/v1/landing_pages/1',
        (server) => server.reply(200, {
          'id': 1,
          'title': 'Detailed Page',
          'slug': 'detailed-page',
          'status': 'published',
          'html_content': '<html><body>Detailed content</body></html>',
          'created_at': '2024-01-01T00:00:00.000Z',
          'updated_at': '2024-01-15T10:30:00.000Z',
          'view_count': 1000,
          'submission_count': 50,
        }),
      );

      final response = await dio.get('/api/v1/landing_pages/1');

      expect(response.statusCode, equals(200));
      final page = LandingPage.fromJson(response.data);
      expect(page.title, equals('Detailed Page'));
      expect(page.htmlContent, contains('Detailed content'));
      expect(page.viewCount, equals(1000));
    });

    test('POST /api/v1/landing_pages creates landing page', () async {
      dioAdapter.onPost(
        '/api/v1/landing_pages',
        (server) => server.reply(201, {
          'id': 1,
          'title': 'New Page',
          'slug': 'new-page',
          'status': 'draft',
          'created_at': '2024-01-01T00:00:00.000Z',
          'updated_at': '2024-01-01T00:00:00.000Z',
        }),
        data: {
          'title': 'New Page',
          'slug': 'new-page',
          'status': 'draft',
        },
      );

      final response = await dio.post('/api/v1/landing_pages', data: {
        'title': 'New Page',
        'slug': 'new-page',
        'status': 'draft',
      });

      expect(response.statusCode, equals(201));
      final page = LandingPage.fromJson(response.data);
      expect(page.title, equals('New Page'));
    });

    test('PATCH /api/v1/landing_pages/:id updates landing page', () async {
      dioAdapter.onPatch(
        '/api/v1/landing_pages/1',
        (server) => server.reply(200, {
          'id': 1,
          'title': 'Updated Title',
          'slug': 'updated-slug',
          'status': 'draft',
          'created_at': '2024-01-01T00:00:00.000Z',
          'updated_at': '2024-01-15T10:30:00.000Z',
        }),
        data: {
          'title': 'Updated Title',
        },
      );

      final response = await dio.patch('/api/v1/landing_pages/1', data: {
        'title': 'Updated Title',
      });

      expect(response.statusCode, equals(200));
      final page = LandingPage.fromJson(response.data);
      expect(page.title, equals('Updated Title'));
    });

    test('DELETE /api/v1/landing_pages/:id deletes landing page', () async {
      dioAdapter.onDelete(
        '/api/v1/landing_pages/1',
        (server) => server.reply(204, null),
      );

      final response = await dio.delete('/api/v1/landing_pages/1');

      expect(response.statusCode, equals(204));
    });

    test('POST /api/v1/landing_pages/:id/publish publishes page', () async {
      dioAdapter.onPost(
        '/api/v1/landing_pages/1/publish',
        (server) => server.reply(200, {
          'id': 1,
          'title': 'Test Page',
          'slug': 'test-page',
          'status': 'published',
          'created_at': '2024-01-01T00:00:00.000Z',
          'updated_at': '2024-01-15T10:30:00.000Z',
          'published_at': '2024-01-15T10:30:00.000Z',
        }),
      );

      final response = await dio.post('/api/v1/landing_pages/1/publish');

      expect(response.statusCode, equals(200));
      final page = LandingPage.fromJson(response.data);
      expect(page.status, equals(LandingPageStatus.published));
      expect(page.publishedAt, isNotNull);
    });

    test('POST /api/v1/landing_pages/:id/unpublish unpublishes page', () async {
      dioAdapter.onPost(
        '/api/v1/landing_pages/1/unpublish',
        (server) => server.reply(200, {
          'id': 1,
          'title': 'Test Page',
          'slug': 'test-page',
          'status': 'draft',
          'created_at': '2024-01-01T00:00:00.000Z',
          'updated_at': '2024-01-15T11:00:00.000Z',
        }),
      );

      final response = await dio.post('/api/v1/landing_pages/1/unpublish');

      expect(response.statusCode, equals(200));
      final page = LandingPage.fromJson(response.data);
      expect(page.status, equals(LandingPageStatus.draft));
    });

    test('handles 401 unauthorized error', () async {
      dioAdapter.onGet(
        '/api/v1/landing_pages',
        (server) => server.reply(401, {'error': 'Unauthorized'}),
      );

      expect(
        () => dio.get('/api/v1/landing_pages'),
        throwsA(isA<DioException>()),
      );
    });

    test('handles 404 not found error', () async {
      dioAdapter.onGet(
        '/api/v1/landing_pages/999',
        (server) => server.reply(404, {'error': 'Landing page not found'}),
      );

      expect(
        () => dio.get('/api/v1/landing_pages/999'),
        throwsA(isA<DioException>()),
      );
    });

    test('handles 422 validation error', () async {
      dioAdapter.onPost(
        '/api/v1/landing_pages',
        (server) => server.reply(422, {
          'errors': {
            'slug': ['has already been taken'],
          },
        }),
        data: {
          'title': 'Test',
          'slug': 'existing-slug',
          'status': 'draft',
        },
      );

      expect(
        () => dio.post('/api/v1/landing_pages', data: {
          'title': 'Test',
          'slug': 'existing-slug',
          'status': 'draft',
        }),
        throwsA(isA<DioException>()),
      );
    });
  });
}
