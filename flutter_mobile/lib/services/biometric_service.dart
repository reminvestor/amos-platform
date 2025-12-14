import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:io' show Platform;

class BiometricService {
  final LocalAuthentication _localAuth = LocalAuthentication();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const _biometricEnabledKey = 'biometric_enabled';
  static const _biometricEmailKey = 'biometric_email';
  static const _biometricPasswordKey = 'biometric_password';

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
}

class BiometricCredentials {
  final String email;
  final String password;

  BiometricCredentials({
    required this.email,
    required this.password,
  });
}
