import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';

class MarketingHubScreen extends ConsumerWidget {
  const MarketingHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Marketing'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.plus),
            onPressed: () => _showCreateOptions(context),
            tooltip: 'Create New',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Campaigns Section
          _SectionHeader(
            title: 'Campaigns',
            icon: LucideIcons.mail,
            color: context.primaryColor,
            onSeeAll: () => context.push('/home/campaigns'),
          ),
          const SizedBox(height: 12),
          _HubCard(
            icon: LucideIcons.mail,
            title: 'Email Campaigns',
            description: 'Create and manage email marketing campaigns',
            color: context.primaryColor,
            onTap: () => context.push('/home/campaigns'),
          ),
          const SizedBox(height: 8),
          _HubCard(
            icon: LucideIcons.circlePlus,
            title: 'New Campaign',
            description: 'Start a new email campaign with AI assistance',
            color: context.primaryColor,
            onTap: () => context.push('/home/campaigns/new'),
            isAction: true,
          ),
          const SizedBox(height: 24),

          // Email Templates Section
          _SectionHeader(
            title: 'Email Templates',
            icon: LucideIcons.fileText,
            color: Colors.amber.shade700,
            onSeeAll: () => context.push('/home/email-templates'),
          ),
          const SizedBox(height: 12),
          _HubCard(
            icon: LucideIcons.fileText,
            title: 'Browse Templates',
            description: 'View and manage your email templates',
            color: Colors.amber.shade700,
            onTap: () => context.push('/home/email-templates'),
          ),
          const SizedBox(height: 8),
          _HubCard(
            icon: LucideIcons.circlePlus,
            title: 'Create Template',
            description: 'Design a new reusable email template',
            color: Colors.amber.shade700,
            onTap: () => context.push('/home/email-templates/new'),
            isAction: true,
          ),
          const SizedBox(height: 24),

          // Landing Pages Section
          _SectionHeader(
            title: 'Landing Pages',
            icon: LucideIcons.layoutGrid,
            color: Colors.purple,
            onSeeAll: () => context.push('/home/landing-pages'),
          ),
          const SizedBox(height: 12),
          _HubCard(
            icon: LucideIcons.layoutGrid,
            title: 'Browse Pages',
            description: 'View and manage your landing pages',
            color: Colors.purple,
            onTap: () => context.push('/home/landing-pages'),
          ),
          const SizedBox(height: 8),
          _HubCard(
            icon: LucideIcons.sparkles,
            title: 'Create with AI',
            description: 'Generate a landing page with AI',
            color: Colors.purple,
            onTap: () => context.push('/chat?prompt=${Uri.encodeComponent("I want to create a new landing page")}'),
            isAction: true,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _showCreateOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Create New',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(LucideIcons.mail),
              title: const Text('Email Campaign'),
              subtitle: const Text('Start a new marketing campaign'),
              onTap: () {
                Navigator.pop(context);
                context.push('/home/campaigns/new');
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.fileText),
              title: const Text('Email Template'),
              subtitle: const Text('Create a reusable template'),
              onTap: () {
                Navigator.pop(context);
                context.push('/home/email-templates/new');
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.layoutGrid),
              title: const Text('Landing Page'),
              subtitle: const Text('Build with AI assistance'),
              onTap: () {
                Navigator.pop(context);
                context.push('/chat?prompt=${Uri.encodeComponent("I want to create a new landing page")}');
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onSeeAll;

  const _SectionHeader({
    required this.title,
    required this.icon,
    required this.color,
    required this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const Spacer(),
        TextButton(
          onPressed: onSeeAll,
          child: const Text('See all'),
        ),
      ],
    );
  }
}

class _HubCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final VoidCallback onTap;
  final bool isAction;

  const _HubCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    required this.onTap,
    this.isAction = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isAction ? color.withValues(alpha: 0.3) : context.borderColor,
        ),
      ),
      color: isAction ? color.withValues(alpha: 0.05) : null,
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
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
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
