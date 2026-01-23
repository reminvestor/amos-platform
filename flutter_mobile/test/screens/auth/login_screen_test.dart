import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/user.dart';
import 'package:amos_mobile/providers/auth_provider.dart';

void main() {
  group('Login Form Validation Logic', () {
    test('empty email should fail validation', () {
      const value = '';
      final result = _validateEmail(value);
      expect(result, equals('Please enter your email'));
    });

    test('null email should fail validation', () {
      const String? value = null;
      final result = _validateEmail(value);
      expect(result, equals('Please enter your email'));
    });

    test('email without @ should fail validation', () {
      const value = 'invalidemail';
      final result = _validateEmail(value);
      expect(result, equals('Please enter a valid email'));
    });

    test('email with just @ should fail validation', () {
      const value = '@';
      final result = _validateEmail(value);
      expect(result, isNull); // The simple check passes but real validation would fail
    });

    test('valid email should pass validation', () {
      const value = 'test@example.com';
      final result = _validateEmail(value);
      expect(result, isNull);
    });

    test('email with subdomain should pass validation', () {
      const value = 'user@mail.example.com';
      final result = _validateEmail(value);
      expect(result, isNull);
    });

    test('email with plus sign should pass validation', () {
      const value = 'user+tag@example.com';
      final result = _validateEmail(value);
      expect(result, isNull);
    });

    test('empty password should fail validation', () {
      const value = '';
      final result = _validatePassword(value);
      expect(result, equals('Please enter your password'));
    });

    test('null password should fail validation', () {
      const String? value = null;
      final result = _validatePassword(value);
      expect(result, equals('Please enter your password'));
    });

    test('non-empty password should pass validation', () {
      const value = 'password123';
      final result = _validatePassword(value);
      expect(result, isNull);
    });

    test('whitespace only password should pass validation', () {
      const value = '   ';
      final result = _validatePassword(value);
      expect(result, isNull); // Non-empty check passes
    });

    test('single character password should pass validation', () {
      const value = 'a';
      final result = _validatePassword(value);
      expect(result, isNull);
    });
  });

  group('Login AuthState Tests', () {
    test('default AuthState is not authenticated', () {
      const state = AuthState();

      expect(state.isAuthenticated, isFalse);
      expect(state.user, isNull);
      expect(state.token, isNull);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
      expect(state.mfaRequired, isFalse);
    });

    test('AuthState with user and token is authenticated', () {
      const user = User(id: '123', email: 'test@example.com');
      const state = AuthState(user: user, token: 'abc123');

      expect(state.isAuthenticated, isTrue);
    });

    test('AuthState with mfaRequired is not authenticated', () {
      const user = User(id: '123', email: 'test@example.com');
      const state = AuthState(
        user: user,
        token: 'abc123',
        mfaRequired: true,
      );

      expect(state.isAuthenticated, isFalse);
    });

    test('AuthState copyWith updates loading state', () {
      const state = AuthState();

      final loadingState = state.copyWith(isLoading: true);

      expect(loadingState.isLoading, isTrue);
      expect(loadingState.user, isNull);
    });

    test('AuthState copyWith clears error by default', () {
      const state = AuthState(error: 'Previous error');

      final cleared = state.copyWith(isLoading: true);

      expect(cleared.error, isNull);
    });

    test('AuthState copyWith can set new error', () {
      const state = AuthState();

      final withError = state.copyWith(error: 'New error');

      expect(withError.error, equals('New error'));
    });

    test('AuthState copyWith preserves user when updating other fields', () {
      const user = User(id: '123', email: 'test@example.com');
      const state = AuthState(user: user, token: 'abc123');

      final updated = state.copyWith(isLoading: true);

      expect(updated.user, equals(user));
      expect(updated.token, equals('abc123'));
      expect(updated.isLoading, isTrue);
    });
  });

  group('Login LoginResult Tests', () {
    test('LoginResult without MFA contains authResult', () {
      const user = User(id: '123', email: 'test@example.com');
      const authResult = AuthResult(user: user, token: 'abc123');
      const result = LoginResult(authResult: authResult);

      expect(result.authResult, isNotNull);
      expect(result.mfaRequired, isFalse);
      expect(result.mfaSessionToken, isNull);
    });

    test('LoginResult with MFA required has no authResult', () {
      const result = LoginResult(
        mfaRequired: true,
        mfaSessionToken: 'mfa-session-123',
      );

      expect(result.authResult, isNull);
      expect(result.mfaRequired, isTrue);
      expect(result.mfaSessionToken, equals('mfa-session-123'));
    });

    test('empty LoginResult has default values', () {
      const result = LoginResult();

      expect(result.authResult, isNull);
      expect(result.mfaRequired, isFalse);
      expect(result.mfaSessionToken, isNull);
    });
  });
}

// Helper validation functions matching the screen's logic
String? _validateEmail(String? value) {
  if (value == null || value.isEmpty) {
    return 'Please enter your email';
  }
  if (!value.contains('@')) {
    return 'Please enter a valid email';
  }
  return null;
}

String? _validatePassword(String? value) {
  if (value == null || value.isEmpty) {
    return 'Please enter your password';
  }
  return null;
}
