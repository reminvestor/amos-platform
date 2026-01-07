import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/services/api_client.dart';
import 'package:amos_mobile/utils/logger.dart';

class ApiKeysScreen extends ConsumerStatefulWidget {
  const ApiKeysScreen({super.key});

  @override
  ConsumerState<ApiKeysScreen> createState() => _ApiKeysScreenState();
}

class _ApiKeysScreenState extends ConsumerState<ApiKeysScreen> {
  String? _apiKey;
  bool _isLoading = true;
  bool _isRevealed = false;
  bool _isRegenerating = false;

  @override
  void initState() {
    super.initState();
    _loadApiKey();
  }

  Future<void> _loadApiKey() async {
    setState(() => _isLoading = true);
    try {
      final token = await ApiClient.instance.getAuthToken();
      setState(() {
        _apiKey = token;
        _isLoading = false;
      });
    } catch (e) {
      AppLogger.error('Failed to load API key', error: e);
      setState(() => _isLoading = false);
    }
  }

  Future<void> _regenerateApiKey() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Regenerate API Key?'),
        content: const Text(
          'This will invalidate your current API key. Any applications using the old key will need to be updated. You will be logged out and need to log in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Regenerate'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isRegenerating = true);
    try {
      final api = ApiClient();
      final response = await api.post('/api/auth/regenerate_api_key');

      if (response.statusCode == 200) {
        final newKey = response.data['api_key'] as String;

        // Update the stored token
        ApiClient.instance.setAuthToken(newKey);

        setState(() {
          _apiKey = newKey;
          _isRevealed = true; // Show the new key
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('API key regenerated successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      AppLogger.error('Failed to regenerate API key', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to regenerate: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRegenerating = false);
      }
    }
  }

  void _copyToClipboard() {
    if (_apiKey == null) return;

    Clipboard.setData(ClipboardData(text: _apiKey!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('API key copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  String _maskApiKey(String key) {
    if (key.length <= 8) return '••••••••';
    return '${key.substring(0, 4)}${'•' * (key.length - 8)}${key.substring(key.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: context.canPop()
            ? IconButton(
                icon: const Icon(LucideIcons.arrowLeft),
                onPressed: () => context.pop(),
              )
            : null,
        title: const Text('API Keys'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Info Card
                Card(
                  elevation: 0,
                  color: context.primaryColor.withValues(alpha: 0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          LucideIcons.info,
                          color: context.primaryColor,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Your API key is used to authenticate requests from external applications.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: context.primaryColor,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // API Key Section
                Text(
                  'Your API Key',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 12),

                // API Key Display
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: context.borderColor),
                    borderRadius: BorderRadius.circular(12),
                    color: Theme.of(context).cardColor,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _apiKey != null
                                  ? (_isRevealed ? _apiKey! : _maskApiKey(_apiKey!))
                                  : 'No API key available',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontFamily: 'monospace',
                                    letterSpacing: 1.2,
                                  ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              _isRevealed ? LucideIcons.eyeOff : LucideIcons.eye,
                              size: 20,
                            ),
                            onPressed: () {
                              setState(() => _isRevealed = !_isRevealed);
                            },
                            tooltip: _isRevealed ? 'Hide' : 'Reveal',
                          ),
                          IconButton(
                            icon: const Icon(LucideIcons.copy, size: 20),
                            onPressed: _apiKey != null ? _copyToClipboard : null,
                            tooltip: 'Copy',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Regenerate Button
                OutlinedButton.icon(
                  onPressed: _isRegenerating ? null : _regenerateApiKey,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                    side: const BorderSide(color: Colors.orange),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: _isRegenerating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(LucideIcons.refreshCw, size: 18),
                  label: Text(_isRegenerating ? 'Regenerating...' : 'Regenerate API Key'),
                ),
                const SizedBox(height: 16),

                // Warning
                Card(
                  elevation: 0,
                  color: Colors.orange.withValues(alpha: 0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          LucideIcons.triangleAlert,
                          color: Colors.orange.shade700,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Keep your API key secure. Never share it publicly or commit it to version control.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.orange.shade700,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Usage Examples Section
                Text(
                  'Usage',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: context.borderColor),
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.grey.shade900,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Authorization Header',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade400,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Authorization: Bearer <your-api-key>',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontFamily: 'monospace',
                              color: Colors.green.shade300,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
