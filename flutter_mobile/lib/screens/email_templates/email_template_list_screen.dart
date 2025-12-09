import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/email_template.dart';
import 'package:amos_mobile/services/email_templates_service.dart';
import 'package:amos_mobile/utils/logger.dart';
import 'package:intl/intl.dart';

class EmailTemplateListScreen extends ConsumerStatefulWidget {
  const EmailTemplateListScreen({super.key});

  @override
  ConsumerState<EmailTemplateListScreen> createState() => _EmailTemplateListScreenState();
}

class _EmailTemplateListScreenState extends ConsumerState<EmailTemplateListScreen> {
  final EmailTemplatesService _emailTemplatesService = EmailTemplatesService();
  final _searchController = TextEditingController();
  List<EmailTemplate> _templates = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTemplates();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates({String? search}) async {
    AppLogger.info('EmailTemplateListScreen: Loading email templates from API');
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final templates = await _emailTemplatesService.getEmailTemplates(search: search);
      if (!mounted) return;
      setState(() => _templates = templates);
      AppLogger.info('EmailTemplateListScreen: Loaded ${templates.length} email templates');
    } catch (e, stackTrace) {
      AppLogger.error('EmailTemplateListScreen: Failed to load templates', error: e, stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _errorMessage = 'Failed to load email templates. Pull to retry.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteTemplate(EmailTemplate template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Template'),
        content: Text('Are you sure you want to delete "${template.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _emailTemplatesService.deleteEmailTemplate(template.id);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Template deleted')),
      );
      _loadTemplates();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete template: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _navigateToCreateTemplate() {
    context.push('/chat?prompt=${Uri.encodeComponent("I want to create a new email template")}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
        title: const Text('Email Templates'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.plus),
            onPressed: _navigateToCreateTemplate,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search templates...',
                prefixIcon: const Icon(LucideIcons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (value) {
                _loadTemplates(search: value.isNotEmpty ? value : null);
              },
            ),
          ),

          // Template List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? _buildErrorState()
                    : _templates.isEmpty
                        ? _buildEmptyState()
                        : RefreshIndicator(
                            onRefresh: _loadTemplates,
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _templates.length,
                              itemBuilder: (context, index) {
                                final template = _templates[index];
                                return _EmailTemplateCard(
                                  template: template,
                                  onTap: () => context.pushNamed(
                                    'email-template-detail',
                                    pathParameters: {'id': template.id},
                                  ),
                                  onDelete: () => _deleteTemplate(template),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.circleX,
              size: 64,
              color: Colors.red.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'An error occurred',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.textSecondary,
                  ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadTemplates,
              icon: const Icon(LucideIcons.refreshCw),
              label: const Text('Retry'),
            ),
          ],
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
              LucideIcons.fileText,
              size: 64,
              color: context.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              'No Email Templates',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Create reusable email templates for your campaigns.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.textSecondary,
                  ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _navigateToCreateTemplate,
              icon: const Icon(LucideIcons.plus),
              label: const Text('Create Template'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmailTemplateCard extends StatelessWidget {
  final EmailTemplate template;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _EmailTemplateCard({
    required this.template,
    required this.onTap,
    required this.onDelete,
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
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: context.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      LucideIcons.fileText,
                      color: context.primaryColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          template.name,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(
                          template.subject,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: context.textSecondary,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(LucideIcons.ellipsisVertical, color: context.textTertiary),
                    onSelected: (value) {
                      if (value == 'delete') {
                        onDelete();
                      } else if (value == 'use') {
                        context.push('/chat?prompt=${Uri.encodeComponent("I want to use the email template '${template.name}' for a campaign")}');
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'use',
                        child: Row(
                          children: [
                            Icon(LucideIcons.send, size: 16),
                            SizedBox(width: 8),
                            Text('Use in Campaign'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(LucideIcons.trash2, size: 16, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Delete', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                template.bodyPreview,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.textTertiary,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (template.campaignsCount > 0) ...[
                    Icon(LucideIcons.mail, size: 14, color: context.textTertiary),
                    const SizedBox(width: 4),
                    Text(
                      '${template.campaignsCount} campaign${template.campaignsCount == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: context.textTertiary,
                          ),
                    ),
                    const SizedBox(width: 16),
                  ],
                  const Spacer(),
                  Text(
                    dateFormat.format(template.createdAt),
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
