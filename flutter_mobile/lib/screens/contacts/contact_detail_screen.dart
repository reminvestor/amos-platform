import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/contact.dart';
import 'package:amos_mobile/providers/app_providers.dart';
import 'package:intl/intl.dart';

class ContactDetailScreen extends ConsumerWidget {
  final String id;

  const ContactDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(contactsProvider);
    final contact = contacts.firstWhere(
      (c) => c.id == id,
      orElse: () => Contact(
        id: id,
        entityId: '',
        email: 'unknown@example.com',
        status: ContactStatus.active,
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
        title: const Text('Contact Details'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.pencil),
            onPressed: () {
              // TODO: Edit contact
            },
          ),
          IconButton(
            icon: const Icon(LucideIcons.ellipsisVertical),
            onPressed: () {
              // TODO: More actions
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
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
                      contact.initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    contact.displayName,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    contact.email,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: context.textSecondary,
                        ),
                  ),
                  if (contact.company != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      contact.company!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: context.textTertiary,
                          ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _StatusBadge(status: contact.status),
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
                      onPressed: () {
                        // TODO: Send email
                      },
                      icon: const Icon(LucideIcons.mail),
                      label: const Text('Email'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        // TODO: Add to campaign
                      },
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
                        value: contact.email,
                      ),
                      if (contact.company != null) ...[
                        const Divider(),
                        _InfoRow(
                          icon: LucideIcons.building,
                          label: 'Company',
                          value: contact.company!,
                        ),
                      ],
                      const Divider(),
                      _InfoRow(
                        icon: LucideIcons.calendar,
                        label: 'Added',
                        value: DateFormat('MMM d, yyyy')
                            .format(contact.createdAt),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
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

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
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
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
