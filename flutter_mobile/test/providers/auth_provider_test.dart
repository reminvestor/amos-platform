import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/user.dart';
import 'package:amos_mobile/providers/auth_provider.dart';

void main() {
  group('AuthState', () {
    test('default state has correct initial values', () {
      const state = AuthState();

      expect(state.user, isNull);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
      expect(state.token, isNull);
      expect(state.mfaRequired, isFalse);
      expect(state.mfaSessionToken, isNull);
    });

    test('isAuthenticated returns false when user is null', () {
      const state = AuthState(token: 'abc123');

      expect(state.isAuthenticated, isFalse);
    });

    test('isAuthenticated returns false when token is null', () {
      const user = User(id: '1', email: 'test@example.com');
      const state = AuthState(user: user);

      expect(state.isAuthenticated, isFalse);
    });

    test('isAuthenticated returns false when MFA is required', () {
      const user = User(id: '1', email: 'test@example.com');
      const state = AuthState(
        user: user,
        token: 'abc123',
        mfaRequired: true,
      );

      expect(state.isAuthenticated, isFalse);
    });

    test('isAuthenticated returns true when fully authenticated', () {
      const user = User(id: '1', email: 'test@example.com');
      const state = AuthState(
        user: user,
        token: 'abc123',
        mfaRequired: false,
      );

      expect(state.isAuthenticated, isTrue);
    });

    test('copyWith updates specified values', () {
      const original = AuthState();
      const user = User(id: '1', email: 'test@example.com');

      final updated = original.copyWith(
        user: user,
        isLoading: true,
        token: 'abc123',
        mfaRequired: true,
        mfaSessionToken: 'mfa-session',
      );

      expect(updated.user, equals(user));
      expect(updated.isLoading, isTrue);
      expect(updated.token, equals('abc123'));
      expect(updated.mfaRequired, isTrue);
      expect(updated.mfaSessionToken, equals('mfa-session'));
    });

    test('copyWith preserves unspecified values', () {
      const user = User(id: '1', email: 'test@example.com');
      const original = AuthState(
        user: user,
        token: 'abc123',
        mfaRequired: false,
      );

      final updated = original.copyWith(isLoading: true);

      expect(updated.user, equals(user));
      expect(updated.token, equals('abc123'));
      expect(updated.mfaRequired, isFalse);
      expect(updated.isLoading, isTrue);
    });

    test('copyWith always replaces error (null clears previous)', () {
      const stateWithError = AuthState(error: 'Previous error');

      final cleared = stateWithError.copyWith(isLoading: true);

      expect(cleared.error, isNull);
    });

    test('copyWith sets new error value', () {
      const state = AuthState();

      final withError = state.copyWith(error: 'New error');

      expect(withError.error, equals('New error'));
    });

    test('clearMfa removes MFA state while preserving other values', () {
      const user = User(id: '1', email: 'test@example.com');
      const state = AuthState(
        user: user,
        token: 'abc123',
        isLoading: true,
        error: 'Some error',
        mfaRequired: true,
        mfaSessionToken: 'mfa-session',
      );

      final cleared = state.clearMfa();

      expect(cleared.user, equals(user));
      expect(cleared.token, equals('abc123'));
      expect(cleared.isLoading, isTrue);
      expect(cleared.error, equals('Some error'));
      expect(cleared.mfaRequired, isFalse);
      expect(cleared.mfaSessionToken, isNull);
    });

    test('clearMfa on clean state has no effect', () {
      const state = AuthState();

      final cleared = state.clearMfa();

      expect(cleared.mfaRequired, isFalse);
      expect(cleared.mfaSessionToken, isNull);
    });
  });
}
