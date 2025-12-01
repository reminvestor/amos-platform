import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/campaign.dart';
import 'package:amos_mobile/providers/app_providers.dart';
import 'package:intl/intl.dart';

class CampaignDetailScreen extends ConsumerWidget {
  final String id;

  const CampaignDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final campaigns = ref.watch(campaignsProvider);
    final campaign = campaigns.firstWhere(
      (c) => c.id == id,
      orElse: () => Campaign(
        id: id,
        entityId: '',
        userId: '',
        name: 'Campaign Not Found',
        subject: '',
        status: CampaignStatus.draft,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
        title: const Text('Campaign Details'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.ellipsisVertical),
            onPressed: () {
              // TODO: Campaign actions
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Campaign Header
            Text(
              campaign.name,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              campaign.subject,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: context.textSecondary,
                  ),
            ),
            const SizedBox(height: 24),

            // Stats Cards
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    icon: LucideIcons.users,
                    label: 'Recipients',
                    value: campaign.contactCount?.toString() ?? '0',
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    icon: LucideIcons.mailOpen,
                    label: 'Open Rate',
                    value: campaign.openRate != null
                        ? '${campaign.openRate!.toStringAsFixed(1)}%'
                        : '-',
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    icon: LucideIcons.mousePointerClick,
                    label: 'Click Rate',
                    value: campaign.clickRate != null
                        ? '${campaign.clickRate!.toStringAsFixed(1)}%'
                        : '-',
                    color: Colors.purple,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    icon: LucideIcons.circleAlert,
                    label: 'Bounce Rate',
                    value: campaign.bounceRate != null
                        ? '${campaign.bounceRate!.toStringAsFixed(1)}%'
                        : '-',
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Details Section
            Text(
              'Details',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: context.borderColor),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _DetailRow(
                      label: 'Status',
                      value: _getStatusLabel(campaign.status),
                    ),
                    const Divider(),
                    _DetailRow(
                      label: 'Created',
                      value: DateFormat('MMM d, yyyy at h:mm a')
                          .format(campaign.createdAt),
                    ),
                    if (campaign.scheduledAt != null) ...[
                      const Divider(),
                      _DetailRow(
                        label: 'Scheduled',
                        value: DateFormat('MMM d, yyyy at h:mm a')
                            .format(campaign.scheduledAt!),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getStatusLabel(CampaignStatus status) {
    switch (status) {
      case CampaignStatus.draft:
        return 'Draft';
      case CampaignStatus.scheduled:
        return 'Scheduled';
      case CampaignStatus.inProgress:
        return 'In Progress';
      case CampaignStatus.completed:
        return 'Completed';
      case CampaignStatus.paused:
        return 'Paused';
      case CampaignStatus.stopped:
        return 'Stopped';
    }
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.textSecondary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.textSecondary,
                ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
