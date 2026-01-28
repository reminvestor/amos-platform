import 'package:amos_mobile/models/user.dart';
import 'package:amos_mobile/providers/auth_provider.dart';
import 'package:amos_mobile/providers/realtime_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Mock user for screenshots
const mockUser = User(
  id: '1',
  email: 'demo@amoslabs.com',
  name: 'Demo User',
  entityId: '1',
  mfaEnabled: false,
);

/// Pre-authenticated auth state for screenshots
const mockAuthState = AuthState(
  user: mockUser,
  token: 'mock_token_for_screenshots',
  isLoading: false,
  mfaRequired: false,
);

/// Mock AuthNotifier that starts in authenticated state
class MockAuthNotifier extends AuthNotifier {
  @override
  AuthState build() {
    // Don't call super.build() - just return authenticated state
    return mockAuthState;
  }

  // Override methods to prevent actual API calls
  @override
  Future<void> login(String email, String password) async {
    state = mockAuthState;
  }

  @override
  Future<void> logout() async {
    // Don't actually logout during screenshots
  }

  @override
  Future<void> checkAuthStatus() async {
    state = mockAuthState;
  }

  @override
  void clearLoadingState() {
    if (state.isLoading) {
      state = state.copyWith(isLoading: false);
    }
  }
}

/// Mock RealtimeNotifier that doesn't connect to network
class MockRealtimeNotifier extends RealtimeNotifier {
  @override
  RealtimeState build() {
    // Return disconnected state - don't try to connect or initialize
    return const RealtimeState(isConnected: false);
  }

  @override
  Future<void> connect() async {
    // No-op - don't connect during screenshots
  }

  @override
  void disconnect() {
    // No-op
  }
}

/// Provider overrides for screenshot testing
final screenshotProviderOverrides = [
  authStateProvider.overrideWith(MockAuthNotifier.new),
  realtimeProvider.overrideWith(MockRealtimeNotifier.new),
];
