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
            onPressed: () => context.push('/notifications'),
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

            // Quick Actions - Wrapping for mobile
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _CompactActionChip(
                  icon: LucideIcons.mail,
                  label: 'Campaigns',
                  color: context.primaryColor,
                  onTap: () => context.push('/home/campaigns'),
                ),
                _CompactActionChip(
                  icon: LucideIcons.users,
                  label: 'Contacts',
                  color: Colors.green,
                  onTap: () => context.go('/contacts'),
                ),
                _CompactActionChip(
                  icon: LucideIcons.layoutGrid,
                  label: 'Pages',
                  color: Colors.purple,
                  onTap: () => context.push('/home/landing-pages'),
                ),
                _CompactActionChip(
                  icon: LucideIcons.bot,
                  label: 'Agents',
                  color: Colors.orange,
                  onTap: () => context.go('/agents'),
                ),
                _CompactActionChip(
                  icon: LucideIcons.chartBar,
                  label: 'Analytics',
                  color: Colors.teal,
                  onTap: () => context.push('/home/analytics'),
                ),
                _CompactActionChip(
                  icon: LucideIcons.plug,
                  label: 'Integrations',
                  color: Colors.indigo,
                  onTap: () => context.push('/home/connections'),
                ),
                _CompactActionChip(
                  icon: LucideIcons.fileText,
                  label: 'Templates',
                  color: Colors.amber.shade700,
                  onTap: () => context.push('/home/email-templates'),
                ),
                _CompactActionChip(
                  icon: LucideIcons.inbox,
                  label: 'Inbox',
                  color: Colors.cyan,
                  onTap: () => context.push('/inbox'),
                ),
                _CompactActionChip(
                  icon: LucideIcons.calendarClock,
                  label: 'Tasks',
                  color: Colors.deepPurple,
                  onTap: () => context.go('/tasks'),
                ),
                _CompactActionChip(
                  icon: LucideIcons.store,
                  label: 'Marketplace',
                  color: Colors.pink,
                  onTap: () => context.push('/marketplace'),
                ),
                _CompactActionChip(
                  icon: LucideIcons.folderOpen,
                  label: 'Documents',
                  color: Colors.blueGrey,
                  onTap: () => context.push('/documents'),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Quick Create Section - Direct to Amos Chat
            Text(
              'Quick Actions',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            _QuickActionCard(
              icon: LucideIcons.sparkles,
              title: 'Ask Amos',
              description: 'Get help with any marketing task',
              onTap: () => context.go('/chat'),
            ),
            const SizedBox(height: 8),
            _QuickActionCard(
              icon: LucideIcons.mail,
              title: 'Create Campaign',
              description: 'Start a new email campaign',
              onTap: () => context.push('/chat?prompt=${Uri.encodeComponent("I want to create a new email campaign")}'),
            ),
            const SizedBox(height: 8),
            _QuickActionCard(
              icon: LucideIcons.userPlus,
              title: 'Add Contact',
              description: 'Add a new contact to your list',
              onTap: () => context.push('/chat?prompt=${Uri.encodeComponent("I want to add a new contact")}'),
            ),
            const SizedBox(height: 8),
            _QuickActionCard(
              icon: LucideIcons.layoutGrid,
              title: 'Create Landing Page',
              description: 'Build an AI-powered landing page',
              onTap: () => context.push('/chat?prompt=${Uri.encodeComponent("I want to create a new landing page")}'),
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

/// Quick action card for common tasks that navigate to Amos chat
class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.borderColor),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: context.primaryColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: context.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(
                LucideIcons.chevronRight,
                color: context.textTertiary,
                size: 20,
              ),
            ],
          ),
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
