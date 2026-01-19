import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amos_mobile/models/campaign.dart';
import 'package:amos_mobile/services/campaigns_service.dart';

/// State for campaigns management
class CampaignsState {
  final List<Campaign> campaigns;
  final Campaign? selectedCampaign;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;
  final int currentPage;
  final bool hasMore;
  final String? searchQuery;
  final CampaignStatus? filterStatus;

  const CampaignsState({
    this.campaigns = const [],
    this.selectedCampaign,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
    this.currentPage = 1,
    this.hasMore = true,
    this.searchQuery,
    this.filterStatus,
  });

  CampaignsState copyWith({
    List<Campaign>? campaigns,
    Campaign? selectedCampaign,
    bool? isLoading,
    bool? isLoadingMore,
    String? error,
    int? currentPage,
    bool? hasMore,
    String? searchQuery,
    CampaignStatus? filterStatus,
    bool clearSelectedCampaign = false,
    bool clearError = false,
    bool clearSearchQuery = false,
    bool clearFilterStatus = false,
  }) {
    return CampaignsState(
      campaigns: campaigns ?? this.campaigns,
      selectedCampaign: clearSelectedCampaign ? null : (selectedCampaign ?? this.selectedCampaign),
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: clearError ? null : (error ?? this.error),
      currentPage: currentPage ?? this.currentPage,
      hasMore: hasMore ?? this.hasMore,
      searchQuery: clearSearchQuery ? null : (searchQuery ?? this.searchQuery),
      filterStatus: clearFilterStatus ? null : (filterStatus ?? this.filterStatus),
    );
  }

  /// Get campaigns filtered by status
  List<Campaign> get draftCampaigns =>
      campaigns.where((c) => c.status == CampaignStatus.draft).toList();

  List<Campaign> get scheduledCampaigns =>
      campaigns.where((c) => c.status == CampaignStatus.scheduled).toList();

  List<Campaign> get inProgressCampaigns =>
      campaigns.where((c) => c.status == CampaignStatus.inProgress).toList();

  List<Campaign> get completedCampaigns =>
      campaigns.where((c) => c.status == CampaignStatus.completed).toList();

  /// Check if there are any campaigns
  bool get isEmpty => campaigns.isEmpty;

  /// Get total count
  int get totalCount => campaigns.length;
}

/// Notifier for campaigns state management
class CampaignsNotifier extends Notifier<CampaignsState> {
  late final CampaignsService _campaignsService;

  @override
  CampaignsState build() {
    _campaignsService = ref.read(campaignsServiceProvider);
    return const CampaignsState();
  }

  /// Load campaigns from API
  Future<void> loadCampaigns({
    String? search,
    CampaignStatus? status,
    bool refresh = false,
  }) async {
    if (state.isLoading) return;

    state = state.copyWith(
      isLoading: true,
      clearError: true,
      searchQuery: search,
      filterStatus: status,
      currentPage: refresh ? 1 : state.currentPage,
    );

    try {
      final campaigns = await _campaignsService.getCampaigns(
        search: search,
        status: status?.value,
        page: refresh ? 1 : state.currentPage,
      );

      state = state.copyWith(
        campaigns: refresh ? campaigns : [...state.campaigns, ...campaigns],
        isLoading: false,
        hasMore: campaigns.length >= 20,
        currentPage: refresh ? 1 : state.currentPage,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Load more campaigns (pagination)
  Future<void> loadMoreCampaigns() async {
    if (state.isLoadingMore || !state.hasMore) return;

    state = state.copyWith(isLoadingMore: true);

    try {
      final campaigns = await _campaignsService.getCampaigns(
        search: state.searchQuery,
        status: state.filterStatus?.value,
        page: state.currentPage + 1,
      );

      state = state.copyWith(
        campaigns: [...state.campaigns, ...campaigns],
        isLoadingMore: false,
        hasMore: campaigns.length >= 20,
        currentPage: state.currentPage + 1,
      );
    } catch (e) {
      state = state.copyWith(
        isLoadingMore: false,
        error: e.toString(),
      );
    }
  }

  /// Select a campaign for detail view
  Future<void> selectCampaign(String id) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final campaign = await _campaignsService.getCampaign(id);
      state = state.copyWith(
        selectedCampaign: campaign,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Clear selected campaign
  void clearSelectedCampaign() {
    state = state.copyWith(clearSelectedCampaign: true);
  }

  /// Set campaigns directly (for testing or external updates)
  void setCampaigns(List<Campaign> campaigns) {
    state = state.copyWith(campaigns: campaigns);
  }

  /// Add a campaign to the list
  void addCampaign(Campaign campaign) {
    state = state.copyWith(campaigns: [campaign, ...state.campaigns]);
  }

  /// Update a campaign in the list
  void updateCampaign(Campaign campaign) {
    final index = state.campaigns.indexWhere((c) => c.id == campaign.id);
    if (index != -1) {
      final updatedList = [...state.campaigns];
      updatedList[index] = campaign;
      state = state.copyWith(
        campaigns: updatedList,
        selectedCampaign: state.selectedCampaign?.id == campaign.id
            ? campaign
            : state.selectedCampaign,
      );
    }
  }

  /// Remove a campaign from the list
  void removeCampaign(String id) {
    state = state.copyWith(
      campaigns: state.campaigns.where((c) => c.id != id).toList(),
      clearSelectedCampaign: state.selectedCampaign?.id == id,
    );
  }

  /// Clear all campaigns
  void clear() {
    state = const CampaignsState();
  }

  /// Clear error
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// Set loading state
  void setLoading(bool loading) {
    state = state.copyWith(isLoading: loading);
  }

  /// Set error state
  void setError(String error) {
    state = state.copyWith(error: error);
  }
}

// Service provider
final campaignsServiceProvider = Provider<CampaignsService>((ref) => CampaignsService());

// State provider
final campaignsStateProvider = NotifierProvider<CampaignsNotifier, CampaignsState>(
  CampaignsNotifier.new,
);

// Convenience providers
final campaignsLoadingProvider = Provider<bool>((ref) {
  return ref.watch(campaignsStateProvider).isLoading;
});

final campaignsErrorProvider = Provider<String?>((ref) {
  return ref.watch(campaignsStateProvider).error;
});

final selectedCampaignProvider = Provider<Campaign?>((ref) {
  return ref.watch(campaignsStateProvider).selectedCampaign;
});

final draftCampaignsProvider = Provider<List<Campaign>>((ref) {
  return ref.watch(campaignsStateProvider).draftCampaigns;
});

final scheduledCampaignsProvider = Provider<List<Campaign>>((ref) {
  return ref.watch(campaignsStateProvider).scheduledCampaigns;
});

final inProgressCampaignsProvider = Provider<List<Campaign>>((ref) {
  return ref.watch(campaignsStateProvider).inProgressCampaigns;
});

final completedCampaignsProvider = Provider<List<Campaign>>((ref) {
  return ref.watch(campaignsStateProvider).completedCampaigns;
});
