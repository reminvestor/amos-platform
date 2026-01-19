import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/landing_page.dart';

// Note: LandingPageDetailScreen triggers async _loadLandingPage in initState
// which can cause "ref used after dispose" errors in widget tests. These tests
// focus on the LandingPage model and data transformations used by the screen
// components.

void main() {
  group('LandingPageDetailScreen Data Models', () {
    group('LandingPage detail view data', () {
      test('published page has all required display data', () {
        final page = LandingPage(
          id: '1',
          entityId: 'entity123',
          title: 'Marketing Campaign Page',
          slug: 'marketing-campaign-2024',
          status: LandingPageStatus.published,
          htmlContent: '<div>Welcome to our campaign!</div>',
          createdAt: DateTime.parse('2024-01-15T10:30:00.000Z'),
          updatedAt: DateTime.parse('2024-01-20T14:45:00.000Z'),
          submissionCount: 150,
          unreadSubmissionsCount: 25,
          viewCount: 5000,
          publishedAt: DateTime.parse('2024-01-16T09:00:00.000Z'),
        );

        expect(page.id, equals('1'));
        expect(page.title, equals('Marketing Campaign Page'));
        expect(page.slug, equals('marketing-campaign-2024'));
        expect(page.status, equals(LandingPageStatus.published));
        expect(page.htmlContent, contains('Welcome'));
        expect(page.submissionCount, equals(150));
        expect(page.unreadSubmissionsCount, equals(25));
        expect(page.viewCount, equals(5000));
        expect(page.publishedAt, isNotNull);
      });

      test('draft page has minimal display data', () {
        final page = LandingPage(
          id: '2',
          title: 'Work in Progress',
          slug: 'work-in-progress',
          status: LandingPageStatus.draft,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        expect(page.status, equals(LandingPageStatus.draft));
        expect(page.publishedAt, isNull);
        expect(page.viewCount, isNull);
        expect(page.submissionCount, isNull);
      });
    });

    group('Status toggle logic', () {
      test('published page can be determined for unpublish action', () {
        final publishedPage = LandingPage(
          id: '1',
          title: 'Test',
          slug: 'test',
          status: LandingPageStatus.published,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final isPublished = publishedPage.status == LandingPageStatus.published;
        expect(isPublished, isTrue);

        // In the screen, this determines whether to show "Unpublish" or "Publish"
        final actionText = isPublished ? 'Unpublish' : 'Publish';
        expect(actionText, equals('Unpublish'));
      });

      test('draft page can be determined for publish action', () {
        final draftPage = LandingPage(
          id: '1',
          title: 'Test',
          slug: 'test',
          status: LandingPageStatus.draft,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final isPublished = draftPage.status == LandingPageStatus.published;
        expect(isPublished, isFalse);

        final actionText = isPublished ? 'Unpublish' : 'Publish';
        expect(actionText, equals('Publish'));
      });
    });

    group('Preview URL construction', () {
      test('can construct preview URL from slug', () {
        final page = LandingPage(
          id: '1',
          title: 'Test Page',
          slug: 'my-awesome-landing-page',
          status: LandingPageStatus.published,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        // Simulates URL construction logic from the screen
        final baseUrl = 'http://localhost:3000';
        final previewUrl = '$baseUrl/p/${page.slug}';

        expect(previewUrl, equals('http://localhost:3000/p/my-awesome-landing-page'));
      });

      test('handles slug with special characters', () {
        final page = LandingPage(
          id: '1',
          title: 'Test Page',
          slug: 'page-2024-01',
          status: LandingPageStatus.draft,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final baseUrl = 'http://localhost:3000';
        final previewUrl = '$baseUrl/p/${page.slug}';

        expect(previewUrl, contains('page-2024-01'));
      });

      test('can parse preview URL as URI', () {
        final page = LandingPage(
          id: '1',
          title: 'Test Page',
          slug: 'test-page',
          status: LandingPageStatus.published,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final previewUrl = Uri.parse('http://localhost:3000/p/${page.slug}');

        expect(previewUrl.scheme, equals('http'));
        expect(previewUrl.host, equals('localhost'));
        expect(previewUrl.port, equals(3000));
        expect(previewUrl.path, equals('/p/test-page'));
      });
    });

    group('Stats card data', () {
      test('view count displays correctly', () {
        final page = LandingPage(
          id: '1',
          title: 'Test',
          slug: 'test',
          status: LandingPageStatus.published,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          viewCount: 1000,
        );

        final displayValue = '${page.viewCount ?? 0}';
        expect(displayValue, equals('1000'));
      });

      test('submission count displays correctly', () {
        final page = LandingPage(
          id: '1',
          title: 'Test',
          slug: 'test',
          status: LandingPageStatus.published,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          submissionCount: 50,
        );

        final displayValue = '${page.submissionCount ?? 0}';
        expect(displayValue, equals('50'));
      });

      test('null stats default to zero', () {
        final page = LandingPage(
          id: '1',
          title: 'Test',
          slug: 'test',
          status: LandingPageStatus.draft,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        expect('${page.viewCount ?? 0}', equals('0'));
        expect('${page.submissionCount ?? 0}', equals('0'));
      });

      test('large view counts display correctly', () {
        final page = LandingPage(
          id: '1',
          title: 'Test',
          slug: 'test',
          status: LandingPageStatus.published,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          viewCount: 1000000,
        );

        final displayValue = '${page.viewCount ?? 0}';
        expect(displayValue, equals('1000000'));
      });
    });

    group('Detail row data', () {
      test('status displays as text', () {
        final publishedPage = LandingPage(
          id: '1',
          title: 'Test',
          slug: 'test',
          status: LandingPageStatus.published,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final draftPage = LandingPage(
          id: '2',
          title: 'Test 2',
          slug: 'test-2',
          status: LandingPageStatus.draft,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final isPublished1 = publishedPage.status == LandingPageStatus.published;
        final isPublished2 = draftPage.status == LandingPageStatus.published;

        expect(isPublished1 ? 'Published' : 'Draft', equals('Published'));
        expect(isPublished2 ? 'Published' : 'Draft', equals('Draft'));
      });

      test('unread submissions display when present', () {
        final pageWithUnread = LandingPage(
          id: '1',
          title: 'Test',
          slug: 'test',
          status: LandingPageStatus.published,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          unreadSubmissionsCount: 10,
        );

        final pageWithoutUnread = LandingPage(
          id: '2',
          title: 'Test 2',
          slug: 'test-2',
          status: LandingPageStatus.published,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          unreadSubmissionsCount: 0,
        );

        final pageWithNullUnread = LandingPage(
          id: '3',
          title: 'Test 3',
          slug: 'test-3',
          status: LandingPageStatus.draft,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        // Logic from screen: show unread if not null and > 0
        final showUnread1 = pageWithUnread.unreadSubmissionsCount != null &&
            pageWithUnread.unreadSubmissionsCount! > 0;
        final showUnread2 = pageWithoutUnread.unreadSubmissionsCount != null &&
            pageWithoutUnread.unreadSubmissionsCount! > 0;
        final showUnread3 = pageWithNullUnread.unreadSubmissionsCount != null &&
            pageWithNullUnread.unreadSubmissionsCount! > 0;

        expect(showUnread1, isTrue);
        expect(showUnread2, isFalse);
        expect(showUnread3, isFalse);
      });

      test('publishedAt conditional display', () {
        final pageWithPublishedAt = LandingPage(
          id: '1',
          title: 'Test',
          slug: 'test',
          status: LandingPageStatus.published,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          publishedAt: DateTime.parse('2024-01-15T10:00:00.000Z'),
        );

        final pageWithoutPublishedAt = LandingPage(
          id: '2',
          title: 'Test 2',
          slug: 'test-2',
          status: LandingPageStatus.draft,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        // Logic from screen: show published date if not null
        expect(pageWithPublishedAt.publishedAt != null, isTrue);
        expect(pageWithoutPublishedAt.publishedAt != null, isFalse);
      });
    });

    group('HTML content handling', () {
      test('htmlContent can contain various HTML tags', () {
        final page = LandingPage(
          id: '1',
          title: 'Test',
          slug: 'test',
          status: LandingPageStatus.published,
          htmlContent:
              '<html><head><title>Test</title></head><body><h1>Hello</h1><p>World</p></body></html>',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        expect(page.htmlContent, contains('<html>'));
        expect(page.htmlContent, contains('<h1>'));
        expect(page.htmlContent, contains('Hello'));
      });

      test('htmlContent can be null', () {
        final page = LandingPage(
          id: '1',
          title: 'Test',
          slug: 'test',
          status: LandingPageStatus.draft,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        expect(page.htmlContent, isNull);
      });

      test('htmlContent can be empty string', () {
        final page = LandingPage(
          id: '1',
          title: 'Test',
          slug: 'test',
          status: LandingPageStatus.draft,
          htmlContent: '',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        expect(page.htmlContent, equals(''));
        expect(page.htmlContent, isEmpty);
      });
    });

    group('Date formatting scenarios', () {
      test('createdAt and updatedAt are always present', () {
        final page = LandingPage(
          id: '1',
          title: 'Test',
          slug: 'test',
          status: LandingPageStatus.draft,
          createdAt: DateTime.parse('2024-01-15T10:30:00.000Z'),
          updatedAt: DateTime.parse('2024-01-16T11:00:00.000Z'),
        );

        expect(page.createdAt, isNotNull);
        expect(page.updatedAt, isNotNull);
        expect(page.updatedAt.isAfter(page.createdAt), isTrue);
      });

      test('dates can be compared for sorting', () {
        final page = LandingPage(
          id: '1',
          title: 'Test',
          slug: 'test',
          status: LandingPageStatus.published,
          createdAt: DateTime.parse('2024-01-15T10:00:00.000Z'),
          updatedAt: DateTime.parse('2024-01-20T10:00:00.000Z'),
          publishedAt: DateTime.parse('2024-01-16T10:00:00.000Z'),
        );

        expect(page.createdAt.isBefore(page.publishedAt!), isTrue);
        expect(page.publishedAt!.isBefore(page.updatedAt), isTrue);
      });

      test('timezone handling in date parsing', () {
        final page = LandingPage.fromJson({
          'id': '1',
          'title': 'Test',
          'slug': 'test',
          'status': 'published',
          'created_at': '2024-01-15T10:30:00.000Z',
          'updated_at': '2024-01-16T11:00:00.000Z',
        });

        // Dates should be parsed correctly in UTC
        expect(page.createdAt.isUtc, isTrue);
        expect(page.updatedAt.isUtc, isTrue);
      });
    });

    group('Entity association', () {
      test('entityId can be present', () {
        final page = LandingPage(
          id: '1',
          entityId: 'entity-123',
          title: 'Test',
          slug: 'test',
          status: LandingPageStatus.draft,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        expect(page.entityId, equals('entity-123'));
      });

      test('entityId can be null', () {
        final page = LandingPage(
          id: '1',
          title: 'Test',
          slug: 'test',
          status: LandingPageStatus.draft,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        expect(page.entityId, isNull);
      });
    });
  });

  group('LandingPage JSON roundtrip for detail screen', () {
    test('full data roundtrip preserves all fields', () {
      final original = LandingPage(
        id: '123',
        entityId: '456',
        title: 'Test Landing Page',
        slug: 'test-landing-page',
        status: LandingPageStatus.published,
        htmlContent: '<div>Content</div>',
        createdAt: DateTime.parse('2024-01-15T10:30:00.000Z'),
        updatedAt: DateTime.parse('2024-01-16T11:00:00.000Z'),
        submissionCount: 100,
        viewCount: 500,
        publishedAt: DateTime.parse('2024-01-15T12:00:00.000Z'),
      );

      final json = original.toJson();
      final restored = LandingPage.fromJson(json);

      expect(restored.id, equals(original.id));
      expect(restored.entityId, equals(original.entityId));
      expect(restored.title, equals(original.title));
      expect(restored.slug, equals(original.slug));
      expect(restored.status, equals(original.status));
      expect(restored.htmlContent, equals(original.htmlContent));
      expect(restored.submissionCount, equals(original.submissionCount));
      expect(restored.viewCount, equals(original.viewCount));
    });

    test('minimal data roundtrip works', () {
      final original = LandingPage(
        id: '1',
        title: 'Minimal Page',
        slug: 'minimal',
        status: LandingPageStatus.draft,
        createdAt: DateTime.parse('2024-01-15T10:00:00.000Z'),
        updatedAt: DateTime.parse('2024-01-15T10:00:00.000Z'),
      );

      final json = original.toJson();
      final restored = LandingPage.fromJson(json);

      expect(restored.id, equals(original.id));
      expect(restored.title, equals(original.title));
      expect(restored.slug, equals(original.slug));
      expect(restored.status, equals(original.status));
      expect(restored.entityId, isNull);
      expect(restored.htmlContent, isNull);
      expect(restored.submissionCount, isNull);
      expect(restored.viewCount, isNull);
      expect(restored.publishedAt, isNull);
    });
  });
}
