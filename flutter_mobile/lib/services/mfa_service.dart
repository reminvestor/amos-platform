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
