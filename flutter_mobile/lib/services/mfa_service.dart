import 'package:amos_mobile/services/api_client.dart';
import 'package:amos_mobile/utils/logger.dart';

class MfaService {
  final ApiClient _api = ApiClient.instance;

  /// Get current MFA status
  Future<MfaStatus> getStatus() async {
    try {
      final response = await _api.get('/api/mfa/status');
      return MfaStatus.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to get MFA status', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Start MFA setup - returns secret and OTP URI for QR code
  Future<MfaSetupResponse> enable() async {
    try {
      final response = await _api.post('/api/mfa/enable');
      return MfaSetupResponse.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to enable MFA', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Confirm MFA setup with verification code
  Future<MfaConfirmResponse> confirm(String code) async {
    try {
      final response = await _api.post('/api/mfa/confirm', data: {'code': code});
      return MfaConfirmResponse.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to confirm MFA', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Disable MFA (requires password)
  Future<MfaResponse> disable(String password) async {
    try {
      final response = await _api.delete('/api/mfa/disable', data: {'password': password});
      return MfaResponse.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to disable MFA', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Regenerate backup codes (requires password)
  Future<MfaConfirmResponse> regenerateBackupCodes(String password) async {
    try {
      final response = await _api.post('/api/mfa/regenerate_backup_codes', data: {'password': password});
      return MfaConfirmResponse.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to regenerate backup codes', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // ============ Trusted Device Methods ============

  /// Trust this device for Face ID/biometric MFA bypass
  Future<TrustDeviceResponse> trustDevice({
    required String deviceName,
    required String deviceIdentifier,
    required String platform,
  }) async {
    try {
      final response = await _api.post('/api/mfa/trust_device', data: {
        'device_name': deviceName,
        'device_identifier': deviceIdentifier,
        'platform': platform,
      });
      return TrustDeviceResponse.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to trust device', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Get list of trusted devices
  Future<List<TrustedDevice>> getTrustedDevices() async {
    try {
      final response = await _api.get('/api/mfa/trusted_devices');
      final devices = (response['trusted_devices'] as List<dynamic>?) ?? [];
      return devices.map((d) => TrustedDevice.fromJson(d)).toList();
    } catch (e, stackTrace) {
      AppLogger.error('Failed to get trusted devices', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Revoke a specific trusted device
  Future<MfaResponse> revokeTrustedDevice(int deviceId) async {
    try {
      final response = await _api.delete('/api/mfa/trusted_devices/$deviceId');
      return MfaResponse.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to revoke trusted device', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Revoke all trusted devices
  Future<MfaResponse> revokeAllTrustedDevices() async {
    try {
      final response = await _api.delete('/api/mfa/trusted_devices');
      return MfaResponse.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('Failed to revoke all trusted devices', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }
}

class MfaStatus {
  final bool mfaEnabled;
  final int backupCodesRemaining;
  final bool emailOtpEnabled;

  MfaStatus({
    required this.mfaEnabled,
    required this.backupCodesRemaining,
    required this.emailOtpEnabled,
  });

  factory MfaStatus.fromJson(Map<String, dynamic> json) {
    return MfaStatus(
      mfaEnabled: json['mfa_enabled'] ?? false,
      backupCodesRemaining: json['backup_codes_remaining'] ?? 0,
      emailOtpEnabled: json['email_otp_enabled'] ?? false,
    );
  }
}

class MfaSetupResponse {
  final String secret;
  final String otpUri;
  final String message;

  MfaSetupResponse({
    required this.secret,
    required this.otpUri,
    required this.message,
  });

  factory MfaSetupResponse.fromJson(Map<String, dynamic> json) {
    return MfaSetupResponse(
      secret: json['secret'] ?? '',
      otpUri: json['otp_uri'] ?? '',
      message: json['message'] ?? '',
    );
  }
}

class MfaConfirmResponse {
  final bool success;
  final String message;
  final List<String> backupCodes;

  MfaConfirmResponse({
    required this.success,
    required this.message,
    required this.backupCodes,
  });

  factory MfaConfirmResponse.fromJson(Map<String, dynamic> json) {
    return MfaConfirmResponse(
      success: json['success'] ?? false,
      message: json['message'] ?? '',
      backupCodes: (json['backup_codes'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList() ?? [],
    );
  }
}

class MfaResponse {
  final bool success;
  final String message;

  MfaResponse({
    required this.success,
    required this.message,
  });

  factory MfaResponse.fromJson(Map<String, dynamic> json) {
    return MfaResponse(
      success: json['success'] ?? false,
      message: json['message'] ?? '',
    );
  }
}

class TrustDeviceResponse {
  final bool success;
  final String deviceToken;
  final DateTime? expiresAt;
  final String message;

  TrustDeviceResponse({
    required this.success,
    required this.deviceToken,
    this.expiresAt,
    required this.message,
  });

  factory TrustDeviceResponse.fromJson(Map<String, dynamic> json) {
    return TrustDeviceResponse(
      success: json['success'] ?? false,
      deviceToken: json['device_token'] ?? '',
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'])
          : null,
      message: json['message'] ?? '',
    );
  }
}

class TrustedDevice {
  final int id;
  final String deviceName;
  final String platform;
  final DateTime? lastUsedAt;
  final DateTime? expiresAt;
  final DateTime createdAt;

  TrustedDevice({
    required this.id,
    required this.deviceName,
    required this.platform,
    this.lastUsedAt,
    this.expiresAt,
    required this.createdAt,
  });

  factory TrustedDevice.fromJson(Map<String, dynamic> json) {
    return TrustedDevice(
      id: json['id'] ?? 0,
      deviceName: json['device_name'] ?? 'Unknown Device',
      platform: json['platform'] ?? 'unknown',
      lastUsedAt: json['last_used_at'] != null
          ? DateTime.parse(json['last_used_at'])
          : null,
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'])
          : null,
      createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
    );
  }
}
