import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/campaign.dart';
import 'package:amos_mobile/services/campaigns_service.dart';
import 'package:amos_mobile/utils/logger.dart';

class CampaignFormScreen extends ConsumerStatefulWidget {
  final String? campaignId; // null for create, id for edit

  const CampaignFormScreen({super.key, this.campaignId});

  @override
  ConsumerState<CampaignFormScreen> createState() => _CampaignFormScreenState();
}

class _CampaignFormScreenState extends ConsumerState<CampaignFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _campaignsService = CampaignsService();

  final _nameController = TextEditingController();
  final _subjectController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _contentController = TextEditingController();

  String _status = 'draft';
  DateTime? _scheduledAt;
  bool _isLoading = false;
  bool _isSaving = false;
  Campaign? _existingCampaign;

  bool get isEditing => widget.campaignId != null;

  @override
  void initState() {
    super.initState();
    if (isEditing) {
      _loadCampaign();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _subjectController.dispose();
    _descriptionController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _loadCampaign() async {
    setState(() => _isLoading = true);
    try {
      final campaign = await _campaignsService.getCampaign(widget.campaignId!);
      if (mounted) {
        setState(() {
          _existingCampaign = campaign;
          _nameController.text = campaign.name;
          _subjectController.text = campaign.subject;
          _descriptionController.text = campaign.description ?? '';
          _contentController.text = campaign.content ?? '';
          _status = campaign.status.name;
          _scheduledAt = campaign.scheduledAt;
          _isLoading = false;
        });
      }
    } catch (e) {
      AppLogger.error('Failed to load campaign', error: e);
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load campaign: $e')),
        );
        context.pop();
      }
    }
  }

  Future<void> _saveCampaign() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      if (isEditing) {
        await _campaignsService.updateCampaign(
          id: widget.campaignId!,
          name: _nameController.text.trim(),
          subject: _subjectController.text.trim(),
          description: _descriptionController.text.trim().isNotEmpty
              ? _descriptionController.text.trim()
              : null,
          content: _contentController.text.trim().isNotEmpty
              ? _contentController.text.trim()
              : null,
          status: _status,
          scheduledAt: _status == 'scheduled' ? _scheduledAt : null,
        );
      } else {
        await _campaignsService.createCampaign(
          name: _nameController.text.trim(),
          subject: _subjectController.text.trim(),
          content: _contentController.text.trim().isNotEmpty
              ? _contentController.text.trim()
              : null,
          status: _status,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEditing
                ? 'Campaign updated successfully'
                : 'Campaign created successfully'),
          ),
        );
        context.pop(true); // Return true to indicate success
      }
    } catch (e) {
      AppLogger.error('Failed to save campaign', error: e);
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save campaign: $e')),
        );
      }
    }
  }

  Future<void> _selectScheduledDate() async {
    final now = DateTime.now();
    final initialDate = _scheduledAt ?? now.add(const Duration(days: 1));

    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );

    if (date != null && mounted) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_scheduledAt ?? initialDate),
      );

      if (time != null && mounted) {
        setState(() {
          _scheduledAt = DateTime(
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute,
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
        title: Text(isEditing ? 'Edit Campaign' : 'New Campaign'),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(LucideIcons.check),
              onPressed: _saveCampaign,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Campaign Name
                    _buildSectionLabel('Campaign Name *'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        hintText: 'e.g., Summer Sale Newsletter',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        prefixIcon: const Icon(LucideIcons.tag),
                      ),
                      textCapitalization: TextCapitalization.words,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Campaign name is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    // Email Subject
                    _buildSectionLabel('Email Subject *'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _subjectController,
                      decoration: InputDecoration(
                        hintText: 'e.g., Don\'t miss our summer sale!',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        prefixIcon: const Icon(LucideIcons.mail),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Email subject is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    // Description
                    _buildSectionLabel('Description'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _descriptionController,
                      decoration: InputDecoration(
                        hintText: 'Brief description of this campaign\'s purpose',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignLabelWithHint: true,
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 24),

                    // Email Content
                    _buildSectionLabel('Email Content'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _contentController,
                      decoration: InputDecoration(
                        hintText: 'Write your email content here...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignLabelWithHint: true,
                      ),
                      maxLines: 8,
                    ),
                    const SizedBox(height: 24),

                    // Status
                    _buildSectionLabel('Status'),
                    const SizedBox(height: 8),
                    _buildStatusSelector(),
                    const SizedBox(height: 24),

                    // Scheduled Date (only shown when status is scheduled)
                    if (_status == 'scheduled') ...[
                      _buildSectionLabel('Schedule Date & Time'),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: _selectScheduledDate,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            border: Border.all(color: context.borderColor),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                LucideIcons.calendar,
                                color: context.textSecondary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _scheduledAt != null
                                      ? _formatDateTime(_scheduledAt!)
                                      : 'Select date and time',
                                  style: TextStyle(
                                    color: _scheduledAt != null
                                        ? null
                                        : context.textTertiary,
                                  ),
                                ),
                              ),
                              Icon(
                                LucideIcons.chevronRight,
                                color: context.textTertiary,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveCampaign,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(
                                isEditing ? 'Update Campaign' : 'Create Campaign',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
    );
  }

  Widget _buildStatusSelector() {
    return Row(
      children: [
        _buildStatusChip('draft', 'Draft', LucideIcons.filePen),
        const SizedBox(width: 12),
        _buildStatusChip('scheduled', 'Scheduled', LucideIcons.clock),
      ],
    );
  }

  Widget _buildStatusChip(String value, String label, IconData icon) {
    final isSelected = _status == value;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _status = value),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: isSelected
                ? context.primaryColor.withOpacity(0.1)
                : Colors.transparent,
            border: Border.all(
              color: isSelected ? context.primaryColor : context.borderColor,
              width: isSelected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? context.primaryColor : context.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? context.primaryColor : context.textSecondary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final hour = dateTime.hour > 12 ? dateTime.hour - 12 : dateTime.hour;
    final period = dateTime.hour >= 12 ? 'PM' : 'AM';
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '${months[dateTime.month - 1]} ${dateTime.day}, ${dateTime.year} at ${hour == 0 ? 12 : hour}:$minute $period';
  }
}
