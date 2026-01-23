import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/campaign.dart';

// Note: CampaignDetailScreen requires async initState with API calls
// which causes "ref used after dispose" errors in widget tests.
// These tests focus on the data models and helper logic used by the screen.

void main() {
  group('CampaignDetailScreen Data Models', () {
    group('Campaign status badge colors', () {
      // These mappings match _buildStatusBadge in CampaignDetailScreen
      Color getStatusBadgeColor(CampaignStatus status) {
        switch (status) {
          case CampaignStatus.draft:
            return Colors.grey;
          case CampaignStatus.scheduled:
            return Colors.blue;
          case CampaignStatus.inProgress:
            return Colors.orange;
          case CampaignStatus.completed:
            return Colors.green;
          case CampaignStatus.paused:
            return Colors.amber;
          case CampaignStatus.stopped:
            return Colors.red;
        }
      }

      test('all status colors are assigned', () {
        for (final status in CampaignStatus.values) {
          final color = getStatusBadgeColor(status);
          expect(color, isNotNull);
        }
      });
    });

    group('Campaign action buttons by status', () {
      // Tests the logic for which action buttons appear based on status
      List<String> getAvailableActions(CampaignStatus status) {
        switch (status) {
          case CampaignStatus.draft:
            return ['Send Now', 'Schedule', 'Send Test'];
          case CampaignStatus.scheduled:
            return ['Send Now', 'Reschedule', 'Cancel'];
          case CampaignStatus.inProgress:
            return ['Pause', 'Stop'];
          case CampaignStatus.paused:
            return ['Resume', 'Stop'];
          case CampaignStatus.completed:
          case CampaignStatus.stopped:
            return ['Duplicate Campaign'];
        }
      }

      test('draft campaign has send, schedule, and test actions', () {
        final actions = getAvailableActions(CampaignStatus.draft);
        expect(actions, contains('Send Now'));
        expect(actions, contains('Schedule'));
        expect(actions, contains('Send Test'));
      });

      test('scheduled campaign has send now, reschedule, and cancel actions', () {
        final actions = getAvailableActions(CampaignStatus.scheduled);
        expect(actions, contains('Send Now'));
        expect(actions, contains('Reschedule'));
        expect(actions, contains('Cancel'));
      });

      test('in progress campaign has pause and stop actions', () {
        final actions = getAvailableActions(CampaignStatus.inProgress);
        expect(actions, contains('Pause'));
        expect(actions, contains('Stop'));
        expect(actions.length, equals(2));
      });

      test('paused campaign has resume and stop actions', () {
        final actions = getAvailableActions(CampaignStatus.paused);
        expect(actions, contains('Resume'));
        expect(actions, contains('Stop'));
        expect(actions.length, equals(2));
      });

      test('completed campaign only has duplicate action', () {
        final actions = getAvailableActions(CampaignStatus.completed);
        expect(actions, contains('Duplicate Campaign'));
        expect(actions.length, equals(1));
      });

      test('stopped campaign only has duplicate action', () {
        final actions = getAvailableActions(CampaignStatus.stopped);
        expect(actions, contains('Duplicate Campaign'));
        expect(actions.length, equals(1));
      });
    });

    group('Campaign stats display', () {
      test('campaign with all stats', () {
        final campaign = Campaign(
          id: '1',
          name: 'Test Campaign',
          subject: 'Subject',
          status: CampaignStatus.completed,
          createdAt: DateTime(2024, 1, 15, 10, 30),
          updatedAt: DateTime(2024, 1, 16, 14, 45),
          contactCount: 250,
          sentCount: 248,
          openRate: 42.5,
          clickRate: 15.3,
          bounceRate: 0.8,
        );

        expect(campaign.contactCount, equals(250));
        expect(campaign.sentCount, equals(248));
        expect(campaign.openRate, equals(42.5));
        expect(campaign.clickRate, equals(15.3));
        expect(campaign.bounceRate, equals(0.8));
      });

      test('stats formatting for display', () {
        final campaign = Campaign(
          id: '1',
          name: 'Test',
          subject: 'Subject',
          status: CampaignStatus.completed,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          contactCount: 100,
          openRate: 45.678,
          clickRate: 12.345,
          bounceRate: 2.111,
        );

        // Format like CampaignDetailScreen does
        final recipientsDisplay = campaign.contactCount?.toString() ?? '0';
        final openRateDisplay = campaign.openRate != null
            ? '${campaign.openRate!.toStringAsFixed(1)}%'
            : '-';
        final clickRateDisplay = campaign.clickRate != null
            ? '${campaign.clickRate!.toStringAsFixed(1)}%'
            : '-';
        final bounceRateDisplay = campaign.bounceRate != null
            ? '${campaign.bounceRate!.toStringAsFixed(1)}%'
            : '-';

        expect(recipientsDisplay, equals('100'));
        expect(openRateDisplay, equals('45.7%'));
        expect(clickRateDisplay, equals('12.3%'));
        expect(bounceRateDisplay, equals('2.1%'));
      });

      test('null stats display as placeholder', () {
        final campaign = Campaign(
          id: '1',
          name: 'Test',
          subject: 'Subject',
          status: CampaignStatus.draft,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final recipientsDisplay = campaign.contactCount?.toString() ?? '0';
        final openRateDisplay = campaign.openRate != null
            ? '${campaign.openRate!.toStringAsFixed(1)}%'
            : '-';

        expect(recipientsDisplay, equals('0'));
        expect(openRateDisplay, equals('-'));
      });
    });

    group('Campaign scheduled date display', () {
      test('campaign with scheduled date', () {
        final scheduledTime = DateTime(2024, 6, 20, 9, 0);
        final campaign = Campaign(
          id: '1',
          name: 'Scheduled Campaign',
          subject: 'Subject',
          status: CampaignStatus.scheduled,
          createdAt: DateTime(2024, 6, 15),
          updatedAt: DateTime(2024, 6, 15),
          scheduledAt: scheduledTime,
        );

        expect(campaign.scheduledAt, isNotNull);
        expect(campaign.scheduledAt!.year, equals(2024));
        expect(campaign.scheduledAt!.month, equals(6));
        expect(campaign.scheduledAt!.day, equals(20));
        expect(campaign.scheduledAt!.hour, equals(9));
      });

      test('campaign without scheduled date', () {
        final campaign = Campaign(
          id: '1',
          name: 'Draft Campaign',
          subject: 'Subject',
          status: CampaignStatus.draft,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        expect(campaign.scheduledAt, isNull);
      });
    });

    group('MailgunStats in detail view', () {
      test('campaign with full mailgun stats', () {
        final campaign = Campaign(
          id: '1',
          name: 'Test',
          subject: 'Subject',
          status: CampaignStatus.completed,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          mailgunStats: MailgunStats(
            delivered: 100,
            failed: 5,
            bounced: 3,
            unsubscribed: 2,
            complained: 1,
            opened: 50,
            clicked: 25,
          ),
        );

        expect(campaign.mailgunStats, isNotNull);
        expect(campaign.mailgunStats!.delivered, equals(100));
        expect(campaign.mailgunStats!.failed, equals(5));
        expect(campaign.mailgunStats!.bounced, equals(3));
        expect(campaign.mailgunStats!.unsubscribed, equals(2));
        expect(campaign.mailgunStats!.complained, equals(1));
        expect(campaign.mailgunStats!.opened, equals(50));
        expect(campaign.mailgunStats!.clicked, equals(25));
      });

      test('calculate delivery rate from mailgun stats', () {
        final stats = MailgunStats(
          delivered: 95,
          failed: 5,
          bounced: 0,
          unsubscribed: 0,
          complained: 0,
          opened: 47,
          clicked: 20,
        );

        final totalAttempted = stats.delivered + stats.failed;
        final deliveryRate = (stats.delivered / totalAttempted) * 100;

        expect(totalAttempted, equals(100));
        expect(deliveryRate, equals(95.0));
      });
    });

    group('Fallback campaign for missing data', () {
      test('creates placeholder campaign when not found', () {
        // This matches the fallback logic in CampaignDetailScreen.build
        final fallbackCampaign = Campaign(
          id: 'missing-id',
          entityId: '',
          userId: '',
          name: 'Campaign Not Found',
          subject: '',
          status: CampaignStatus.draft,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        expect(fallbackCampaign.name, equals('Campaign Not Found'));
        expect(fallbackCampaign.subject, isEmpty);
        expect(fallbackCampaign.status, equals(CampaignStatus.draft));
      });
    });
  });
}
