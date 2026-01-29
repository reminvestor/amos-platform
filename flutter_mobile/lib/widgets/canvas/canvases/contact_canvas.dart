import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/canvas.dart';
import 'package:amos_mobile/services/canvas_service.dart';
import 'package:amos_mobile/utils/logger.dart';

/// Canvas for displaying a list of contacts
class ContactListCanvas extends ConsumerStatefulWidget {
  final Canvas canvas;

  const ContactListCanvas({super.key, required this.canvas});

  @override
  ConsumerState<ContactListCanvas> createState() => _ContactListCanvasState();
}

class _ContactListCanvasState extends ConsumerState<ContactListCanvas> {
  final _canvasService = CanvasService();
  List<Map<String, dynamic>> _contacts = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final contacts = await _canvasService.fetchResourceList(
        resourceType: 'contacts',
        filters: widget.canvas.data.isNotEmpty ? widget.canvas.data : null,
      );
      setState(() {
        _contacts = contacts;
        _isLoading = false;
      });
    } catch (e) {
      AppLogger.error('Failed to load contacts', error: e);
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

    if (_contacts.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _loadContacts,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _contacts.length,
        itemBuilder: (context, index) {
          return _ContactCard(
            contact: _contacts[index],
            onTap: () => _openContact(_contacts[index]),
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
            LucideIcons.users,
            size: 48,
            color: context.textTertiary,
          ),
          const SizedBox(height: 16),
          Text(
            'No contacts yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Add contacts to get started',
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
            'Failed to load contacts',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _loadContacts,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  void _openContact(Map<String, dynamic> contact) {
    final id = contact['id'];
    if (id != null) {
      context.push('/contacts/$id');
    }
  }
}

class _ContactCard extends StatelessWidget {
  final Map<String, dynamic> contact;
  final VoidCallback onTap;

  const _ContactCard({
    required this.contact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final firstName = contact['first_name'] ?? '';
    final lastName = contact['last_name'] ?? '';
    final name = '$firstName $lastName'.trim();
    final email = contact['email'] ?? '';
    final company = contact['company'] ?? contact['organization'];
    final tags = (contact['tags'] as List?)?.cast<String>() ?? [];
    final avatarUrl = contact['avatar_url'];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 24,
                backgroundColor: context.primaryColor.withOpacity(0.1),
                backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                child: avatarUrl == null
                    ? Text(
                        _getInitials(name.isNotEmpty ? name : email),
                        style: TextStyle(
                          color: context.primaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : null,
              ),

              const SizedBox(width: 12),

              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isNotEmpty ? name : email,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (name.isNotEmpty && email.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        email,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: context.textSecondary,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (company != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            LucideIcons.building,
                            size: 12,
                            color: context.textTertiary,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              company,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: context.textTertiary,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (tags.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: tags.take(3).map((tag) => _TagChip(tag: tag)).toList(),
                      ),
                    ],
                  ],
                ),
              ),

              // Arrow
              Icon(
                LucideIcons.chevronRight,
                size: 20,
                color: context.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getInitials(String text) {
    final parts = text.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (parts.isNotEmpty && parts[0].isNotEmpty) {
      return parts[0][0].toUpperCase();
    }
    return '?';
  }
}

class _TagChip extends StatelessWidget {
  final String tag;

  const _TagChip({required this.tag});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: context.primaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        tag,
        style: TextStyle(
          fontSize: 10,
          color: context.primaryColor,
        ),
      ),
    );
  }
}

/// Canvas for displaying a single contact's details
class ContactDetailCanvas extends ConsumerStatefulWidget {
  final Canvas canvas;

  const ContactDetailCanvas({super.key, required this.canvas});

  @override
  ConsumerState<ContactDetailCanvas> createState() => _ContactDetailCanvasState();
}

class _ContactDetailCanvasState extends ConsumerState<ContactDetailCanvas> {
  final _canvasService = CanvasService();
  Map<String, dynamic>? _contact;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadContact();
  }

  Future<void> _loadContact() async {
    final contactId = widget.canvas.getData<dynamic>('contact_id')?.toString();
    if (contactId == null) {
      setState(() {
        _error = 'No contact ID provided';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final contact = await _canvasService.fetchResourceData(
        resourceType: 'contact',
        resourceId: contactId,
      );
      setState(() {
        _contact = contact;
        _isLoading = false;
      });
    } catch (e) {
      AppLogger.error('Failed to load contact', error: e);
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
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.circleAlert, size: 48, color: Colors.red.shade400),
            const SizedBox(height: 16),
            Text(_error!, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _loadContact,
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_contact == null) {
      return const Center(child: Text('Contact not found'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          const SizedBox(height: 24),
          _buildContactInfo(context),
          const SizedBox(height: 24),
          _buildActions(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final firstName = _contact!['first_name'] ?? '';
    final lastName = _contact!['last_name'] ?? '';
    final name = '$firstName $lastName'.trim();
    final email = _contact!['email'] ?? '';
    final avatarUrl = _contact!['avatar_url'];

    return Row(
      children: [
        CircleAvatar(
          radius: 40,
          backgroundColor: context.primaryColor.withOpacity(0.1),
          backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
          child: avatarUrl == null
              ? Text(
                  _getInitials(name.isNotEmpty ? name : email),
                  style: TextStyle(
                    fontSize: 24,
                    color: context.primaryColor,
                    fontWeight: FontWeight.w600,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.isNotEmpty ? name : 'No Name',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              if (email.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  email,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.textSecondary,
                      ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContactInfo(BuildContext context) {
    final phone = _contact!['phone'];
    final company = _contact!['company'] ?? _contact!['organization'];
    final title = _contact!['title'] ?? _contact!['job_title'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Contact Information',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 12),
        if (phone != null) _buildInfoRow(context, LucideIcons.phone, 'Phone', phone),
        if (company != null) _buildInfoRow(context, LucideIcons.building, 'Company', company),
        if (title != null) _buildInfoRow(context, LucideIcons.briefcase, 'Title', title),
      ],
    );
  }

  Widget _buildInfoRow(BuildContext context, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: context.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.textTertiary,
                      ),
                ),
                Text(value, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              // TODO: Send email
            },
            icon: const Icon(LucideIcons.mail, size: 16),
            label: const Text('Email'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: () {
              // TODO: Open chat with context
            },
            icon: const Icon(LucideIcons.messageSquare, size: 16),
            label: const Text('Message'),
          ),
        ),
      ],
    );
  }

  String _getInitials(String text) {
    final parts = text.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (parts.isNotEmpty && parts[0].isNotEmpty) {
      return parts[0][0].toUpperCase();
    }
    return '?';
  }
}
