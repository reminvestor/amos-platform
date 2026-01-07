import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/contact.dart';
import 'package:amos_mobile/services/contact_groups_service.dart';
import 'package:amos_mobile/utils/logger.dart';
import 'package:intl/intl.dart';

class ContactGroupDetailScreen extends ConsumerStatefulWidget {
  final String id;

  const ContactGroupDetailScreen({super.key, required this.id});

  @override
  ConsumerState<ContactGroupDetailScreen> createState() => _ContactGroupDetailScreenState();
}

class _ContactGroupDetailScreenState extends ConsumerState<ContactGroupDetailScreen> {
  final ContactGroupsService _contactGroupsService = ContactGroupsService();
  ContactGroupDetail? _detail;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadGroupDetail();
    });
  }

  Future<void> _loadGroupDetail() async {
    AppLogger.info('ContactGroupDetailScreen: Loading group ${widget.id}');
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final detail = await _contactGroupsService.getContactGroup(widget.id);
      if (!mounted) return;
      setState(() => _detail = detail);
      AppLogger.info('ContactGroupDetailScreen: Loaded group "${detail.group.name}" with ${detail.contacts.length} contacts');
    } catch (e, stackTrace) {
      AppLogger.error('ContactGroupDetailScreen: Failed to load group', error: e, stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _errorMessage = 'Failed to load contact group');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _editGroup() async {
    if (_detail == null) return;

    final nameController = TextEditingController(text: _detail!.group.name);
    final descController = TextEditingController(text: _detail!.group.description ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Group Name',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != true || nameController.text.isEmpty) return;

    try {
      await _contactGroupsService.updateContactGroup(
        widget.id,
        name: nameController.text.trim(),
        description: descController.text.trim().isNotEmpty ? descController.text.trim() : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Group updated')),
      );
      _loadGroupDetail();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update group: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _useToCampaign() {
    if (_detail == null) return;
    final prompt = "Create a campaign for the contact group '${_detail!.group.name}'";
    context.push('/chat?prompt=${Uri.encodeComponent(prompt)}');
  }

  void _importContacts() {
    if (_detail == null) return;
    final prompt = "Import contacts into the group '${_detail!.group.name}'";
    context.push('/chat?prompt=${Uri.encodeComponent(prompt)}');
  }

  Future<void> _removeContact(Contact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Contact'),
        content: Text('Remove "${contact.displayName}" from this group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _contactGroupsService.removeContactsFromGroup(widget.id, [contact.id]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contact removed from group')),
      );
      _loadGroupDetail();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to remove contact: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d, yyyy');

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
        title: Text(_detail?.group.name ?? 'Contact Group'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.pencil),
            onPressed: _detail != null ? _editGroup : null,
          ),
          PopupMenuButton<String>(
            icon: const Icon(LucideIcons.ellipsisVertical),
            onSelected: (value) {
              switch (value) {
                case 'campaign':
                  _useToCampaign();
                  break;
                case 'import':
                  _importContacts();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'campaign',
                child: Row(
                  children: [
                    Icon(LucideIcons.send, size: 16),
                    SizedBox(width: 8),
                    Text('Use in Campaign'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'import',
                child: Row(
                  children: [
                    Icon(LucideIcons.upload, size: 16),
                    SizedBox(width: 8),
                    Text('Import Contacts'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorState()
              : _detail == null
                  ? _buildErrorState()
                  : RefreshIndicator(
                      onRefresh: _loadGroupDetail,
                      child: CustomScrollView(
                        slivers: [
                          // Header Card
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
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
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: context.primaryColor.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Icon(
                                              LucideIcons.users,
                                              color: context.primaryColor,
                                              size: 28,
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  _detail!.group.name,
                                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  '${_detail!.totalCount} contacts',
                                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                        color: context.textSecondary,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (_detail!.group.description != null && _detail!.group.description!.isNotEmpty) ...[
                                        const SizedBox(height: 16),
                                        Text(
                                          _detail!.group.description!,
                                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                color: context.textSecondary,
                                              ),
                                        ),
                                      ],
                                      const SizedBox(height: 16),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: ElevatedButton.icon(
                                              onPressed: _useToCampaign,
                                              icon: const Icon(LucideIcons.send),
                                              label: const Text('Use in Campaign'),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // Contacts Header
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                              child: Row(
                                children: [
                                  Text(
                                    'Contacts',
                                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                  const Spacer(),
                                  TextButton.icon(
                                    onPressed: _importContacts,
                                    icon: const Icon(LucideIcons.plus, size: 16),
                                    label: const Text('Add'),
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Contacts List
                          if (_detail!.contacts.isEmpty)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Center(
                                  child: Column(
                                    children: [
                                      Icon(
                                        LucideIcons.userX,
                                        size: 48,
                                        color: context.textTertiary,
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        'No contacts in this group',
                                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                              color: context.textSecondary,
                                            ),
                                      ),
                                      const SizedBox(height: 16),
                                      ElevatedButton.icon(
                                        onPressed: _importContacts,
                                        icon: const Icon(LucideIcons.upload),
                                        label: const Text('Import Contacts'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          else
                            SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final contact = _detail!.contacts[index];
                                  return _ContactListItem(
                                    contact: contact,
                                    onTap: () => context.pushNamed(
                                      'contact-detail',
                                      pathParameters: {'id': contact.id},
                                    ),
                                    onRemove: () => _removeContact(contact),
                                  );
                                },
                                childCount: _detail!.contacts.length,
                              ),
                            ),

                          // Bottom padding
                          const SliverToBoxAdapter(
                            child: SizedBox(height: 24),
                          ),
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
              _errorMessage ?? 'Failed to load contact group',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.textSecondary,
                  ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadGroupDetail,
              icon: const Icon(LucideIcons.refreshCw),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactListItem extends StatelessWidget {
  final Contact contact;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _ContactListItem({
    required this.contact,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: CircleAvatar(
        backgroundColor: context.primaryColor,
        child: Text(
          contact.initials,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      title: Text(contact.displayName),
      subtitle: Text(
        contact.email,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.textSecondary,
            ),
      ),
      trailing: IconButton(
        icon: Icon(LucideIcons.x, size: 18, color: context.textTertiary),
        onPressed: onRemove,
        tooltip: 'Remove from group',
      ),
      onTap: onTap,
    );
  }
}
