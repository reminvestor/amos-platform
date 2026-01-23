import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/email_template.dart';

void main() {
  group('EmailTemplate', () {
    final createdAt = DateTime(2025, 1, 15, 10, 0);
    final updatedAt = DateTime(2025, 1, 15, 12, 0);

    test('creates with required values', () {
      final template = EmailTemplate(
        id: '1',
        name: 'Welcome Email',
        subject: 'Welcome to Our Service!',
        body: '<h1>Welcome!</h1><p>Thank you for joining us.</p>',
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      expect(template.id, '1');
      expect(template.name, 'Welcome Email');
      expect(template.subject, 'Welcome to Our Service!');
      expect(template.body, '<h1>Welcome!</h1><p>Thank you for joining us.</p>');
      expect(template.description, isNull);
      expect(template.campaignsCount, 0);
      expect(template.createdAt, createdAt);
      expect(template.updatedAt, updatedAt);
    });

    test('creates with all optional values', () {
      final template = EmailTemplate(
        id: '2',
        name: 'Newsletter Template',
        subject: 'Monthly Newsletter',
        body: '<p>Hello {{name}},</p><p>Here is your newsletter.</p>',
        description: 'Standard monthly newsletter template',
        campaignsCount: 15,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      expect(template.description, 'Standard monthly newsletter template');
      expect(template.campaignsCount, 15);
    });

    test('fromJson parses complete data', () {
      final json = {
        'id': 123,
        'name': 'Promotional Email',
        'subject': 'Special Offer Inside!',
        'body': '<h1>Special Offer</h1><p>Get 50% off today!</p>',
        'description': 'Template for promotional campaigns',
        'campaigns_count': 25,
        'created_at': '2025-01-15T10:00:00Z',
        'updated_at': '2025-01-15T12:00:00Z',
      };

      final template = EmailTemplate.fromJson(json);

      expect(template.id, '123');
      expect(template.name, 'Promotional Email');
      expect(template.subject, 'Special Offer Inside!');
      expect(template.body, '<h1>Special Offer</h1><p>Get 50% off today!</p>');
      expect(template.description, 'Template for promotional campaigns');
      expect(template.campaignsCount, 25);
      expect(template.createdAt.year, 2025);
      expect(template.createdAt.month, 1);
      expect(template.createdAt.day, 15);
    });

    test('fromJson handles minimal data', () {
      final json = {
        'id': 1,
        'created_at': '2025-01-15T10:00:00Z',
        'updated_at': '2025-01-15T10:00:00Z',
      };

      final template = EmailTemplate.fromJson(json);

      expect(template.id, '1');
      expect(template.name, '');
      expect(template.subject, '');
      expect(template.body, '');
      expect(template.description, isNull);
      expect(template.campaignsCount, 0);
    });

    test('fromJson handles string id', () {
      final json = {
        'id': 'template-abc-123',
        'name': 'Test',
        'subject': 'Test',
        'body': 'Test',
        'created_at': '2025-01-15T10:00:00Z',
        'updated_at': '2025-01-15T10:00:00Z',
      };

      final template = EmailTemplate.fromJson(json);

      expect(template.id, 'template-abc-123');
    });

    group('toJson', () {
      test('serializes all fields', () {
        final template = EmailTemplate(
          id: '1',
          name: 'Test Template',
          subject: 'Test Subject',
          body: '<p>Test body</p>',
          description: 'A test template',
          campaignsCount: 5,
          createdAt: DateTime.parse('2025-01-15T10:00:00Z'),
          updatedAt: DateTime.parse('2025-01-15T12:00:00Z'),
        );

        final json = template.toJson();

        expect(json['id'], '1');
        expect(json['name'], 'Test Template');
        expect(json['subject'], 'Test Subject');
        expect(json['body'], '<p>Test body</p>');
        expect(json['description'], 'A test template');
        expect(json['campaigns_count'], 5);
        expect(json['created_at'], isA<String>());
        expect(json['updated_at'], isA<String>());
      });

      test('excludes null description', () {
        final template = EmailTemplate(
          id: '1',
          name: 'Test',
          subject: 'Test',
          body: 'Test',
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        final json = template.toJson();

        expect(json.containsKey('description'), false);
      });

      test('includes description when present', () {
        final template = EmailTemplate(
          id: '1',
          name: 'Test',
          subject: 'Test',
          body: 'Test',
          description: 'Has description',
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        final json = template.toJson();

        expect(json.containsKey('description'), true);
        expect(json['description'], 'Has description');
      });
    });

    group('bodyPreview', () {
      test('returns full content when short', () {
        final template = EmailTemplate(
          id: '1',
          name: 'Test',
          subject: 'Test',
          body: '<p>Short content</p>',
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        expect(template.bodyPreview, 'Short content');
      });

      test('strips HTML tags', () {
        final template = EmailTemplate(
          id: '1',
          name: 'Test',
          subject: 'Test',
          body: '<h1>Title</h1><p>Some <strong>bold</strong> text</p>',
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        // HTML tags are stripped but no spaces are added between adjacent tags
        expect(template.bodyPreview, 'TitleSome bold text');
      });

      test('normalizes whitespace', () {
        final template = EmailTemplate(
          id: '1',
          name: 'Test',
          subject: 'Test',
          body: '<p>Multiple    spaces</p>\n\n<p>And   newlines</p>',
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        expect(template.bodyPreview, 'Multiple spaces And newlines');
      });

      test('truncates long content with ellipsis', () {
        final longBody = '<p>${'A' * 150}</p>';
        final template = EmailTemplate(
          id: '1',
          name: 'Test',
          subject: 'Test',
          body: longBody,
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        expect(template.bodyPreview.length, 103); // 100 chars + "..."
        expect(template.bodyPreview.endsWith('...'), true);
      });

      test('handles exactly 100 characters', () {
        final exactBody = '<p>${'B' * 100}</p>';
        final template = EmailTemplate(
          id: '1',
          name: 'Test',
          subject: 'Test',
          body: exactBody,
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        expect(template.bodyPreview, 'B' * 100);
        expect(template.bodyPreview.endsWith('...'), false);
      });

      test('handles empty body', () {
        final template = EmailTemplate(
          id: '1',
          name: 'Test',
          subject: 'Test',
          body: '',
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        expect(template.bodyPreview, '');
      });

      test('handles body with only HTML tags', () {
        final template = EmailTemplate(
          id: '1',
          name: 'Test',
          subject: 'Test',
          body: '<div><span></span></div>',
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        expect(template.bodyPreview, '');
      });

      test('handles body with HTML entities', () {
        final template = EmailTemplate(
          id: '1',
          name: 'Test',
          subject: 'Test',
          body: '<p>Price: &lt;\$50&gt;</p>',
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        // Note: HTML entities are not decoded, just tags are stripped
        expect(template.bodyPreview.contains('Price:'), true);
      });
    });

    test('round trips through JSON', () {
      final original = EmailTemplate(
        id: '1',
        name: 'Round Trip Test',
        subject: 'Test Subject',
        body: '<p>Test body</p>',
        description: 'Test description',
        campaignsCount: 10,
        createdAt: DateTime.parse('2025-01-15T10:00:00.000Z'),
        updatedAt: DateTime.parse('2025-01-15T12:00:00.000Z'),
      );

      final json = original.toJson();
      final restored = EmailTemplate.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.subject, original.subject);
      expect(restored.body, original.body);
      expect(restored.description, original.description);
      expect(restored.campaignsCount, original.campaignsCount);
    });

    test('creates templates for different use cases', () {
      final welcomeTemplate = EmailTemplate(
        id: '1',
        name: 'Welcome',
        subject: 'Welcome!',
        body: '<p>Welcome to our platform!</p>',
        campaignsCount: 0,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      final promoTemplate = EmailTemplate(
        id: '2',
        name: 'Promo',
        subject: '50% Off Sale!',
        body: '<p>Limited time offer!</p>',
        campaignsCount: 5,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      final newsletterTemplate = EmailTemplate(
        id: '3',
        name: 'Newsletter',
        subject: 'Weekly Update',
        body: '<p>This week\'s highlights...</p>',
        campaignsCount: 52,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      expect(welcomeTemplate.campaignsCount, 0);
      expect(promoTemplate.campaignsCount, 5);
      expect(newsletterTemplate.campaignsCount, 52);
    });
  });
}
