import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/providers/auth_provider.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final user = authState.user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('More'),
      ),
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

          // Integrations Section
          _SectionHeader(
            title: 'Integrations',
            icon: LucideIcons.plug,
          ),
          const SizedBox(height: 12),
          _MenuItem(
            icon: LucideIcons.link,
            title: 'Connected Apps',
            description: 'Manage your connected integrations',
            onTap: () => context.push('/home/connections'),
          ),
          const SizedBox(height: 24),

          // Marketplace Section
          _SectionHeader(
            title: 'Marketplace',
            icon: LucideIcons.store,
          ),
          const SizedBox(height: 12),
          _MenuItem(
            icon: LucideIcons.layoutGrid,
            title: 'Browse Templates',
            description: 'Explore pre-built templates',
            onTap: () => context.push('/marketplace'),
          ),
          const SizedBox(height: 8),
          _MenuItem(
            icon: LucideIcons.sparkles,
            title: 'AI Agents',
            description: 'Discover and install AI agents',
            onTap: () => context.push('/agents'),
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
            onTap: () => _showComingSoon(context, 'Help Center'),
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
