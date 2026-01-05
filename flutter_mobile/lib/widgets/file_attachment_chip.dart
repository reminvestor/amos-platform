import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/uploaded_file.dart';

class FileAttachmentChip extends StatelessWidget {
  final UploadedFile file;
  final VoidCallback? onRemove;
  final bool showRemove;

  const FileAttachmentChip({
    super.key,
    required this.file,
    this.onRemove,
    this.showRemove = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getFileIcon(),
            size: 14,
            color: _getFileColor(context),
          ),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              file.filename,
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (file.sizeString.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(
              '(${file.sizeString})',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.textTertiary,
                    fontSize: 10,
                  ),
            ),
          ],
          if (showRemove && onRemove != null) ...[
            const SizedBox(width: 4),
            InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  LucideIcons.x,
                  size: 12,
                  color: context.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData _getFileIcon() {
    if (file.isImage) return LucideIcons.image;
    if (file.isDocument) return LucideIcons.fileText;
    if (file.isSpreadsheet) return LucideIcons.sheet;
    return LucideIcons.file;
  }

  Color _getFileColor(BuildContext context) {
    if (file.isImage) return Colors.purple;
    if (file.isDocument) return Colors.blue;
    if (file.isSpreadsheet) return Colors.green;
    return context.textSecondary;
  }
}

class FileAttachmentList extends StatelessWidget {
  final List<UploadedFile> files;
  final void Function(String assetId)? onRemove;

  const FileAttachmentList({
    super.key,
    required this.files,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: files
            .map((file) => FileAttachmentChip(
                  file: file,
                  onRemove: onRemove != null
                      ? () => onRemove!(file.assetId)
                      : null,
                ))
            .toList(),
      ),
    );
  }
}
