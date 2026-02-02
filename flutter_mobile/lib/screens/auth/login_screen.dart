import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/providers/auth_provider.dart';
import 'package:amos_mobile/services/biometric_service.dart';
import 'package:amos_mobile/utils/error_handler.dart';
import 'package:amos_mobile/utils/logger.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> with ErrorHandler {
  final _formKey = GlobalKey<FormState>();
  // Pre-fill demo credentials only in debug mode (not in production builds)
  final _emailController = TextEditingController(text: kDebugMode ? 'admin@demo.com' : '');
  final _passwordController = TextEditingController(text: kDebugMode ? 'password123' : '');
  bool _obscurePassword = true;

  final BiometricService _biometricService = BiometricService();
  bool _biometricAvailable = false;
  bool _hasTrustedDevice = false;
  bool _legacyBiometricEnabled = false;
  String _biometricTypeName = 'Biometric';

  @override
  void initState() {
    super.initState();
    AppLogger.debug('LoginScreen initialized');
    _checkBiometricAvailability();
  }

  Future<void> _autoTriggerBiometric() async {
    // Wait a moment for UI to settle
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted && (_hasTrustedDevice || _legacyBiometricEnabled)) {
      AppLogger.debug('Auto-triggering biometric authentication');
      _handleBiometricLogin();
    }
  }

  Future<void> _checkBiometricAvailability() async {
    final available = await _biometricService.isBiometricAvailable();
    final hasTrusted = await _biometricService.hasTrustedDeviceToken();
    final legacyEnabled = await _biometricService.isBiometricLoginEnabled();
    final typeName = await _biometricService.getBiometricTypeName();

    if (mounted) {
      setState(() {
        _biometricAvailable = available;
        _hasTrustedDevice = hasTrusted;
        _legacyBiometricEnabled = legacyEnabled;
        _biometricTypeName = typeName;
      });

      // Auto-trigger biometric if trusted device exists or legacy biometric enabled
      if (available && (hasTrusted || legacyEnabled)) {
        _autoTriggerBiometric();
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      AppLogger.debug('Login attempt for: ${_emailController.text.trim()}');

      await ref.read(authStateProvider.notifier).login(
            _emailController.text.trim(),
            _passwordController.text,
          );

      if (mounted) {
        final state = ref.read(authStateProvider);
        if (state.error != null) {
          showError(context, state.error);
        } else if (state.mfaRequired) {
          // Navigate to MFA verification screen
          AppLogger.info('MFA required, navigating to verification');
          context.pushNamed('mfa-verification');
        } else if (state.isAuthenticated) {
          AppLogger.info('Login successful');
          showSuccess(context, 'Welcome back!');
          // MFA setup is NOT enforced here - only required when adding integrations
          // (matching web behavior where require_two_factor! is only on oauth_controller)
          // Offer legacy biometric only if no trusted device (device trust is set up via MFA flow)
          if (_biometricAvailable && !_hasTrustedDevice && !_legacyBiometricEnabled) {
            _offerBiometricSetup();
          }
          context.go('/chat');
        }
      }
    } catch (e, stackTrace) {
      AppLogger.error('Login failed', error: e, stackTrace: stackTrace);
      if (mounted) {
        showError(context, e, fallbackMessage: 'Login failed. Please try again.');
      }
    }
  }

  Future<void> _handleBiometricLogin() async {
    try {
      // Try trusted device token first (bypasses MFA entirely)
      if (_hasTrustedDevice) {
        final deviceCreds = await _biometricService.authenticateAndGetDeviceToken();
        if (deviceCreds != null) {
          AppLogger.debug('Biometric login with trusted device token');

          // SECURITY: Server rotates token on each use - we get the new token back
          final newDeviceToken = await ref.read(authStateProvider.notifier).loginWithDeviceToken(
                deviceCreds.email,
                deviceCreds.deviceToken,
              );

          if (newDeviceToken != null && mounted) {
            // SECURITY: Store the rotated token for next login
            await _biometricService.storeTrustedDeviceToken(
              token: newDeviceToken,
              email: deviceCreds.email,
            );
            AppLogger.info('Trusted device login successful, token rotated');
            showSuccess(context, 'Welcome back!');
            context.go('/chat');
            return;
          } else if (mounted) {
            // Device token was invalid/expired - clear it and fall back
            await _biometricService.clearTrustedDeviceToken();
            setState(() => _hasTrustedDevice = false);
            AppLogger.info('Device trust expired, falling back to normal login');
          }
        }
      }

      // Fallback to legacy credential-based biometric
      final credentials = await _biometricService.authenticateAndGetCredentials();

      if (credentials == null) {
        if (mounted) {
          showError(context, 'Biometric authentication failed');
        }
        return;
      }

      AppLogger.debug('Biometric login attempt with stored credentials');

      await ref.read(authStateProvider.notifier).login(
            credentials.email,
            credentials.password,
          );

      if (mounted) {
        final state = ref.read(authStateProvider);
        if (state.error != null) {
          showError(context, state.error);
        } else if (state.mfaRequired) {
          AppLogger.info('MFA required after biometric login');
          context.pushNamed('mfa-verification');
        } else if (state.isAuthenticated) {
          AppLogger.info('Biometric login successful');
          // MFA setup is NOT enforced here - only required when adding integrations
          showSuccess(context, 'Welcome back!');
          context.go('/chat');
        }
      }
    } catch (e, stackTrace) {
      AppLogger.error('Biometric login failed', error: e, stackTrace: stackTrace);
      if (mounted) {
        showError(context, e, fallbackMessage: 'Biometric login failed.');
      }
    }
  }

  Future<void> _offerBiometricSetup() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Enable $_biometricTypeName'),
        content: Text(
          'Would you like to enable $_biometricTypeName login for faster access?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not Now'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Enable'),
          ),
        ],
      ),
    );

    if (result == true) {
      try {
        await _biometricService.enableBiometricLogin(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        setState(() => _legacyBiometricEnabled = true);
        if (mounted) {
          showSuccess(context, '$_biometricTypeName enabled!');
        }
      } catch (e) {
        if (mounted) {
          showError(context, 'Failed to enable $_biometricTypeName');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 60),

                // Logo
                Center(
                  child: Image.asset(
                    'assets/images/logo-header.png',
                    height: 40,
                    color: Theme.of(context).brightness == Brightness.light
                        ? const Color(0xFF1a1a2e)
                        : null,
                  ),
                ),
                const SizedBox(height: 48),

                // Email Field
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(LucideIcons.mail),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your email';
                    }
                    if (!value.contains('@')) {
                      return 'Please enter a valid email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Password Field
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _handleLogin(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(LucideIcons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? LucideIcons.eyeOff : LucideIcons.eye,
                      ),
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your password';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),

                // Forgot Password
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => context.pushNamed('forgot-password'),
                    child: const Text('Forgot Password?'),
                  ),
                ),
                const SizedBox(height: 24),

                // Login Button
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: authState.isLoading ? null : _handleLogin,
                    child: authState.isLoading
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Sign In',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),

                // Biometric Login Button (show if trusted device or legacy biometric)
                if (_biometricAvailable && (_hasTrustedDevice || _legacyBiometricEnabled)) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'OR',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: context.textSecondary,
                              ),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: authState.isLoading ? null : _handleBiometricLogin,
                    icon: const Icon(LucideIcons.scan),
                    label: Text('Sign in with $_biometricTypeName'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Create Account Link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Don't have an account? ",
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: context.textSecondary,
                          ),
                    ),
                    TextButton(
                      onPressed: () => context.pushNamed('signup'),
                      child: const Text('Create Account'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
