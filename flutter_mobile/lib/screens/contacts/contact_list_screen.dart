import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/contact.dart';
import 'package:amos_mobile/providers/app_providers.dart';

class ContactListScreen extends ConsumerStatefulWidget {
  const ContactListScreen({super.key});

  @override
  ConsumerState<ContactListScreen> createState() => _ContactListScreenState();
}

class _ContactListScreenState extends ConsumerState<ContactListScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    ref.read(contactsLoadingProvider.notifier).setLoading(true);
    // TODO: Implement actual API call
    await Future.delayed(const Duration(milliseconds: 500));

    // Mock data
    ref.read(contactsProvider.notifier).setContacts([
      Contact(
        id: '1',
        entityId: 'e1',
        email: 'john.doe@example.com',
        status: ContactStatus.active,
        name: 'John Doe',
        company: 'Acme Inc',
        createdAt: DateTime.now().subtract(const Duration(days: 30)),
        updatedAt: DateTime.now(),
      ),
      Contact(
        id: '2',
        entityId: 'e1',
        email: 'jane.smith@example.com',
        status: ContactStatus.active,
        name: 'Jane Smith',
        company: 'Tech Corp',
        createdAt: DateTime.now().subtract(const Duration(days: 20)),
        updatedAt: DateTime.now(),
      ),
      Contact(
        id: '3',
        entityId: 'e1',
        email: 'bob.wilson@example.com',
        status: ContactStatus.inactive,
        name: 'Bob Wilson',
        createdAt: DateTime.now().subtract(const Duration(days: 15)),
        updatedAt: DateTime.now(),
      ),
      Contact(
        id: '4',
        entityId: 'e1',
        email: 'sarah.johnson@example.com',
        status: ContactStatus.unsubscribed,
        name: 'Sarah Johnson',
        company: 'StartUp Co',
        createdAt: DateTime.now().subtract(const Duration(days: 10)),
        updatedAt: DateTime.now(),
      ),
    ]);

    ref.read(contactsLoadingProvider.notifier).setLoading(false);
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
            icon: const Icon(LucideIcons.userPlus),
            onPressed: () {
              // TODO: Add contact
            },
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
                // TODO: Filter contacts
              },
            ),
          ),

          // Contact List
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
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
              onPressed: () {
                // TODO: Add contact
              },
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
