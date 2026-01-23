import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/user.dart';
import 'package:amos_mobile/providers/auth_provider.dart';

void main() {
  group('MFA Code Validation Logic', () {
    test('empty code should fail validation', () {
      const code = '';
      final isValid = _isValidMFACode(code);
      expect(isValid, isFalse);
    });

    test('code with less than 6 digits should fail validation', () {
      const code = '12345';
      final isValid = _isValidMFACode(code);
      expect(isValid, isFalse);
    });

    test('code with exactly 6 digits should pass validation', () {
      const code = '123456';
      final isValid = _isValidMFACode(code);
      expect(isValid, isTrue);
    });

    test('code with more than 6 digits should fail validation', () {
      const code = '1234567';
      final isValid = _isValidMFACode(code);
      expect(isValid, isFalse);
    });

    test('code with non-numeric characters should fail validation', () {
      const code = '12345a';
      final isValid = _isValidMFACode(code);
      expect(isValid, isFalse);
    });

    test('code with spaces should fail validation', () {
      const code = '123 456';
      final isValid = _isValidMFACode(code);
      expect(isValid, isFalse);
    });

    test('code with special characters should fail validation', () {
      const code = '12345!';
      final isValid = _isValidMFACode(code);
      expect(isValid, isFalse);
    });

    test('valid 6-digit all zeros code should pass validation', () {
      const code = '000000';
      final isValid = _isValidMFACode(code);
      expect(isValid, isTrue);
    });

    test('valid 6-digit mixed code should pass validation', () {
      const code = '987654';
      final isValid = _isValidMFACode(code);
      expect(isValid, isTrue);
    });

    test('code with leading zeros should pass validation', () {
      const code = '001234';
      final isValid = _isValidMFACode(code);
      expect(isValid, isTrue);
    });

    test('code that is null returns false for validation', () {
      const String? code = null;
      final isValid = code != null && _isValidMFACode(code);
      expect(isValid, isFalse);
    });
  });

  group('MFA AuthState Tests', () {
    test('AuthState with mfaRequired true should not be authenticated', () {
      const state = AuthState(
        mfaRequired: true,
        mfaSessionToken: 'mfa-session-123',
      );

      expect(state.isAuthenticated, isFalse);
      expect(state.mfaRequired, isTrue);
      expect(state.mfaSessionToken, equals('mfa-session-123'));
    });

    test('AuthState with mfaRequired true and user should not be authenticated', () {
      const user = User(id: '123', email: 'test@example.com');
      const state = AuthState(
        user: user,
        token: 'temp-token',
        mfaRequired: true,
        mfaSessionToken: 'mfa-session',
      );

      expect(state.isAuthenticated, isFalse);
      expect(state.user, isNotNull);
    });

    test('AuthState clearMfa removes MFA state', () {
      const state = AuthState(
        token: 'some-token',
        mfaRequired: true,
        mfaSessionToken: 'mfa-session',
      );

      final cleared = state.clearMfa();

      expect(cleared.token, equals('some-token'));
      expect(cleared.mfaRequired, isFalse);
      expect(cleared.mfaSessionToken, isNull);
    });

    test('AuthState clearMfa preserves other state', () {
      const user = User(id: '123', email: 'test@example.com');
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

    test('AuthState copyWith can update mfaRequired', () {
      const state = AuthState();

      final updated = state.copyWith(
        mfaRequired: true,
        mfaSessionToken: 'new-session',
      );

      expect(updated.mfaRequired, isTrue);
      expect(updated.mfaSessionToken, equals('new-session'));
    });

    test('AuthState after MFA verification', () {
      const user = User(id: '123', email: 'test@example.com', mfaEnabled: true);
      const state = AuthState(
        user: user,
        token: 'verified-token',
        mfaRequired: false,
      );

      expect(state.isAuthenticated, isTrue);
      expect(state.mfaRequired, isFalse);
      expect(state.user?.mfaEnabled, isTrue);
    });
  });

  group('MFA LoginResult Tests', () {
    test('LoginResult requiring MFA has no authResult', () {
      const result = LoginResult(
        mfaRequired: true,
        mfaSessionToken: 'mfa-session-token',
      );

      expect(result.authResult, isNull);
      expect(result.mfaRequired, isTrue);
      expect(result.mfaSessionToken, equals('mfa-session-token'));
    });

    test('LoginResult after MFA verification has authResult', () {
      const user = User(id: '123', email: 'test@example.com');
      const authResult = AuthResult(user: user, token: 'verified-token');
      const result = LoginResult(authResult: authResult);

      expect(result.authResult, isNotNull);
      expect(result.authResult!.token, equals('verified-token'));
      expect(result.mfaRequired, isFalse);
    });
  });

  group('MFA User Model Tests', () {
    test('User with mfaEnabled from JSON', () {
      final json = {
        'id': '123',
        'email': 'test@example.com',
        'mfa_enabled': true,
      };

      final user = User.fromJson(json);

      expect(user.mfaEnabled, isTrue);
    });

    test('User with otp_required_for_login from JSON', () {
      final json = {
        'id': '123',
        'email': 'test@example.com',
        'otp_required_for_login': true,
      };

      final user = User.fromJson(json);

      expect(user.mfaEnabled, isTrue);
    });

    test('User without MFA flags defaults to false', () {
      final json = {
        'id': '123',
        'email': 'test@example.com',
      };

      final user = User.fromJson(json);

      expect(user.mfaEnabled, isFalse);
    });

    test('User toJson includes mfa_enabled', () {
      const user = User(
        id: '123',
        email: 'test@example.com',
        mfaEnabled: true,
      );

      final json = user.toJson();

      expect(json['mfa_enabled'], isTrue);
    });
  });

  group('MFA Session Token Validation', () {
    test('valid session token format', () {
      const token = 'mfa-session-abc123';
      final isValid = _isValidSessionToken(token);
      expect(isValid, isTrue);
    });

    test('empty session token is invalid', () {
      const token = '';
      final isValid = _isValidSessionToken(token);
      expect(isValid, isFalse);
    });

    test('null session token check', () {
      const String? token = null;
      final isValid = token != null && _isValidSessionToken(token);
      expect(isValid, isFalse);
    });

    test('session token with only whitespace is invalid', () {
      const token = '   ';
      final isValid = _isValidSessionToken(token);
      expect(isValid, isFalse);
    });
  });
}

// Helper validation function matching the screen's logic
bool _isValidMFACode(String code) {
  if (code.length != 6) {
    return false;
  }
  // Check if all characters are digits
  return RegExp(r'^[0-9]{6}$').hasMatch(code);
}

// Helper function to validate session token
bool _isValidSessionToken(String token) {
  return token.trim().isNotEmpty;
}
