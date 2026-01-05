// Custom exception classes for better error handling

class AppException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;

  AppException(this.message, [this.code, this.originalError]);

  @override
  String toString() => message;
}

class NetworkException extends AppException {
  NetworkException([String? message, dynamic originalError])
      : super(
          message ?? 'Network error. Please check your connection.',
          'NETWORK_ERROR',
          originalError,
        );
}

class AuthException extends AppException {
  AuthException([String? message, dynamic originalError])
      : super(
          message ?? 'Authentication failed. Please log in again.',
          'AUTH_ERROR',
          originalError,
        );
}

class ValidationException extends AppException {
  ValidationException(String message, [dynamic originalError])
      : super(message, 'VALIDATION_ERROR', originalError);
}

class ServerException extends AppException {
  ServerException([String? message, dynamic originalError])
      : super(
          message ?? 'Server error occurred. Please try again later.',
          'SERVER_ERROR',
          originalError,
        );
}

class TimeoutException extends AppException {
  TimeoutException([String? message, dynamic originalError])
      : super(
          message ?? 'Request timed out. Please try again.',
          'TIMEOUT_ERROR',
          originalError,
        );
}
