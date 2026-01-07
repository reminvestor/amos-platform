import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';

class MarketplaceScreen extends StatelessWidget {
  const MarketplaceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Marketplace'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Agent Marketplace',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Discover and install pre-built agents to automate your workflows',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.textSecondary,
                  ),
            ),
            const SizedBox(height: 24),

            // Featured Agents Section
            _SectionHeader(title: 'Featured Agents'),
            const SizedBox(height: 12),
            _AgentCard(
              name: 'Email Campaign Assistant',
              description: 'Automates email campaign creation and scheduling',
              icon: LucideIcons.mail,
              color: Colors.blue,
              isInstalled: true,
            ),
            const SizedBox(height: 12),
            _AgentCard(
              name: 'Lead Qualifier',
              description: 'Scores and qualifies incoming leads automatically',
              icon: LucideIcons.userCheck,
              color: Colors.green,
              isInstalled: false,
            ),
            const SizedBox(height: 12),
            _AgentCard(
              name: 'Social Media Scheduler',
              description: 'Plans and schedules social media posts',
              icon: LucideIcons.share2,
              color: Colors.purple,
              isInstalled: false,
            ),
            const SizedBox(height: 24),

            // Integration Agents Section
            _SectionHeader(title: 'Integration Agents'),
            const SizedBox(height: 12),
            _AgentCard(
              name: 'Stripe Revenue Reporter',
              description: 'Tracks and reports on Stripe revenue metrics',
              icon: LucideIcons.creditCard,
              color: Colors.indigo,
              isInstalled: false,
            ),
            const SizedBox(height: 12),
            _AgentCard(
              name: 'HubSpot Sync Agent',
              description: 'Syncs contacts and deals with HubSpot CRM',
              icon: LucideIcons.refreshCw,
              color: Colors.orange,
              isInstalled: false,
            ),
            const SizedBox(height: 24),

            // Coming Soon Section
            _SectionHeader(title: 'Coming Soon'),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: context.borderColor),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      LucideIcons.sparkles,
                      size: 48,
                      color: context.textTertiary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'More agents coming soon!',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'We\'re building new agents to help automate your marketing.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: context.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
    );
  }
}

class _AgentCard extends StatelessWidget {
  final String name;
  final String description;
  final IconData icon;
  final Color color;
  final bool isInstalled;

  const _AgentCard({
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.isInstalled,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
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
                    name,
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
            const SizedBox(width: 12),
            if (isInstalled)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'Installed',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.green,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              )
            else
              OutlinedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Installing $name...'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  minimumSize: Size.zero,
                ),
                child: const Text('Install'),
              ),
          ],
        ),
      ),
    );
  }
}
