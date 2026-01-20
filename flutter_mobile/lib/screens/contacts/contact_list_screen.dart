import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/contact.dart';
import 'package:amos_mobile/providers/app_providers.dart';
import 'package:amos_mobile/services/contacts_service.dart';
import 'package:amos_mobile/utils/logger.dart';

class ContactListScreen extends ConsumerStatefulWidget {
  const ContactListScreen({super.key});

  @override
  ConsumerState<ContactListScreen> createState() => _ContactListScreenState();
}

class _ContactListScreenState extends ConsumerState<ContactListScreen> {
  final _searchController = TextEditingController();
  final ContactsService _contactsService = ContactsService();
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Schedule load after first frame to ensure widget is fully mounted
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadContacts();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts({String? search}) async {
    AppLogger.info('ContactListScreen: Loading contacts from API');
    if (!mounted) return;
    try {
      ref.read(contactsLoadingProvider.notifier).setLoading(true);
    } catch (e) {
      AppLogger.error('Error setting loading state', error: e);
    }

    if (!mounted) return;
    setState(() => _errorMessage = null);

    try {
      final contacts = await _contactsService.getContacts(search: search);
      if (!mounted) return;
      ref.read(contactsProvider.notifier).setContacts(contacts);
      AppLogger.info('ContactListScreen: Loaded ${contacts.length} contacts');
    } catch (e, stackTrace) {
      AppLogger.error('ContactListScreen: Failed to load contacts', error: e, stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _errorMessage = 'Failed to load contacts. Pull to retry.');
    } finally {
      if (mounted) {
        ref.read(contactsLoadingProvider.notifier).setLoading(false);
      }
    }
  }

  Color _getStatusColor(ContactStatus status) {
    switch (status) {
      case ContactStatus.active:
        return Colors.green;
      case ContactStatus.inactive:
        return Colors.grey;
      case ContactStatus.unsubscribed:
        return Colors.red;
    }
  }

  void _navigateToCreateContact() {
    // Navigate to Amos chat with a prompt to add a new contact
    context.push('/chat?prompt=${Uri.encodeComponent("I want to add a new contact")}');
  }

  @override
  Widget build(BuildContext context) {
    final contacts = ref.watch(contactsProvider);
    final isLoading = ref.watch(contactsLoadingProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
        title: const Text('Contacts'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.upload),
            onPressed: () => context.push('/contacts/import'),
            tooltip: 'Import CSV',
          ),
          IconButton(
            icon: const Icon(LucideIcons.users),
            onPressed: () => context.pushNamed('contact-groups'),
            tooltip: 'Contact Groups',
          ),
          IconButton(
            icon: const Icon(LucideIcons.userPlus),
            onPressed: _navigateToCreateContact,
            tooltip: 'Add Contact',
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
                hintText: 'Search contacts...',
                prefixIcon: const Icon(LucideIcons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (value) {
                _loadContacts(search: value.isNotEmpty ? value : null);
              },
            ),
          ),

          // Contact List
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? _buildErrorState()
                    : contacts.isEmpty
                        ? _buildEmptyState()
                        : RefreshIndicator(
                            onRefresh: _loadContacts,
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: contacts.length,
                              itemBuilder: (context, index) {
                                final contact = contacts[index];
                                return _ContactCard(
                                  contact: contact,
                                  statusColor: _getStatusColor(contact.status),
                                  onTap: () => context.pushNamed(
                                    'contact-detail',
                                    pathParameters: {'id': contact.id},
                                  ),
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
              onPressed: _loadContacts,
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
              LucideIcons.users,
              size: 64,
              color: context.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              'No Contacts',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Add your first contact to get started.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.textSecondary,
                  ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _navigateToCreateContact,
              icon: const Icon(LucideIcons.userPlus),
              label: const Text('Add Contact'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  final Contact contact;
  final Color statusColor;
  final VoidCallback onTap;

  const _ContactCard({
    required this.contact,
    required this.statusColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.borderColor),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: context.primaryColor.withOpacity(0.1),
                child: Text(
                  contact.initials,
                  style: TextStyle(
                    color: context.primaryColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          contact.displayName,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      contact.email,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: context.textSecondary,
                          ),
                    ),
                    if (contact.company != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        contact.company!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: context.textTertiary,
                            ),
                      ),
                    ],
                  ],
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
    );
  }
}
