import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amos_mobile/models/user.dart';
import 'package:amos_mobile/services/auth_service.dart';

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
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Invalid verification code',
      );
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

  Future<void> logout() async {
    state = state.copyWith(isLoading: true);
    try {
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
      } else {
        state = const AuthState();
      }
    } catch (e) {
      state = const AuthState();
    }
  }
}

// Providers
final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final authStateProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
