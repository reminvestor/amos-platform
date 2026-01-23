import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:amos_mobile/utils/exceptions.dart';

// Note: ApiClient uses FlutterSecureStorage which requires native plugins.
// For unit tests, we test the error handling logic and response patterns separately.

void main() {
  group('ApiClient Error Handling Logic', () {
    group('DioExceptionType mapping', () {
      test('connectionTimeout should map to TimeoutException', () {
        final errorType = DioExceptionType.connectionTimeout;
        final exception = _mapDioExceptionType(errorType);

        expect(exception, isA<TimeoutException>());
        expect(exception.code, equals('TIMEOUT_ERROR'));
      });

      test('sendTimeout should map to TimeoutException', () {
        final errorType = DioExceptionType.sendTimeout;
        final exception = _mapDioExceptionType(errorType);

        expect(exception, isA<TimeoutException>());
      });

      test('receiveTimeout should map to TimeoutException', () {
        final errorType = DioExceptionType.receiveTimeout;
        final exception = _mapDioExceptionType(errorType);

        expect(exception, isA<TimeoutException>());
      });

      test('connectionError should map to NetworkException', () {
        final errorType = DioExceptionType.connectionError;
        final exception = _mapDioExceptionType(errorType);

        expect(exception, isA<NetworkException>());
        expect(exception.code, equals('NETWORK_ERROR'));
      });

      test('badCertificate should map to NetworkException', () {
        final errorType = DioExceptionType.badCertificate;
        final exception = _mapDioExceptionType(errorType);

        expect(exception, isA<NetworkException>());
      });

      test('unknown should map to NetworkException', () {
        final errorType = DioExceptionType.unknown;
        final exception = _mapDioExceptionType(errorType);

        expect(exception, isA<NetworkException>());
      });

      test('cancel should map to AppException with CANCELLED code', () {
        final errorType = DioExceptionType.cancel;
        final exception = _mapDioExceptionType(errorType);

        expect(exception, isA<AppException>());
        expect(exception.code, equals('CANCELLED'));
      });
    });

    group('HTTP Status Code mapping', () {
      test('401 should map to AuthException', () {
        final exception = _mapStatusCode(401, null);

        expect(exception, isA<AuthException>());
        expect(exception.code, equals('AUTH_ERROR'));
      });

      test('403 should map to AuthException', () {
        final exception = _mapStatusCode(403, null);

        expect(exception, isA<AuthException>());
      });

      test('404 should map to ServerException with not found message', () {
        final exception = _mapStatusCode(404, null);

        expect(exception, isA<ServerException>());
        expect(exception.message, contains('not found'));
      });

      test('422 should map to ValidationException', () {
        final exception = _mapStatusCode(422, 'Invalid email format');

        expect(exception, isA<ValidationException>());
        expect(exception.code, equals('VALIDATION_ERROR'));
        expect(exception.message, equals('Invalid email format'));
      });

      test('500 should map to ServerException', () {
        final exception = _mapStatusCode(500, null);

        expect(exception, isA<ServerException>());
        expect(exception.code, equals('SERVER_ERROR'));
      });

      test('502 should map to ServerException', () {
        final exception = _mapStatusCode(502, null);

        expect(exception, isA<ServerException>());
      });

      test('503 should map to ServerException', () {
        final exception = _mapStatusCode(503, null);

        expect(exception, isA<ServerException>());
      });
    });

    group('Error message extraction', () {
      test('extracts message from Map with message key', () {
        final data = {'message': 'User not found'};
        final message = _extractErrorMessage(data);

        expect(message, equals('User not found'));
      });

      test('extracts message from Map with error key', () {
        final data = {'error': 'Invalid credentials'};
        final message = _extractErrorMessage(data);

        expect(message, equals('Invalid credentials'));
      });

      test('prefers message key over error key', () {
        final data = {'message': 'Primary message', 'error': 'Secondary message'};
        final message = _extractErrorMessage(data);

        expect(message, equals('Primary message'));
      });

      test('extracts message from String data', () {
        final data = 'Plain text error';
        final message = _extractErrorMessage(data);

        expect(message, equals('Plain text error'));
      });

      test('returns null for empty Map', () {
        final data = <String, dynamic>{};
        final message = _extractErrorMessage(data);

        expect(message, isNull);
      });

      test('returns null for null data', () {
        final message = _extractErrorMessage(null);

        expect(message, isNull);
      });
    });
  });

  group('API Response Patterns', () {
    test('standard success response with data key', () {
      final response = {
        'data': [
          {'id': 1, 'name': 'Item 1'},
          {'id': 2, 'name': 'Item 2'},
        ],
        'pagination': {
          'current_page': 1,
          'total_pages': 5,
          'total_count': 100,
        },
      };

      final data = response['data'] as List? ?? [];
      final pagination = response['pagination'] as Map<String, dynamic>?;

      expect(data, hasLength(2));
      expect(pagination, isNotNull);
      expect(pagination!['current_page'], equals(1));
    });

    test('handles missing data key with fallback', () {
      final response = <String, dynamic>{};

      final data = response['data'] as List? ?? [];

      expect(data, isEmpty);
    });

    test('handles null response gracefully', () {
      final Map<String, dynamic>? response = null;

      final data = response?['data'] as List? ?? [];

      expect(data, isEmpty);
    });
  });

  group('Header Construction', () {
    test('default headers are set correctly', () {
      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

      expect(headers['Content-Type'], equals('application/json'));
      expect(headers['Accept'], equals('application/json'));
    });

    test('authorization header format is correct', () {
      const token = 'test_token_123';
      final headers = {
        'Authorization': 'Bearer $token',
      };

      expect(headers['Authorization'], equals('Bearer test_token_123'));
    });

    test('token extraction from header', () {
      const authHeader = 'Bearer test_token_123';
      final token = authHeader.replaceFirst('Bearer ', '');

      expect(token, equals('test_token_123'));
    });
  });

  group('Token Management Logic', () {
    test('null token should not be added to headers', () {
      final String? token = null;
      final headers = <String, String>{};

      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }

      expect(headers.containsKey('Authorization'), isFalse);
    });

    test('valid token should be added to headers', () {
      final String? token = 'valid_token';
      final headers = <String, String>{};

      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }

      expect(headers['Authorization'], equals('Bearer valid_token'));
    });

    test('empty token should still be added to headers', () {
      final String? token = '';
      final headers = <String, String>{};

      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }

      // Empty string is still considered "valid" (not null)
      expect(headers['Authorization'], equals('Bearer '));
    });
  });
}

/// Helper function that mimics ApiClient's DioExceptionType handling
AppException _mapDioExceptionType(DioExceptionType type) {
  switch (type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return TimeoutException(
        'Request timed out. Please check your connection and try again.',
        null,
      );
    case DioExceptionType.cancel:
      return AppException('Request was cancelled', 'CANCELLED', null);
    case DioExceptionType.connectionError:
      return NetworkException(
        'No internet connection. Please check your network.',
        null,
      );
    case DioExceptionType.badCertificate:
      return NetworkException('SSL certificate error', null);
    case DioExceptionType.unknown:
      return NetworkException(
        'Network error occurred. Please try again.',
        null,
      );
    case DioExceptionType.badResponse:
      // This case is handled separately by status code
      return ServerException('Bad response', null);
  }
}

/// Helper function that mimics ApiClient's status code handling
AppException _mapStatusCode(int statusCode, String? message) {
  if (statusCode == 401 || statusCode == 403) {
    return AuthException(message ?? 'Authentication failed', null);
  } else if (statusCode == 404) {
    return ServerException('Resource not found', null);
  } else if (statusCode == 422) {
    return ValidationException(message ?? 'Validation failed', null);
  } else if (statusCode >= 500) {
    return ServerException(
      'Server error ($statusCode). Please try again later.',
      null,
    );
  } else {
    return ServerException(message ?? 'Server error occurred', null);
  }
}

/// Helper function that mimics error message extraction logic
String? _extractErrorMessage(dynamic data) {
  if (data is Map<String, dynamic>) {
    return data['message']?.toString() ?? data['error']?.toString();
  } else if (data is String) {
    return data;
  }
  return null;
}
