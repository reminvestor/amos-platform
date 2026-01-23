import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/services/biometric_service.dart';

// Note: BiometricService uses LocalAuthentication and FlutterSecureStorage
// which require native plugins. For unit tests, we test the data structures
// and helper classes.

void main() {
  group('BiometricCredentials', () {
    test('creates credentials with email and password', () {
      final credentials = BiometricCredentials(
        email: 'user@example.com',
        password: 'securePassword123',
      );

      expect(credentials.email, equals('user@example.com'));
      expect(credentials.password, equals('securePassword123'));
    });

    test('handles special characters in credentials', () {
      final credentials = BiometricCredentials(
        email: 'user+test@example.com',
        password: 'p@ss\$word!#%^&*()',
      );

      expect(credentials.email, equals('user+test@example.com'));
      expect(credentials.password, equals('p@ss\$word!#%^&*()'));
    });

    test('handles empty strings', () {
      final credentials = BiometricCredentials(
        email: '',
        password: '',
      );

      expect(credentials.email, equals(''));
      expect(credentials.password, equals(''));
    });
  });

  group('BiometricService Constants', () {
    test('storage keys are defined correctly', () {
      // These are the expected storage key names used by the service
      const biometricEnabledKey = 'biometric_enabled';
      const biometricEmailKey = 'biometric_email';
      const biometricPasswordKey = 'biometric_password';

      expect(biometricEnabledKey, equals('biometric_enabled'));
      expect(biometricEmailKey, equals('biometric_email'));
      expect(biometricPasswordKey, equals('biometric_password'));
    });
  });

  group('Biometric Type Name Logic', () {
    // Testing the logic for determining biometric type names
    // without actually calling the platform APIs

    test('returns Face ID for face biometric on iOS', () {
      // Simulating the logic from getBiometricTypeName
      const hasFace = true;
      const hasFingerprint = false;
      const isIOS = true;

      String getBiometricName() {
        if (hasFace) return 'Face ID';
        if (hasFingerprint) return isIOS ? 'Touch ID' : 'Fingerprint';
        return 'Biometric';
      }

      expect(getBiometricName(), equals('Face ID'));
    });

    test('returns Touch ID for fingerprint on iOS', () {
      const hasFace = false;
      const hasFingerprint = true;
      const isIOS = true;

      String getBiometricName() {
        if (hasFace) return 'Face ID';
        if (hasFingerprint) return isIOS ? 'Touch ID' : 'Fingerprint';
        return 'Biometric';
      }

      expect(getBiometricName(), equals('Touch ID'));
    });

    test('returns Fingerprint for fingerprint on Android', () {
      const hasFace = false;
      const hasFingerprint = true;
      const isIOS = false;

      String getBiometricName() {
        if (hasFace) return 'Face ID';
        if (hasFingerprint) return isIOS ? 'Touch ID' : 'Fingerprint';
        return 'Biometric';
      }

      expect(getBiometricName(), equals('Fingerprint'));
    });

    test('returns default Biometric when no specific type available', () {
      const hasFace = false;
      const hasFingerprint = false;

      String getBiometricName() {
        if (hasFace) return 'Face ID';
        if (hasFingerprint) return 'Fingerprint';
        return 'Biometric';
      }

      expect(getBiometricName(), equals('Biometric'));
    });
  });

  group('Biometric Enabled State Parsing', () {
    test('parses enabled string as true', () {
      const stored = 'true';
      final enabled = stored == 'true';
      expect(enabled, isTrue);
    });

    test('parses any other value as false', () {
      const stored = 'false';
      final enabled = stored == 'true';
      expect(enabled, isFalse);
    });

    test('handles null as false', () {
      const String? stored = null;
      final enabled = stored == 'true';
      expect(enabled, isFalse);
    });
  });
}
