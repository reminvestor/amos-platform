import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';

class ToolsHubScreen extends ConsumerWidget {
  const ToolsHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tools'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Documents / Knowledge Base Section
          _SectionHeader(
            title: 'Knowledge Base',
            icon: LucideIcons.folderOpen,
            color: Colors.blueGrey,
          ),
          const SizedBox(height: 12),
          _ToolCard(
            icon: LucideIcons.folderOpen,
            title: 'Documents',
            description: 'Upload and manage documents for AI knowledge',
            color: Colors.blueGrey,
            onTap: () => context.push('/documents'),
          ),
          const SizedBox(height: 24),

          // Inbox / Work Items Section
          _SectionHeader(
            title: 'Inbox',
            icon: LucideIcons.inbox,
            color: Colors.indigo,
          ),
          const SizedBox(height: 12),
          _ToolCard(
            icon: LucideIcons.inbox,
            title: 'Work Items',
            description: 'View agent completions and notifications',
            color: Colors.indigo,
            onTap: () => context.push('/inbox'),
          ),
          const SizedBox(height: 24),

          // Tasks Section
          _SectionHeader(
            title: 'Productivity',
            icon: LucideIcons.listTodo,
            color: Colors.deepPurple,
          ),
          const SizedBox(height: 12),
          _ToolCard(
            icon: LucideIcons.listTodo,
            title: 'Tasks',
            description: 'View and manage your tasks and to-dos',
            color: Colors.deepPurple,
            onTap: () => context.go('/tasks'),
          ),
          const SizedBox(height: 24),

          // AI & Automation Section
          _SectionHeader(
            title: 'AI & Automation',
            icon: LucideIcons.bot,
            color: Colors.orange,
          ),
          const SizedBox(height: 12),
          _ToolCard(
            icon: LucideIcons.bot,
            title: 'AI Agents',
            description: 'View and configure your AI agents',
            color: Colors.orange,
            onTap: () => context.go('/agents'),
          ),
          const SizedBox(height: 24),

          // Analytics Section
          _SectionHeader(
            title: 'Insights',
            icon: LucideIcons.chartBar,
            color: Colors.teal,
          ),
          const SizedBox(height: 12),
          _ToolCard(
            icon: LucideIcons.chartBar,
            title: 'Analytics',
            description: 'View performance metrics and insights',
            color: Colors.teal,
            onTap: () => context.push('/home/analytics'),
          ),
          const SizedBox(height: 32),

          // Quick Actions
          Text(
            'Quick Actions',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _QuickActionChip(
                icon: LucideIcons.upload,
                label: 'Upload Document',
                onTap: () => context.push('/documents'),
              ),
              _QuickActionChip(
                icon: LucideIcons.circlePlus,
                label: 'New Task',
                onTap: () => context.push('/tasks/new'),
              ),
              _QuickActionChip(
                icon: LucideIcons.sparkles,
                label: 'Ask Amos',
                onTap: () => context.go('/chat'),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;

  const _SectionHeader({
    required this.title,
    required this.icon,
    required this.color,
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
      ],
    );
  }
}

class _ToolCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final VoidCallback onTap;

  const _ToolCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
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
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
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
                    const SizedBox(height: 4),
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

class _QuickActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: context.primaryColor.withValues(alpha: 0.1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: context.primaryColor, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.primaryColor,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
