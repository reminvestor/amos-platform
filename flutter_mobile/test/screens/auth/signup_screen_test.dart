import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/user.dart';
import 'package:amos_mobile/providers/auth_provider.dart';

void main() {
  group('Signup Form Validation Logic', () {
    group('Name Validation', () {
      test('empty name should fail validation', () {
        const value = '';
        final result = _validateName(value);
        expect(result, equals('Please enter your name'));
      });

      test('null name should fail validation', () {
        const String? value = null;
        final result = _validateName(value);
        expect(result, equals('Please enter your name'));
      });

      test('valid name should pass validation', () {
        const value = 'John Doe';
        final result = _validateName(value);
        expect(result, isNull);
      });

      test('single name should pass validation', () {
        const value = 'John';
        final result = _validateName(value);
        expect(result, isNull);
      });

      test('name with numbers should pass validation', () {
        const value = 'John123';
        final result = _validateName(value);
        expect(result, isNull);
      });

      test('whitespace only name should pass validation check', () {
        const value = '   ';
        final result = _validateName(value);
        expect(result, isNull); // Non-empty check passes
      });
    });

    group('Email Validation', () {
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

      test('valid email should pass validation', () {
        const value = 'test@example.com';
        final result = _validateEmail(value);
        expect(result, isNull);
      });

      test('email with subdomain should pass validation', () {
        const value = 'user@mail.example.co.uk';
        final result = _validateEmail(value);
        expect(result, isNull);
      });
    });

    group('Password Validation', () {
      test('empty password should fail validation', () {
        const value = '';
        final result = _validatePassword(value);
        expect(result, equals('Please enter a password'));
      });

      test('null password should fail validation', () {
        const String? value = null;
        final result = _validatePassword(value);
        expect(result, equals('Please enter a password'));
      });

      test('password less than 6 characters should fail validation', () {
        const value = '12345';
        final result = _validatePassword(value);
        expect(result, equals('Password must be at least 6 characters'));
      });

      test('password with exactly 6 characters should pass validation', () {
        const value = '123456';
        final result = _validatePassword(value);
        expect(result, isNull);
      });

      test('password with more than 6 characters should pass validation', () {
        const value = 'password123';
        final result = _validatePassword(value);
        expect(result, isNull);
      });

      test('password with only 1 character should fail validation', () {
        const value = 'a';
        final result = _validatePassword(value);
        expect(result, equals('Password must be at least 6 characters'));
      });

      test('password with spaces should pass if 6+ characters', () {
        const value = '12 34 5';
        final result = _validatePassword(value);
        expect(result, isNull);
      });
    });

    group('Confirm Password Validation', () {
      test('empty confirm password should fail validation', () {
        const value = '';
        const password = 'password123';
        final result = _validateConfirmPassword(value, password);
        expect(result, equals('Please confirm your password'));
      });

      test('null confirm password should fail validation', () {
        const String? value = null;
        const password = 'password123';
        final result = _validateConfirmPassword(value, password);
        expect(result, equals('Please confirm your password'));
      });

      test('mismatched confirm password should fail validation', () {
        const value = 'different';
        const password = 'password123';
        final result = _validateConfirmPassword(value, password);
        expect(result, equals('Passwords do not match'));
      });

      test('matching confirm password should pass validation', () {
        const value = 'password123';
        const password = 'password123';
        final result = _validateConfirmPassword(value, password);
        expect(result, isNull);
      });

      test('case sensitive password matching', () {
        const value = 'Password123';
        const password = 'password123';
        final result = _validateConfirmPassword(value, password);
        expect(result, equals('Passwords do not match'));
      });

      test('passwords with spaces match correctly', () {
        const value = 'pass word 123';
        const password = 'pass word 123';
        final result = _validateConfirmPassword(value, password);
        expect(result, isNull);
      });
    });
  });

  group('Signup AuthState Tests', () {
    test('default AuthState has correct initial values', () {
      const state = AuthState();

      expect(state.user, isNull);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
      expect(state.token, isNull);
      expect(state.isAuthenticated, isFalse);
    });

    test('AuthState after successful registration', () {
      const user = User(id: '123', email: 'new@example.com', name: 'New User');
      const state = AuthState(user: user, token: 'new-token');

      expect(state.isAuthenticated, isTrue);
      expect(state.user?.name, equals('New User'));
      expect(state.user?.email, equals('new@example.com'));
    });

    test('AuthState during registration loading', () {
      const state = AuthState(isLoading: true);

      expect(state.isLoading, isTrue);
      expect(state.isAuthenticated, isFalse);
    });

    test('AuthState with registration error', () {
      const state = AuthState(error: 'Email already exists');

      expect(state.error, equals('Email already exists'));
      expect(state.isAuthenticated, isFalse);
      expect(state.isLoading, isFalse);
    });
  });

  group('Signup AuthResult Tests', () {
    test('AuthResult contains user and token', () {
      const user = User(
        id: '123',
        email: 'new@example.com',
        name: 'New User',
      );
      const result = AuthResult(user: user, token: 'new-token');

      expect(result.user.id, equals('123'));
      expect(result.user.email, equals('new@example.com'));
      expect(result.token, equals('new-token'));
    });

    test('AuthResult with minimal user data', () {
      const user = User(id: '456', email: 'minimal@example.com');
      const result = AuthResult(user: user, token: 'min-token');

      expect(result.user.name, isNull);
      expect(result.user.entityId, isNull);
      expect(result.token, equals('min-token'));
    });
  });

  group('User Model Tests for Signup', () {
    test('User initials from full name', () {
      const user = User(
        id: '1',
        email: 'test@example.com',
        name: 'John Doe',
      );

      expect(user.initials, equals('JD'));
    });

    test('User initials from single name', () {
      const user = User(
        id: '1',
        email: 'test@example.com',
        name: 'John',
      );

      expect(user.initials, equals('J'));
    });

    test('User initials from email when no name', () {
      const user = User(
        id: '1',
        email: 'test@example.com',
      );

      expect(user.initials, equals('T'));
    });

    test('User initials from three-part name', () {
      const user = User(
        id: '1',
        email: 'test@example.com',
        name: 'John Michael Doe',
      );

      expect(user.initials, equals('JM'));
    });
  });
}

// Helper validation functions matching the screen's logic
String? _validateName(String? value) {
  if (value == null || value.isEmpty) {
    return 'Please enter your name';
  }
  return null;
}

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
    return 'Please enter a password';
  }
  if (value.length < 6) {
    return 'Password must be at least 6 characters';
  }
  return null;
}

String? _validateConfirmPassword(String? value, String password) {
  if (value == null || value.isEmpty) {
    return 'Please confirm your password';
  }
  if (value != password) {
    return 'Passwords do not match';
  }
  return null;
}
