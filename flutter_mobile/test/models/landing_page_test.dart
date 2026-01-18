import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/landing_page.dart';

void main() {
  group('LandingPageStatus', () {
    test('value returns correct string', () {
      expect(LandingPageStatus.draft.value, equals('draft'));
      expect(LandingPageStatus.published.value, equals('published'));
    });

    test('fromString converts string to enum correctly', () {
      expect(LandingPageStatusX.fromString('draft'), equals(LandingPageStatus.draft));
      expect(LandingPageStatusX.fromString('published'), equals(LandingPageStatus.published));
    });

    test('fromString returns draft for unknown values', () {
      expect(LandingPageStatusX.fromString('unknown'), equals(LandingPageStatus.draft));
      expect(LandingPageStatusX.fromString(''), equals(LandingPageStatus.draft));
    });
  });

  group('LandingPage', () {
    test('fromJson parses complete JSON correctly', () {
      final json = {
        'id': 1,
        'entity_id': '123',
        'title': 'Welcome Page',
        'slug': 'welcome-page',
        'status': 'published',
        'html_content': '<div>Hello World</div>',
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-16T11:00:00.000Z',
        'submission_count': 50,
        'unread_submissions_count': 5,
        'view_count': 1000,
        'published_at': '2024-01-15T12:00:00.000Z',
      };

      final page = LandingPage.fromJson(json);

      expect(page.id, equals('1'));
      expect(page.entityId, equals('123'));
      expect(page.title, equals('Welcome Page'));
      expect(page.slug, equals('welcome-page'));
      expect(page.status, equals(LandingPageStatus.published));
      expect(page.htmlContent, equals('<div>Hello World</div>'));
      expect(page.createdAt, equals(DateTime.parse('2024-01-15T10:30:00.000Z')));
      expect(page.updatedAt, equals(DateTime.parse('2024-01-16T11:00:00.000Z')));
      expect(page.submissionCount, equals(50));
      expect(page.unreadSubmissionsCount, equals(5));
      expect(page.viewCount, equals(1000));
      expect(page.publishedAt, equals(DateTime.parse('2024-01-15T12:00:00.000Z')));
    });

    test('fromJson handles content field as fallback for html_content', () {
      final json = {
        'id': '123',
        'title': 'Test Page',
        'slug': 'test-page',
        'content': '<div>Fallback Content</div>',
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-16T11:00:00.000Z',
      };

      final page = LandingPage.fromJson(json);

      expect(page.htmlContent, equals('<div>Fallback Content</div>'));
    });

    test('fromJson handles minimal required fields', () {
      final json = {
        'id': '123',
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-16T11:00:00.000Z',
      };

      final page = LandingPage.fromJson(json);

      expect(page.id, equals('123'));
      expect(page.title, equals(''));
      expect(page.slug, equals(''));
      expect(page.status, equals(LandingPageStatus.draft));
      expect(page.htmlContent, isNull);
      expect(page.entityId, isNull);
      expect(page.submissionCount, isNull);
      expect(page.viewCount, isNull);
      expect(page.publishedAt, isNull);
    });

    test('toJson serializes correctly', () {
      final page = LandingPage(
        id: '123',
        entityId: '456',
        title: 'Welcome Page',
        slug: 'welcome-page',
        status: LandingPageStatus.published,
        htmlContent: '<div>Hello World</div>',
        createdAt: DateTime.parse('2024-01-15T10:30:00.000Z'),
        updatedAt: DateTime.parse('2024-01-16T11:00:00.000Z'),
        submissionCount: 50,
        viewCount: 1000,
        publishedAt: DateTime.parse('2024-01-15T12:00:00.000Z'),
      );

      final json = page.toJson();

      expect(json['id'], equals('123'));
      expect(json['entity_id'], equals('456'));
      expect(json['title'], equals('Welcome Page'));
      expect(json['slug'], equals('welcome-page'));
      expect(json['status'], equals('published'));
      expect(json['html_content'], equals('<div>Hello World</div>'));
      expect(json['submission_count'], equals(50));
      expect(json['view_count'], equals(1000));
      expect(json['published_at'], equals('2024-01-15T12:00:00.000Z'));
    });

    test('toJson excludes null optional fields', () {
      final page = LandingPage(
        id: '123',
        title: 'Test Page',
        slug: 'test-page',
        status: LandingPageStatus.draft,
        createdAt: DateTime.parse('2024-01-15T10:30:00.000Z'),
        updatedAt: DateTime.parse('2024-01-16T11:00:00.000Z'),
      );

      final json = page.toJson();

      expect(json.containsKey('submission_count'), isFalse);
      expect(json.containsKey('view_count'), isFalse);
      expect(json.containsKey('published_at'), isFalse);
    });
  });

  group('LandingPageSubmission', () {
    test('fromJson parses complete JSON correctly', () {
      final json = {
        'id': '123',
        'landing_page_id': '456',
        'email': 'test@example.com',
        'data': {'name': 'John Doe', 'company': 'ACME'},
        'ip_address': '192.168.1.1',
        'user_agent': 'Mozilla/5.0',
        'created_at': '2024-01-15T10:30:00.000Z',
      };

      final submission = LandingPageSubmission.fromJson(json);

      expect(submission.id, equals('123'));
      expect(submission.landingPageId, equals('456'));
      expect(submission.email, equals('test@example.com'));
      expect(submission.data, equals({'name': 'John Doe', 'company': 'ACME'}));
      expect(submission.ipAddress, equals('192.168.1.1'));
      expect(submission.userAgent, equals('Mozilla/5.0'));
      expect(submission.createdAt, equals(DateTime.parse('2024-01-15T10:30:00.000Z')));
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'id': '123',
        'landing_page_id': '456',
        'email': 'test@example.com',
        'created_at': '2024-01-15T10:30:00.000Z',
      };

      final submission = LandingPageSubmission.fromJson(json);

      expect(submission.id, equals('123'));
      expect(submission.email, equals('test@example.com'));
      expect(submission.data, isNull);
      expect(submission.ipAddress, isNull);
      expect(submission.userAgent, isNull);
    });
  });
}
