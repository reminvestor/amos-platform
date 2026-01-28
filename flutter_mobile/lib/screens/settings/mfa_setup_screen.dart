import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/providers/auth_provider.dart';
import 'package:amos_mobile/services/mfa_service.dart';

class MfaSetupScreen extends ConsumerStatefulWidget {
  const MfaSetupScreen({super.key});

  @override
  ConsumerState<MfaSetupScreen> createState() => _MfaSetupScreenState();
}

class _MfaSetupScreenState extends ConsumerState<MfaSetupScreen> {
  final MfaService _mfaService = MfaService();

  bool _isLoading = true;
  String? _error;
  MfaStatus? _status;

  // Setup flow state
  bool _isSettingUp = false;
  MfaSetupResponse? _setupData;
  final _codeController = TextEditingController();
  List<String>? _backupCodes;

  // Disable flow state
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final status = await _mfaService.getStatus();
      if (mounted) {
        setState(() {
          _status = status;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _startSetup() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final setupData = await _mfaService.enable();
      if (mounted) {
        setState(() {
          _setupData = setupData;
          _isSettingUp = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
        _showError('Failed to start MFA setup: $e');
      }
    }
  }

  Future<void> _confirmSetup() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      _showError('Please enter the verification code');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await _mfaService.confirm(code);
      if (mounted) {
        if (result.success) {
          setState(() {
            _backupCodes = result.backupCodes;
            _isLoading = false;
          });
        } else {
          setState(() => _isLoading = false);
          _showError(result.message);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showError('Verification failed: $e');
      }
    }
  }

  Future<void> _regenerateBackupCodes() async {
    final password = await _showPasswordDialog('Regenerate Backup Codes');
    if (password == null || password.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final result = await _mfaService.regenerateBackupCodes(password);
      if (mounted) {
        if (result.success) {
          setState(() {
            _backupCodes = result.backupCodes;
            _isLoading = false;
          });
        } else {
          setState(() => _isLoading = false);
          _showError(result.message);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showError('Failed to regenerate backup codes: $e');
      }
    }
  }

  Future<String?> _showPasswordDialog(String action) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(action),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password',
            hintText: 'Enter your password',
            prefixIcon: Icon(LucideIcons.lock),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _showSuccess('Copied to clipboard');
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  bool get _canLeave {
    // Can only leave if MFA is enabled
    final isEnabled = _status?.mfaEnabled ?? false;
    return isEnabled;
  }

  void _handleBackButton() {
    if (_backupCodes != null) {
      // If showing backup codes, confirm user has saved them
      _showSaveConfirmation();
    } else if (_isSettingUp) {
      setState(() {
        _isSettingUp = false;
        _setupData = null;
      });
    } else if (_canLeave) {
      context.pop();
    } else {
      // Can't leave - show message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must set up two-factor authentication to continue'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _canLeave,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_canLeave) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You must set up two-factor authentication to continue'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(LucideIcons.arrowLeft),
            onPressed: _handleBackButton,
          ),
          title: const Text('Two-Factor Authentication'),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null && !_isSettingUp
                ? _buildErrorState()
                : _backupCodes != null
                    ? _buildBackupCodesView()
                    : _isSettingUp
                        ? _buildSetupFlow()
                        : _buildStatusView(),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.circleAlert, size: 48, color: Colors.red.shade400),
          const SizedBox(height: 16),
          Text('Failed to load MFA status', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ElevatedButton(onPressed: _loadStatus, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildStatusView() {
    final isEnabled = _status?.mfaEnabled ?? false;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Required banner when MFA not enabled
          if (!isEnabled) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(LucideIcons.triangleAlert, color: Colors.orange.shade700, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Required Setup',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: Colors.orange.shade900,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Two-factor authentication is required to use the app. Please complete the setup below to continue.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.orange.shade800,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          // Status Card
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: isEnabled ? Colors.green.shade200 : context.borderColor,
              ),
            ),
            color: isEnabled ? Colors.green.shade50 : null,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isEnabled ? Colors.green.shade100 : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isEnabled ? LucideIcons.shieldCheck : LucideIcons.shield,
                      color: isEnabled ? Colors.green.shade700 : Colors.grey.shade600,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isEnabled ? 'Enabled' : 'Disabled',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: isEnabled ? Colors.green.shade700 : null,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isEnabled
                              ? 'Your account is protected with 2FA'
                              : 'Add an extra layer of security',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: context.textSecondary,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          if (isEnabled) ...[
            // Backup codes info
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: context.borderColor),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(LucideIcons.key, color: context.textSecondary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Backup Codes',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_status?.backupCodesRemaining ?? 0} codes remaining',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _regenerateBackupCodes,
                      icon: const Icon(LucideIcons.refreshCw, size: 16),
                      label: const Text('Regenerate Codes'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Required notice
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.info, size: 18, color: context.textSecondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Two-factor authentication is required for all accounts and cannot be disabled.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: context.textSecondary,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            // Required notice
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(LucideIcons.triangleAlert, size: 20, color: Colors.orange.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Setup Required',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: Colors.orange.shade700,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Two-factor authentication is required for your account security.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.orange.shade700,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Info about 2FA
            Text(
              'How it works',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            _InfoRow(
              icon: LucideIcons.smartphone,
              text: 'Use any authenticator app like Google Authenticator or Authy',
            ),
            const SizedBox(height: 8),
            _InfoRow(
              icon: LucideIcons.lock,
              text: 'Enter a 6-digit code from your app each time you log in',
            ),
            const SizedBox(height: 8),
            _InfoRow(
              icon: LucideIcons.key,
              text: 'Get backup codes for emergency access',
            ),
            const SizedBox(height: 24),

            // Enable button
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _startSetup,
                icon: const Icon(LucideIcons.shieldPlus, size: 18),
                label: const Text('Set Up Two-Factor Authentication'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openInAuthenticator() async {
    final uri = _setupData?.otpUri;
    if (uri == null || uri.isEmpty) return;

    try {
      final url = Uri.parse(uri);
      final launched = await launchUrl(
        url,
        mode: LaunchMode.externalApplication,
      );

      if (!launched && mounted) {
        // If no authenticator app handles the URL, show manual entry
        _showError('No authenticator app found. Please enter the key manually.');
      }
    } catch (e) {
      if (mounted) {
        _showError('Could not open authenticator app. Please enter the key manually.');
      }
    }
  }

  Widget _buildSetupFlow() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step 1: Add to authenticator
          Text(
            'Step 1: Add to Authenticator App',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add your account to an authenticator app like Google Authenticator, Authy, or Microsoft Authenticator.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.textSecondary,
                ),
          ),
          const SizedBox(height: 20),

          // Primary: Open in Authenticator button
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _openInAuthenticator,
              icon: const Icon(LucideIcons.externalLink, size: 18),
              label: const Text('Open in Authenticator App'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Info about automatic setup
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.info, size: 18, color: Colors.green.shade700),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'This will automatically add your account to your installed authenticator app.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.green.shade700,
                        ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Divider with "OR"
          Row(
            children: [
              Expanded(child: Divider(color: context.borderColor)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'OR',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.textSecondary,
                      ),
                ),
              ),
              Expanded(child: Divider(color: context.borderColor)),
            ],
          ),
          const SizedBox(height: 24),

          // Secondary: QR Code (for scanning from another device)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              leading: Icon(LucideIcons.qrCode, size: 20, color: context.textSecondary),
              title: Text(
                'Scan QR code from another device',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
              ),
              children: [
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: context.borderColor),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text(
                          'If you have an authenticator on another device, scan this QR code:',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: context.textSecondary,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        if (_setupData?.otpUri.isNotEmpty == true)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: QrImageView(
                              data: _setupData!.otpUri,
                              version: QrVersions.auto,
                              size: 180,
                              backgroundColor: Colors.white,
                              errorCorrectionLevel: QrErrorCorrectLevel.M,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Tertiary: Manual entry option
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              leading: Icon(LucideIcons.keyboard, size: 20, color: context.textSecondary),
              title: Text(
                'Enter secret key manually',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
              ),
              children: [
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: context.borderColor),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Secret Key',
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                color: context.textSecondary,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: context.surfaceColor,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: context.borderColor),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: SelectableText(
                                  _setupData?.secret ?? '',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontFamily: 'monospace',
                                        letterSpacing: 2,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ),
                              IconButton(
                                onPressed: () => _copyToClipboard(_setupData?.secret ?? ''),
                                icon: const Icon(LucideIcons.copy, size: 20),
                                tooltip: 'Copy',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _copyToClipboard(_setupData?.secret ?? ''),
                            icon: const Icon(LucideIcons.copy, size: 16),
                            label: const Text('Copy Secret Key'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(LucideIcons.lightbulb, size: 16, color: Colors.blue.shade700),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'In your authenticator app, tap "+" then "Enter key manually"',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Colors.blue.shade700,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Step 2: Verify
          Text(
            'Step 2: Enter Verification Code',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Enter the 6-digit code from your authenticator app to confirm setup.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.textSecondary,
                ),
          ),
          const SizedBox(height: 16),

          // Verification code input
          Center(
            child: SizedBox(
              width: 200,
              child: TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      letterSpacing: 8,
                    ),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '000000',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Verify button
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _confirmSetup,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Verify and Enable'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackupCodesView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Success message
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.circleCheck, color: Colors.green.shade700),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Two-factor authentication is now enabled!',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Backup codes header
          Text(
            'Save Your Backup Codes',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Store these codes in a safe place. You can use them to access your account if you lose your authenticator.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.textSecondary,
                ),
          ),
          const SizedBox(height: 16),

          // Backup codes grid
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: context.borderColor),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: (_backupCodes ?? []).map((code) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: context.surfaceColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: context.borderColor),
                        ),
                        child: Text(
                          code,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => _copyToClipboard((_backupCodes ?? []).join('\n')),
                    icon: const Icon(LucideIcons.copy, size: 16),
                    label: const Text('Copy All Codes'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Warning
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.triangleAlert, color: Colors.orange.shade700, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Each backup code can only be used once. Keep them secure and don\'t share them.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.orange.shade700,
                        ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Done button
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () async {
                setState(() {
                  _backupCodes = null;
                  _isSettingUp = false;
                  _setupData = null;
                });
                await _loadStatus();
                // Refresh auth state so router knows MFA is now enabled
                if (mounted) {
                  await ref.read(authStateProvider.notifier).refreshUser();
                  // Navigate to home now that MFA is set up
                  if (mounted) {
                    context.go('/');
                  }
                }
              },
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('I\'ve Saved My Codes'),
            ),
          ),
        ],
      ),
    );
  }

  void _showSaveConfirmation() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Have you saved your codes?'),
        content: const Text(
          'Make sure you\'ve saved your backup codes before leaving. You won\'t be able to see them again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Go Back'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              setState(() {
                _backupCodes = null;
                _isSettingUp = false;
                _setupData = null;
              });
              await _loadStatus();
              // Refresh auth state so router knows MFA is now enabled
              if (mounted) {
                await ref.read(authStateProvider.notifier).refreshUser();
                if (mounted) {
                  context.go('/');
                }
              }
            },
            child: const Text('Yes, Continue'),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: context.primaryColor),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
