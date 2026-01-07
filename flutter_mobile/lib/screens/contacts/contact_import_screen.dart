import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/services/api_client.dart';
import 'package:amos_mobile/utils/logger.dart';

class ContactImportScreen extends ConsumerStatefulWidget {
  const ContactImportScreen({super.key});

  @override
  ConsumerState<ContactImportScreen> createState() => _ContactImportScreenState();
}

class _ContactImportScreenState extends ConsumerState<ContactImportScreen> {
  final ApiClient _api = ApiClient.instance;

  bool _isLoading = false;
  bool _isParsing = false;
  String? _error;
  String? _fileName;
  List<Map<String, String>> _parsedContacts = [];
  List<String> _headers = [];

  // Column mapping
  String? _emailColumn;
  String? _firstNameColumn;
  String? _lastNameColumn;

  Future<void> _pickFile() async {
    setState(() {
      _isParsing = true;
      _error = null;
      _parsedContacts = [];
      _headers = [];
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        setState(() => _isParsing = false);
        return;
      }

      final file = result.files.first;
      _fileName = file.name;

      if (file.bytes == null) {
        setState(() {
          _error = 'Could not read file';
          _isParsing = false;
        });
        return;
      }

      // Parse CSV
      final content = utf8.decode(file.bytes!);
      final lines = content.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();

      if (lines.isEmpty) {
        setState(() {
          _error = 'CSV file is empty';
          _isParsing = false;
        });
        return;
      }

      // Parse headers
      _headers = _parseCSVLine(lines.first);

      // Parse data rows
      final contacts = <Map<String, String>>[];
      for (var i = 1; i < lines.length && i <= 100; i++) {
        final values = _parseCSVLine(lines[i]);
        final contact = <String, String>{};
        for (var j = 0; j < _headers.length && j < values.length; j++) {
          contact[_headers[j]] = values[j];
        }
        if (contact.isNotEmpty) {
          contacts.add(contact);
        }
      }

      // Try to auto-detect columns
      _autoDetectColumns();

      setState(() {
        _parsedContacts = contacts;
        _isParsing = false;
      });
    } catch (e, stackTrace) {
      AppLogger.error('Failed to parse CSV', error: e, stackTrace: stackTrace);
      setState(() {
        _error = 'Failed to parse CSV: $e';
        _isParsing = false;
      });
    }
  }

  List<String> _parseCSVLine(String line) {
    final result = <String>[];
    var current = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < line.length; i++) {
      final char = line[i];

      if (char == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          current.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        result.add(current.toString().trim());
        current = StringBuffer();
      } else {
        current.write(char);
      }
    }
    result.add(current.toString().trim());

    return result;
  }

  void _autoDetectColumns() {
    final emailPatterns = ['email', 'e-mail', 'email_address', 'emailaddress'];
    final firstNamePatterns = ['first_name', 'firstname', 'first', 'given_name', 'givenname'];
    final lastNamePatterns = ['last_name', 'lastname', 'last', 'surname', 'family_name'];

    for (final header in _headers) {
      final lowerHeader = header.toLowerCase();

      if (_emailColumn == null && emailPatterns.any((p) => lowerHeader.contains(p))) {
        _emailColumn = header;
      }
      if (_firstNameColumn == null && firstNamePatterns.any((p) => lowerHeader.contains(p))) {
        _firstNameColumn = header;
      }
      if (_lastNameColumn == null && lastNamePatterns.any((p) => lowerHeader.contains(p))) {
        _lastNameColumn = header;
      }
    }
  }

  Future<void> _importContacts() async {
    if (_emailColumn == null) {
      _showError('Please select the email column');
      return;
    }
    if (_firstNameColumn == null) {
      _showError('Please select the first name column');
      return;
    }
    if (_lastNameColumn == null) {
      _showError('Please select the last name column');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Build contacts array
      final contacts = _parsedContacts.map((row) {
        return {
          'email': row[_emailColumn!] ?? '',
          'first_name': row[_firstNameColumn!] ?? '',
          'last_name': row[_lastNameColumn!] ?? '',
          'status': 'active',
        };
      }).where((c) => c['email']!.isNotEmpty).toList();

      if (contacts.isEmpty) {
        _showError('No valid contacts found');
        setState(() => _isLoading = false);
        return;
      }

      final response = await _api.post('/api/v1/contacts', data: {
        'contacts': contacts,
      });

      final created = response['created'] ?? 0;
      final updated = response['updated'] ?? 0;
      final errors = response['errors'] as List? ?? [];

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Import Complete'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Created: $created contacts'),
                Text('Updated: $updated contacts'),
                if (errors.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${errors.length} errors occurred',
                    style: TextStyle(color: Colors.orange.shade700),
                  ),
                ],
              ],
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  context.pop();
                },
                child: const Text('Done'),
              ),
            ],
          ),
        );
      }
    } catch (e, stackTrace) {
      AppLogger.error('Failed to import contacts', error: e, stackTrace: stackTrace);
      _showError('Failed to import: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
        title: const Text('Import Contacts'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Instructions
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: context.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(LucideIcons.info, color: context.primaryColor),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Import contacts from a CSV file. The file must have columns for email, first name, and last name.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // File picker
                  if (_parsedContacts.isEmpty) ...[
                    InkWell(
                      onTap: _isParsing ? null : _pickFile,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 48),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: context.borderColor,
                            style: BorderStyle.solid,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            if (_isParsing)
                              const CircularProgressIndicator()
                            else
                              Icon(
                                LucideIcons.upload,
                                size: 48,
                                color: context.textSecondary,
                              ),
                            const SizedBox(height: 16),
                            Text(
                              _isParsing ? 'Parsing file...' : 'Tap to select CSV file',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: context.textSecondary,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Maximum 100 contacts per import',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: context.textTertiary,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    // File info
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.green.shade200),
                      ),
                      color: Colors.green.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(LucideIcons.fileSpreadsheet, color: Colors.green.shade700),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _fileName ?? 'Selected file',
                                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                  Text(
                                    '${_parsedContacts.length} contacts found',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: Colors.green.shade700,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(LucideIcons.x),
                              onPressed: () {
                                setState(() {
                                  _parsedContacts = [];
                                  _headers = [];
                                  _fileName = null;
                                  _emailColumn = null;
                                  _firstNameColumn = null;
                                  _lastNameColumn = null;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Column mapping
                    Text(
                      'Map Columns',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 12),

                    _ColumnMapper(
                      label: 'Email',
                      icon: LucideIcons.mail,
                      headers: _headers,
                      selectedColumn: _emailColumn,
                      required: true,
                      onChanged: (value) => setState(() => _emailColumn = value),
                    ),
                    const SizedBox(height: 12),

                    _ColumnMapper(
                      label: 'First Name',
                      icon: LucideIcons.user,
                      headers: _headers,
                      selectedColumn: _firstNameColumn,
                      required: true,
                      onChanged: (value) => setState(() => _firstNameColumn = value),
                    ),
                    const SizedBox(height: 12),

                    _ColumnMapper(
                      label: 'Last Name',
                      icon: LucideIcons.user,
                      headers: _headers,
                      selectedColumn: _lastNameColumn,
                      required: true,
                      onChanged: (value) => setState(() => _lastNameColumn = value),
                    ),
                    const SizedBox(height: 24),

                    // Preview
                    Text(
                      'Preview (first 5 rows)',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 12),

                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: context.borderColor),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            for (var i = 0; i < _parsedContacts.length && i < 5; i++)
                              Padding(
                                padding: EdgeInsets.only(bottom: i < 4 ? 8 : 0),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        _emailColumn != null
                                            ? _parsedContacts[i][_emailColumn!] ?? '-'
                                            : '-',
                                        style: Theme.of(context).textTheme.bodySmall,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _firstNameColumn != null
                                            ? _parsedContacts[i][_firstNameColumn!] ?? '-'
                                            : '-',
                                        style: Theme.of(context).textTheme.bodySmall,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _lastNameColumn != null
                                            ? _parsedContacts[i][_lastNameColumn!] ?? '-'
                                            : '-',
                                        style: Theme.of(context).textTheme.bodySmall,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Import button
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _emailColumn != null &&
                                _firstNameColumn != null &&
                                _lastNameColumn != null
                            ? _importContacts
                            : null,
                        icon: const Icon(LucideIcons.upload, size: 18),
                        label: Text('Import ${_parsedContacts.length} Contacts'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],

                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(LucideIcons.circleAlert, color: Colors.red.shade700, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(color: Colors.red.shade700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _ColumnMapper extends StatelessWidget {
  final String label;
  final IconData icon;
  final List<String> headers;
  final String? selectedColumn;
  final bool required;
  final ValueChanged<String?> onChanged;

  const _ColumnMapper({
    required this.label,
    required this.icon,
    required this.headers,
    required this.selectedColumn,
    required this.required,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: context.surfaceColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: context.textSecondary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  if (required) ...[
                    const SizedBox(width: 4),
                    Text(
                      '*',
                      style: TextStyle(color: Colors.red.shade600),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        SizedBox(
          width: 150,
          child: DropdownButtonFormField<String>(
            value: selectedColumn,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            hint: const Text('Select...'),
            items: headers.map((h) {
              return DropdownMenuItem(
                value: h,
                child: Text(h, overflow: TextOverflow.ellipsis),
              );
            }).toList(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
