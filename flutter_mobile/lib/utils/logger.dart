import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

/// Simple logger utility for the app
class AppLogger {
  static const String _name = 'AMOS';

  /// Log debug message
  static void debug(String message, {String? tag}) {
    if (kDebugMode) {
      developer.log(
        message,
        name: tag ?? _name,
        level: 500,
      );
    }
  }

  /// Log info message
  static void info(String message, {String? tag}) {
    developer.log(
      message,
      name: tag ?? _name,
      level: 800,
    );
  }

  /// Log warning message
  static void warning(String message, {String? tag}) {
    developer.log(
      message,
      name: tag ?? _name,
      level: 900,
    );
  }

  /// Log error with optional error object and stack trace
  static void error(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    developer.log(
      message,
      name: tag ?? _name,
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
