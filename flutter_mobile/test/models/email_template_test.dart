import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/email_template.dart';

void main() {
  group('EmailTemplate', () {
    test('fromJson parses complete JSON correctly', () {
      final json = {
        'id': 1,
        'name': 'Welcome Email',
        'subject': 'Welcome to AMOS!',
        'body': '<h1>Welcome</h1><p>Thank you for joining us.</p>',
        'description': 'Template for new user welcome emails',
        'campaigns_count': 5,
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-16T11:00:00.000Z',
      };

      final template = EmailTemplate.fromJson(json);

      expect(template.id, equals('1'));
      expect(template.name, equals('Welcome Email'));
      expect(template.subject, equals('Welcome to AMOS!'));
      expect(template.body, equals('<h1>Welcome</h1><p>Thank you for joining us.</p>'));
      expect(template.description, equals('Template for new user welcome emails'));
      expect(template.campaignsCount, equals(5));
      expect(template.createdAt, equals(DateTime.parse('2024-01-15T10:30:00.000Z')));
      expect(template.updatedAt, equals(DateTime.parse('2024-01-16T11:00:00.000Z')));
    });

    test('fromJson handles minimal required fields with defaults', () {
      final json = {
        'id': '123',
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-16T11:00:00.000Z',
      };

      final template = EmailTemplate.fromJson(json);

      expect(template.id, equals('123'));
      expect(template.name, equals(''));
      expect(template.subject, equals(''));
      expect(template.body, equals(''));
      expect(template.description, isNull);
      expect(template.campaignsCount, equals(0));
    });

    test('toJson serializes correctly', () {
      final template = EmailTemplate(
        id: '123',
        name: 'Welcome Email',
        subject: 'Welcome!',
        body: '<p>Hello</p>',
        description: 'Welcome template',
        campaignsCount: 3,
        createdAt: DateTime.parse('2024-01-15T10:30:00.000Z'),
        updatedAt: DateTime.parse('2024-01-16T11:00:00.000Z'),
      );

      final json = template.toJson();

      expect(json['id'], equals('123'));
      expect(json['name'], equals('Welcome Email'));
      expect(json['subject'], equals('Welcome!'));
      expect(json['body'], equals('<p>Hello</p>'));
      expect(json['description'], equals('Welcome template'));
      expect(json['campaigns_count'], equals(3));
    });

    test('toJson excludes null description', () {
      final template = EmailTemplate(
        id: '123',
        name: 'Test',
        subject: 'Test',
        body: 'Test',
        createdAt: DateTime.parse('2024-01-15T10:30:00.000Z'),
        updatedAt: DateTime.parse('2024-01-16T11:00:00.000Z'),
      );

      final json = template.toJson();

      expect(json.containsKey('description'), isFalse);
    });

    test('bodyPreview strips HTML tags', () {
      final template = EmailTemplate(
        id: '123',
        name: 'Test',
        subject: 'Test',
        body: '<h1>Hello</h1><p>This is a <strong>test</strong> email.</p>',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Note: Adjacent tags result in no space between them
      expect(template.bodyPreview, equals('HelloThis is a test email.'));
    });

    test('bodyPreview normalizes whitespace', () {
      final template = EmailTemplate(
        id: '123',
        name: 'Test',
        subject: 'Test',
        body: '<p>Hello    world</p>\n\n<p>New paragraph</p>',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(template.bodyPreview, equals('Hello world New paragraph'));
    });

    test('bodyPreview truncates long content with ellipsis', () {
      final longBody = '<p>${'A' * 150}</p>';
      final template = EmailTemplate(
        id: '123',
        name: 'Test',
        subject: 'Test',
        body: longBody,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(template.bodyPreview.length, equals(103)); // 100 chars + '...'
      expect(template.bodyPreview.endsWith('...'), isTrue);
    });

    test('bodyPreview returns full content when under 100 chars', () {
      final template = EmailTemplate(
        id: '123',
        name: 'Test',
        subject: 'Test',
        body: '<p>Short content</p>',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(template.bodyPreview, equals('Short content'));
      expect(template.bodyPreview.endsWith('...'), isFalse);
    });

    test('bodyPreview handles empty body', () {
      final template = EmailTemplate(
        id: '123',
        name: 'Test',
        subject: 'Test',
        body: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(template.bodyPreview, equals(''));
    });
  });
}
