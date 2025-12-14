import 'package:dio/dio.dart';
import 'package:amos_mobile/config/env.dart';
import 'package:amos_mobile/services/storage_service.dart';
import 'package:amos_mobile/utils/exceptions.dart';
import 'package:amos_mobile/utils/logger.dart';

class ApiClient {
  static ApiClient? _instance;
  static ApiClient get instance => _instance ??= ApiClient._();

  late final Dio _dio;
  final StorageService _storage = StorageService.instance;

  // In-memory token cache for reliable token access
  // flutter_secure_storage can have issues on iOS simulator
  String? _cachedToken;

  ApiClient._() {
    _dio = Dio(BaseOptions(
      baseUrl: Env.apiBaseUrl,
      connectTimeout: Duration(seconds: Env.requestTimeout),
      receiveTimeout: Duration(seconds: Env.requestTimeout),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        // Always access the singleton's cached token directly
        // This ensures we get the latest value even if set after this closure was created
        String? token = ApiClient.instance._cachedToken;
        print('🔑 [ApiClient] Request: ${options.method} ${options.path}');
        print('🔑 [ApiClient] Singleton hashCode: ${ApiClient.instance.hashCode}');
        print('🔑 [ApiClient] _cachedToken: ${token != null ? "${token.substring(0, 8)}..." : "NULL"}');
        if (token == null) {
          token = await StorageService.instance.read('auth_token');
          print('🔑 [ApiClient] Token from storage: ${token != null ? "${token.substring(0, 8)}..." : "NULL"}');
          if (token != null) {
            ApiClient.instance._cachedToken = token;
          }
        }

        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
          print('🔑 [ApiClient] Authorization header SET');
        } else {
          print('⚠️ [ApiClient] NO TOKEN - Authorization header NOT set');
        }
        return handler.next(options);
      },
      onResponse: (response, handler) {
        AppLogger.debug('API Response: ${response.statusCode}');
        return handler.next(response);
      },
      onError: (error, handler) {
        AppLogger.error('API Error: ${error.type} - ${error.response?.statusCode}');
        // Only clear the token if we actually sent one and it was rejected
        // Don't clear if we never had a token (that's a different error)
        if (error.response?.statusCode == 401) {
          final hadToken = error.requestOptions.headers['Authorization'] != null;
          if (hadToken) {
            print('🔐 [ApiClient] 401 with token - clearing invalid token');
            ApiClient.instance._cachedToken = null;
            StorageService.instance.delete('auth_token');
          } else {
            print('⚠️ [ApiClient] 401 without token - NOT clearing (no token was sent)');
          }
        }
        return handler.next(error);
      },
    ));
  }

  /// Set the auth token directly (bypasses storage issues on iOS simulator)
  void setAuthToken(String? token) {
    print('🔐 [ApiClient.setAuthToken] Called with: ${token != null ? "${token.substring(0, 8)}..." : "NULL"}');
    print('🔐 [ApiClient.setAuthToken] Instance hashCode: $hashCode');
    _cachedToken = token;
    if (token != null) {
      _storage.write('auth_token', token);
    } else {
      _storage.delete('auth_token');
    }
    print('🔐 [ApiClient.setAuthToken] _cachedToken is now: ${_cachedToken != null ? "SET" : "NULL"}');
  }

  /// Clear the auth token
  void clearAuthToken() {
    _cachedToken = null;
    _storage.delete('auth_token');
  }

  /// Get the current auth token (prefers cached, falls back to storage)
  /// Use this in services that need their own Dio instance (e.g., for SSE streaming)
  Future<String?> getAuthToken() async {
    if (_cachedToken != null) return _cachedToken;
    final token = await _storage.read('auth_token');
    if (token != null) {
      _cachedToken = token;
    }
    return token;
  }

  // Factory constructor for backward compatibility
  factory ApiClient() => instance;

  Future<dynamic> get(String path, {Map<String, dynamic>? queryParameters}) async {
    try {
      final response = await _dio.get(path, queryParameters: queryParameters);
      return response.data;
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e, stackTrace) {
      AppLogger.error('Unexpected error in GET $path', error: e, stackTrace: stackTrace);
      throw AppException('An unexpected error occurred', null, e);
    }
  }

  Future<dynamic> post(String path, {dynamic data}) async {
    try {
      final response = await _dio.post(path, data: data);
      return response.data;
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e, stackTrace) {
      AppLogger.error('Unexpected error in POST $path', error: e, stackTrace: stackTrace);
      throw AppException('An unexpected error occurred', null, e);
    }
  }

  Future<dynamic> put(String path, {dynamic data}) async {
    try {
      final response = await _dio.put(path, data: data);
      return response.data;
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e, stackTrace) {
      AppLogger.error('Unexpected error in PUT $path', error: e, stackTrace: stackTrace);
      throw AppException('An unexpected error occurred', null, e);
    }
  }

  Future<dynamic> patch(String path, {dynamic data}) async {
    try {
      final response = await _dio.patch(path, data: data);
      return response.data;
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e, stackTrace) {
      AppLogger.error('Unexpected error in PATCH $path', error: e, stackTrace: stackTrace);
      throw AppException('An unexpected error occurred', null, e);
    }
  }

  Future<dynamic> delete(String path) async {
    try {
      final response = await _dio.delete(path);
      return response.data;
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e, stackTrace) {
      AppLogger.error('Unexpected error in DELETE $path', error: e, stackTrace: stackTrace);
      throw AppException('An unexpected error occurred', null, e);
    }
  }

  /// Handle Dio errors and convert to custom exceptions
  AppException _handleDioError(DioException error) {
    AppLogger.error(
      'API Error: ${error.type}',
      error: error,
      stackTrace: error.stackTrace,
    );

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return TimeoutException(
          'Request timed out. Please check your connection and try again.',
          error,
        );

      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode;
        final data = error.response?.data;
        String? message;
        if (data is Map<String, dynamic>) {
          message = data['message']?.toString() ?? data['error']?.toString();
        } else if (data is String) {
          message = data;
        }
        message ??= error.response?.statusMessage;

        if (statusCode == 401 || statusCode == 403) {
          return AuthException(message ?? 'Authentication failed', error);
        } else if (statusCode == 404) {
          return ServerException('Resource not found', error);
        } else if (statusCode == 422) {
          return ValidationException(message ?? 'Validation failed', error);
        } else if (statusCode != null && statusCode >= 500) {
          return ServerException(
            'Server error ($statusCode). Please try again later.',
            error,
          );
        } else {
          return ServerException(message ?? 'Server error occurred', error);
        }

      case DioExceptionType.cancel:
        return AppException('Request was cancelled', 'CANCELLED', error);

      case DioExceptionType.connectionError:
        return NetworkException(
          'No internet connection. Please check your network.',
          error,
        );

      case DioExceptionType.badCertificate:
        return NetworkException('SSL certificate error', error);

      case DioExceptionType.unknown:
        return NetworkException(
          'Network error occurred. Please try again.',
          error,
        );
    }
  }
}
