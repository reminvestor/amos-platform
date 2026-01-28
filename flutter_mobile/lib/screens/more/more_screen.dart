import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/providers/auth_provider.dart';
import 'package:amos_mobile/services/connections_service.dart';
import 'package:amos_mobile/widgets/branded_app_bar.dart';

class MoreScreen extends ConsumerStatefulWidget {
  const MoreScreen({super.key});

  @override
  ConsumerState<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends ConsumerState<MoreScreen> {
  final ConnectionsService _connectionsService = ConnectionsService();
  bool _gmailConnected = false;
  bool _checkingConnections = true;

  @override
  void initState() {
    super.initState();
    _checkConnections();
  }

  Future<void> _checkConnections() async {
    try {
      final connected = await _connectionsService.isGmailConnected();
      if (mounted) {
        setState(() {
          _gmailConnected = connected;
          _checkingConnections = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _checkingConnections = false);
      }
    }
  }

  Future<void> _connectGmail() async {
    try {
      final oauthResponse = await _connectionsService.getOAuthUrl('gmail');
      final url = Uri.parse(oauthResponse.url);

      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
        // Show a message telling user to return after completing OAuth
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Complete sign-in in your browser, then return here'),
              duration: Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to connect Gmail: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final user = authState.user;

    return Scaffold(
      appBar: const BrandedAppBar(),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // User Profile Card
          if (user != null) ...[
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: context.borderColor),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: context.primaryColor.withValues(alpha: 0.1),
                      child: Text(
                        user.initials,
                        style: TextStyle(
                          color: context.primaryColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.name ?? 'User',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user.email,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: context.textSecondary,
                                ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        LucideIcons.chevronRight,
                        color: context.textTertiary,
                        size: 20,
                      ),
                      onPressed: () => context.push('/settings'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Account Section
          _SectionHeader(
            title: 'Account',
            icon: LucideIcons.user,
          ),
          const SizedBox(height: 12),
          _MenuItem(
            icon: LucideIcons.building2,
            title: 'Business Profile',
            description: 'Your business info and brand voice',
            onTap: () => context.push('/business-profile'),
          ),
          const SizedBox(height: 8),
          _MenuItem(
            icon: LucideIcons.settings,
            title: 'Settings',
            description: 'App preferences and notifications',
            onTap: () => context.push('/settings'),
          ),
          const SizedBox(height: 8),
          _MenuItem(
            icon: LucideIcons.bell,
            title: 'Notifications',
            description: 'Manage notification preferences',
            onTap: () => context.push('/settings'),
          ),
          const SizedBox(height: 24),

          // Connected Services Section
          _SectionHeader(
            title: 'Connected Services',
            icon: LucideIcons.plug,
          ),
          const SizedBox(height: 12),
          _ConnectionItem(
            icon: Icons.email_outlined,
            iconColor: Colors.red,
            title: 'Gmail',
            description: _gmailConnected
                ? 'Connected - AI can read your inbox'
                : 'Connect to summarize your email',
            isConnected: _gmailConnected,
            isLoading: _checkingConnections,
            onTap: _gmailConnected ? () => _showDisconnectOption() : _connectGmail,
          ),
          const SizedBox(height: 24),

          // Support Section
          _SectionHeader(
            title: 'Support',
            icon: LucideIcons.info,
          ),
          const SizedBox(height: 12),
          _MenuItem(
            icon: LucideIcons.messageCircle,
            title: 'Help Center',
            description: 'FAQs and documentation',
            onTap: () => context.push('/help'),
          ),
          const SizedBox(height: 8),
          _MenuItem(
            icon: LucideIcons.mail,
            title: 'Contact Support',
            description: 'Get help from our team',
            onTap: () => _showComingSoon(context, 'Contact Support'),
          ),
          const SizedBox(height: 24),

          // Logout Button
          OutlinedButton.icon(
            onPressed: () => _showLogoutConfirmation(context, ref),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(LucideIcons.logOut, size: 18),
            label: const Text('Sign Out'),
          ),
          const SizedBox(height: 32),

          // App Version
          Center(
            child: Text(
              'Amos v1.0.0',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.textTertiary,
                  ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _showComingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature coming soon'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showLogoutConfirmation(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(authStateProvider.notifier).logout();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  void _showDisconnectOption() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gmail Connected'),
        content: const Text('Your Gmail account is connected. The AI can now summarize your inbox and help manage your email.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({
    required this.title,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: context.textSecondary),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: context.textSecondary,
              ),
        ),
      ],
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
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
              Icon(icon, size: 22, color: context.textSecondary),
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

class _ConnectionItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final bool isConnected;
  final bool isLoading;
  final VoidCallback onTap;

  const _ConnectionItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.isConnected,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isConnected ? Colors.green.withValues(alpha: 0.5) : context.borderColor,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
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
                    Row(
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                        if (isConnected) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Connected',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.green,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
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
              if (isLoading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (!isConnected)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: context.primaryColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Connect',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                Icon(
                  LucideIcons.check,
                  color: Colors.green,
                  size: 18,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
