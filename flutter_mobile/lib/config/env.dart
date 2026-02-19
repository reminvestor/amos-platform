import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode, kDebugMode;

/// Environment types
enum Environment { development, staging, production }

/// Environment configuration
///
/// Configure via dart-define flags:
/// - flutter run --dart-define=ENVIRONMENT=production --dart-define=API_BASE_URL=https://api.amoslabs.com
class Env {
  /// Current environment (defaults to production in release mode)
  static Environment get environment {
    const envString = String.fromEnvironment('ENVIRONMENT', defaultValue: '');
    switch (envString.toLowerCase()) {
      case 'development':
      case 'dev':
        return Environment.development;
      case 'staging':
      case 'stage':
        return Environment.staging;
      case 'production':
      case 'prod':
      default:
        return kReleaseMode ? Environment.production : Environment.development;
    }
  }

  /// Whether we're in production mode
  static bool get isProduction => environment == Environment.production;

  /// Whether we're in development mode
  static bool get isDevelopment => environment == Environment.development;

  /// API base URL - configured via environment or dart-define
  ///
  /// For production builds:
  ///   flutter build --dart-define=API_BASE_URL=https://api.amoslabs.com
  ///
  /// For development:
  ///   flutter run --dart-define=API_BASE_URL=http://192.168.1.211:3000
  static String get apiBaseUrl {
    // Check for environment override first (highest priority)
    const envUrl = String.fromEnvironment('API_BASE_URL');
    if (envUrl.isNotEmpty) return envUrl;

    // Environment-based defaults
    switch (environment) {
      case Environment.production:
        return 'https://api.amoslabs.com';
      case Environment.staging:
        return 'https://staging-api.amoslabs.com';
      case Environment.development:
        // Web runs in browser on same machine as Docker
        if (kIsWeb) {
          return 'http://localhost:3000';
        }
        // Physical devices need LAN IP - override with dart-define for your network
        return 'http://localhost:3000';
    }
  }

  /// Privacy policy URL
  static String get privacyPolicyUrl {
    const url = String.fromEnvironment('PRIVACY_POLICY_URL');
    return url.isNotEmpty ? url : 'https://www.amoslabs.com/privacy';
  }

  /// Terms of service / License agreement URL
  static String get termsOfServiceUrl {
    const url = String.fromEnvironment('TERMS_OF_SERVICE_URL');
    return url.isNotEmpty ? url : 'https://www.amoslabs.com/license';
  }

  /// Support email
  static String get supportEmail {
    const email = String.fromEnvironment('SUPPORT_EMAIL');
    return email.isNotEmpty ? email : 'support@amoslabs.com';
  }

  /// App name
  static const String appName = 'AMOS Labs';

  /// App version
  static const String appVersion = '1.1.0';

  /// Enable debug logging (disabled in production by default)
  static bool get debugMode {
    const override = bool.fromEnvironment('DEBUG_MODE');
    if (override) return true;
    return kDebugMode && !isProduction;
  }

  /// Request timeout in seconds
  static const int requestTimeout = 30;

  /// Enable analytics (enabled in production by default)
  static bool get analyticsEnabled {
    const override = bool.fromEnvironment('ANALYTICS_ENABLED');
    if (override) return true;
    return isProduction;
  }

  /// Validate that production builds use HTTPS
  static void validateConfiguration() {
    if (isProduction && !apiBaseUrl.startsWith('https://')) {
      throw StateError(
        'Production builds must use HTTPS. '
        'Configure API_BASE_URL with an https:// URL.',
      );
    }
  }
}
