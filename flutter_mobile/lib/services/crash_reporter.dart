import 'package:flutter/foundation.dart';
import 'package:amos_mobile/config/env.dart';
import 'package:amos_mobile/utils/logger.dart';

/// Crash reporter service that can be configured to send errors to a backend
///
/// In production, this can be configured to:
/// - Send errors to AWS CloudWatch
/// - Send errors to your Rails backend for logging
/// - Integrate with Sentry, Datadog, or other APM tools
class CrashReporter {
  static CrashReporter? _instance;
  static CrashReporter get instance => _instance ??= CrashReporter._();

  CrashReporter._();

  bool _initialized = false;

  /// Initialize the crash reporter
  Future<void> initialize() async {
    if (_initialized) return;

    // Only enable remote reporting in production
    if (Env.isProduction) {
      AppLogger.info('CrashReporter initialized for production');
      // TODO: Initialize your preferred crash reporting service here
      // Examples:
      // - Sentry.init(...)
      // - Amplify.addPlugin(AmplifyAnalytics())
    }

    _initialized = true;
  }

  /// Record a non-fatal error
  void recordError(
    dynamic error, {
    StackTrace? stackTrace,
    String? reason,
    bool fatal = false,
  }) {
    // Always log locally
    AppLogger.error(
      reason ?? 'Error recorded',
      error: error,
      stackTrace: stackTrace,
    );

    // In production, send to remote service
    if (Env.isProduction && !kDebugMode) {
      _sendToRemote(error, stackTrace: stackTrace, reason: reason, fatal: fatal);
    }
  }

  /// Record a Flutter error
  void recordFlutterError(FlutterErrorDetails details) {
    recordError(
      details.exception,
      stackTrace: details.stack,
      reason: details.context?.toString(),
      fatal: false,
    );
  }

  /// Set user identifier for crash reports
  void setUser({String? id, String? email, String? name}) {
    if (Env.isProduction) {
      AppLogger.debug('Set crash reporter user: $id');
      // TODO: Set user info in your crash reporting service
    }
  }

  /// Log a custom event
  void logEvent(String name, {Map<String, dynamic>? parameters}) {
    if (Env.analyticsEnabled) {
      AppLogger.debug('Event: $name ${parameters ?? {}}');
      // TODO: Send to analytics service
    }
  }

  /// Send error to remote service
  Future<void> _sendToRemote(
    dynamic error, {
    StackTrace? stackTrace,
    String? reason,
    bool fatal = false,
  }) async {
    // TODO: Implement remote error reporting
    //
    // Option 1: Send to your Rails backend
    // await ApiClient.instance.post('/api/mobile/errors', data: {
    //   'error': error.toString(),
    //   'stack_trace': stackTrace?.toString(),
    //   'reason': reason,
    //   'fatal': fatal,
    //   'platform': Platform.operatingSystem,
    //   'app_version': Env.appVersion,
    // });
    //
    // Option 2: Use Sentry
    // await Sentry.captureException(error, stackTrace: stackTrace);
    //
    // Option 3: Use AWS CloudWatch via Amplify
    // await Amplify.Analytics.recordEvent(...)
  }
}
