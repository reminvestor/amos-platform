import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/campaign.dart';

void main() {
  group('MailgunStats', () {
    test('creates with default values', () {
      final stats = MailgunStats();

      expect(stats.delivered, equals(0));
      expect(stats.failed, equals(0));
      expect(stats.bounced, equals(0));
      expect(stats.unsubscribed, equals(0));
      expect(stats.complained, equals(0));
      expect(stats.opened, equals(0));
      expect(stats.clicked, equals(0));
    });

    test('creates with custom values', () {
      final stats = MailgunStats(
        delivered: 100,
        failed: 5,
        bounced: 3,
        unsubscribed: 2,
        complained: 1,
        opened: 50,
        clicked: 25,
      );

      expect(stats.delivered, equals(100));
      expect(stats.failed, equals(5));
      expect(stats.bounced, equals(3));
      expect(stats.unsubscribed, equals(2));
      expect(stats.complained, equals(1));
      expect(stats.opened, equals(50));
      expect(stats.clicked, equals(25));
    });

    test('fromJson parses correctly', () {
      final json = {
        'delivered': 100,
        'failed': 5,
        'bounced': 3,
        'unsubscribed': 2,
        'complained': 1,
        'opened': 50,
        'clicked': 25,
      };

      final stats = MailgunStats.fromJson(json);

      expect(stats.delivered, equals(100));
      expect(stats.failed, equals(5));
      expect(stats.bounced, equals(3));
      expect(stats.unsubscribed, equals(2));
      expect(stats.complained, equals(1));
      expect(stats.opened, equals(50));
      expect(stats.clicked, equals(25));
    });

    test('fromJson handles missing fields with defaults', () {
      final json = <String, dynamic>{};

      final stats = MailgunStats.fromJson(json);

      expect(stats.delivered, equals(0));
      expect(stats.failed, equals(0));
      expect(stats.bounced, equals(0));
      expect(stats.unsubscribed, equals(0));
      expect(stats.complained, equals(0));
      expect(stats.opened, equals(0));
      expect(stats.clicked, equals(0));
    });
  });

  group('CampaignStatus', () {
    test('value returns correct string', () {
      expect(CampaignStatus.draft.value, equals('draft'));
      expect(CampaignStatus.scheduled.value, equals('scheduled'));
      expect(CampaignStatus.inProgress.value, equals('in_progress'));
      expect(CampaignStatus.completed.value, equals('completed'));
      expect(CampaignStatus.paused.value, equals('paused'));
      expect(CampaignStatus.stopped.value, equals('stopped'));
    });

    test('fromString converts string to enum correctly', () {
      expect(CampaignStatusX.fromString('draft'), equals(CampaignStatus.draft));
      expect(CampaignStatusX.fromString('scheduled'), equals(CampaignStatus.scheduled));
      expect(CampaignStatusX.fromString('in_progress'), equals(CampaignStatus.inProgress));
      expect(CampaignStatusX.fromString('completed'), equals(CampaignStatus.completed));
      expect(CampaignStatusX.fromString('paused'), equals(CampaignStatus.paused));
      expect(CampaignStatusX.fromString('stopped'), equals(CampaignStatus.stopped));
    });

    test('fromString returns draft for unknown values', () {
      expect(CampaignStatusX.fromString('unknown'), equals(CampaignStatus.draft));
      expect(CampaignStatusX.fromString(''), equals(CampaignStatus.draft));
    });
  });

  group('Campaign', () {
    test('fromJson parses complete JSON correctly', () {
      final json = {
        'id': 1,
        'entity_id': '123',
        'user_id': '456',
        'name': 'Test Campaign',
        'subject': 'Test Subject',
        'description': 'Test Description',
        'content': '<p>Test Content</p>',
        'status': 'scheduled',
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-16T11:00:00.000Z',
        'scheduled_at': '2024-01-20T09:00:00.000Z',
        'contact_count': 100,
        'sent_count': 50,
        'open_rate': 0.45,
        'click_rate': 0.15,
        'bounce_rate': 0.02,
        'mailgun_stats': {
          'delivered': 50,
          'opened': 22,
          'clicked': 7,
        },
      };

      final campaign = Campaign.fromJson(json);

      expect(campaign.id, equals('1'));
      expect(campaign.entityId, equals('123'));
      expect(campaign.userId, equals('456'));
      expect(campaign.name, equals('Test Campaign'));
      expect(campaign.subject, equals('Test Subject'));
      expect(campaign.description, equals('Test Description'));
      expect(campaign.content, equals('<p>Test Content</p>'));
      expect(campaign.status, equals(CampaignStatus.scheduled));
      expect(campaign.createdAt, equals(DateTime.parse('2024-01-15T10:30:00.000Z')));
      expect(campaign.updatedAt, equals(DateTime.parse('2024-01-16T11:00:00.000Z')));
      expect(campaign.scheduledAt, equals(DateTime.parse('2024-01-20T09:00:00.000Z')));
      expect(campaign.contactCount, equals(100));
      expect(campaign.sentCount, equals(50));
      expect(campaign.openRate, equals(0.45));
      expect(campaign.clickRate, equals(0.15));
      expect(campaign.bounceRate, equals(0.02));
      expect(campaign.mailgunStats, isNotNull);
      expect(campaign.mailgunStats!.delivered, equals(50));
    });

    test('fromJson handles minimal required fields', () {
      final json = {
        'id': '123',
        'name': 'Test',
        'subject': 'Subject',
        'status': 'draft',
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-16T11:00:00.000Z',
      };

      final campaign = Campaign.fromJson(json);

      expect(campaign.id, equals('123'));
      expect(campaign.name, equals('Test'));
      expect(campaign.subject, equals('Subject'));
      expect(campaign.status, equals(CampaignStatus.draft));
      expect(campaign.entityId, isNull);
      expect(campaign.description, isNull);
      expect(campaign.scheduledAt, isNull);
      expect(campaign.mailgunStats, isNull);
    });

    test('fromJson handles missing name and subject with defaults', () {
      final json = {
        'id': '123',
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-16T11:00:00.000Z',
      };

      final campaign = Campaign.fromJson(json);

      expect(campaign.name, equals(''));
      expect(campaign.subject, equals(''));
      expect(campaign.status, equals(CampaignStatus.draft));
    });

    test('toJson serializes correctly', () {
      final campaign = Campaign(
        id: '123',
        entityId: '456',
        userId: '789',
        name: 'Test Campaign',
        subject: 'Test Subject',
        description: 'Test Description',
        content: '<p>Content</p>',
        status: CampaignStatus.scheduled,
        createdAt: DateTime.parse('2024-01-15T10:30:00.000Z'),
        updatedAt: DateTime.parse('2024-01-16T11:00:00.000Z'),
        scheduledAt: DateTime.parse('2024-01-20T09:00:00.000Z'),
        contactCount: 100,
        openRate: 0.5,
      );

      final json = campaign.toJson();

      expect(json['id'], equals('123'));
      expect(json['entity_id'], equals('456'));
      expect(json['user_id'], equals('789'));
      expect(json['name'], equals('Test Campaign'));
      expect(json['subject'], equals('Test Subject'));
      expect(json['description'], equals('Test Description'));
      expect(json['content'], equals('<p>Content</p>'));
      expect(json['status'], equals('scheduled'));
      expect(json['scheduled_at'], equals('2024-01-20T09:00:00.000Z'));
      expect(json['contact_count'], equals(100));
      expect(json['open_rate'], equals(0.5));
    });

    test('toJson excludes null optional fields', () {
      final campaign = Campaign(
        id: '123',
        name: 'Test',
        subject: 'Subject',
        status: CampaignStatus.draft,
        createdAt: DateTime.parse('2024-01-15T10:30:00.000Z'),
        updatedAt: DateTime.parse('2024-01-16T11:00:00.000Z'),
      );

      final json = campaign.toJson();

      expect(json.containsKey('description'), isFalse);
      expect(json.containsKey('content'), isFalse);
      expect(json.containsKey('scheduled_at'), isFalse);
      expect(json.containsKey('contact_count'), isFalse);
      expect(json.containsKey('open_rate'), isFalse);
    });
  });
}
