import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/contact.dart';
import 'package:amos_mobile/services/contacts_service.dart';
import 'package:amos_mobile/utils/logger.dart';
import 'package:intl/intl.dart';

class ContactDetailScreen extends ConsumerStatefulWidget {
  final String id;

  const ContactDetailScreen({super.key, required this.id});

  @override
  ConsumerState<ContactDetailScreen> createState() => _ContactDetailScreenState();
}

class _ContactDetailScreenState extends ConsumerState<ContactDetailScreen> {
  final ContactsService _contactsService = ContactsService();
  Contact? _contact;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadContact();
    });
  }

  Future<void> _loadContact() async {
    AppLogger.info('ContactDetailScreen: Loading contact ${widget.id}');
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final contact = await _contactsService.getContact(widget.id);
      if (!mounted) return;
      setState(() => _contact = contact);
      AppLogger.info('ContactDetailScreen: Loaded contact "${contact.displayName}"');
    } catch (e, stackTrace) {
      AppLogger.error('ContactDetailScreen: Failed to load contact', error: e, stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _errorMessage = 'Failed to load contact');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _editContact() async {
    final result = await context.pushNamed(
      'contact-edit',
      pathParameters: {'id': widget.id},
    );
    if (result == true) {
      _loadContact();
    }
  }

  Future<void> _sendEmail() async {
    if (_contact == null) return;

    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: _contact!.email,
    );

    try {
      if (await canLaunchUrl(emailUri)) {
        await launchUrl(emailUri);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open email client')),
        );
      }
    } catch (e) {
      AppLogger.error('Failed to launch email', error: e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open email: $e')),
      );
    }
  }

  void _callPhone() async {
    if (_contact?.phone == null || _contact!.phone!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number available')),
      );
      return;
    }

    final Uri phoneUri = Uri(
      scheme: 'tel',
      path: _contact!.phone,
    );

    try {
      if (await canLaunchUrl(phoneUri)) {
        await launchUrl(phoneUri);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open phone app')),
        );
      }
    } catch (e) {
      AppLogger.error('Failed to launch phone', error: e);
    }
  }

  void _addToCampaign() {
    if (_contact == null) return;
    // Navigate to chat with a prompt to add this contact to a campaign
    final prompt = "Add ${_contact!.displayName} (${_contact!.email}) to a campaign";
    context.push('/chat?prompt=${Uri.encodeComponent(prompt)}');
  }

  void _sendEmailViaScout() {
    if (_contact == null) return;
    // Navigate to chat with a prompt to compose an email
    final prompt = "Send an email to ${_contact!.displayName} at ${_contact!.email}";
    context.push('/chat?prompt=${Uri.encodeComponent(prompt)}');
  }

  Future<void> _deleteContact() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Contact'),
        content: Text('Are you sure you want to delete "${_contact?.displayName}"?'),
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

    if (confirmed != true || _contact == null) return;

    try {
      await _contactsService.deleteContact(_contact!.id);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contact deleted')),
      );
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete contact: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showMoreActions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(LucideIcons.mail),
                title: const Text('Compose Email with Scout'),
                subtitle: const Text('AI-assisted email composition'),
                onTap: () {
                  Navigator.pop(context);
                  _sendEmailViaScout();
                },
              ),
              ListTile(
                leading: const Icon(LucideIcons.send),
                title: const Text('Add to Campaign'),
                subtitle: const Text('Add contact to an email campaign'),
                onTap: () {
                  Navigator.pop(context);
                  _addToCampaign();
                },
              ),
              if (_contact?.phone != null && _contact!.phone!.isNotEmpty)
                ListTile(
                  leading: const Icon(LucideIcons.phone),
                  title: const Text('Call'),
                  subtitle: Text(_contact!.phone!),
                  onTap: () {
                    Navigator.pop(context);
                    _callPhone();
                  },
                ),
              const Divider(),
              ListTile(
                leading: const Icon(LucideIcons.trash2, color: Colors.red),
                title: const Text('Delete Contact', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _deleteContact();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Contact Details'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.pencil),
            onPressed: _contact != null ? _editContact : null,
          ),
          IconButton(
            icon: const Icon(LucideIcons.ellipsisVertical),
            onPressed: _contact != null ? _showMoreActions : null,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorState()
              : _contact == null
                  ? _buildErrorState()
                  : RefreshIndicator(
                      onRefresh: _loadContact,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Column(
                          children: [
                            // Profile Header
                            Container(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                children: [
                                  CircleAvatar(
                                    radius: 48,
                                    backgroundColor: context.primaryColor,
                                    child: Text(
                                      _contact!.initials,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 32,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _contact!.displayName,
                                    style: Theme.of(context).textTheme.headlineSmall,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _contact!.email,
                                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                          color: context.textSecondary,
                                        ),
                                  ),
                                  if (_contact!.company != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      _contact!.company!,
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                            color: context.textTertiary,
                                          ),
                                    ),
                                  ],
                                  const SizedBox(height: 16),
                                  _StatusBadge(status: _contact!.status),
                                ],
                              ),
                            ),

                            // Action Buttons
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _sendEmail,
                                      icon: const Icon(LucideIcons.mail),
                                      label: const Text('Email'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _addToCampaign,
                                      icon: const Icon(LucideIcons.send),
                                      label: const Text('Campaign'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Details Section
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Card(
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
                                      Text(
                                        'Contact Information',
                                        style: Theme.of(context).textTheme.titleMedium,
                                      ),
                                      const SizedBox(height: 16),
                                      _InfoRow(
                                        icon: LucideIcons.mail,
                                        label: 'Email',
                                        value: _contact!.email,
                                        onTap: _sendEmail,
                                      ),
                                      if (_contact!.phone != null && _contact!.phone!.isNotEmpty) ...[
                                        const Divider(),
                                        _InfoRow(
                                          icon: LucideIcons.phone,
                                          label: 'Phone',
                                          value: _contact!.phone!,
                                          onTap: _callPhone,
                                        ),
                                      ],
                                      if (_contact!.company != null) ...[
                                        const Divider(),
                                        _InfoRow(
                                          icon: LucideIcons.building,
                                          label: 'Company',
                                          value: _contact!.company!,
                                        ),
                                      ],
                                      if (_contact!.tags != null && _contact!.tags!.isNotEmpty) ...[
                                        const Divider(),
                                        _InfoRow(
                                          icon: LucideIcons.tag,
                                          label: 'Tags',
                                          value: _contact!.tags!.join(', '),
                                        ),
                                      ],
                                      const Divider(),
                                      _InfoRow(
                                        icon: LucideIcons.calendar,
                                        label: 'Added',
                                        value: DateFormat('MMM d, yyyy')
                                            .format(_contact!.createdAt),
                                      ),
                                      if (_contact!.updatedAt != _contact!.createdAt) ...[
                                        const Divider(),
                                        _InfoRow(
                                          icon: LucideIcons.clock,
                                          label: 'Last Updated',
                                          value: DateFormat('MMM d, yyyy')
                                              .format(_contact!.updatedAt),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
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
              _errorMessage ?? 'Failed to load contact',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.textSecondary,
                  ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadContact,
              icon: const Icon(LucideIcons.refreshCw),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final ContactStatus status;

  const _StatusBadge({required this.status});

  Color _getColor() {
    switch (status) {
      case ContactStatus.active:
        return Colors.green;
      case ContactStatus.inactive:
        return Colors.grey;
      case ContactStatus.unsubscribed:
        return Colors.red;
    }
  }

  String _getLabel() {
    switch (status) {
      case ContactStatus.active:
        return 'Active';
      case ContactStatus.inactive:
        return 'Inactive';
      case ContactStatus.unsubscribed:
        return 'Unsubscribed';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColor();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _getLabel(),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: context.textTertiary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.textSecondary,
                      ),
                ),
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: onTap != null ? context.primaryColor : null,
                      ),
                ),
              ],
            ),
          ),
          if (onTap != null)
            Icon(
              LucideIcons.externalLink,
              size: 16,
              color: context.textTertiary,
            ),
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: content,
      );
    }
    return content;
  }
}
