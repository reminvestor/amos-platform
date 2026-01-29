import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/canvas.dart';
import 'package:amos_mobile/services/canvas_service.dart';
import 'package:amos_mobile/utils/logger.dart';

/// Canvas for displaying a list of email campaigns
class CampaignListCanvas extends ConsumerStatefulWidget {
  final Canvas canvas;

  const CampaignListCanvas({super.key, required this.canvas});

  @override
  ConsumerState<CampaignListCanvas> createState() => _CampaignListCanvasState();
}

class _CampaignListCanvasState extends ConsumerState<CampaignListCanvas> {
  final _canvasService = CanvasService();
  List<Map<String, dynamic>> _campaigns = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCampaigns();
  }

  Future<void> _loadCampaigns() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final campaigns = await _canvasService.fetchResourceList(
        resourceType: 'campaigns',
        filters: widget.canvas.data.isNotEmpty ? widget.canvas.data : null,
      );
      setState(() {
        _campaigns = campaigns;
        _isLoading = false;
      });
    } catch (e) {
      AppLogger.error('Failed to load campaigns', error: e);
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _buildErrorState();
    }

    if (_campaigns.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _loadCampaigns,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _campaigns.length,
        itemBuilder: (context, index) {
          return _CampaignCard(
            campaign: _campaigns[index],
            onTap: () => _openCampaign(_campaigns[index]),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.mail,
            size: 48,
            color: context.textTertiary,
          ),
          const SizedBox(height: 16),
          Text(
            'No campaigns yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Ask the AI to create one for you',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.textSecondary,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.circleAlert,
            size: 48,
            color: Colors.red.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'Failed to load campaigns',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _loadCampaigns,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  void _openCampaign(Map<String, dynamic> campaign) {
    final id = campaign['id'];
    if (id != null) {
      context.push('/campaigns/$id');
    }
  }
}

class _CampaignCard extends StatelessWidget {
  final Map<String, dynamic> campaign;
  final VoidCallback onTap;

  const _CampaignCard({
    required this.campaign,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = campaign['name'] ?? campaign['subject'] ?? 'Untitled';
    final status = campaign['status'] ?? 'draft';
    final recipientCount = campaign['recipient_count'] ?? campaign['recipients_count'] ?? 0;
    final openRate = campaign['open_rate'];
    final clickRate = campaign['click_rate'];
    final scheduledAt = campaign['scheduled_at'];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: context.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      LucideIcons.mail,
                      size: 20,
                      color: context.primaryColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            _StatusBadge(status: status),
                            const SizedBox(width: 8),
                            Icon(LucideIcons.users, size: 12, color: context.textTertiary),
                            const SizedBox(width: 4),
                            Text(
                              '$recipientCount',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: context.textTertiary,
                                  ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    LucideIcons.chevronRight,
                    size: 20,
                    color: context.textTertiary,
                  ),
                ],
              ),

              // Stats row (if campaign has been sent)
              if (openRate != null || clickRate != null) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (openRate != null)
                      _StatChip(
                        icon: LucideIcons.eye,
                        label: 'Opens',
                        value: '${(openRate * 100).toStringAsFixed(1)}%',
                      ),
                    if (openRate != null && clickRate != null)
                      const SizedBox(width: 16),
                    if (clickRate != null)
                      _StatChip(
                        icon: LucideIcons.mousePointerClick,
                        label: 'Clicks',
                        value: '${(clickRate * 100).toStringAsFixed(1)}%',
                      ),
                  ],
                ),
              ],

              // Scheduled time
              if (scheduledAt != null && status.toLowerCase() == 'scheduled') ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      LucideIcons.clock,
                      size: 14,
                      color: context.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Scheduled: ${_formatDate(scheduledAt)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: context.textSecondary,
                          ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return '${date.month}/${date.day}/${date.year} at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr;
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color backgroundColor;
    Color textColor;
    IconData? icon;

    switch (status.toLowerCase()) {
      case 'sent':
      case 'completed':
        backgroundColor = Colors.green.shade100;
        textColor = Colors.green.shade700;
        icon = LucideIcons.circleCheck;
        break;
      case 'scheduled':
        backgroundColor = Colors.blue.shade100;
        textColor = Colors.blue.shade700;
        icon = LucideIcons.clock;
        break;
      case 'sending':
        backgroundColor = Colors.orange.shade100;
        textColor = Colors.orange.shade700;
        icon = LucideIcons.loader;
        break;
      case 'draft':
        backgroundColor = Colors.grey.shade200;
        textColor = Colors.grey.shade600;
        icon = LucideIcons.pencil;
        break;
      case 'failed':
        backgroundColor = Colors.red.shade100;
        textColor = Colors.red.shade700;
        icon = LucideIcons.circleAlert;
        break;
      default:
        backgroundColor = context.surfaceColor;
        textColor = context.textSecondary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: textColor),
            const SizedBox(width: 4),
          ],
          Text(
            status.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: context.textSecondary),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.textSecondary,
              ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}
