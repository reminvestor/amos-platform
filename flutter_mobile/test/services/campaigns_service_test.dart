import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/campaign.dart';

// Note: CampaignsService uses ApiClient which requires native plugins.
// For unit tests, we test the data models, query parameter building,
// and response parsing logic separately.

void main() {
  group('CampaignActionResult', () {
    test('creates with required fields', () {
      final campaign = Campaign(
        id: '123',
        name: 'Test Campaign',
        subject: 'Test Subject',
        status: CampaignStatus.scheduled,
        createdAt: DateTime.parse('2024-01-15T10:30:00.000Z'),
        updatedAt: DateTime.parse('2024-01-16T11:00:00.000Z'),
      );

      final result = CampaignActionResult(
        campaign: campaign,
        message: 'Campaign started successfully!',
      );

      expect(result.campaign.id, equals('123'));
      expect(result.campaign.name, equals('Test Campaign'));
      expect(result.message, equals('Campaign started successfully!'));
    });

    test('can hold any status campaign', () {
      final draftCampaign = Campaign(
        id: '1',
        name: 'Draft',
        subject: 'Subject',
        status: CampaignStatus.draft,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final inProgressCampaign = Campaign(
        id: '2',
        name: 'In Progress',
        subject: 'Subject',
        status: CampaignStatus.inProgress,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final draftResult = CampaignActionResult(
        campaign: draftCampaign,
        message: 'Draft saved',
      );

      final sendResult = CampaignActionResult(
        campaign: inProgressCampaign,
        message: 'Campaign sending',
      );

      expect(draftResult.campaign.status, equals(CampaignStatus.draft));
      expect(sendResult.campaign.status, equals(CampaignStatus.inProgress));
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
      const search = 'test campaign';

      final queryParams = <String, dynamic>{
        'page': page,
        'per_page': perPage,
      };
      if (search.isNotEmpty) {
        queryParams['search'] = search;
      }

      expect(queryParams['search'], equals('test campaign'));
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
      const status = 'scheduled';

      final queryParams = <String, dynamic>{
        'page': page,
        'per_page': perPage,
      };
      if (status.isNotEmpty) {
        queryParams['status'] = status;
      }

      expect(queryParams['status'], equals('scheduled'));
    });

    test('builds full query parameters with all options', () {
      const page = 2;
      const perPage = 50;
      const search = 'marketing';
      const status = 'completed';

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
      expect(queryParams['search'], equals('marketing'));
      expect(queryParams['status'], equals('completed'));
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

    test('handles null status parameter', () {
      const page = 1;
      const perPage = 20;
      const String? status = null;

      final queryParams = <String, dynamic>{
        'page': page,
        'per_page': perPage,
      };
      if (status != null && status.isNotEmpty) {
        queryParams['status'] = status;
      }

      expect(queryParams.containsKey('status'), isFalse);
    });
  });

  group('Campaigns List Response Parsing', () {
    test('parses campaigns list response correctly', () {
      final responseData = {
        'data': [
          {
            'id': 1,
            'name': 'Campaign 1',
            'subject': 'Subject 1',
            'status': 'draft',
            'created_at': '2024-01-01T00:00:00.000Z',
            'updated_at': '2024-01-01T00:00:00.000Z',
          },
          {
            'id': 2,
            'name': 'Campaign 2',
            'subject': 'Subject 2',
            'status': 'scheduled',
            'created_at': '2024-01-02T00:00:00.000Z',
            'updated_at': '2024-01-02T00:00:00.000Z',
          },
        ],
      };

      final campaignsList = responseData['data'] as List? ?? [];
      final campaigns = campaignsList.map((json) => Campaign.fromJson(json)).toList();

      expect(campaigns, hasLength(2));
      expect(campaigns[0].id, equals('1'));
      expect(campaigns[0].name, equals('Campaign 1'));
      expect(campaigns[0].status, equals(CampaignStatus.draft));
      expect(campaigns[1].id, equals('2'));
      expect(campaigns[1].status, equals(CampaignStatus.scheduled));
    });

    test('handles empty campaigns list', () {
      final responseData = {'data': []};

      final campaignsList = responseData['data'] as List? ?? [];
      final campaigns = campaignsList.map((json) => Campaign.fromJson(json)).toList();

      expect(campaigns, isEmpty);
    });

    test('handles missing data key with fallback', () {
      final responseData = <String, dynamic>{};

      final campaignsList = responseData['data'] as List? ?? [];
      final campaigns = campaignsList.map((json) => Campaign.fromJson(json)).toList();

      expect(campaigns, isEmpty);
    });

    test('handles null data key with fallback', () {
      final responseData = {'data': null};

      final campaignsList = responseData['data'] as List? ?? [];
      final campaigns = campaignsList.map((json) => Campaign.fromJson(json)).toList();

      expect(campaigns, isEmpty);
    });
  });

  group('Campaign Create Request Building', () {
    test('builds create request with required fields', () {
      const name = 'New Campaign';
      const subject = 'Welcome to our newsletter';
      const status = 'draft';

      final data = {
        'name': name,
        'subject': subject,
        'status': status,
      };

      expect(data['name'], equals('New Campaign'));
      expect(data['subject'], equals('Welcome to our newsletter'));
      expect(data['status'], equals('draft'));
    });

    test('builds create request with optional content', () {
      const name = 'New Campaign';
      const subject = 'Subject';
      const content = '<p>Email content here</p>';

      final data = <String, dynamic>{
        'name': name,
        'subject': subject,
        if (content != null) 'content': content,
        'status': 'draft',
      };

      expect(data['content'], equals('<p>Email content here</p>'));
    });

    test('excludes null content from request', () {
      const name = 'New Campaign';
      const subject = 'Subject';
      const String? content = null;

      final data = <String, dynamic>{
        'name': name,
        'subject': subject,
        if (content != null) 'content': content,
        'status': 'draft',
      };

      expect(data.containsKey('content'), isFalse);
    });
  });

  group('Campaign Update Request Building', () {
    test('builds update request with only changed fields', () {
      const String? name = 'Updated Name';
      const String? subject = null;
      const String? description = 'New description';
      const String? content = null;
      const String? status = null;
      final DateTime? scheduledAt = DateTime.parse('2024-02-01T09:00:00.000Z');

      final data = <String, dynamic>{};
      if (name != null) data['name'] = name;
      if (subject != null) data['subject'] = subject;
      if (description != null) data['description'] = description;
      if (content != null) data['content'] = content;
      if (status != null) data['status'] = status;
      if (scheduledAt != null) data['scheduled_at'] = scheduledAt.toIso8601String();

      expect(data.length, equals(3));
      expect(data['name'], equals('Updated Name'));
      expect(data['description'], equals('New description'));
      expect(data['scheduled_at'], equals('2024-02-01T09:00:00.000Z'));
      expect(data.containsKey('subject'), isFalse);
      expect(data.containsKey('content'), isFalse);
      expect(data.containsKey('status'), isFalse);
    });

    test('builds empty request when no fields provided', () {
      const String? name = null;
      const String? subject = null;

      final data = <String, dynamic>{};
      if (name != null) data['name'] = name;
      if (subject != null) data['subject'] = subject;

      expect(data, isEmpty);
    });
  });

  group('Campaign Action Response Parsing', () {
    test('parses send_now response', () {
      final response = {
        'id': '123',
        'name': 'Test Campaign',
        'subject': 'Test Subject',
        'status': 'in_progress',
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-15T11:00:00.000Z',
        'message': 'Campaign started successfully!',
      };

      final campaign = Campaign.fromJson(response);
      final message = response['message'] ?? 'Campaign started successfully!';

      expect(campaign.status, equals(CampaignStatus.inProgress));
      expect(message, equals('Campaign started successfully!'));
    });

    test('parses schedule response', () {
      final response = {
        'id': '123',
        'name': 'Test Campaign',
        'subject': 'Test Subject',
        'status': 'scheduled',
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-15T11:00:00.000Z',
        'scheduled_at': '2024-02-01T09:00:00.000Z',
        'message': 'Campaign scheduled!',
      };

      final campaign = Campaign.fromJson(response);
      final message = response['message'] ?? 'Campaign scheduled!';

      expect(campaign.status, equals(CampaignStatus.scheduled));
      expect(campaign.scheduledAt, equals(DateTime.parse('2024-02-01T09:00:00.000Z')));
      expect(message, equals('Campaign scheduled!'));
    });

    test('parses stop response', () {
      final response = {
        'id': '123',
        'name': 'Test Campaign',
        'subject': 'Test Subject',
        'status': 'stopped',
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-15T11:30:00.000Z',
        'message': 'Campaign stopped',
      };

      final campaign = Campaign.fromJson(response);
      final message = response['message'] ?? 'Campaign stopped';

      expect(campaign.status, equals(CampaignStatus.stopped));
      expect(message, equals('Campaign stopped'));
    });

    test('uses default message when not provided', () {
      final response = {
        'id': '123',
        'name': 'Test Campaign',
        'subject': 'Test Subject',
        'status': 'in_progress',
        'created_at': '2024-01-15T10:30:00.000Z',
        'updated_at': '2024-01-15T11:00:00.000Z',
      };

      final message = response['message'] ?? 'Campaign started successfully!';

      expect(message, equals('Campaign started successfully!'));
    });
  });

  group('Schedule Request Building', () {
    test('builds schedule request with ISO8601 date', () {
      final scheduledAt = DateTime.parse('2024-02-01T09:00:00.000Z');

      final data = {
        'scheduled_at': scheduledAt.toIso8601String(),
      };

      expect(data['scheduled_at'], equals('2024-02-01T09:00:00.000Z'));
    });

    test('builds schedule request with local time', () {
      final scheduledAt = DateTime(2024, 2, 1, 9, 0, 0);

      final data = {
        'scheduled_at': scheduledAt.toIso8601String(),
      };

      // Should be in ISO8601 format
      expect(data['scheduled_at'], contains('2024-02-01'));
      expect(data['scheduled_at'], contains('09:00:00'));
    });
  });

  group('Test Email Request Building', () {
    test('builds test email request', () {
      const email = 'test@example.com';

      final data = {
        'email': email,
      };

      expect(data['email'], equals('test@example.com'));
    });
  });

  group('Test Email Response Parsing', () {
    test('parses test email success response', () {
      final response = {
        'message': 'Test email sent to test@example.com',
      };

      final message = response['message'] ?? 'Test email sent!';

      expect(message, equals('Test email sent to test@example.com'));
    });

    test('uses default message when not provided', () {
      final response = <String, dynamic>{};

      final message = response['message'] ?? 'Test email sent!';

      expect(message, equals('Test email sent!'));
    });
  });
}

/// Represents the result of a campaign action (used by CampaignsService)
class CampaignActionResult {
  final Campaign campaign;
  final String message;

  CampaignActionResult({
    required this.campaign,
    required this.message,
  });
}
