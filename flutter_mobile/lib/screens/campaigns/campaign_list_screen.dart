import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/campaign.dart';
import 'package:amos_mobile/providers/app_providers.dart';
import 'package:intl/intl.dart';

class CampaignListScreen extends ConsumerStatefulWidget {
  const CampaignListScreen({super.key});

  @override
  ConsumerState<CampaignListScreen> createState() => _CampaignListScreenState();
}

class _CampaignListScreenState extends ConsumerState<CampaignListScreen> {
  @override
  void initState() {
    super.initState();
    _loadCampaigns();
  }

  Future<void> _loadCampaigns() async {
    ref.read(campaignsLoadingProvider.notifier).setLoading(true);
    // TODO: Implement actual API call
    await Future.delayed(const Duration(milliseconds: 500));

    // Mock data
    ref.read(campaignsProvider.notifier).setCampaigns([
      Campaign(
        id: '1',
        entityId: 'e1',
        userId: 'u1',
        name: 'Welcome Series',
        subject: 'Welcome to our platform!',
        status: CampaignStatus.completed,
        createdAt: DateTime.now().subtract(const Duration(days: 7)),
        updatedAt: DateTime.now().subtract(const Duration(days: 2)),
        contactCount: 1250,
        openRate: 45.2,
        clickRate: 12.8,
      ),
      Campaign(
        id: '2',
        entityId: 'e1',
        userId: 'u1',
        name: 'Product Launch',
        subject: 'Introducing our new feature',
        status: CampaignStatus.scheduled,
        createdAt: DateTime.now().subtract(const Duration(days: 3)),
        updatedAt: DateTime.now(),
        scheduledAt: DateTime.now().add(const Duration(days: 2)),
        contactCount: 3500,
      ),
      Campaign(
        id: '3',
        entityId: 'e1',
        userId: 'u1',
        name: 'Holiday Sale',
        subject: 'Special holiday discounts inside!',
        status: CampaignStatus.draft,
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
        updatedAt: DateTime.now(),
      ),
    ]);

    ref.read(campaignsLoadingProvider.notifier).setLoading(false);
  }

  Color _getStatusColor(CampaignStatus status) {
    switch (status) {
      case CampaignStatus.draft:
        return Colors.grey;
      case CampaignStatus.scheduled:
        return Colors.blue;
      case CampaignStatus.inProgress:
        return Colors.orange;
      case CampaignStatus.completed:
        return Colors.green;
      case CampaignStatus.paused:
        return Colors.amber;
      case CampaignStatus.stopped:
        return Colors.red;
    }
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

  @override
  Widget build(BuildContext context) {
    final campaigns = ref.watch(campaignsProvider);
    final isLoading = ref.watch(campaignsLoadingProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
        title: const Text('Campaigns'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.plus),
            onPressed: () {
              // TODO: Create campaign
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : campaigns.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadCampaigns,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: campaigns.length,
                    itemBuilder: (context, index) {
                      final campaign = campaigns[index];
                      return _CampaignCard(
                        campaign: campaign,
                        statusColor: _getStatusColor(campaign.status),
                        statusLabel: _getStatusLabel(campaign.status),
                        onTap: () => context.pushNamed(
                          'campaign-detail',
                          pathParameters: {'id': campaign.id},
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.mail,
              size: 64,
              color: context.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              'No Campaigns',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Create your first email campaign to get started.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.textSecondary,
                  ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                // TODO: Create campaign
              },
              icon: const Icon(LucideIcons.plus),
              label: const Text('Create Campaign'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CampaignCard extends StatelessWidget {
  final Campaign campaign;
  final Color statusColor;
  final String statusLabel;
  final VoidCallback onTap;

  const _CampaignCard({
    required this.campaign,
    required this.statusColor,
    required this.statusLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d, yyyy');

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.borderColor),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      campaign.name,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      statusLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                campaign.subject,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.textSecondary,
                    ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (campaign.contactCount != null) ...[
                    Icon(
                      LucideIcons.users,
                      size: 14,
                      color: context.textTertiary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${campaign.contactCount}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: context.textTertiary,
                          ),
                    ),
                    const SizedBox(width: 16),
                  ],
                  if (campaign.openRate != null) ...[
                    Icon(
                      LucideIcons.mailOpen,
                      size: 14,
                      color: context.textTertiary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${campaign.openRate!.toStringAsFixed(1)}%',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: context.textTertiary,
                          ),
                    ),
                    const SizedBox(width: 16),
                  ],
                  const Spacer(),
                  Text(
                    dateFormat.format(campaign.createdAt),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.textTertiary,
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
