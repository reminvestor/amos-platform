import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/providers/auth_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final user = authState.user;

    return Scaffold(
      appBar: AppBar(
        title: Image.asset(
          'assets/images/logo-header.png',
          height: 26,
          color: Theme.of(context).brightness == Brightness.light
              ? const Color(0xFF1a1a2e)
              : null,
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.bell),
            onPressed: () {
              // TODO: Notifications
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome message
            if (user != null) ...[
              Text(
                'Welcome back, ${user.name?.split(' ').first ?? 'there'}!',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'What would you like to do today?',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: context.textSecondary,
                    ),
              ),
              const SizedBox(height: 20),
            ],

            // Quick Actions - Compact horizontal list
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _CompactActionChip(
                    icon: LucideIcons.mail,
                    label: 'Campaigns',
                    color: context.primaryColor,
                    onTap: () => context.push('/home/campaigns'),
                  ),
                  const SizedBox(width: 8),
                  _CompactActionChip(
                    icon: LucideIcons.users,
                    label: 'Contacts',
                    color: Colors.green,
                    onTap: () => context.push('/home/contacts'),
                  ),
                  const SizedBox(width: 8),
                  _CompactActionChip(
                    icon: LucideIcons.layoutGrid,
                    label: 'Pages',
                    color: Colors.purple,
                    onTap: () => context.push('/home/landing-pages'),
                  ),
                  const SizedBox(width: 8),
                  _CompactActionChip(
                    icon: LucideIcons.bot,
                    label: 'Agents',
                    color: Colors.orange,
                    onTap: () => context.go('/agents'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Recent Activity Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Activity',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                TextButton(
                  onPressed: () {},
                  child: const Text('See all'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _ActivityList(),
          ],
        ),
      ),
    );
  }
}

/// Compact action chip for quick navigation
class _CompactActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _CompactActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Placeholder for recent activity
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            children: [
              Icon(
                LucideIcons.activity,
                size: 48,
                color: context.textTertiary,
              ),
              const SizedBox(height: 12),
              Text(
                'No recent activity',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: context.textSecondary,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
