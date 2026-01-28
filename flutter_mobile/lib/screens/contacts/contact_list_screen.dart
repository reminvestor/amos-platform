import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/contact.dart';
import 'package:amos_mobile/services/contact_service.dart';
import 'package:amos_mobile/widgets/branded_app_bar.dart';

final contactServiceProvider = Provider((ref) => ContactService());

final contactsProvider = FutureProvider.autoDispose
    .family<ContactsResponse, String>((ref, search) async {
  final service = ref.watch(contactServiceProvider);
  return service.getContacts(search: search.isEmpty ? null : search);
});

class ContactListScreen extends ConsumerStatefulWidget {
  const ContactListScreen({super.key});

  @override
  ConsumerState<ContactListScreen> createState() => _ContactListScreenState();
}

class _ContactListScreenState extends ConsumerState<ContactListScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contactsAsync = ref.watch(contactsProvider(_searchQuery));

    return Scaffold(
      appBar: const BrandedAppBar(
        title: 'Contacts',
        showBackButton: true,
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search contacts...',
                prefixIcon: Icon(
                  LucideIcons.search,
                  color: context.textTertiary,
                  size: 20,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          LucideIcons.x,
                          color: context.textTertiary,
                          size: 18,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: context.surfaceColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.primaryColor),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
              },
            ),
          ),

          // Contacts list
          Expanded(
            child: contactsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      LucideIcons.circleAlert,
                      size: 48,
                      color: context.textTertiary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Failed to load contacts',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: context.textSecondary,
                          ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => ref.invalidate(contactsProvider(_searchQuery)),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (response) {
                if (response.data.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          LucideIcons.users,
                          size: 48,
                          color: context.textTertiary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isEmpty
                              ? 'No contacts yet'
                              : 'No contacts found',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: context.textSecondary,
                              ),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(contactsProvider(_searchQuery));
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: response.data.length,
                    itemBuilder: (context, index) {
                      final contact = response.data[index];
                      return _ContactCard(contact: contact);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  final Contact contact;

  const _ContactCard({required this.contact});

  @override
  Widget build(BuildContext context) {
    final displayName = contact.name?.isNotEmpty == true
        ? contact.name!
        : contact.email;

    final initials = _getInitials(contact);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: context.primaryColor.withValues(alpha: 0.1),
              child: Text(
                initials,
                style: TextStyle(
                  color: context.primaryColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (contact.name?.isNotEmpty == true) ...[
                    const SizedBox(height: 2),
                    Text(
                      contact.email,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: context.textSecondary,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (contact.groups?.isNotEmpty == true) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: contact.groups!.take(2).map((group) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: context.primaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            group.name,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: context.primaryColor,
                                ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
            _StatusBadge(status: contact.status),
          ],
        ),
      ),
    );
  }

  String _getInitials(Contact contact) {
    if (contact.firstName?.isNotEmpty == true) {
      final first = contact.firstName![0].toUpperCase();
      if (contact.lastName?.isNotEmpty == true) {
        return '$first${contact.lastName![0].toUpperCase()}';
      }
      return first;
    }
    if (contact.email.isNotEmpty) {
      return contact.email[0].toUpperCase();
    }
    return '?';
  }
}

class _StatusBadge extends StatelessWidget {
  final String? status;

  const _StatusBadge({this.status});

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status ?? 'active',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: statusColor,
              fontWeight: FontWeight.w500,
            ),
      ),
    );
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'subscribed':
      case 'active':
        return Colors.green;
      case 'unsubscribed':
        return Colors.red;
      case 'bounced':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
}
