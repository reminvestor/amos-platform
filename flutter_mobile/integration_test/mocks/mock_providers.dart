import 'package:amos_mobile/models/user.dart';
import 'package:amos_mobile/providers/auth_provider.dart';
import 'package:amos_mobile/providers/realtime_provider.dart';
import 'package:amos_mobile/services/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Mock user for screenshots
const mockUser = User(
  id: '1',
  email: 'demo@amoslabs.com',
  name: 'Demo User',
  entityId: '1',
  mfaEnabled: false,
);

/// Screenshot API token - use real token from dev environment
/// Set via: --dart-define=SCREENSHOT_TOKEN=your_token
const String _screenshotToken = String.fromEnvironment(
  'SCREENSHOT_TOKEN',
  defaultValue: 'mock_token_for_screenshots',
);

/// Pre-authenticated auth state for screenshots
final mockAuthState = AuthState(
  user: mockUser,
  token: _screenshotToken,
  isLoading: false,
  mfaRequired: false,
);

/// Mock AuthNotifier that starts in authenticated state
class MockAuthNotifier extends AuthNotifier {
  @override
  AuthState build() {
    // Set the mock token on ApiClient so API calls work
    ApiClient.instance.setAuthToken(mockAuthState.token);
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
