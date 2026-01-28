import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/widgets/branded_app_bar.dart';

class ToolsHubScreen extends ConsumerWidget {
  const ToolsHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: const BrandedAppBar(
        title: 'Toolbox',
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Quick Access - Scanner, Notes & Inbox
          _SectionHeader(
            title: 'Quick Access',
            icon: LucideIcons.zap,
            color: Colors.amber.shade700,
          ),
          const SizedBox(height: 12),
          _ToolCard(
            icon: LucideIcons.scan,
            title: 'Scanner',
            description: 'Scan business cards, receipts & documents',
            color: Colors.teal,
            onTap: () => context.push('/scanner'),
          ),
          const SizedBox(height: 12),
          _ToolCard(
            icon: LucideIcons.stickyNote,
            title: 'Notes',
            description: 'Your personal notes and ideas',
            color: Colors.amber.shade700,
            onTap: () => context.push('/personal-notes'),
          ),
          const SizedBox(height: 12),
          _ToolCard(
            icon: LucideIcons.inbox,
            title: 'Inbox',
            description: 'View completions and notifications',
            color: Colors.indigo,
            onTap: () => context.push('/inbox'),
          ),
          const SizedBox(height: 24),

          // Productivity Section
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
            onTap: () => context.push('/tasks'),
          ),
          const SizedBox(height: 24),

          // Contacts Section
          _SectionHeader(
            title: 'People',
            icon: LucideIcons.users,
            color: Colors.teal,
          ),
          const SizedBox(height: 12),
          _ToolCard(
            icon: LucideIcons.users,
            title: 'Contacts',
            description: 'View and search your contacts',
            color: Colors.teal,
            onTap: () => context.push('/contacts'),
          ),
          const SizedBox(height: 24),

          // Knowledge Section
          _SectionHeader(
            title: 'Knowledge',
            icon: LucideIcons.folderOpen,
            color: Colors.blueGrey,
          ),
          const SizedBox(height: 12),
          _ToolCard(
            icon: LucideIcons.fileText,
            title: 'Documents',
            description: 'Browse your knowledge base',
            color: Colors.blueGrey,
            onTap: () => context.push('/documents'),
          ),
          const SizedBox(height: 16),
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
