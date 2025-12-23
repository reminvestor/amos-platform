import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/email_template.dart';
import 'package:amos_mobile/services/email_templates_service.dart';
import 'package:amos_mobile/utils/logger.dart';

class EmailTemplateFormScreen extends ConsumerStatefulWidget {
  final String? templateId; // null for create, set for edit

  const EmailTemplateFormScreen({super.key, this.templateId});

  bool get isEditing => templateId != null;

  @override
  ConsumerState<EmailTemplateFormScreen> createState() => _EmailTemplateFormScreenState();
}

class _EmailTemplateFormScreenState extends ConsumerState<EmailTemplateFormScreen> {
  final EmailTemplatesService _emailTemplatesService = EmailTemplatesService();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _subjectController = TextEditingController();
  final _bodyController = TextEditingController();

  bool _isLoading = false;
  bool _isLoadingTemplate = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.isEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadTemplate();
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _loadTemplate() async {
    if (widget.templateId == null) return;

    AppLogger.info('EmailTemplateFormScreen: Loading template ${widget.templateId}');
    setState(() {
      _isLoadingTemplate = true;
      _errorMessage = null;
    });

    try {
      final template = await _emailTemplatesService.getEmailTemplate(widget.templateId!);
      if (!mounted) return;

      _nameController.text = template.name;
      _subjectController.text = template.subject;
      _bodyController.text = template.body;

      AppLogger.info('EmailTemplateFormScreen: Loaded template "${template.name}"');
    } catch (e, stackTrace) {
      AppLogger.error('EmailTemplateFormScreen: Failed to load template', error: e, stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _errorMessage = 'Failed to load template');
    } finally {
      if (mounted) {
        setState(() => _isLoadingTemplate = false);
      }
    }
  }

  Future<void> _saveTemplate() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      EmailTemplate template;

      if (widget.isEditing) {
        template = await _emailTemplatesService.updateEmailTemplate(
          widget.templateId!,
          name: _nameController.text.trim(),
          subject: _subjectController.text.trim(),
          body: _bodyController.text.trim(),
        );
        AppLogger.info('EmailTemplateFormScreen: Updated template "${template.name}"');
      } else {
        template = await _emailTemplatesService.createEmailTemplate(
          name: _nameController.text.trim(),
          subject: _subjectController.text.trim(),
          body: _bodyController.text.trim(),
        );
        AppLogger.info('EmailTemplateFormScreen: Created template "${template.name}"');
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.isEditing ? 'Template updated' : 'Template created'),
        ),
      );

      // Navigate back and trigger refresh
      context.pop(true);
    } catch (e, stackTrace) {
      AppLogger.error('EmailTemplateFormScreen: Failed to save template', error: e, stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _errorMessage = 'Failed to save template: ${e.toString()}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _duplicateTemplate() async {
    if (widget.templateId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Duplicate Template'),
        content: const Text('Create a copy of this template?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Duplicate'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      final newTemplate = await _emailTemplatesService.duplicateEmailTemplate(widget.templateId!);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Created "${newTemplate.name}"')),
      );

      // Navigate to edit the new template
      context.pushReplacementNamed(
        'email-template-edit',
        pathParameters: {'id': newTemplate.id},
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to duplicate: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
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
        title: Text(widget.isEditing ? 'Edit Template' : 'New Template'),
        actions: [
          if (widget.isEditing)
            IconButton(
              icon: const Icon(LucideIcons.copy),
              onPressed: _isLoading ? null : _duplicateTemplate,
              tooltip: 'Duplicate',
            ),
        ],
      ),
      body: _isLoadingTemplate
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null && widget.isEditing
              ? _buildErrorState()
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Name Field
                      Text(
                        'Template Name',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          hintText: 'e.g., Welcome Email',
                          prefixIcon: const Icon(LucideIcons.fileText),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a template name';
                          }
                          return null;
                        },
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 24),

                      // Subject Field
                      Text(
                        'Subject Line',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _subjectController,
                        decoration: InputDecoration(
                          hintText: 'e.g., Welcome to {{company_name}}!',
                          prefixIcon: const Icon(LucideIcons.type),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          helperText: 'Use {{variable}} for personalization',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a subject line';
                          }
                          return null;
                        },
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 24),

                      // Body Field
                      Row(
                        children: [
                          Text(
                            'Email Body',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () => _showVariablesHelp(context),
                            icon: const Icon(LucideIcons.info, size: 16),
                            label: const Text('Variables'),
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _bodyController,
                        decoration: InputDecoration(
                          hintText: 'Write your email content here...',
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        maxLines: 12,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter email content';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 32),

                      // Save Button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _saveTemplate,
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Icon(widget.isEditing ? LucideIcons.save : LucideIcons.plus),
                          label: Text(widget.isEditing ? 'Save Changes' : 'Create Template'),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
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
              _errorMessage ?? 'Failed to load template',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.textSecondary,
                  ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadTemplate,
              icon: const Icon(LucideIcons.refreshCw),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  void _showVariablesHelp(BuildContext context) {
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
            Row(
              children: [
                Text(
                  'Available Variables',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(LucideIcons.x),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Use these variables in your subject or body:',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.textSecondary,
                  ),
            ),
            const SizedBox(height: 16),
            _VariableItem(
              variable: '{{first_name}}',
              description: "Contact's first name",
            ),
            _VariableItem(
              variable: '{{last_name}}',
              description: "Contact's last name",
            ),
            _VariableItem(
              variable: '{{email}}',
              description: "Contact's email address",
            ),
            _VariableItem(
              variable: '{{company_name}}',
              description: 'Your company name',
            ),
            _VariableItem(
              variable: '{{unsubscribe_link}}',
              description: 'Link to unsubscribe',
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _VariableItem extends StatelessWidget {
  final String variable;
  final String description;

  const _VariableItem({
    required this.variable,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: context.primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              variable,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: context.primaryColor,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.textSecondary,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
