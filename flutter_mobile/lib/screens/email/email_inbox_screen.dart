import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/services/connections_service.dart';
import 'package:amos_mobile/widgets/branded_app_bar.dart';

class EmailInboxScreen extends ConsumerStatefulWidget {
  const EmailInboxScreen({super.key});

  @override
  ConsumerState<EmailInboxScreen> createState() => _EmailInboxScreenState();
}

class _EmailInboxScreenState extends ConsumerState<EmailInboxScreen> {
  final ConnectionsService _connectionsService = ConnectionsService();
  EmailProviderStatus? _emailStatus;
  List<EmailProvider> _availableProviders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkEmailConnection();
  }

  Future<void> _checkEmailConnection() async {
    try {
      final status = await _connectionsService.getEmailProviderStatus();
      final providers = await _connectionsService.getAvailableEmailProviders();
      if (mounted) {
        setState(() {
          _emailStatus = status;
          _availableProviders = providers;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _connectProvider(String slug) async {
    try {
      setState(() => _isLoading = true);
      final oauthResponse = await _connectionsService.getOAuthUrl(slug);
      final url = Uri.parse(oauthResponse.url);

      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Complete sign-in for ${oauthResponse.integrationName} in your browser'),
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to connect: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _emailStatus?.isConnected ?? false;

    return Scaffold(
      appBar: const BrandedAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : isConnected
              ? _buildConnectedView()
              : _buildConnectPrompt(),
    );
  }

  Widget _buildConnectPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: context.primaryColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                LucideIcons.mail,
                size: 64,
                color: context.primaryColor,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Connect Your Email',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              'Connect your email to let Amos help you manage your inbox, summarize emails, and draft responses.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.textSecondary,
                  ),
            ),
            const SizedBox(height: 32),

            // Email provider options
            ..._availableProviders.map((provider) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _EmailProviderButton(
                provider: provider,
                onTap: () => _connectProvider(provider.slug),
              ),
            )),

            const SizedBox(height: 8),
            TextButton(
              onPressed: () => context.go('/chat'),
              child: Text(
                'Skip for now',
                style: TextStyle(color: context.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectedView() {
    final providerName = _emailStatus?.providerName ?? 'Email';
    final providerSlug = _emailStatus?.provider ?? 'email';

    // Provider-specific styling
    final (Color iconColor, IconData icon) = switch (providerSlug) {
      'gmail' => (Colors.red, Icons.email_outlined),
      'outlook' => (Colors.blue, LucideIcons.mail),
      _ => (context.primaryColor, LucideIcons.mail),
    };

    return RefreshIndicator(
      onRefresh: _checkEmailConnection,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Connected status card
          Card(
            elevation: 0,
            color: Colors.green.withValues(alpha: 0.1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: iconColor, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '$providerName Connected',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(LucideIcons.check, color: Colors.green, size: 18),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Amos can now help with your email',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
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

          // Quick actions
          Text(
            'Quick Actions',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),

          _QuickActionCard(
            icon: LucideIcons.sparkles,
            iconColor: Colors.purple,
            title: 'Summarize my inbox',
            description: 'Get a quick overview of your recent emails',
            onTap: () => _askAmos('Summarize my inbox and highlight anything important'),
          ),
          const SizedBox(height: 8),

          _QuickActionCard(
            icon: LucideIcons.circleAlert,
            iconColor: Colors.orange,
            title: 'What needs attention?',
            description: 'Find urgent or important emails',
            onTap: () => _askAmos('What emails in my inbox need my attention today?'),
          ),
          const SizedBox(height: 8),

          _QuickActionCard(
            icon: LucideIcons.search,
            iconColor: Colors.blue,
            title: 'Search emails',
            description: 'Find specific emails or conversations',
            onTap: () => _askAmos('Help me search my emails for '),
          ),
          const SizedBox(height: 8),

          _QuickActionCard(
            icon: LucideIcons.penLine,
            iconColor: Colors.green,
            title: 'Draft a reply',
            description: 'Get help writing email responses',
            onTap: () => _askAmos('Help me draft a reply to my most recent email'),
          ),
        ],
      ),
    );
  }

  void _askAmos(String prompt) {
    // Navigate to chat with the prompt
    context.go('/chat', extra: {'initialPrompt': prompt});
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.borderColor),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 22, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: context.textTertiary,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(
                LucideIcons.chevronRight,
                color: context.textTertiary,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Button for connecting an email provider
class _EmailProviderButton extends StatelessWidget {
  final EmailProvider provider;
  final VoidCallback onTap;

  const _EmailProviderButton({
    required this.provider,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Provider-specific styling
    final (Color color, IconData icon) = switch (provider.slug) {
      'gmail' => (Colors.red, Icons.email_outlined),
      'outlook' => (const Color(0xFF0078D4), LucideIcons.mail), // Microsoft blue
      _ => (context.primaryColor, LucideIcons.mail),
    };

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: provider.isConnected ? null : onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: provider.isConnected ? Colors.green : color),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: Icon(icon, size: 20),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              provider.isConnected ? '${provider.name} Connected' : 'Connect ${provider.name}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
            if (provider.isConnected) ...[
              const SizedBox(width: 8),
              const Icon(LucideIcons.check, color: Colors.green, size: 16),
            ],
          ],
        ),
      ),
    );
  }
}
