import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/utils/exceptions.dart';

void main() {
  group('AppException', () {
    test('creates with message only', () {
      final exception = AppException('Test error');

      expect(exception.message, equals('Test error'));
      expect(exception.code, isNull);
      expect(exception.originalError, isNull);
    });

    test('creates with message and code', () {
      final exception = AppException('Test error', 'TEST_CODE');

      expect(exception.message, equals('Test error'));
      expect(exception.code, equals('TEST_CODE'));
      expect(exception.originalError, isNull);
    });

    test('creates with message, code, and original error', () {
      final originalError = Exception('Original');
      final exception = AppException('Test error', 'TEST_CODE', originalError);

      expect(exception.message, equals('Test error'));
      expect(exception.code, equals('TEST_CODE'));
      expect(exception.originalError, equals(originalError));
    });

    test('toString returns message', () {
      final exception = AppException('Test error message');

      expect(exception.toString(), equals('Test error message'));
    });
  });

  group('NetworkException', () {
    test('creates with default message', () {
      final exception = NetworkException();

      expect(exception.message, equals('Network error. Please check your connection.'));
      expect(exception.code, equals('NETWORK_ERROR'));
      expect(exception.originalError, isNull);
    });

    test('creates with custom message', () {
      final exception = NetworkException('Custom network error');

      expect(exception.message, equals('Custom network error'));
      expect(exception.code, equals('NETWORK_ERROR'));
    });

    test('creates with message and original error', () {
      final originalError = Exception('Socket exception');
      final exception = NetworkException('Network failed', originalError);

      expect(exception.message, equals('Network failed'));
      expect(exception.originalError, equals(originalError));
    });
  });

  group('AuthException', () {
    test('creates with default message', () {
      final exception = AuthException();

      expect(exception.message, equals('Authentication failed. Please log in again.'));
      expect(exception.code, equals('AUTH_ERROR'));
    });

    test('creates with custom message', () {
      final exception = AuthException('Session expired');

      expect(exception.message, equals('Session expired'));
      expect(exception.code, equals('AUTH_ERROR'));
    });

    test('creates with message and original error', () {
      final originalError = Exception('401 Unauthorized');
      final exception = AuthException('Token invalid', originalError);

      expect(exception.message, equals('Token invalid'));
      expect(exception.originalError, equals(originalError));
    });
  });

  group('ValidationException', () {
    test('creates with message', () {
      final exception = ValidationException('Email is required');

      expect(exception.message, equals('Email is required'));
      expect(exception.code, equals('VALIDATION_ERROR'));
      expect(exception.originalError, isNull);
    });

    test('creates with message and original error', () {
      final originalError = FormatException('Invalid email format');
      final exception = ValidationException('Invalid email', originalError);

      expect(exception.message, equals('Invalid email'));
      expect(exception.code, equals('VALIDATION_ERROR'));
      expect(exception.originalError, equals(originalError));
    });
  });

  group('ServerException', () {
    test('creates with default message', () {
      final exception = ServerException();

      expect(exception.message, equals('Server error occurred. Please try again later.'));
      expect(exception.code, equals('SERVER_ERROR'));
    });

    test('creates with custom message', () {
      final exception = ServerException('Database connection failed');

      expect(exception.message, equals('Database connection failed'));
      expect(exception.code, equals('SERVER_ERROR'));
    });

    test('creates with message and original error', () {
      final originalError = Exception('500 Internal Server Error');
      final exception = ServerException('Server unavailable', originalError);

      expect(exception.message, equals('Server unavailable'));
      expect(exception.originalError, equals(originalError));
    });
  });

  group('TimeoutException', () {
    test('creates with default message', () {
      final exception = TimeoutException();

      expect(exception.message, equals('Request timed out. Please try again.'));
      expect(exception.code, equals('TIMEOUT_ERROR'));
    });

    test('creates with custom message', () {
      final exception = TimeoutException('Connection timeout after 30s');

      expect(exception.message, equals('Connection timeout after 30s'));
      expect(exception.code, equals('TIMEOUT_ERROR'));
    });

    test('creates with message and original error', () {
      final originalError = Exception('Connection timeout');
      final exception = TimeoutException('Request failed', originalError);

      expect(exception.message, equals('Request failed'));
      expect(exception.originalError, equals(originalError));
    });
  });

  group('Exception inheritance', () {
    test('all custom exceptions implement Exception', () {
      expect(AppException('test'), isA<Exception>());
      expect(NetworkException(), isA<Exception>());
      expect(AuthException(), isA<Exception>());
      expect(ValidationException('test'), isA<Exception>());
      expect(ServerException(), isA<Exception>());
      expect(TimeoutException(), isA<Exception>());
    });

    test('all custom exceptions extend AppException', () {
      expect(NetworkException(), isA<AppException>());
      expect(AuthException(), isA<AppException>());
      expect(ValidationException('test'), isA<AppException>());
      expect(ServerException(), isA<AppException>());
      expect(TimeoutException(), isA<AppException>());
    });
  });
}
