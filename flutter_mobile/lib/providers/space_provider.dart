import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amos_mobile/models/space.dart';
import 'package:amos_mobile/services/storage_service.dart';

/// State for the space provider
class SpaceState {
  final Space currentSpace;
  final List<Space> availableSpaces;
  final bool isLoading;
  final String? error;

  const SpaceState({
    required this.currentSpace,
    required this.availableSpaces,
    this.isLoading = false,
    this.error,
  });

  SpaceState copyWith({
    Space? currentSpace,
    List<Space>? availableSpaces,
    bool? isLoading,
    String? error,
  }) {
    return SpaceState(
      currentSpace: currentSpace ?? this.currentSpace,
      availableSpaces: availableSpaces ?? this.availableSpaces,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  factory SpaceState.initial() {
    return SpaceState(
      currentSpace: Space.operations, // Default to Operations mode
      availableSpaces: Space.all,
    );
  }
}

/// Notifier for space state management
class SpaceNotifier extends Notifier<SpaceState> {
  static const String _storageKey = 'current_space';

  @override
  SpaceState build() {
    // Load saved space preference on initialization
    _loadSavedSpace();
    return SpaceState.initial();
  }

  Future<void> _loadSavedSpace() async {
    try {
      final storage = StorageService.instance;
      final savedSlug = await storage.read(_storageKey);
      if (savedSlug != null) {
        // Map legacy slugs to current ones
        var mappedSlug = savedSlug;
        if (savedSlug == 'work') mappedSlug = 'operations';
        // Map old design/team slugs to operations (no longer supported)
        if (savedSlug == 'team' || savedSlug == 'design') {
          mappedSlug = 'operations';
        }

        final space = Space.all.firstWhere(
          (s) => s.slug == mappedSlug,
          orElse: () => Space.operations,
        );
        state = state.copyWith(currentSpace: space);
      }
    } catch (e) {
      // Ignore storage errors, use default
    }
  }

  Future<void> switchSpace(Space space) async {
    if (state.currentSpace.slug == space.slug) return;

    state = state.copyWith(isLoading: true);

    try {
      // Save preference
      final storage = StorageService.instance;
      await storage.write(_storageKey, space.slug);

      state = state.copyWith(
        currentSpace: space,
        isLoading: false,
        error: null,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to switch space: $e',
      );
    }
  }

  void switchToPersonal() => switchSpace(Space.personal);
  void switchToOperations() => switchSpace(Space.operations);

  // Legacy methods for backward compatibility
  void switchToWork() => switchToOperations();

  bool get isInPersonalSpace => state.currentSpace.isPersonal;
  bool get isInOperationsSpace => state.currentSpace.isOperations;

  // Legacy getters for backward compatibility
  bool get isInWorkSpace => isInOperationsSpace;
}

/// Provider for space state
final spaceProvider = NotifierProvider<SpaceNotifier, SpaceState>(() {
  return SpaceNotifier();
});

/// Convenience provider for current space
final currentSpaceProvider = Provider<Space>((ref) {
  return ref.watch(spaceProvider).currentSpace;
});

/// Provider for checking if in personal space
final isInPersonalSpaceProvider = Provider<bool>((ref) {
  return ref.watch(currentSpaceProvider).isPersonal;
});

/// Provider for checking if in operations space
final isInOperationsSpaceProvider = Provider<bool>((ref) {
  return ref.watch(currentSpaceProvider).isOperations;
});

// Legacy alias
final isInWorkSpaceProvider = isInOperationsSpaceProvider;
