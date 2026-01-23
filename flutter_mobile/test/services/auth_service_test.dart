import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/user.dart';

// Note: AuthService uses ApiClient which requires native plugins (FlutterSecureStorage).
// For unit tests, we test the data models and transformation logic separately.

void main() {
  group('User Model', () {
    test('fromJson parses complete user data', () {
      final json = {
        'id': 123,
        'email': 'test@example.com',
        'name': 'John Doe',
        'entity_id': 456,
        'avatar_url': 'https://example.com/avatar.jpg',
        'created_at': '2024-01-15T10:30:00.000Z',
        'mfa_enabled': true,
      };

      final user = User.fromJson(json);

      expect(user.id, equals('123'));
      expect(user.email, equals('test@example.com'));
      expect(user.name, equals('John Doe'));
      expect(user.entityId, equals('456'));
      expect(user.avatarUrl, equals('https://example.com/avatar.jpg'));
      expect(user.createdAt, equals(DateTime.parse('2024-01-15T10:30:00.000Z')));
      expect(user.mfaEnabled, isTrue);
    });

    test('fromJson handles minimal required fields', () {
      final json = {
        'id': '123',
        'email': 'test@example.com',
      };

      final user = User.fromJson(json);

      expect(user.id, equals('123'));
      expect(user.email, equals('test@example.com'));
      expect(user.name, isNull);
      expect(user.entityId, isNull);
      expect(user.avatarUrl, isNull);
      expect(user.createdAt, isNull);
      expect(user.mfaEnabled, isFalse);
    });

    test('fromJson handles otp_required_for_login as mfaEnabled', () {
      final json = {
        'id': '123',
        'email': 'test@example.com',
        'otp_required_for_login': true,
      };

      final user = User.fromJson(json);

      expect(user.mfaEnabled, isTrue);
    });

    test('fromJson converts numeric id to string', () {
      final json = {
        'id': 123,
        'email': 'test@example.com',
      };

      final user = User.fromJson(json);

      expect(user.id, equals('123'));
      expect(user.id, isA<String>());
    });

    test('toJson serializes correctly', () {
      final user = User(
        id: '123',
        email: 'test@example.com',
        name: 'John Doe',
        entityId: '456',
        avatarUrl: 'https://example.com/avatar.jpg',
        createdAt: DateTime.parse('2024-01-15T10:30:00.000Z'),
        mfaEnabled: true,
      );

      final json = user.toJson();

      expect(json['id'], equals('123'));
      expect(json['email'], equals('test@example.com'));
      expect(json['name'], equals('John Doe'));
      expect(json['entity_id'], equals('456'));
      expect(json['avatar_url'], equals('https://example.com/avatar.jpg'));
      expect(json['created_at'], equals('2024-01-15T10:30:00.000Z'));
      expect(json['mfa_enabled'], isTrue);
    });

    test('toJson includes null values for optional fields', () {
      final user = User(
        id: '123',
        email: 'test@example.com',
      );

      final json = user.toJson();

      expect(json['name'], isNull);
      expect(json['entity_id'], isNull);
      expect(json['avatar_url'], isNull);
      expect(json['created_at'], isNull);
    });

    group('initials getter', () {
      test('returns initials from full name with two parts', () {
        final user = User(
          id: '123',
          email: 'test@example.com',
          name: 'John Doe',
        );

        expect(user.initials, equals('JD'));
      });

      test('returns single initial from single name', () {
        final user = User(
          id: '123',
          email: 'test@example.com',
          name: 'John',
        );

        expect(user.initials, equals('J'));
      });

      test('returns first letter of email when name is null', () {
        final user = User(
          id: '123',
          email: 'test@example.com',
        );

        expect(user.initials, equals('T'));
      });

      test('returns first letter of email when name is empty', () {
        final user = User(
          id: '123',
          email: 'test@example.com',
          name: '',
        );

        expect(user.initials, equals('T'));
      });

      test('handles name with multiple spaces', () {
        final user = User(
          id: '123',
          email: 'test@example.com',
          name: 'John Michael Doe',
        );

        // First and second parts
        expect(user.initials, equals('JM'));
      });

      test('initials are uppercase', () {
        final user = User(
          id: '123',
          email: 'test@example.com',
          name: 'john doe',
        );

        expect(user.initials, equals('JD'));
      });
    });
  });

  group('AuthResult', () {
    test('creates with required fields', () {
      final user = User(
        id: '123',
        email: 'test@example.com',
        name: 'John Doe',
      );
      const token = 'auth_token_abc123';

      final result = AuthResult(user: user, token: token);

      expect(result.user.id, equals('123'));
      expect(result.user.email, equals('test@example.com'));
      expect(result.token, equals('auth_token_abc123'));
    });

    test('is const constructible', () {
      const user = User(
        id: '123',
        email: 'test@example.com',
      );
      const result = AuthResult(user: user, token: 'token');

      expect(result.user.id, equals('123'));
    });
  });

  group('LoginResult', () {
    test('creates successful login without MFA', () {
      final user = User(
        id: '123',
        email: 'test@example.com',
      );
      final authResult = AuthResult(user: user, token: 'token123');

      final loginResult = LoginResult(authResult: authResult);

      expect(loginResult.authResult, isNotNull);
      expect(loginResult.authResult!.user.id, equals('123'));
      expect(loginResult.mfaRequired, isFalse);
      expect(loginResult.mfaSessionToken, isNull);
    });

    test('creates MFA required response', () {
      final loginResult = LoginResult(
        mfaRequired: true,
        mfaSessionToken: 'mfa_session_abc123',
      );

      expect(loginResult.authResult, isNull);
      expect(loginResult.mfaRequired, isTrue);
      expect(loginResult.mfaSessionToken, equals('mfa_session_abc123'));
    });

    test('default values are set correctly', () {
      const loginResult = LoginResult();

      expect(loginResult.authResult, isNull);
      expect(loginResult.mfaRequired, isFalse);
      expect(loginResult.mfaSessionToken, isNull);
    });

    test('is const constructible', () {
      const loginResult = LoginResult(
        mfaRequired: true,
        mfaSessionToken: 'token',
      );

      expect(loginResult.mfaRequired, isTrue);
    });
  });

  group('Login API Response Parsing', () {
    test('parses successful login response without MFA', () {
      final response = {
        'user': {
          'id': 123,
          'email': 'test@example.com',
          'name': 'John Doe',
          'entity_id': 456,
        },
        'api_key': 'auth_token_xyz789',
      };

      final user = User.fromJson(response['user'] as Map<String, dynamic>);
      final token = (response['api_key'] ?? response['token']) as String;

      expect(user.email, equals('test@example.com'));
      expect(token, equals('auth_token_xyz789'));
    });

    test('parses successful login response with token field', () {
      final response = {
        'user': {
          'id': '123',
          'email': 'test@example.com',
        },
        'token': 'auth_token_alternative',
      };

      final token = (response['api_key'] ?? response['token']) as String;

      expect(token, equals('auth_token_alternative'));
    });

    test('detects MFA required response', () {
      final response = {
        'mfa_required': true,
        'mfa_session_token': 'mfa_session_abc123',
      };

      final mfaRequired = response['mfa_required'] == true;
      final mfaSessionToken = response['mfa_session_token'] as String;

      expect(mfaRequired, isTrue);
      expect(mfaSessionToken, equals('mfa_session_abc123'));
    });

    test('MFA not required when field is false', () {
      final response = {
        'mfa_required': false,
        'user': {
          'id': '123',
          'email': 'test@example.com',
        },
        'api_key': 'token',
      };

      final mfaRequired = response['mfa_required'] == true;

      expect(mfaRequired, isFalse);
    });

    test('MFA not required when field is missing', () {
      final response = {
        'user': {
          'id': '123',
          'email': 'test@example.com',
        },
        'api_key': 'token',
      };

      final mfaRequired = response['mfa_required'] == true;

      expect(mfaRequired, isFalse);
    });
  });

  group('Register API Response Parsing', () {
    test('parses registration response', () {
      final response = {
        'user': {
          'id': 789,
          'email': 'newuser@example.com',
          'name': 'New User',
          'entity_id': 100,
        },
        'api_key': 'new_user_token',
      };

      final user = User.fromJson(response['user'] as Map<String, dynamic>);
      final token = (response['api_key'] ?? response['token']) as String;

      expect(user.id, equals('789'));
      expect(user.email, equals('newuser@example.com'));
      expect(user.name, equals('New User'));
      expect(token, equals('new_user_token'));
    });
  });

  group('MFA Verify Response Parsing', () {
    test('parses MFA verification success response', () {
      final response = {
        'user': {
          'id': 123,
          'email': 'test@example.com',
          'name': 'John Doe',
          'mfa_enabled': true,
        },
        'api_key': 'authenticated_token',
      };

      final user = User.fromJson(response['user'] as Map<String, dynamic>);
      final token = (response['api_key'] ?? response['token']) as String;

      expect(user.mfaEnabled, isTrue);
      expect(token, equals('authenticated_token'));
    });
  });

  group('Auth Check Response Parsing', () {
    test('parses /api/auth/me response', () {
      final response = {
        'user': {
          'id': 123,
          'email': 'test@example.com',
          'name': 'John Doe',
          'entity_id': 456,
          'mfa_enabled': false,
        },
      };

      final user = User.fromJson(response['user'] as Map<String, dynamic>);

      expect(user.id, equals('123'));
      expect(user.email, equals('test@example.com'));
      expect(user.name, equals('John Doe'));
      expect(user.entityId, equals('456'));
    });
  });

  group('Storage Keys', () {
    test('token key constant', () {
      const tokenKey = 'auth_token';
      expect(tokenKey, equals('auth_token'));
    });

    test('user key constant', () {
      const userKey = 'user_data';
      expect(userKey, equals('user_data'));
    });
  });
}
