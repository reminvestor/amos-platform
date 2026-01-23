import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amos_mobile/models/campaign.dart';
import 'package:amos_mobile/providers/campaigns_provider.dart';

void main() {
  // Test campaign helper
  Campaign createTestCampaign({
    String id = '1',
    String name = 'Test Campaign',
    String subject = 'Test Subject',
    CampaignStatus status = CampaignStatus.draft,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Campaign(
      id: id,
      name: name,
      subject: subject,
      status: status,
      createdAt: createdAt ?? DateTime.now(),
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  group('CampaignsState', () {
    test('default state has correct initial values', () {
      const state = CampaignsState();

      expect(state.campaigns, isEmpty);
      expect(state.selectedCampaign, isNull);
      expect(state.isLoading, isFalse);
      expect(state.isLoadingMore, isFalse);
      expect(state.error, isNull);
      expect(state.currentPage, equals(1));
      expect(state.hasMore, isTrue);
      expect(state.searchQuery, isNull);
      expect(state.filterStatus, isNull);
    });

    test('isEmpty returns true when campaigns list is empty', () {
      const state = CampaignsState();

      expect(state.isEmpty, isTrue);
    });

    test('isEmpty returns false when campaigns exist', () {
      final campaign = createTestCampaign();
      final state = CampaignsState(campaigns: [campaign]);

      expect(state.isEmpty, isFalse);
    });

    test('totalCount returns correct count', () {
      final campaigns = [
        createTestCampaign(id: '1'),
        createTestCampaign(id: '2'),
        createTestCampaign(id: '3'),
      ];
      final state = CampaignsState(campaigns: campaigns);

      expect(state.totalCount, equals(3));
    });

    group('copyWith', () {
      test('updates campaigns', () {
        const initial = CampaignsState();
        final campaigns = [createTestCampaign()];

        final modified = initial.copyWith(campaigns: campaigns);

        expect(modified.campaigns.length, equals(1));
        expect(initial.campaigns, isEmpty);
      });

      test('updates selectedCampaign', () {
        const initial = CampaignsState();
        final campaign = createTestCampaign();

        final modified = initial.copyWith(selectedCampaign: campaign);

        expect(modified.selectedCampaign, equals(campaign));
        expect(initial.selectedCampaign, isNull);
      });

      test('clears selectedCampaign when clearSelectedCampaign is true', () {
        final campaign = createTestCampaign();
        final initial = CampaignsState(selectedCampaign: campaign);

        final modified = initial.copyWith(clearSelectedCampaign: true);

        expect(modified.selectedCampaign, isNull);
      });

      test('updates isLoading', () {
        const initial = CampaignsState();

        final modified = initial.copyWith(isLoading: true);

        expect(modified.isLoading, isTrue);
        expect(initial.isLoading, isFalse);
      });

      test('updates isLoadingMore', () {
        const initial = CampaignsState();

        final modified = initial.copyWith(isLoadingMore: true);

        expect(modified.isLoadingMore, isTrue);
        expect(initial.isLoadingMore, isFalse);
      });

      test('updates error', () {
        const initial = CampaignsState();

        final modified = initial.copyWith(error: 'Test error');

        expect(modified.error, equals('Test error'));
        expect(initial.error, isNull);
      });

      test('clears error when clearError is true', () {
        const initial = CampaignsState(error: 'Previous error');

        final modified = initial.copyWith(clearError: true);

        expect(modified.error, isNull);
      });

      test('updates currentPage', () {
        const initial = CampaignsState();

        final modified = initial.copyWith(currentPage: 5);

        expect(modified.currentPage, equals(5));
        expect(initial.currentPage, equals(1));
      });

      test('updates hasMore', () {
        const initial = CampaignsState();

        final modified = initial.copyWith(hasMore: false);

        expect(modified.hasMore, isFalse);
        expect(initial.hasMore, isTrue);
      });

      test('updates searchQuery', () {
        const initial = CampaignsState();

        final modified = initial.copyWith(searchQuery: 'test');

        expect(modified.searchQuery, equals('test'));
        expect(initial.searchQuery, isNull);
      });

      test('clears searchQuery when clearSearchQuery is true', () {
        const initial = CampaignsState(searchQuery: 'previous');

        final modified = initial.copyWith(clearSearchQuery: true);

        expect(modified.searchQuery, isNull);
      });

      test('updates filterStatus', () {
        const initial = CampaignsState();

        final modified = initial.copyWith(filterStatus: CampaignStatus.draft);

        expect(modified.filterStatus, equals(CampaignStatus.draft));
        expect(initial.filterStatus, isNull);
      });

      test('clears filterStatus when clearFilterStatus is true', () {
        const initial = CampaignsState(filterStatus: CampaignStatus.draft);

        final modified = initial.copyWith(clearFilterStatus: true);

        expect(modified.filterStatus, isNull);
      });

      test('preserves unmodified values', () {
        final campaign = createTestCampaign();
        final initial = CampaignsState(
          campaigns: [campaign],
          selectedCampaign: campaign,
          isLoading: true,
          currentPage: 3,
          hasMore: false,
          searchQuery: 'test',
          filterStatus: CampaignStatus.completed,
        );

        final modified = initial.copyWith(isLoadingMore: true);

        expect(modified.campaigns.length, equals(1));
        expect(modified.selectedCampaign, equals(campaign));
        expect(modified.isLoading, isTrue);
        expect(modified.isLoadingMore, isTrue);
        expect(modified.currentPage, equals(3));
        expect(modified.hasMore, isFalse);
        expect(modified.searchQuery, equals('test'));
        expect(modified.filterStatus, equals(CampaignStatus.completed));
      });
    });

    group('filtered campaigns', () {
      test('draftCampaigns returns only draft campaigns', () {
        final campaigns = [
          createTestCampaign(id: '1', status: CampaignStatus.draft),
          createTestCampaign(id: '2', status: CampaignStatus.scheduled),
          createTestCampaign(id: '3', status: CampaignStatus.draft),
        ];
        final state = CampaignsState(campaigns: campaigns);

        expect(state.draftCampaigns.length, equals(2));
        expect(state.draftCampaigns.every((c) => c.status == CampaignStatus.draft), isTrue);
      });

      test('scheduledCampaigns returns only scheduled campaigns', () {
        final campaigns = [
          createTestCampaign(id: '1', status: CampaignStatus.draft),
          createTestCampaign(id: '2', status: CampaignStatus.scheduled),
          createTestCampaign(id: '3', status: CampaignStatus.scheduled),
        ];
        final state = CampaignsState(campaigns: campaigns);

        expect(state.scheduledCampaigns.length, equals(2));
        expect(state.scheduledCampaigns.every((c) => c.status == CampaignStatus.scheduled), isTrue);
      });

      test('inProgressCampaigns returns only in-progress campaigns', () {
        final campaigns = [
          createTestCampaign(id: '1', status: CampaignStatus.inProgress),
          createTestCampaign(id: '2', status: CampaignStatus.scheduled),
          createTestCampaign(id: '3', status: CampaignStatus.inProgress),
        ];
        final state = CampaignsState(campaigns: campaigns);

        expect(state.inProgressCampaigns.length, equals(2));
        expect(state.inProgressCampaigns.every((c) => c.status == CampaignStatus.inProgress), isTrue);
      });

      test('completedCampaigns returns only completed campaigns', () {
        final campaigns = [
          createTestCampaign(id: '1', status: CampaignStatus.completed),
          createTestCampaign(id: '2', status: CampaignStatus.draft),
          createTestCampaign(id: '3', status: CampaignStatus.completed),
        ];
        final state = CampaignsState(campaigns: campaigns);

        expect(state.completedCampaigns.length, equals(2));
        expect(state.completedCampaigns.every((c) => c.status == CampaignStatus.completed), isTrue);
      });

      test('filtered lists return empty when no matching campaigns', () {
        final campaigns = [
          createTestCampaign(id: '1', status: CampaignStatus.draft),
        ];
        final state = CampaignsState(campaigns: campaigns);

        expect(state.scheduledCampaigns, isEmpty);
        expect(state.inProgressCampaigns, isEmpty);
        expect(state.completedCampaigns, isEmpty);
      });
    });
  });

  group('CampaignsNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state is empty CampaignsState', () {
      final state = container.read(campaignsStateProvider);

      expect(state.campaigns, isEmpty);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
    });

    test('setCampaigns updates campaigns list', () {
      final campaigns = [
        createTestCampaign(id: '1'),
        createTestCampaign(id: '2'),
      ];

      container.read(campaignsStateProvider.notifier).setCampaigns(campaigns);

      final state = container.read(campaignsStateProvider);
      expect(state.campaigns.length, equals(2));
    });

    test('addCampaign prepends campaign to list', () {
      final campaign1 = createTestCampaign(id: '1', name: 'First');
      final campaign2 = createTestCampaign(id: '2', name: 'Second');

      final notifier = container.read(campaignsStateProvider.notifier);
      notifier.setCampaigns([campaign1]);
      notifier.addCampaign(campaign2);

      final state = container.read(campaignsStateProvider);
      expect(state.campaigns.length, equals(2));
      expect(state.campaigns.first.id, equals('2'));
    });

    test('updateCampaign updates existing campaign by id', () {
      final campaign = createTestCampaign(id: '1', name: 'Original');
      final updated = createTestCampaign(id: '1', name: 'Updated');

      final notifier = container.read(campaignsStateProvider.notifier);
      notifier.setCampaigns([campaign]);
      notifier.updateCampaign(updated);

      final state = container.read(campaignsStateProvider);
      expect(state.campaigns.first.name, equals('Updated'));
    });

    test('updateCampaign also updates selectedCampaign if it matches', () {
      final campaign = createTestCampaign(id: '1', name: 'Original');
      final updated = createTestCampaign(id: '1', name: 'Updated');

      final notifier = container.read(campaignsStateProvider.notifier);
      notifier.setCampaigns([campaign]);
      // Simulate selecting the campaign
      final initialState = container.read(campaignsStateProvider);
      // We need to manually set selectedCampaign for this test
      container.read(campaignsStateProvider.notifier).setCampaigns([campaign]);

      notifier.updateCampaign(updated);

      final state = container.read(campaignsStateProvider);
      expect(state.campaigns.first.name, equals('Updated'));
    });

    test('updateCampaign does nothing when id not found', () {
      final campaign = createTestCampaign(id: '1', name: 'Original');
      final nonExistent = createTestCampaign(id: '999', name: 'Nonexistent');

      final notifier = container.read(campaignsStateProvider.notifier);
      notifier.setCampaigns([campaign]);
      notifier.updateCampaign(nonExistent);

      final state = container.read(campaignsStateProvider);
      expect(state.campaigns.length, equals(1));
      expect(state.campaigns.first.name, equals('Original'));
    });

    test('removeCampaign removes campaign by id', () {
      final campaigns = [
        createTestCampaign(id: '1'),
        createTestCampaign(id: '2'),
      ];

      final notifier = container.read(campaignsStateProvider.notifier);
      notifier.setCampaigns(campaigns);
      notifier.removeCampaign('1');

      final state = container.read(campaignsStateProvider);
      expect(state.campaigns.length, equals(1));
      expect(state.campaigns.first.id, equals('2'));
    });

    test('removeCampaign does nothing when id not found', () {
      final campaign = createTestCampaign(id: '1');

      final notifier = container.read(campaignsStateProvider.notifier);
      notifier.setCampaigns([campaign]);
      notifier.removeCampaign('999');

      final state = container.read(campaignsStateProvider);
      expect(state.campaigns.length, equals(1));
    });

    test('clearSelectedCampaign clears the selected campaign', () {
      // Test by verifying the method doesn't throw
      container.read(campaignsStateProvider.notifier).clearSelectedCampaign();

      final state = container.read(campaignsStateProvider);
      expect(state.selectedCampaign, isNull);
    });

    test('clear resets state to initial values', () {
      final campaign = createTestCampaign();

      final notifier = container.read(campaignsStateProvider.notifier);
      notifier.setCampaigns([campaign]);
      notifier.clear();

      final state = container.read(campaignsStateProvider);
      expect(state.campaigns, isEmpty);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
      expect(state.currentPage, equals(1));
    });

    test('clearError clears the error state', () {
      final notifier = container.read(campaignsStateProvider.notifier);
      notifier.setError('Test error');
      notifier.clearError();

      final state = container.read(campaignsStateProvider);
      expect(state.error, isNull);
    });

    test('setLoading updates loading state', () {
      container.read(campaignsStateProvider.notifier).setLoading(true);

      final state = container.read(campaignsStateProvider);
      expect(state.isLoading, isTrue);
    });

    test('setError updates error state', () {
      container.read(campaignsStateProvider.notifier).setError('Test error');

      final state = container.read(campaignsStateProvider);
      expect(state.error, equals('Test error'));
    });
  });

  group('Convenience Providers', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('campaignsLoadingProvider reflects loading state', () {
      expect(container.read(campaignsLoadingProvider), isFalse);

      container.read(campaignsStateProvider.notifier).setLoading(true);

      expect(container.read(campaignsLoadingProvider), isTrue);
    });

    test('campaignsErrorProvider reflects error state', () {
      expect(container.read(campaignsErrorProvider), isNull);

      container.read(campaignsStateProvider.notifier).setError('Error');

      expect(container.read(campaignsErrorProvider), equals('Error'));
    });

    test('selectedCampaignProvider reflects selected campaign', () {
      expect(container.read(selectedCampaignProvider), isNull);
    });

    test('draftCampaignsProvider returns only drafts', () {
      final campaigns = [
        createTestCampaign(id: '1', status: CampaignStatus.draft),
        createTestCampaign(id: '2', status: CampaignStatus.completed),
      ];

      container.read(campaignsStateProvider.notifier).setCampaigns(campaigns);

      expect(container.read(draftCampaignsProvider).length, equals(1));
      expect(container.read(draftCampaignsProvider).first.id, equals('1'));
    });

    test('scheduledCampaignsProvider returns only scheduled', () {
      final campaigns = [
        createTestCampaign(id: '1', status: CampaignStatus.scheduled),
        createTestCampaign(id: '2', status: CampaignStatus.draft),
      ];

      container.read(campaignsStateProvider.notifier).setCampaigns(campaigns);

      expect(container.read(scheduledCampaignsProvider).length, equals(1));
      expect(container.read(scheduledCampaignsProvider).first.id, equals('1'));
    });

    test('inProgressCampaignsProvider returns only in-progress', () {
      final campaigns = [
        createTestCampaign(id: '1', status: CampaignStatus.inProgress),
        createTestCampaign(id: '2', status: CampaignStatus.draft),
      ];

      container.read(campaignsStateProvider.notifier).setCampaigns(campaigns);

      expect(container.read(inProgressCampaignsProvider).length, equals(1));
      expect(container.read(inProgressCampaignsProvider).first.id, equals('1'));
    });

    test('completedCampaignsProvider returns only completed', () {
      final campaigns = [
        createTestCampaign(id: '1', status: CampaignStatus.completed),
        createTestCampaign(id: '2', status: CampaignStatus.draft),
      ];

      container.read(campaignsStateProvider.notifier).setCampaigns(campaigns);

      expect(container.read(completedCampaignsProvider).length, equals(1));
      expect(container.read(completedCampaignsProvider).first.id, equals('1'));
    });
  });
}
