import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/providers/space_provider.dart';
import 'package:amos_mobile/models/space.dart';

void main() {
  group('SpaceState', () {
    test('initial factory creates default state', () {
      final state = SpaceState.initial();

      expect(state.currentSpace.slug, equals('work'));
      expect(state.availableSpaces, equals(Space.all));
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
    });

    test('copyWith updates currentSpace', () {
      final initial = SpaceState.initial();
      final modified = initial.copyWith(currentSpace: Space.personal);

      expect(modified.currentSpace.slug, equals('personal'));
      expect(initial.currentSpace.slug, equals('work'));
    });

    test('copyWith updates isLoading', () {
      final initial = SpaceState.initial();
      final modified = initial.copyWith(isLoading: true);

      expect(modified.isLoading, isTrue);
      expect(initial.isLoading, isFalse);
    });

    test('copyWith updates error', () {
      final initial = SpaceState.initial();
      final modified = initial.copyWith(error: 'Something went wrong');

      expect(modified.error, equals('Something went wrong'));
      expect(initial.error, isNull);
    });

    test('copyWith clears error when set to null explicitly', () {
      final initial = SpaceState(
        currentSpace: Space.work,
        availableSpaces: Space.all,
        error: 'Previous error',
      );
      // Note: copyWith with error: null will clear the error
      final modified = initial.copyWith(error: null);

      expect(modified.error, isNull);
    });

    test('copyWith preserves unmodified values', () {
      final initial = SpaceState(
        currentSpace: Space.team,
        availableSpaces: Space.all,
        isLoading: true,
        error: 'An error',
      );
      final modified = initial.copyWith(currentSpace: Space.personal);

      expect(modified.currentSpace.slug, equals('personal'));
      expect(modified.isLoading, isTrue);
      expect(modified.error, isNull); // error is explicitly set to null in copyWith
    });
  });
}
