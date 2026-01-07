import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/contact.dart';
import 'package:amos_mobile/services/contacts_service.dart';
import 'package:amos_mobile/utils/logger.dart';

class ContactFormScreen extends ConsumerStatefulWidget {
  final String? contactId; // null for create, id for edit

  const ContactFormScreen({super.key, this.contactId});

  @override
  ConsumerState<ContactFormScreen> createState() => _ContactFormScreenState();
}

class _ContactFormScreenState extends ConsumerState<ContactFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _contactsService = ContactsService();

  final _emailController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _companyController = TextEditingController();
  final _phoneController = TextEditingController();
  final _tagsController = TextEditingController();

  ContactStatus _status = ContactStatus.active;
  bool _isLoading = false;
  bool _isSaving = false;
  Contact? _existingContact;

  bool get isEditing => widget.contactId != null;

  @override
  void initState() {
    super.initState();
    if (isEditing) {
      _loadContact();
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _companyController.dispose();
    _phoneController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _loadContact() async {
    setState(() => _isLoading = true);
    try {
      final contact = await _contactsService.getContact(widget.contactId!);
      if (mounted) {
        setState(() {
          _existingContact = contact;
          _emailController.text = contact.email;
          _firstNameController.text = contact.firstName ?? '';
          _lastNameController.text = contact.lastName ?? '';
          _companyController.text = contact.company ?? '';
          _phoneController.text = contact.phone ?? '';
          _tagsController.text = contact.tags?.join(', ') ?? '';
          _status = contact.status;
          _isLoading = false;
        });
      }
    } catch (e) {
      AppLogger.error('Failed to load contact', error: e);
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load contact: $e')),
        );
        context.pop();
      }
    }
  }

  Future<void> _saveContact() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final tags = _tagsController.text.trim().isNotEmpty
          ? _tagsController.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList()
          : null;

      if (isEditing) {
        await _contactsService.updateContact(
          id: widget.contactId!,
          email: _emailController.text.trim(),
          firstName: _firstNameController.text.trim().isNotEmpty
              ? _firstNameController.text.trim()
              : null,
          lastName: _lastNameController.text.trim().isNotEmpty
              ? _lastNameController.text.trim()
              : null,
          company: _companyController.text.trim().isNotEmpty
              ? _companyController.text.trim()
              : null,
          phone: _phoneController.text.trim().isNotEmpty
              ? _phoneController.text.trim()
              : null,
          status: _status.name,
          tags: tags,
        );
      } else {
        await _contactsService.createContact(
          email: _emailController.text.trim(),
          firstName: _firstNameController.text.trim().isNotEmpty
              ? _firstNameController.text.trim()
              : null,
          lastName: _lastNameController.text.trim().isNotEmpty
              ? _lastNameController.text.trim()
              : null,
          company: _companyController.text.trim().isNotEmpty
              ? _companyController.text.trim()
              : null,
          phone: _phoneController.text.trim().isNotEmpty
              ? _phoneController.text.trim()
              : null,
          status: _status.name,
          tags: tags,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEditing
                ? 'Contact updated successfully'
                : 'Contact added successfully'),
          ),
        );
        context.pop(true); // Return true to indicate success
      }
    } catch (e) {
      AppLogger.error('Failed to save contact', error: e);
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save contact: $e')),
        );
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
        title: Text(isEditing ? 'Edit Contact' : 'New Contact'),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(LucideIcons.check),
              onPressed: _saveContact,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Email
                    _buildSectionLabel('Email Address *'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        hintText: 'contact@example.com',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        prefixIcon: const Icon(LucideIcons.mail),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Email is required';
                        }
                        if (!value.contains('@') || !value.contains('.')) {
                          return 'Please enter a valid email address';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    // Name Section
                    _buildSectionLabel('Name'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _firstNameController,
                            decoration: InputDecoration(
                              hintText: 'First name',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            textCapitalization: TextCapitalization.words,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _lastNameController,
                            decoration: InputDecoration(
                              hintText: 'Last name',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            textCapitalization: TextCapitalization.words,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Company
                    _buildSectionLabel('Company'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _companyController,
                      decoration: InputDecoration(
                        hintText: 'Company name',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        prefixIcon: const Icon(LucideIcons.building2),
                      ),
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: 24),

                    // Phone
                    _buildSectionLabel('Phone'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _phoneController,
                      decoration: InputDecoration(
                        hintText: '+1 (555) 123-4567',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        prefixIcon: const Icon(LucideIcons.phone),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 24),

                    // Status
                    _buildSectionLabel('Status'),
                    const SizedBox(height: 8),
                    _buildStatusSelector(),
                    const SizedBox(height: 24),

                    // Tags
                    _buildSectionLabel('Tags'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _tagsController,
                      decoration: InputDecoration(
                        hintText: 'customer, newsletter, prospect',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        prefixIcon: const Icon(LucideIcons.tag),
                        helperText: 'Separate tags with commas',
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveContact,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(
                                isEditing ? 'Update Contact' : 'Add Contact',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
    );
  }

  Widget _buildStatusSelector() {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        _buildStatusChip(ContactStatus.active, 'Active', Colors.green),
        _buildStatusChip(ContactStatus.inactive, 'Inactive', Colors.grey),
        _buildStatusChip(ContactStatus.unsubscribed, 'Unsubscribed', Colors.red),
      ],
    );
  }

  Widget _buildStatusChip(ContactStatus status, String label, Color color) {
    final isSelected = _status == status;
    return InkWell(
      onTap: () => setState(() => _status = status),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.transparent,
          border: Border.all(
            color: isSelected ? color : context.borderColor,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(20),
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
              label,
              style: TextStyle(
                color: isSelected ? color : context.textSecondary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
