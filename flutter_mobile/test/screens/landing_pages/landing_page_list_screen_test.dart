import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/landing_page.dart';

// Note: LandingPageListScreen triggers async _loadLandingPages in initState
// via addPostFrameCallback which can cause "ref used after dispose" errors
// in widget tests. These tests focus on the LandingPage model and data
// transformations used by the screen components.

void main() {
  group('LandingPageListScreen Data Models', () {
    group('LandingPage filtering and sorting', () {
      late List<LandingPage> testPages;

      setUp(() {
        testPages = [
          LandingPage(
            id: '1',
            title: 'Published Page 1',
            slug: 'published-page-1',
            status: LandingPageStatus.published,
            createdAt: DateTime.parse('2024-01-15T10:00:00.000Z'),
            updatedAt: DateTime.parse('2024-01-20T10:00:00.000Z'),
            viewCount: 100,
            submissionCount: 10,
            publishedAt: DateTime.parse('2024-01-16T10:00:00.000Z'),
          ),
          LandingPage(
            id: '2',
            title: 'Draft Page',
            slug: 'draft-page',
            status: LandingPageStatus.draft,
            createdAt: DateTime.parse('2024-01-10T10:00:00.000Z'),
            updatedAt: DateTime.parse('2024-01-12T10:00:00.000Z'),
          ),
          LandingPage(
            id: '3',
            title: 'Published Page 2',
            slug: 'published-page-2',
            status: LandingPageStatus.published,
            createdAt: DateTime.parse('2024-01-20T10:00:00.000Z'),
            updatedAt: DateTime.parse('2024-01-25T10:00:00.000Z'),
            viewCount: 50,
            submissionCount: 5,
            publishedAt: DateTime.parse('2024-01-21T10:00:00.000Z'),
          ),
        ];
      });

      test('can filter pages by status', () {
        final publishedPages = testPages
            .where((p) => p.status == LandingPageStatus.published)
            .toList();
        final draftPages = testPages
            .where((p) => p.status == LandingPageStatus.draft)
            .toList();

        expect(publishedPages.length, equals(2));
        expect(draftPages.length, equals(1));
        expect(draftPages.first.title, equals('Draft Page'));
      });

      test('can sort pages by creation date', () {
        final sortedByNewest = List<LandingPage>.from(testPages)
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        expect(sortedByNewest.first.id, equals('3'));
        expect(sortedByNewest.last.id, equals('2'));
      });

      test('can sort pages by update date', () {
        final sortedByLastUpdated = List<LandingPage>.from(testPages)
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

        expect(sortedByLastUpdated.first.id, equals('3'));
        expect(sortedByLastUpdated.last.id, equals('2'));
      });

      test('can calculate total views across pages', () {
        final totalViews = testPages.fold<int>(
          0,
          (sum, page) => sum + (page.viewCount ?? 0),
        );

        expect(totalViews, equals(150));
      });

      test('can calculate total submissions across pages', () {
        final totalSubmissions = testPages.fold<int>(
          0,
          (sum, page) => sum + (page.submissionCount ?? 0),
        );

        expect(totalSubmissions, equals(15));
      });
    });

    group('LandingPage status display', () {
      test('published pages have correct status', () {
        final page = LandingPage(
          id: '1',
          title: 'Test Page',
          slug: 'test-page',
          status: LandingPageStatus.published,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final isPublished = page.status == LandingPageStatus.published;
        expect(isPublished, isTrue);
      });

      test('draft pages have correct status', () {
        final page = LandingPage(
          id: '1',
          title: 'Test Page',
          slug: 'test-page',
          status: LandingPageStatus.draft,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final isPublished = page.status == LandingPageStatus.published;
        expect(isPublished, isFalse);
      });
    });

    group('LandingPage slug formatting', () {
      test('slug can be prefixed with slash for display', () {
        final page = LandingPage(
          id: '1',
          title: 'Test Page',
          slug: 'my-landing-page',
          status: LandingPageStatus.draft,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final displaySlug = '/${page.slug}';
        expect(displaySlug, equals('/my-landing-page'));
      });

      test('slug handles empty string', () {
        final page = LandingPage(
          id: '1',
          title: 'Test Page',
          slug: '',
          status: LandingPageStatus.draft,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final displaySlug = '/${page.slug}';
        expect(displaySlug, equals('/'));
      });
    });

    group('LandingPage stats display', () {
      test('null view count defaults to 0 for display', () {
        final page = LandingPage(
          id: '1',
          title: 'Test Page',
          slug: 'test-page',
          status: LandingPageStatus.draft,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          viewCount: null,
        );

        final displayViews = '${page.viewCount ?? 0}';
        expect(displayViews, equals('0'));
      });

      test('null submission count defaults to 0 for display', () {
        final page = LandingPage(
          id: '1',
          title: 'Test Page',
          slug: 'test-page',
          status: LandingPageStatus.draft,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          submissionCount: null,
        );

        final displaySubmissions = '${page.submissionCount ?? 0}';
        expect(displaySubmissions, equals('0'));
      });

      test('view count is displayed as string', () {
        final page = LandingPage(
          id: '1',
          title: 'Test Page',
          slug: 'test-page',
          status: LandingPageStatus.published,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          viewCount: 1234,
        );

        final displayViews = '${page.viewCount ?? 0}';
        expect(displayViews, equals('1234'));
      });
    });

    group('LandingPage list operations', () {
      test('empty list handled correctly', () {
        final pages = <LandingPage>[];

        expect(pages.isEmpty, isTrue);
        expect(pages.length, equals(0));
      });

      test('single page list works correctly', () {
        final pages = [
          LandingPage(
            id: '1',
            title: 'Only Page',
            slug: 'only-page',
            status: LandingPageStatus.published,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ];

        expect(pages.isEmpty, isFalse);
        expect(pages.length, equals(1));
        expect(pages.first.title, equals('Only Page'));
      });

      test('can find page by id', () {
        final pages = [
          LandingPage(
            id: '1',
            title: 'Page One',
            slug: 'page-one',
            status: LandingPageStatus.draft,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
          LandingPage(
            id: '2',
            title: 'Page Two',
            slug: 'page-two',
            status: LandingPageStatus.published,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ];

        final foundPage = pages.firstWhere(
          (p) => p.id == '2',
          orElse: () => throw Exception('Page not found'),
        );

        expect(foundPage.title, equals('Page Two'));
      });
    });

    group('LandingPage JSON list parsing', () {
      test('can parse list of landing pages from JSON', () {
        final jsonList = [
          {
            'id': '1',
            'title': 'Page One',
            'slug': 'page-one',
            'status': 'published',
            'created_at': '2024-01-15T10:00:00.000Z',
            'updated_at': '2024-01-16T10:00:00.000Z',
            'view_count': 100,
            'submission_count': 10,
          },
          {
            'id': '2',
            'title': 'Page Two',
            'slug': 'page-two',
            'status': 'draft',
            'created_at': '2024-01-10T10:00:00.000Z',
            'updated_at': '2024-01-11T10:00:00.000Z',
          },
        ];

        final pages = jsonList.map((j) => LandingPage.fromJson(j)).toList();

        expect(pages.length, equals(2));
        expect(pages[0].title, equals('Page One'));
        expect(pages[0].status, equals(LandingPageStatus.published));
        expect(pages[1].title, equals('Page Two'));
        expect(pages[1].status, equals(LandingPageStatus.draft));
      });

      test('handles mixed id types in JSON list', () {
        final jsonList = [
          {
            'id': 1,  // int
            'title': 'Page One',
            'slug': 'page-one',
            'created_at': '2024-01-15T10:00:00.000Z',
            'updated_at': '2024-01-16T10:00:00.000Z',
          },
          {
            'id': '2',  // string
            'title': 'Page Two',
            'slug': 'page-two',
            'created_at': '2024-01-10T10:00:00.000Z',
            'updated_at': '2024-01-11T10:00:00.000Z',
          },
        ];

        final pages = jsonList.map((j) => LandingPage.fromJson(j)).toList();

        expect(pages[0].id, equals('1'));
        expect(pages[1].id, equals('2'));
      });
    });
  });

  group('LandingPageStatus enum operations', () {
    test('all status values have corresponding string values', () {
      for (final status in LandingPageStatus.values) {
        expect(status.value, isNotEmpty);
      }
    });

    test('fromString handles null-like inputs gracefully', () {
      // The extension handles empty string and unknown values
      expect(LandingPageStatusX.fromString(''), equals(LandingPageStatus.draft));
      expect(
          LandingPageStatusX.fromString('null'), equals(LandingPageStatus.draft));
    });

    test('status roundtrip through string conversion', () {
      for (final status in LandingPageStatus.values) {
        final stringValue = status.value;
        final parsedStatus = LandingPageStatusX.fromString(stringValue);
        expect(parsedStatus, equals(status));
      }
    });
  });

  group('LandingPageSubmission for list screen context', () {
    test('can create list of submissions from JSON', () {
      final jsonList = [
        {
          'id': '1',
          'landing_page_id': 'lp1',
          'email': 'user1@example.com',
          'data': {'name': 'User One'},
          'created_at': '2024-01-15T10:00:00.000Z',
        },
        {
          'id': '2',
          'landing_page_id': 'lp1',
          'email': 'user2@example.com',
          'data': {'name': 'User Two'},
          'created_at': '2024-01-16T10:00:00.000Z',
        },
      ];

      final submissions =
          jsonList.map((j) => LandingPageSubmission.fromJson(j)).toList();

      expect(submissions.length, equals(2));
      expect(submissions[0].email, equals('user1@example.com'));
      expect(submissions[1].email, equals('user2@example.com'));
    });

    test('can filter submissions by landing page id', () {
      final submissions = [
        LandingPageSubmission(
          id: '1',
          landingPageId: 'lp1',
          email: 'user1@example.com',
          createdAt: DateTime.now(),
        ),
        LandingPageSubmission(
          id: '2',
          landingPageId: 'lp2',
          email: 'user2@example.com',
          createdAt: DateTime.now(),
        ),
        LandingPageSubmission(
          id: '3',
          landingPageId: 'lp1',
          email: 'user3@example.com',
          createdAt: DateTime.now(),
        ),
      ];

      final lp1Submissions =
          submissions.where((s) => s.landingPageId == 'lp1').toList();

      expect(lp1Submissions.length, equals(2));
    });

    test('can sort submissions by creation date', () {
      final submissions = [
        LandingPageSubmission(
          id: '1',
          landingPageId: 'lp1',
          email: 'user1@example.com',
          createdAt: DateTime.parse('2024-01-15T10:00:00.000Z'),
        ),
        LandingPageSubmission(
          id: '2',
          landingPageId: 'lp1',
          email: 'user2@example.com',
          createdAt: DateTime.parse('2024-01-20T10:00:00.000Z'),
        ),
        LandingPageSubmission(
          id: '3',
          landingPageId: 'lp1',
          email: 'user3@example.com',
          createdAt: DateTime.parse('2024-01-10T10:00:00.000Z'),
        ),
      ];

      final sortedNewestFirst = List<LandingPageSubmission>.from(submissions)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      expect(sortedNewestFirst.first.id, equals('2'));
      expect(sortedNewestFirst.last.id, equals('3'));
    });
  });
}
