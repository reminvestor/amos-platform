import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/widgets/branded_app_bar.dart';
import 'package:amos_mobile/services/scanner_service.dart';
import 'package:amos_mobile/screens/scanner/camera_preview_screen.dart';

/// Scan modes available in the scanner
enum ScanMode {
  businessCard,
  receipt,
  document,
  whiteboard,
}

extension ScanModeExtension on ScanMode {
  String get label {
    switch (this) {
      case ScanMode.businessCard:
        return 'Business Card';
      case ScanMode.receipt:
        return 'Receipt';
      case ScanMode.document:
        return 'Document';
      case ScanMode.whiteboard:
        return 'Whiteboard';
    }
  }

  String get description {
    switch (this) {
      case ScanMode.businessCard:
        return 'Add to Contacts';
      case ScanMode.receipt:
        return 'Track Expense';
      case ScanMode.document:
        return 'Add to Knowledge';
      case ScanMode.whiteboard:
        return 'Convert to Notes';
    }
  }

  IconData get icon {
    switch (this) {
      case ScanMode.businessCard:
        return LucideIcons.contactRound;
      case ScanMode.receipt:
        return LucideIcons.receipt;
      case ScanMode.document:
        return LucideIcons.fileText;
      case ScanMode.whiteboard:
        return LucideIcons.presentation;
    }
  }

  Color get color {
    switch (this) {
      case ScanMode.businessCard:
        return Colors.teal;
      case ScanMode.receipt:
        return Colors.green;
      case ScanMode.document:
        return Colors.blue;
      case ScanMode.whiteboard:
        return Colors.purple;
    }
  }
}

class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  final _scanner = ScannerService();
  ScanMode _selectedMode = ScanMode.businessCard;
  bool _isProcessing = false;

  Future<void> _openCamera() async {
    final File? imageFile = await Navigator.push<File>(
      context,
      MaterialPageRoute(
        builder: (context) => CameraPreviewScreen(mode: _selectedMode),
      ),
    );

    if (imageFile == null || !mounted) return;
    await _processImage(imageFile);
  }

  Future<void> _processImage(File imageFile) async {
    setState(() => _isProcessing = true);

    try {
      final result = await _scanner.scan(imageFile, _selectedMode);

      if (!mounted) return;
      setState(() => _isProcessing = false);

      if (result.isSuccess) {
        _showResultSheet(result, imageFile);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? 'Failed to scan'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showResultSheet(ScanResult result, File imageFile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => _ScanResultSheet(
          result: result,
          imageFile: imageFile,
          mode: _selectedMode,
          onSave: () => _saveResult(result, imageFile),
        ),
      ),
    );
  }

  Future<void> _saveResult(ScanResult result, File imageFile) async {
    Navigator.pop(context);
    setState(() => _isProcessing = true);

    try {
      final saveResult = await _scanner.saveResult(imageFile, _selectedMode, result);

      if (!mounted) return;
      setState(() => _isProcessing = false);

      if (saveResult.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(saveResult.message ?? 'Saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        // Navigate based on mode
        _navigateAfterSave();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(saveResult.error ?? 'Failed to save'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _navigateAfterSave() {
    switch (_selectedMode) {
      case ScanMode.businessCard:
        context.push('/contacts');
        break;
      case ScanMode.receipt:
        // Stay on scanner or go to expenses when implemented
        break;
      case ScanMode.document:
        context.push('/documents');
        break;
      case ScanMode.whiteboard:
        context.push('/personal-notes');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const BrandedAppBar(
        title: 'Scan',
        showBackButton: true,
      ),
      body: Column(
        children: [
          // Mode selector
          Container(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ScanMode.values.map((mode) {
                  final isSelected = mode == _selectedMode;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _ModeChip(
                      mode: mode,
                      isSelected: isSelected,
                      onTap: () => setState(() => _selectedMode = mode),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // Selected mode info
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _selectedMode.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _selectedMode.color.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _selectedMode.icon,
                    color: _selectedMode.color,
                    size: 32,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedMode.label,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        Text(
                          _selectedMode.description,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: context.textSecondary,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const Spacer(),

          // Processing indicator
          if (_isProcessing)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Processing...',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: context.textSecondary,
                        ),
                  ),
                ],
              ),
            ),

          // Camera button
          if (!_isProcessing)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: FilledButton.icon(
                onPressed: _openCamera,
                icon: const Icon(LucideIcons.camera),
                label: const Text('Scan'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  minimumSize: const Size(double.infinity, 56),
                ),
              ),
            ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final ScanMode mode;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModeChip({
    required this.mode,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? mode.color : context.surfaceColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? mode.color : context.borderColor,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              mode.icon,
              size: 18,
              color: isSelected ? Colors.white : context.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              mode.label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isSelected ? Colors.white : context.textColor,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet showing scan results
class _ScanResultSheet extends StatelessWidget {
  final ScanResult result;
  final File imageFile;
  final ScanMode mode;
  final VoidCallback onSave;

  const _ScanResultSheet({
    required this.result,
    required this.imageFile,
    required this.mode,
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
              Icon(mode.icon, size: 24, color: mode.color),
              const SizedBox(width: 12),
              Text(
                'Scanned ${mode.label}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),

        const Divider(height: 24),

        // Content
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              // Image preview
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

              // Extracted data based on mode
              ...result.extractedFields.entries.map((entry) {
                if (entry.value == null || entry.value.toString().isEmpty) {
                  return const SizedBox.shrink();
                }
                return _FieldRow(
                  label: _formatFieldName(entry.key),
                  value: entry.value.toString(),
                );
              }),

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
                  onPressed: onSave,
                  icon: Icon(_getSaveIcon(), size: 18),
                  label: Text(_getSaveLabel()),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  IconData _getSaveIcon() {
    switch (mode) {
      case ScanMode.businessCard:
        return LucideIcons.userPlus;
      case ScanMode.receipt:
        return LucideIcons.piggyBank;
      case ScanMode.document:
        return LucideIcons.folderPlus;
      case ScanMode.whiteboard:
        return LucideIcons.notebookPen;
    }
  }

  String _getSaveLabel() {
    switch (mode) {
      case ScanMode.businessCard:
        return 'Save Contact';
      case ScanMode.receipt:
        return 'Save Expense';
      case ScanMode.document:
        return 'Add to Docs';
      case ScanMode.whiteboard:
        return 'Save Note';
    }
  }

  String _formatFieldName(String key) {
    return key
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.isNotEmpty
            ? '${word[0].toUpperCase()}${word.substring(1)}'
            : '')
        .join(' ');
  }
}

class _FieldRow extends StatelessWidget {
  final String label;
  final String value;

  const _FieldRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: context.textTertiary,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
