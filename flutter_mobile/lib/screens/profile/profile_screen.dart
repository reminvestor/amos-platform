import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/providers/auth_provider.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final user = authState.user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Account'),
      ),
      body: ListView(
        children: [
          // Profile Header
          Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 48,
                  backgroundColor: context.primaryColor,
                  child: Text(
                    user?.initials ?? 'U',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  user?.name ?? 'User',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  user?.email ?? '',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.textSecondary,
                      ),
                ),
              ],
            ),
          ),
          const Divider(),

          // Account Settings
          _SectionHeader(title: 'Account'),
          ListTile(
            leading: Icon(LucideIcons.user, color: context.textSecondary),
            title: const Text('Edit Profile'),
            subtitle: const Text('Change your name and photo'),
            trailing: const Icon(LucideIcons.chevronRight),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Profile editing coming soon')),
              );
            },
          ),
          ListTile(
            leading: Icon(LucideIcons.mail, color: context.textSecondary),
            title: const Text('Email Address'),
            subtitle: Text(user?.email ?? ''),
            trailing: const Icon(LucideIcons.chevronRight),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Email change coming soon')),
              );
            },
          ),

          // Security
          _SectionHeader(title: 'Security'),
          ListTile(
            leading: Icon(LucideIcons.lock, color: context.textSecondary),
            title: const Text('Change Password'),
            subtitle: const Text('Update your password'),
            trailing: const Icon(LucideIcons.chevronRight),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Password change coming soon')),
              );
            },
          ),
          ListTile(
            leading: Icon(LucideIcons.shield, color: context.textSecondary),
            title: const Text('Two-Factor Authentication'),
            subtitle: const Text('Add extra security to your account'),
            trailing: const Icon(LucideIcons.chevronRight),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('2FA settings coming soon')),
              );
            },
          ),

          const SizedBox(height: 24),

          // Sign Out Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Sign Out'),
                    content: const Text('Are you sure you want to sign out?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(
                          'Sign Out',
                          style: TextStyle(color: context.errorColor),
                        ),
                      ),
                    ],
                  ),
                );

                if (confirmed == true) {
                  await ref.read(authStateProvider.notifier).logout();
                }
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: context.errorColor,
                side: BorderSide(color: context.errorColor),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(LucideIcons.logOut),
              label: const Text('Sign Out'),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: context.textSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
      ),
    );
  }
}
