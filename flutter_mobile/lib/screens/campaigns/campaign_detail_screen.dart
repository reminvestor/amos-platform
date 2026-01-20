import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/campaign.dart';
import 'package:amos_mobile/providers/app_providers.dart';
import 'package:amos_mobile/services/campaigns_service.dart';
import 'package:intl/intl.dart';

class CampaignDetailScreen extends ConsumerStatefulWidget {
  final String id;

  const CampaignDetailScreen({super.key, required this.id});

  @override
  ConsumerState<CampaignDetailScreen> createState() => _CampaignDetailScreenState();
}

class _CampaignDetailScreenState extends ConsumerState<CampaignDetailScreen> {
  final CampaignsService _campaignsService = CampaignsService();
  bool _isLoading = false;
  Campaign? _campaign;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadCampaign();
    });
  }

  Future<void> _loadCampaign() async {
    try {
      final campaign = await _campaignsService.getCampaign(widget.id);
      if (mounted) {
        setState(() {
          _campaign = campaign;
        });
      }
    } catch (e) {
      // Fall back to provider data
    }
  }

  @override
  Widget build(BuildContext context) {
    final campaigns = ref.watch(campaignsProvider);
    final campaign = _campaign ?? campaigns.firstWhere(
      (c) => c.id == widget.id,
      orElse: () => Campaign(
        id: widget.id,
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
            icon: const Icon(LucideIcons.pencil),
            onPressed: () {
              // Navigate to edit campaign
              context.push('/marketing/campaigns/${widget.id}/edit');
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Campaign Header with Status
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
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
                          ],
                        ),
                      ),
                      _buildStatusBadge(campaign.status),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Action Buttons based on status
                  _buildActionButtons(campaign),
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

  Widget _buildStatusBadge(CampaignStatus status) {
    Color color;
    switch (status) {
      case CampaignStatus.draft:
        color = Colors.grey;
        break;
      case CampaignStatus.scheduled:
        color = Colors.blue;
        break;
      case CampaignStatus.inProgress:
        color = Colors.orange;
        break;
      case CampaignStatus.completed:
        color = Colors.green;
        break;
      case CampaignStatus.paused:
        color = Colors.amber;
        break;
      case CampaignStatus.stopped:
        color = Colors.red;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        _getStatusLabel(status),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildActionButtons(Campaign campaign) {
    switch (campaign.status) {
      case CampaignStatus.draft:
        return Column(
          children: [
            // Primary action: Send Now
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _confirmSendNow(campaign),
                icon: const Icon(LucideIcons.send, size: 18),
                label: const Text('Send Now'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Secondary actions row
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showScheduleDialog(campaign),
                    icon: const Icon(LucideIcons.calendar, size: 18),
                    label: const Text('Schedule'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showSendTestDialog(campaign),
                    icon: const Icon(LucideIcons.mailCheck, size: 18),
                    label: const Text('Send Test'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );

      case CampaignStatus.scheduled:
        return Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _confirmSendNow(campaign),
                icon: const Icon(LucideIcons.send, size: 18),
                label: const Text('Send Now'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showScheduleDialog(campaign),
                    icon: const Icon(LucideIcons.calendar, size: 18),
                    label: const Text('Reschedule'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _confirmStop(campaign),
                    icon: const Icon(LucideIcons.circleStop, size: 18),
                    label: const Text('Cancel'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );

      case CampaignStatus.inProgress:
        return Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pauseCampaign(campaign),
                icon: const Icon(LucideIcons.pause, size: 18),
                label: const Text('Pause'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orange,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _confirmStop(campaign),
                icon: const Icon(LucideIcons.circleStop, size: 18),
                label: const Text('Stop'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        );

      case CampaignStatus.paused:
        return Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _resumeCampaign(campaign),
                icon: const Icon(LucideIcons.play, size: 18),
                label: const Text('Resume'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _confirmStop(campaign),
                icon: const Icon(LucideIcons.circleStop, size: 18),
                label: const Text('Stop'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        );

      case CampaignStatus.completed:
      case CampaignStatus.stopped:
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              // Could implement duplicate/clone functionality
              _showMessage('Duplicate campaign feature coming soon');
            },
            icon: const Icon(LucideIcons.copy, size: 18),
            label: const Text('Duplicate Campaign'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        );
    }
  }

  Future<void> _confirmSendNow(Campaign campaign) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send Campaign Now?'),
        content: Text(
          'This will immediately start sending "${campaign.name}" to ${campaign.contactCount ?? 0} recipients.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send Now'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _sendNow(campaign);
    }
  }

  Future<void> _sendNow(Campaign campaign) async {
    setState(() => _isLoading = true);
    try {
      final result = await _campaignsService.sendNow(campaign.id);
      if (!mounted) return;
      setState(() {
        _campaign = result.campaign;
      });
      _showMessage(result.message);
      // Refresh campaigns list
      ref.invalidate(campaignsProvider);
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to send campaign: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showScheduleDialog(Campaign campaign) async {
    DateTime selectedDate = DateTime.now().add(const Duration(hours: 1));
    TimeOfDay selectedTime = TimeOfDay.fromDateTime(selectedDate);

    final result = await showDialog<DateTime>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Schedule Campaign'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(LucideIcons.calendar),
                title: Text(DateFormat('MMMM d, yyyy').format(selectedDate)),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date != null) {
                    setDialogState(() {
                      selectedDate = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        selectedTime.hour,
                        selectedTime.minute,
                      );
                    });
                  }
                },
              ),
              ListTile(
                leading: const Icon(LucideIcons.clock),
                title: Text(selectedTime.format(context)),
                onTap: () async {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: selectedTime,
                  );
                  if (time != null) {
                    setDialogState(() {
                      selectedTime = time;
                      selectedDate = DateTime(
                        selectedDate.year,
                        selectedDate.month,
                        selectedDate.day,
                        time.hour,
                        time.minute,
                      );
                    });
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selectedDate),
              child: const Text('Schedule'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      await _scheduleCampaign(campaign, result);
    }
  }

  Future<void> _scheduleCampaign(Campaign campaign, DateTime scheduledAt) async {
    setState(() => _isLoading = true);
    try {
      final result = await _campaignsService.scheduleCampaign(campaign.id, scheduledAt);
      if (!mounted) return;
      setState(() {
        _campaign = result.campaign;
      });
      _showMessage(result.message);
      ref.invalidate(campaignsProvider);
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to schedule campaign: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showSendTestDialog(Campaign campaign) async {
    final emailController = TextEditingController();

    final email = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send Test Email'),
        content: TextField(
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Email Address',
            hintText: 'Enter your email',
            prefixIcon: Icon(LucideIcons.mail),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, emailController.text),
            child: const Text('Send Test'),
          ),
        ],
      ),
    );

    if (email != null && email.isNotEmpty) {
      await _sendTestEmail(campaign, email);
    }
  }

  Future<void> _sendTestEmail(Campaign campaign, String email) async {
    setState(() => _isLoading = true);
    try {
      final message = await _campaignsService.sendTestEmail(campaign.id, email);
      if (!mounted) return;
      _showMessage(message);
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to send test email: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _confirmStop(Campaign campaign) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop Campaign?'),
        content: const Text(
          'This will stop the campaign and it cannot be restarted. Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Stop'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _stopCampaign(campaign);
    }
  }

  Future<void> _stopCampaign(Campaign campaign) async {
    setState(() => _isLoading = true);
    try {
      final result = await _campaignsService.stopCampaign(campaign.id);
      if (!mounted) return;
      setState(() {
        _campaign = result.campaign;
      });
      _showMessage(result.message);
      ref.invalidate(campaignsProvider);
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to stop campaign: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pauseCampaign(Campaign campaign) async {
    setState(() => _isLoading = true);
    try {
      final updated = await _campaignsService.pauseCampaign(campaign.id);
      if (!mounted) return;
      setState(() {
        _campaign = updated;
      });
      _showMessage('Campaign paused');
      ref.invalidate(campaignsProvider);
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to pause campaign: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _resumeCampaign(Campaign campaign) async {
    setState(() => _isLoading = true);
    try {
      final updated = await _campaignsService.resumeCampaign(campaign.id);
      if (!mounted) return;
      setState(() {
        _campaign = updated;
      });
      _showMessage('Campaign resumed');
      ref.invalidate(campaignsProvider);
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to resume campaign: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.red,
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
