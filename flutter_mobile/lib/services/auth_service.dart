import 'package:amos_mobile/models/user.dart';
import 'package:amos_mobile/services/api_client.dart';
import 'package:amos_mobile/services/storage_service.dart';

class AuthService {
  final ApiClient _api = ApiClient();
  final StorageService _storage = StorageService.instance;

  static const _tokenKey = 'auth_token';
  static const _userKey = 'user_data';

  Future<LoginResult> login(String email, String password) async {
    final response = await _api.post('/api/auth/login', data: {
      'email': email,
      'password': password,
    });

    // Check if MFA is required
    if (response['mfa_required'] == true) {
      return LoginResult(
        mfaRequired: true,
        mfaSessionToken: response['mfa_session_token'] as String,
      );
    }

    // Normal login without MFA
    final user = User.fromJson(response['user']);
    final token = (response['api_key'] ?? response['token']) as String;

    // ignore: avoid_print
    print('[Auth] Login successful, storing token (${token.length} chars)');
    await _storage.write(_tokenKey, token);
    await _storage.write(_userKey, user.id);
    // ignore: avoid_print
    print('[Auth] Token stored successfully');

    return LoginResult(
      authResult: AuthResult(user: user, token: token),
    );
  }

  Future<AuthResult> verifyMFACode({
    required String mfaSessionToken,
    required String code,
    bool useBackupCode = false,
  }) async {
    final response = await _api.post('/mfa/verify', data: {
      'mfa_session_token': mfaSessionToken,
      'code': code,
      'backup_code': useBackupCode,
    });

    final user = User.fromJson(response['user']);
    final token = (response['api_key'] ?? response['token']) as String;

    await _storage.write(_tokenKey, token);
    await _storage.write(_userKey, user.id);

    return AuthResult(user: user, token: token);
  }

  Future<void> resendMFACode(String mfaSessionToken) async {
    await _api.post('/mfa/resend_code', data: {
      'mfa_session_token': mfaSessionToken,
    });
  }

  Future<void> logout() async {
    try {
      await _api.post('/api/auth/logout');
    } finally {
      await _storage.delete(_tokenKey);
      await _storage.delete(_userKey);
    }
  }

  Future<AuthResult?> checkAuth() async {
    final token = await _storage.read(_tokenKey);
    if (token == null) return null;

    try {
      final response = await _api.get('/api/auth/me');
      final user = User.fromJson(response['user']);
      return AuthResult(user: user, token: token);
    } catch (e) {
      await _storage.delete(_tokenKey);
      await _storage.delete(_userKey);
      return null;
    }
  }

  Future<void> forgotPassword(String email) async {
    await _api.post('/api/auth/forgot-password', data: {'email': email});
  }
}
