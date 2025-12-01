import 'package:flutter/foundation.dart' show kIsWeb;

/// Environment configuration
///
/// Update these values or use flutter_dotenv for environment variables
class Env {
  /// API base URL - automatically uses localhost for web, LAN IP for devices
  static String get apiBaseUrl {
    // Check for environment override first
    const envUrl = String.fromEnvironment('API_BASE_URL');
    if (envUrl.isNotEmpty) return envUrl;

    // Web runs in browser on same machine as Docker - use localhost
    if (kIsWeb) {
      return 'http://localhost:3000';
    }

    // Physical devices need LAN IP to reach the Mac running Docker
    return 'http://192.168.1.211:3000';
  }

  /// App name
  static const String appName = 'AMOS';

  /// App version
  static const String appVersion = '1.0.0';

  /// Enable debug logging
  static const bool debugMode = bool.fromEnvironment(
    'DEBUG_MODE',
    defaultValue: true,
  );

  /// Request timeout in seconds
  static const int requestTimeout = 30;

  /// Enable analytics
  static const bool analyticsEnabled = bool.fromEnvironment(
    'ANALYTICS_ENABLED',
    defaultValue: false,
  );
}
