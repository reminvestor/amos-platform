import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_jailbreak_detection/flutter_jailbreak_detection.dart';
import 'package:safe_device/safe_device.dart';
import 'package:amos_mobile/utils/logger.dart';

/// Banking-level security service for the AMOS mobile app.
///
/// This service provides:
/// - Jailbreak/root detection
/// - Debugger detection
/// - Emulator detection
/// - Real device verification
/// - Security policy enforcement
class SecurityService {
  static final SecurityService _instance = SecurityService._internal();
  factory SecurityService() => _instance;
  SecurityService._internal();

  static SecurityService get instance => _instance;

  // Cached security status
  SecurityStatus? _cachedStatus;
  DateTime? _lastCheck;
  static const _cacheValidDuration = Duration(minutes: 5);

  /// Check all security conditions.
  /// Returns a SecurityStatus object with detailed results.
  Future<SecurityStatus> checkSecurity() async {
    // Return cached status if still valid
    if (_cachedStatus != null &&
        _lastCheck != null &&
        DateTime.now().difference(_lastCheck!) < _cacheValidDuration) {
      return _cachedStatus!;
    }

    AppLogger.info('🔐 Running security checks...');

    bool isJailbroken = false;
    bool isRooted = false;
    bool isOnRealDevice = true;
    bool isDebugging = false;
    bool isEmulator = false;
    bool canMockLocation = false;

    try {
      // Jailbreak detection (iOS)
      if (Platform.isIOS) {
        isJailbroken = await FlutterJailbreakDetection.jailbroken;
        if (isJailbroken) {
          AppLogger.warning('⚠️ SECURITY: Jailbroken device detected');
        }
      }

      // Root detection (Android)
      if (Platform.isAndroid) {
        // FlutterJailbreakDetection also detects root on Android
        isRooted = await FlutterJailbreakDetection.jailbroken;
        if (isRooted) {
          AppLogger.warning('⚠️ SECURITY: Rooted device detected');
        }
      }

      // Developer mode check
      isDebugging = await FlutterJailbreakDetection.developerMode;
      if (isDebugging) {
        AppLogger.debug('Developer mode enabled');
      }
    } catch (e) {
      AppLogger.error('Jailbreak detection failed', error: e);
    }

    try {
      // SafeDevice provides additional checks
      isOnRealDevice = await SafeDevice.isRealDevice;
      isEmulator = !isOnRealDevice;
      canMockLocation = await SafeDevice.isMockLocation;

      if (isEmulator) {
        AppLogger.debug('Running on emulator/simulator');
      }
      if (canMockLocation) {
        AppLogger.warning('⚠️ SECURITY: Mock location detected');
      }
    } catch (e) {
      AppLogger.error('SafeDevice checks failed', error: e);
      // Default to safe values on error
      isOnRealDevice = true;
      isEmulator = false;
    }

    final status = SecurityStatus(
      isJailbroken: isJailbroken,
      isRooted: isRooted,
      isEmulator: isEmulator,
      isDebugging: isDebugging,
      isOnRealDevice: isOnRealDevice,
      canMockLocation: canMockLocation,
    );

    // Cache the result
    _cachedStatus = status;
    _lastCheck = DateTime.now();

    AppLogger.info('🔐 Security check complete: ${status.summary}');

    return status;
  }

  /// Quick check if the device is compromised (jailbroken/rooted).
  Future<bool> isDeviceCompromised() async {
    final status = await checkSecurity();
    return status.isCompromised;
  }

  /// Check if biometric login should be allowed.
  /// For banking-level security, we block on compromised devices.
  Future<BiometricSecurityDecision> shouldAllowBiometric() async {
    final status = await checkSecurity();

    // In debug mode (development), allow everything but warn
    if (kDebugMode) {
      if (status.isCompromised) {
        AppLogger.warning('⚠️ DEV MODE: Allowing biometric on compromised device');
      }
      return BiometricSecurityDecision(
        allowed: true,
        reason: 'Development mode - security checks bypassed',
        status: status,
      );
    }

    // Production: Block on compromised devices
    if (status.isJailbroken) {
      return BiometricSecurityDecision(
        allowed: false,
        reason: 'Biometric login is disabled on jailbroken devices for security.',
        status: status,
      );
    }

    if (status.isRooted) {
      return BiometricSecurityDecision(
        allowed: false,
        reason: 'Biometric login is disabled on rooted devices for security.',
        status: status,
      );
    }

    // Allow on real devices
    return BiometricSecurityDecision(
      allowed: true,
      reason: 'Device passed security checks',
      status: status,
    );
  }

  /// Clear cached security status (call when app resumes).
  void clearCache() {
    _cachedStatus = null;
    _lastCheck = null;
  }
}

/// Result of security checks.
class SecurityStatus {
  final bool isJailbroken;
  final bool isRooted;
  final bool isEmulator;
  final bool isDebugging;
  final bool isOnRealDevice;
  final bool canMockLocation;

  const SecurityStatus({
    required this.isJailbroken,
    required this.isRooted,
    required this.isEmulator,
    required this.isDebugging,
    required this.isOnRealDevice,
    required this.canMockLocation,
  });

  /// True if device is jailbroken or rooted.
  bool get isCompromised => isJailbroken || isRooted;

  /// Human-readable summary.
  String get summary {
    final issues = <String>[];
    if (isJailbroken) issues.add('jailbroken');
    if (isRooted) issues.add('rooted');
    if (isEmulator) issues.add('emulator');
    if (isDebugging) issues.add('debug mode');
    if (canMockLocation) issues.add('mock location');

    if (issues.isEmpty) {
      return 'secure';
    }
    return issues.join(', ');
  }
}

/// Decision about whether to allow biometric login.
class BiometricSecurityDecision {
  final bool allowed;
  final String reason;
  final SecurityStatus status;

  const BiometricSecurityDecision({
    required this.allowed,
    required this.reason,
    required this.status,
  });
}
