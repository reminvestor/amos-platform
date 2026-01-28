import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/contact.dart';
import 'package:amos_mobile/services/contact_service.dart';
import 'package:amos_mobile/services/business_card_scanner_service.dart';
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
  final _scanner = BusinessCardScannerService();
  String _searchQuery = '';
  bool _isScanning = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _scanBusinessCard() async {
    // Show source picker
    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(LucideIcons.camera),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: const Icon(LucideIcons.image),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
          ],
        ),
      ),
    );

    if (source == null || !mounted) return;

    // Pick image
    File? imageFile;
    if (source == 'camera') {
      imageFile = await _scanner.pickFromCamera();
    } else {
      imageFile = await _scanner.pickFromGallery();
    }

    if (imageFile == null || !mounted) return;

    // Show scanning indicator
    setState(() => _isScanning = true);

    try {
      final result = await _scanner.scanBusinessCard(imageFile);

      if (!mounted) return;
      setState(() => _isScanning = false);

      if (result.isSuccess && result.contact != null) {
        _showScannedContactSheet(result.contact!, imageFile);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? 'Failed to scan business card'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isScanning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showScannedContactSheet(ExtractedContact contact, File imageFile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => _ScannedContactSheet(
          contact: contact,
          imageFile: imageFile,
          onSave: () async {
            Navigator.pop(context);
            setState(() => _isScanning = true);

            try {
              final result = await _scanner.scanAndSaveContact(imageFile);

              if (!mounted) return;
              setState(() => _isScanning = false);

              if (result.isSuccess) {
                ref.invalidate(contactsProvider(_searchQuery));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Contact saved successfully!'),
                    backgroundColor: Colors.green,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(result.error ?? 'Failed to save contact'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            } catch (e) {
              if (mounted) {
                setState(() => _isScanning = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                );
              }
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contactsAsync = ref.watch(contactsProvider(_searchQuery));

    return Scaffold(
      appBar: BrandedAppBar(
        title: 'Contacts',
        showBackButton: true,
        actions: [
          IconButton(
            icon: _isScanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(LucideIcons.camera, size: 22),
            onPressed: _isScanning ? null : _scanBusinessCard,
            tooltip: 'Scan Business Card',
          ),
        ],
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

/// Bottom sheet to display scanned business card data
class _ScannedContactSheet extends StatelessWidget {
  final ExtractedContact contact;
  final File imageFile;
  final VoidCallback onSave;

  const _ScannedContactSheet({
    required this.contact,
    required this.imageFile,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Handle bar
        Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(2),
          ),
        ),

        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Icon(LucideIcons.scan, size: 24),
              const SizedBox(width: 12),
              Text(
                'Scanned Contact',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),

        const Divider(height: 24),

        // Scrollable content
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              // Card preview
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  imageFile,
                  height: 150,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 20),

              // Extracted info
              _InfoRow(
                icon: LucideIcons.user,
                label: 'Name',
                value: contact.displayName,
              ),
              if (contact.title != null)
                _InfoRow(
                  icon: LucideIcons.briefcase,
                  label: 'Title',
                  value: contact.title!,
                ),
              if (contact.company != null)
                _InfoRow(
                  icon: LucideIcons.building2,
                  label: 'Company',
                  value: contact.company!,
                ),
              if (contact.email != null)
                _InfoRow(
                  icon: LucideIcons.mail,
                  label: 'Email',
                  value: contact.email!,
                ),
              if (contact.bestPhone != null)
                _InfoRow(
                  icon: LucideIcons.phone,
                  label: 'Phone',
                  value: contact.bestPhone!,
                ),
              if (contact.website != null)
                _InfoRow(
                  icon: LucideIcons.globe,
                  label: 'Website',
                  value: contact.website!,
                ),
              if (contact.address != null)
                _InfoRow(
                  icon: LucideIcons.mapPin,
                  label: 'Address',
                  value: contact.address!,
                ),
              if (contact.linkedin != null)
                _InfoRow(
                  icon: LucideIcons.linkedin,
                  label: 'LinkedIn',
                  value: contact.linkedin!,
                ),

              const SizedBox(height: 24),
            ],
          ),
        ),

        // Action buttons
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: contact.hasMinimumData ? onSave : null,
                  icon: const Icon(LucideIcons.userPlus, size: 18),
                  label: const Text('Save Contact'),
                ),
              ),
            ],
          ),
        ),
      ],
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: context.textTertiary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: context.textTertiary,
                      ),
                ),
                const SizedBox(height: 2),
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
