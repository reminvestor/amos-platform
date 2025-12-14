import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:amos_mobile/config/env.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/providers/auth_provider.dart';
import 'package:amos_mobile/providers/theme_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  // URLs - hardcoded to avoid compile-time constant issues
  static const String _privacyPolicyUrl = 'https://www.amoslabs.com/privacy';
  static const String _termsOfServiceUrl = 'https://www.amoslabs.com/license';
  static const String _helpCenterUrl = 'https://www.amoslabs.com/help';
  static String get _supportEmail => Env.supportEmail;

  Future<void> _launchUrl(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    try {
      // On web, skip canLaunchUrl check as it's unreliable
      // Use platformDefault for web (opens new tab), externalApplication for mobile
      await launchUrl(
        uri,
        mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open $url')),
        );
      }
    }
  }

  Future<void> _launchEmail(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      queryParameters: {'subject': 'AMOS Labs Mobile App Support'},
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Email: $_supportEmail')),
        );
      }
    }
  }

  void _showAccountDetails(BuildContext context, WidgetRef ref) {
    final user = ref.read(authStateProvider).user;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: Text(
                      user?.initials ?? 'U',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.name ?? 'User',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          user?.email ?? '',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.grey,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Divider(),
              ListTile(
                leading: const Icon(LucideIcons.user),
                title: const Text('Edit Profile'),
                trailing: const Icon(LucideIcons.chevronRight),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Profile editing coming soon')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(LucideIcons.lock),
                title: const Text('Change Password'),
                trailing: const Icon(LucideIcons.chevronRight),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Password change coming soon')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(LucideIcons.shield),
                title: const Text('Two-Factor Authentication'),
                trailing: const Icon(LucideIcons.chevronRight),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('2FA settings coming soon')),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showEmailNotificationSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Email Notifications',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Campaign Updates'),
                subtitle: const Text('Get notified about campaign performance'),
                value: true,
                onChanged: (value) {},
              ),
              SwitchListTile(
                title: const Text('New Contacts'),
                subtitle: const Text('Get notified when contacts are added'),
                value: true,
                onChanged: (value) {},
              ),
              SwitchListTile(
                title: const Text('Weekly Reports'),
                subtitle: const Text('Receive weekly analytics summary'),
                value: false,
                onChanged: (value) {},
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final themeMode = ref.watch(themeModeProvider);
    final user = authState.user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          // User Profile Section
          InkWell(
            onTap: () => context.push('/profile'),
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: context.primaryColor,
                    child: Text(
                      user?.initials ?? 'U',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.name ?? 'User',
                          style: Theme.of(context).textTheme.titleMedium,
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
                  const Icon(LucideIcons.chevronRight),
                ],
              ),
            ),
          ),
          const Divider(),

          // Appearance Section
          _SectionHeader(title: 'Appearance'),
          Builder(
            builder: (context) {
              // Check actual theme brightness, not just the ThemeMode setting
              final isDark = themeMode == ThemeMode.dark ||
                  (themeMode == ThemeMode.system &&
                      MediaQuery.platformBrightnessOf(context) == Brightness.dark);
              return _SettingsTile(
                icon: LucideIcons.moon,
                title: 'Dark Mode',
                trailing: Switch(
                  value: isDark,
                  onChanged: (value) {
                    ref.read(themeModeProvider.notifier).setThemeMode(
                          value ? ThemeMode.dark : ThemeMode.light,
                        );
                  },
                ),
              );
            },
          ),

          // Notifications Section
          _SectionHeader(title: 'Notifications'),
          _SettingsTile(
            icon: LucideIcons.bell,
            title: 'Push Notifications',
            trailing: Switch(
              value: true,
              onChanged: (value) {
                // TODO: Toggle notifications
              },
            ),
          ),
          _SettingsTile(
            icon: LucideIcons.mail,
            title: 'Email Notifications',
            trailing: const Icon(LucideIcons.chevronRight),
            onTap: () {
              _showEmailNotificationSettings(context);
            },
          ),

          // Data & Privacy Section
          _SectionHeader(title: 'Data & Privacy'),
          _SettingsTile(
            icon: LucideIcons.shield,
            title: 'Privacy Policy',
            trailing: const Icon(LucideIcons.chevronRight),
            onTap: () => _launchUrl(context, _privacyPolicyUrl),
          ),
          _SettingsTile(
            icon: LucideIcons.fileText,
            title: 'Terms of Service',
            trailing: const Icon(LucideIcons.chevronRight),
            onTap: () => _launchUrl(context, _termsOfServiceUrl),
          ),

          // Support Section
          _SectionHeader(title: 'Support'),
          _SettingsTile(
            icon: LucideIcons.circleQuestionMark,
            title: 'Help Center',
            trailing: const Icon(LucideIcons.chevronRight),
            onTap: () => _launchUrl(context, _helpCenterUrl),
          ),
          _SettingsTile(
            icon: LucideIcons.messageCircle,
            title: 'Contact Support',
            trailing: const Icon(LucideIcons.chevronRight),
            onTap: () => _launchEmail(context),
          ),

          // App Info Section
          _SectionHeader(title: 'About'),
          _SettingsTile(
            icon: LucideIcons.info,
            title: 'App Version',
            trailing: Text(
              Env.appVersion,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.textSecondary,
                  ),
            ),
          ),

          const SizedBox(height: 16),

          // Logout Button
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

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: context.textSecondary),
      title: Text(title),
      trailing: trailing,
      onTap: onTap,
    );
  }
}
