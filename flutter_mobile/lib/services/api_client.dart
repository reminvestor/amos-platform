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
        final token = await _storage.read('auth_token');
        // ignore: avoid_print
        print('[API] Request: ${options.method} ${options.uri}');
        // ignore: avoid_print
        print('[API] Token present: ${token != null}');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        AppLogger.debug('API Request: ${options.method} ${options.path}');
        return handler.next(options);
      },
      onResponse: (response, handler) {
        // ignore: avoid_print
        print('[API] Response: ${response.statusCode}');
        AppLogger.debug('API Response: ${response.statusCode}');
        return handler.next(response);
      },
      onError: (error, handler) {
        // ignore: avoid_print
        print('[API] Error: ${error.type} - ${error.response?.statusCode}');
        // ignore: avoid_print
        print('[API] Error message: ${error.message}');
        AppLogger.error('API Error: ${error.response?.statusCode}');
        if (error.response?.statusCode == 401) {
          _storage.delete('auth_token');
        }
        return handler.next(error);
      },
    ));
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
        final message = error.response?.data?['message'] ??
                       error.response?.data?['error'] ??
                       error.response?.statusMessage;

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
      default:
        return NetworkException(
          'Network error occurred. Please try again.',
          error,
        );
    }
  }
}
