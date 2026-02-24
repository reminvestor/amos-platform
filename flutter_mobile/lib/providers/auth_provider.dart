import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amos_mobile/config/env.dart';
import 'package:amos_mobile/models/user.dart';
import 'package:amos_mobile/services/auth_service.dart';
import 'package:amos_mobile/services/push_notification_service.dart';

// Auth state
class AuthState {
  final User? user;
  final bool isLoading;
  final String? error;
  final String? token;
  final bool mfaRequired;
  final String? mfaSessionToken;

  const AuthState({
    this.user,
    this.isLoading = false,
    this.error,
    this.token,
    this.mfaRequired = false,
    this.mfaSessionToken,
  });

  bool get isAuthenticated => user != null && token != null && !mfaRequired;

  AuthState copyWith({
    User? user,
    bool? isLoading,
    String? error,
    String? token,
    bool? mfaRequired,
    String? mfaSessionToken,
  }) {
    return AuthState(
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      token: token ?? this.token,
      mfaRequired: mfaRequired ?? this.mfaRequired,
      mfaSessionToken: mfaSessionToken ?? this.mfaSessionToken,
    );
  }

  AuthState clearMfa() {
    return AuthState(
      user: user,
      isLoading: isLoading,
      error: error,
      token: token,
      mfaRequired: false,
      mfaSessionToken: null,
    );
  }
}

// Auth notifier
class AuthNotifier extends Notifier<AuthState> {
  late final AuthService _authService;

  @override
  AuthState build() {
    _authService = ref.read(authServiceProvider);
    return const AuthState();
  }

  Future<void> login(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final result = await _authService.login(email, password);

      if (result.mfaRequired && result.mfaSessionToken != null) {
        // In development mode, auto-verify MFA to skip the verification screen
        if (Env.isDevelopment) {
          try {
            // Try to auto-verify MFA in dev mode (Rails backend should bypass for localhost)
            final mfaResult = await _authService.verifyMFACode(
              mfaSessionToken: result.mfaSessionToken!,
              code: '000000', // Dev bypass code
              useBackupCode: false,
            );
            state = AuthState(
              user: mfaResult.user,
              token: mfaResult.token,
              isLoading: false,
            );
            // Register device for push notifications
            _registerForPushNotifications();
            return;
          } catch (_) {
            // If auto-verify fails, fall through to normal MFA flow
          }
        }

        // MFA is required - update state to show MFA screen
        state = state.copyWith(
          isLoading: false,
          mfaRequired: true,
          mfaSessionToken: result.mfaSessionToken,
          error: null,
        );
      } else if (result.authResult != null) {
        // Login successful without MFA
        state = AuthState(
          user: result.authResult!.user,
          token: result.authResult!.token,
          isLoading: false,
        );
        // Register device for push notifications
        _registerForPushNotifications();
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> verifyMFA(String code, {bool useBackupCode = false}) async {
    if (state.mfaSessionToken == null) {
      state = state.copyWith(
        isLoading: false,
        error: 'No MFA session found',
      );
      return;
    }

    state = state.copyWith(isLoading: true, error: null);

    try {
      final result = await _authService.verifyMFACode(
        mfaSessionToken: state.mfaSessionToken!,
        code: code,
        useBackupCode: useBackupCode,
      );

      state = AuthState(
        user: result.user,
        token: result.token,
        isLoading: false,
      );
      // Register device for push notifications
      _registerForPushNotifications();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Invalid verification code',
      );
    }
  }

  /// Login using a trusted device token (bypasses MFA)
  /// Returns the new rotated device token if successful, null if failed.
  /// SECURITY: Server rotates token on each use - caller MUST store the new token.
  Future<String?> loginWithDeviceToken(String email, String deviceToken) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final result = await _authService.loginWithDeviceToken(
        email: email,
        deviceToken: deviceToken,
      );

      if (result.authResult != null) {
        // Login successful with device token
        state = AuthState(
          user: result.authResult!.user,
          token: result.authResult!.token,
          isLoading: false,
        );
        // Register device for push notifications
        _registerForPushNotifications();
        // Return the rotated token for storage
        return result.newDeviceToken;
      }

      // Unexpected state
      state = state.copyWith(isLoading: false);
      return null;
    } catch (e) {
      // Device token was invalid/expired - don't show error, let caller handle
      state = state.copyWith(isLoading: false);
      return null;
    }
  }

  /// Register device for push notifications after successful auth
  Future<void> _registerForPushNotifications() async {
    try {
      final pushService = PushNotificationService();
      await pushService.initialize();
      await pushService.requestPermissions();
      await pushService.registerDeviceIfNeeded();
    } catch (e) {
      // Don't fail auth if push registration fails
    }
  }

  Future<void> resendMFACode() async {
    if (state.mfaSessionToken == null) return;

    try {
      await _authService.resendMFACode(state.mfaSessionToken!);
    } catch (e) {
      state = state.copyWith(error: 'Failed to resend code');
    }
  }

  void clearMFA() {
    state = state.clearMfa();
  }

  /// Clear loading state (used after splash screen timeout)
  void clearLoadingState() {
    if (state.isLoading) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> register({
    required String email,
    required String password,
    required String name,
    String? businessName,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final result = await _authService.register(
        email: email,
        password: password,
        name: name,
        businessName: businessName,
      );

      state = AuthState(
        user: result.user,
        token: result.token,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> deactivateAccount(String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final pushService = PushNotificationService();
      await pushService.unregisterDevice();

      await _authService.deactivateAccount(password);
      state = const AuthState();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
      rethrow;
    }
  }

  Future<void> permanentlyDeleteAccount(String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final pushService = PushNotificationService();
      await pushService.unregisterDevice();

      await _authService.permanentlyDeleteAccount(password);
      state = const AuthState();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
      rethrow;
    }
  }

  Future<void> logout() async {
    state = state.copyWith(isLoading: true);
    try {
      // Unregister device from push notifications
      final pushService = PushNotificationService();
      await pushService.unregisterDevice();

      await _authService.logout();
    } finally {
      state = const AuthState();
    }
  }

  Future<void> checkAuthStatus() async {
    state = state.copyWith(isLoading: true);

    try {
      final result = await _authService.checkAuth();
      if (result != null) {
        state = AuthState(
          user: result.user,
          token: result.token,
          isLoading: false,
        );
        // Register device for push notifications on app launch
        _registerForPushNotifications();
      } else {
        state = const AuthState();
      }
    } catch (e) {
      state = const AuthState();
    }
  }

  /// Refresh user data from the server (e.g., after MFA setup)
  Future<void> refreshUser() async {
    if (state.token == null) return;

    try {
      final result = await _authService.checkAuth();
      if (result != null) {
        state = state.copyWith(
          user: result.user,
          isLoading: false,
        );
      }
    } catch (e) {
      // Keep current state on error
    }
  }
}

// Providers
final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final authStateProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
