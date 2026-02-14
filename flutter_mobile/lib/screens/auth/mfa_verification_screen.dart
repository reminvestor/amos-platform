import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:amos_mobile/providers/auth_provider.dart';
import 'package:amos_mobile/services/biometric_service.dart';
import 'package:amos_mobile/services/mfa_service.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class MFAVerificationScreen extends ConsumerStatefulWidget {
  const MFAVerificationScreen({super.key});

  @override
  ConsumerState<MFAVerificationScreen> createState() => _MFAVerificationScreenState();
}

class _MFAVerificationScreenState extends ConsumerState<MFAVerificationScreen> {
  final TextEditingController _otpController = TextEditingController();
  final BiometricService _biometricService = BiometricService();
  final MfaService _mfaService = MfaService();
  bool _isLoading = false;
  bool _biometricAvailable = false;
  bool _hasTrustedDevice = false;
  bool _legacyBiometricEnabled = false;
  String _biometricTypeName = 'Biometric';

  @override
  void initState() {
    super.initState();
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
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
    }
  }

  Future<void> _handleBiometricVerify() async {
    setState(() => _isLoading = true);

    try {
      // Try to use trusted device token first
      final deviceCreds = await _biometricService.authenticateAndGetDeviceToken();
      if (deviceCreds != null) {
        // Clear MFA state and login with device token
        ref.read(authStateProvider.notifier).clearMFA();

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
          context.go('/chat');
          return;
        } else if (mounted) {
          // Device token was invalid/expired - clear it
          await _biometricService.clearTrustedDeviceToken();
          _showError('Device trust expired. Please enter the verification code.');
          setState(() {
            _hasTrustedDevice = false;
            _isLoading = false;
          });
        }
        return;
      }

      // Fallback to legacy credential-based biometric (if configured)
      final credentials = await _biometricService.authenticateAndGetCredentials();
      if (credentials == null) {
        _showError('$_biometricTypeName authentication failed');
        setState(() => _isLoading = false);
        return;
      }

      // Clear MFA state and start fresh login with stored credentials
      ref.read(authStateProvider.notifier).clearMFA();

      // Re-login with stored credentials
      await ref.read(authStateProvider.notifier).login(
        credentials.email,
        credentials.password,
      );

      // If still requires MFA after biometric login, show error
      // If authenticated without MFA, navigate to chat
      if (mounted) {
        final state = ref.read(authStateProvider);
        if (state.mfaRequired) {
          _showError('Please enter the verification code');
        } else if (state.isAuthenticated) {
          context.go('/chat');
        }
      }
    } catch (e) {
      _showError('$_biometricTypeName verification failed');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _verifyCode() async {
    if (_otpController.text.length != 6) {
      _showError('Please enter a 6-digit code');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await ref.read(authStateProvider.notifier).verifyMFA(_otpController.text);

      // Check if verification was successful
      if (mounted) {
        final state = ref.read(authStateProvider);
        if (state.isAuthenticated) {
          // Offer to trust this device for future biometric logins
          // (skips MFA on subsequent logins via Face ID/fingerprint)
          if (_biometricAvailable && !_hasTrustedDevice) {
            await _offerDeviceTrust();
          }
          // Navigate to chat after device trust flow completes (or is skipped)
          if (mounted) {
            context.go('/chat');
          }
        }
      }
    } catch (e) {
      _showError('Verification failed. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _offerDeviceTrust() async {
    final shouldTrust = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(LucideIcons.shieldCheck, color: Theme.of(context).primaryColor),
            const SizedBox(width: 12),
            const Expanded(child: Text('Trust This Device?')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Would you like to use $_biometricTypeName to sign in next time instead of entering a code?',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.info, size: 18, color: Colors.blue[700]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'You can manage trusted devices in Settings.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blue[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not Now'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(LucideIcons.scan, size: 18),
            label: Text('Enable $_biometricTypeName'),
          ),
        ],
      ),
    );

    if (shouldTrust == true && mounted) {
      await _trustDevice();
    }
  }

  Future<void> _trustDevice() async {
    try {
      // Authenticate with biometric first
      final authenticated = await _biometricService.authenticate(
        reason: 'Confirm $_biometricTypeName to enable quick sign-in',
      );

      if (!authenticated) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$_biometricTypeName authentication cancelled'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Get device info
      final deviceInfo = await _biometricService.getDeviceIdentity();

      // Request trust token from server
      final response = await _mfaService.trustDevice(
        deviceName: deviceInfo.name,
        deviceIdentifier: deviceInfo.identifier,
        platform: deviceInfo.platform,
      );

      if (response.success) {
        // Store the device token locally
        final authState = ref.read(authStateProvider);
        final email = authState.user?.email ?? '';

        await _biometricService.storeTrustedDeviceToken(
          token: response.deviceToken,
          email: email,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$_biometricTypeName enabled for quick sign-in'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          _showError('Failed to enable $_biometricTypeName');
        }
      }
    } catch (e) {
      if (mounted) {
        _showError('Failed to enable $_biometricTypeName');
      }
    }
  }

  Future<void> _resendCode() async {
    try {
      await ref.read(authStateProvider.notifier).resendMFACode();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Code sent successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _showError('Failed to resend code');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _cancel() {
    ref.read(authStateProvider.notifier).clearMFA();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Two-Factor Authentication'),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: _cancel,
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),

              // Lock icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.shield,
                  size: 40,
                  color: Theme.of(context).primaryColor,
                ),
              ),

              const SizedBox(height: 24),

              // Title and description
              Text(
                'Enter Verification Code',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 12),

              Text(
                'Enter the 6-digit code from your authenticator app',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 48),

              // OTP Input
              PinCodeTextField(
                appContext: context,
                length: 6,
                controller: _otpController,
                autoFocus: true,
                keyboardType: TextInputType.number,
                animationType: AnimationType.fade,
                pinTheme: PinTheme(
                  shape: PinCodeFieldShape.box,
                  borderRadius: BorderRadius.circular(8),
                  fieldHeight: 56,
                  fieldWidth: 48,
                  activeFillColor: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey[800]
                      : Colors.white,
                  inactiveFillColor: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey[900]
                      : Colors.grey[100],
                  selectedFillColor: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey[700]
                      : Colors.white,
                  activeColor: Theme.of(context).primaryColor,
                  inactiveColor: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey[600]!
                      : Colors.grey[300]!,
                  selectedColor: Theme.of(context).primaryColor,
                  errorBorderColor: Colors.red,
                ),
                textStyle: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black,
                ),
                animationDuration: const Duration(milliseconds: 200),
                enableActiveFill: true,
                autoDisposeControllers: false,
                useHapticFeedback: true,
                hapticFeedbackTypes: HapticFeedbackTypes.light,
                onCompleted: (code) {
                  _verifyCode();
                },
                onChanged: (value) {
                  // Trigger rebuild to show pasted values
                  setState(() {});
                },
                beforeTextPaste: (text) {
                  // Allow paste of 6-digit codes
                  return text != null && RegExp(r'^\d{6}$').hasMatch(text.trim());
                },
              ),

              if (authState.error != null) ...[
                const SizedBox(height: 16),
                Text(
                  authState.error!,
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],

              const SizedBox(height: 32),

              // Verify button
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _verifyCode,
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Verify',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),

              // Biometric alternative (show if device is trusted or legacy biometric is enabled)
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
                  onPressed: _isLoading ? null : _handleBiometricVerify,
                  icon: const Icon(LucideIcons.scan, size: 18),
                  label: Text('Use $_biometricTypeName instead'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Resend code button
              TextButton.icon(
                onPressed: _isLoading ? null : _resendCode,
                icon: const Icon(LucideIcons.refreshCw, size: 18),
                label: const Text('Resend Code'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),

              const SizedBox(height: 16),

              // Help text
              Text(
                'Having trouble? Contact your administrator.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
