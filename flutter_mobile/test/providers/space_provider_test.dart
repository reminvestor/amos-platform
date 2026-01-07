import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/space.dart';
import 'package:amos_mobile/providers/space_provider.dart';

void main() {
  group('SpaceState', () {
    test('initial state has work as default space', () {
      final state = SpaceState.initial();

      expect(state.currentSpace.slug, equals('work'));
      expect(state.availableSpaces.length, equals(3));
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
    });

    test('copyWith creates new state with updated values', () {
      final initialState = SpaceState.initial();

      final newState = initialState.copyWith(
        currentSpace: Space.team,
        isLoading: true,
      );

      expect(newState.currentSpace.slug, equals('team'));
      expect(newState.isLoading, isTrue);
      expect(newState.availableSpaces, equals(initialState.availableSpaces));
    });

    test('copyWith with error clears previous error', () {
      final stateWithError = SpaceState(
        currentSpace: Space.work,
        availableSpaces: Space.all,
        error: 'Previous error',
      );

      final clearedState = stateWithError.copyWith(error: null);

      expect(clearedState.error, isNull);
    });

    test('copyWith preserves values when not specified', () {
      final state = SpaceState(
        currentSpace: Space.team,
        availableSpaces: Space.all,
        isLoading: true,
        error: 'Some error',
      );

      final newState = state.copyWith(isLoading: false);

      expect(newState.currentSpace.isTeam, isTrue);
      expect(newState.availableSpaces.length, equals(3));
      expect(newState.isLoading, isFalse);
    });

    test('initial state availableSpaces contains all space types', () {
      final state = SpaceState.initial();

      expect(state.availableSpaces.any((s) => s.isPersonal), isTrue);
      expect(state.availableSpaces.any((s) => s.isWork), isTrue);
      expect(state.availableSpaces.any((s) => s.isTeam), isTrue);
    });

    test('SpaceState factory sets correct default values', () {
      final state = SpaceState(
        currentSpace: Space.personal,
        availableSpaces: [Space.personal],
      );

      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
    });
  });

  // Note: SpaceNotifier tests that require StorageService are skipped in unit tests
  // because flutter_secure_storage doesn't work properly in test environment.
  // These would need to be tested in integration tests with proper mocking.
}
