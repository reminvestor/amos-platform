import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/user.dart';

void main() {
  group('User', () {
    test('fromJson parses complete JSON correctly', () {
      final json = {
        'id': 1,
        'email': 'test@example.com',
        'name': 'John Doe',
        'entity_id': '123',
        'avatar_url': 'https://example.com/avatar.jpg',
        'created_at': '2024-01-15T10:30:00.000Z',
        'mfa_enabled': true,
      };

      final user = User.fromJson(json);

      expect(user.id, equals('1'));
      expect(user.email, equals('test@example.com'));
      expect(user.name, equals('John Doe'));
      expect(user.entityId, equals('123'));
      expect(user.avatarUrl, equals('https://example.com/avatar.jpg'));
      expect(user.createdAt, equals(DateTime.parse('2024-01-15T10:30:00.000Z')));
      expect(user.mfaEnabled, isTrue);
    });

    test('fromJson handles otp_required_for_login for mfa', () {
      final json = {
        'id': '123',
        'email': 'test@example.com',
        'otp_required_for_login': true,
      };

      final user = User.fromJson(json);

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

    test('initials returns two letters for full name', () {
      const user = User(
        id: '123',
        email: 'test@example.com',
        name: 'John Doe',
      );

      expect(user.initials, equals('JD'));
    });

    test('initials returns single letter for single name', () {
      const user = User(
        id: '123',
        email: 'test@example.com',
        name: 'John',
      );

      expect(user.initials, equals('J'));
    });

    test('initials returns email first letter when name is null', () {
      const user = User(
        id: '123',
        email: 'test@example.com',
      );

      expect(user.initials, equals('T'));
    });

    test('initials returns email first letter when name is empty', () {
      const user = User(
        id: '123',
        email: 'test@example.com',
        name: '',
      );

      expect(user.initials, equals('T'));
    });

    test('initials handles three-part name correctly', () {
      const user = User(
        id: '123',
        email: 'test@example.com',
        name: 'John Michael Doe',
      );

      expect(user.initials, equals('JM'));
    });

    test('toJson serializes correctly', () {
      const user = User(
        id: '123',
        email: 'test@example.com',
        name: 'John Doe',
        entityId: '456',
        avatarUrl: 'https://example.com/avatar.jpg',
        createdAt: null,
        mfaEnabled: true,
      );

      final json = user.toJson();

      expect(json['id'], equals('123'));
      expect(json['email'], equals('test@example.com'));
      expect(json['name'], equals('John Doe'));
      expect(json['entity_id'], equals('456'));
      expect(json['avatar_url'], equals('https://example.com/avatar.jpg'));
      expect(json['created_at'], isNull);
      expect(json['mfa_enabled'], isTrue);
    });

    test('toJson includes createdAt when present', () {
      final user = User(
        id: '123',
        email: 'test@example.com',
        createdAt: DateTime.parse('2024-01-15T10:30:00.000Z'),
      );

      final json = user.toJson();

      expect(json['created_at'], equals('2024-01-15T10:30:00.000Z'));
    });
  });

  group('AuthResult', () {
    test('creates with required fields', () {
      const user = User(id: '123', email: 'test@example.com');
      const result = AuthResult(user: user, token: 'abc123');

      expect(result.user.id, equals('123'));
      expect(result.token, equals('abc123'));
    });
  });

  group('LoginResult', () {
    test('creates successful login result', () {
      const user = User(id: '123', email: 'test@example.com');
      const authResult = AuthResult(user: user, token: 'abc123');
      const result = LoginResult(authResult: authResult);

      expect(result.authResult, isNotNull);
      expect(result.authResult!.user.id, equals('123'));
      expect(result.mfaRequired, isFalse);
      expect(result.mfaSessionToken, isNull);
    });

    test('creates MFA required result', () {
      const result = LoginResult(
        mfaRequired: true,
        mfaSessionToken: 'mfa-session-123',
      );

      expect(result.authResult, isNull);
      expect(result.mfaRequired, isTrue);
      expect(result.mfaSessionToken, equals('mfa-session-123'));
    });

    test('has default values', () {
      const result = LoginResult();

      expect(result.authResult, isNull);
      expect(result.mfaRequired, isFalse);
      expect(result.mfaSessionToken, isNull);
    });
  });
}
