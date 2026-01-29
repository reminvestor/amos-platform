import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io' show Platform;

class BiometricService {
  final LocalAuthentication _localAuth = LocalAuthentication();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  // Legacy keys for email/password storage (kept for migration)
  static const _biometricEnabledKey = 'biometric_enabled';
  static const _biometricEmailKey = 'biometric_email';
  static const _biometricPasswordKey = 'biometric_password';

  // New keys for trusted device token storage
  static const _deviceTokenKey = 'trusted_device_token';
  static const _deviceTokenEmailKey = 'trusted_device_email';

  /// Check if device supports biometric authentication
  Future<bool> isDeviceSupported() async {
    try {
      return await _localAuth.isDeviceSupported();
    } catch (e) {
      return false;
    }
  }

  /// Check if biometric authentication is available (hardware + enrolled)
  Future<bool> isBiometricAvailable() async {
    try {
      final isSupported = await _localAuth.isDeviceSupported();
      if (!isSupported) return false;

      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      return canCheckBiometrics;
    } catch (e) {
      return false;
    }
  }

  /// Get list of available biometric types
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      return [];
    }
  }

  /// Get user-friendly name for biometric type
  Future<String> getBiometricTypeName() async {
    final biometrics = await getAvailableBiometrics();

    if (biometrics.contains(BiometricType.face)) {
      return 'Face ID';
    } else if (biometrics.contains(BiometricType.fingerprint)) {
      return Platform.isIOS ? 'Touch ID' : 'Fingerprint';
    } else if (biometrics.contains(BiometricType.iris)) {
      return 'Iris';
    } else if (biometrics.contains(BiometricType.strong)) {
      return 'Biometric';
    }

    return 'Biometric';
  }

  /// Authenticate using biometrics
  Future<bool> authenticate({String? reason}) async {
    try {
      final isAvailable = await isBiometricAvailable();
      if (!isAvailable) return false;

      return await _localAuth.authenticate(
        localizedReason: reason ?? 'Authenticate to access AMOS',
        biometricOnly: false,
      );
    } catch (e) {
      return false;
    }
  }

  /// Check if biometric login is enabled
  Future<bool> isBiometricLoginEnabled() async {
    final enabled = await _storage.read(key: _biometricEnabledKey);
    return enabled == 'true';
  }

  /// Enable biometric login and store credentials
  Future<void> enableBiometricLogin({
    required String email,
    required String password,
  }) async {
    await _storage.write(key: _biometricEnabledKey, value: 'true');
    await _storage.write(key: _biometricEmailKey, value: email);
    await _storage.write(key: _biometricPasswordKey, value: password);
  }

  /// Disable biometric login and clear stored credentials
  Future<void> disableBiometricLogin() async {
    await _storage.delete(key: _biometricEnabledKey);
    await _storage.delete(key: _biometricEmailKey);
    await _storage.delete(key: _biometricPasswordKey);
  }

  /// Get stored biometric credentials
  Future<BiometricCredentials?> getStoredCredentials() async {
    final enabled = await isBiometricLoginEnabled();
    if (!enabled) return null;

    final email = await _storage.read(key: _biometricEmailKey);
    final password = await _storage.read(key: _biometricPasswordKey);

    if (email == null || password == null) return null;

    return BiometricCredentials(email: email, password: password);
  }

  /// Authenticate and get stored credentials
  Future<BiometricCredentials?> authenticateAndGetCredentials() async {
    final authenticated = await authenticate(
      reason: 'Authenticate to sign in',
    );

    if (!authenticated) return null;

    return await getStoredCredentials();
  }

  // ============ Trusted Device Token Methods ============

  /// Store a trusted device token for Face ID/biometric MFA bypass
  Future<void> storeTrustedDeviceToken({
    required String token,
    required String email,
  }) async {
    await _storage.write(key: _deviceTokenKey, value: token);
    await _storage.write(key: _deviceTokenEmailKey, value: email);
    // Also mark biometric as enabled
    await _storage.write(key: _biometricEnabledKey, value: 'true');
  }

  /// Get the stored trusted device token
  Future<String?> getTrustedDeviceToken() async {
    return await _storage.read(key: _deviceTokenKey);
  }

  /// Get the email associated with the trusted device
  Future<String?> getTrustedDeviceEmail() async {
    return await _storage.read(key: _deviceTokenEmailKey);
  }

  /// Check if a trusted device token exists
  Future<bool> hasTrustedDeviceToken() async {
    final token = await _storage.read(key: _deviceTokenKey);
    return token != null && token.isNotEmpty;
  }

  /// Clear the trusted device token (when logging out or revoking trust)
  Future<void> clearTrustedDeviceToken() async {
    await _storage.delete(key: _deviceTokenKey);
    await _storage.delete(key: _deviceTokenEmailKey);
  }

  /// Authenticate with biometric and get device token for login
  Future<TrustedDeviceCredentials?> authenticateAndGetDeviceToken() async {
    final authenticated = await authenticate(
      reason: 'Use biometrics to sign in',
    );

    if (!authenticated) return null;

    final token = await getTrustedDeviceToken();
    final email = await getTrustedDeviceEmail();

    if (token == null || email == null) return null;

    return TrustedDeviceCredentials(
      email: email,
      deviceToken: token,
    );
  }

  /// Get device information for trust registration
  Future<DeviceIdentity> getDeviceIdentity() async {
    String deviceName = 'Unknown Device';
    String deviceIdentifier = '';
    String platform = Platform.isIOS ? 'ios' : 'android';

    try {
      if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        deviceName = '${iosInfo.name} (${iosInfo.model})';
        deviceIdentifier = iosInfo.identifierForVendor ?? '';
      } else if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        deviceName = '${androidInfo.brand} ${androidInfo.model}';
        deviceIdentifier = androidInfo.id;
      }
    } catch (e) {
      // Fallback to generic name
    }

    return DeviceIdentity(
      name: deviceName,
      identifier: deviceIdentifier,
      platform: platform,
    );
  }

  /// Clear all biometric data (both legacy credentials and device token)
  Future<void> clearAllBiometricData() async {
    await disableBiometricLogin();
    await clearTrustedDeviceToken();
  }
}

class BiometricCredentials {
  final String email;
  final String password;

  BiometricCredentials({
    required this.email,
    required this.password,
  });
}

class TrustedDeviceCredentials {
  final String email;
  final String deviceToken;

  TrustedDeviceCredentials({
    required this.email,
    required this.deviceToken,
  });
}

class DeviceIdentity {
  final String name;
  final String identifier;
  final String platform;

  DeviceIdentity({
    required this.name,
    required this.identifier,
    required this.platform,
  });
}
