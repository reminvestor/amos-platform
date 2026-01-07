import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/document.dart';
import 'package:amos_mobile/services/documents_service.dart';
import 'package:amos_mobile/utils/logger.dart';
import 'package:intl/intl.dart';
import 'dart:async';

class DocumentDetailScreen extends ConsumerStatefulWidget {
  final String documentId;

  const DocumentDetailScreen({super.key, required this.documentId});

  @override
  ConsumerState<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends ConsumerState<DocumentDetailScreen> {
  final DocumentsService _documentsService = DocumentsService();
  Document? _document;
  bool _isLoading = true;
  String? _errorMessage;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDocument();
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDocument() async {
    AppLogger.info('DocumentDetailScreen: Loading document ${widget.documentId}');
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final document = await _documentsService.getDocument(widget.documentId);
      if (!mounted) return;
      setState(() => _document = document);
      AppLogger.info('DocumentDetailScreen: Loaded document "${document.title}"');

      // If document is processing, start polling for status
      if (document.isProcessing) {
        _startStatusPolling();
      }
    } catch (e, stackTrace) {
      AppLogger.error('DocumentDetailScreen: Failed to load document', error: e, stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _errorMessage = 'Failed to load document');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _startStatusPolling() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted) {
        _statusTimer?.cancel();
        return;
      }

      try {
        final status = await _documentsService.getDocumentStatus(widget.documentId);
        if (!mounted) return;

        setState(() {
          if (_document != null) {
            _document = Document(
              id: _document!.id,
              filename: _document!.filename,
              title: _document!.title,
              contentType: _document!.contentType,
              fileSize: _document!.fileSize,
              fileSizeBytes: _document!.fileSizeBytes,
              processingStatus: status['processing_status'] ?? _document!.processingStatus,
              processingProgress: status['processing_progress'] ?? _document!.processingProgress,
              processingStage: status['processing_stage'],
              processingStageDescription: status['processing_stage_description'],
              chunksCount: status['chunks_count'] ?? _document!.chunksCount,
              embeddedChunksCount: status['embedded_chunks_count'],
              viewCount: _document!.viewCount,
              downloadCount: _document!.downloadCount,
              collectionName: _document!.collectionName,
              collectionId: _document!.collectionId,
              icon: _document!.icon,
              createdAt: _document!.createdAt,
              updatedAt: _document!.updatedAt,
              tags: _document!.tags,
              subjects: _document!.subjects,
              hasTables: _document!.hasTables,
              hasImages: _document!.hasImages,
              author: _document!.author,
              language: _document!.language,
              version: _document!.version,
              lastAccessedAt: _document!.lastAccessedAt,
            );
          }
        });

        // Stop polling if processing is complete
        if (_document != null && !_document!.isProcessing) {
          _statusTimer?.cancel();
        }
      } catch (e) {
        AppLogger.error('Failed to poll document status', error: e);
      }
    });
  }

  Future<void> _deleteDocument() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Document'),
        content: Text('Are you sure you want to delete "${_document?.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _documentsService.deleteDocument(widget.documentId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document deleted')),
      );
      context.pop(true); // Signal refresh needed
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _askAboutDocument() {
    if (_document == null) return;
    context.push('/chat?prompt=${Uri.encodeComponent("Based on the document '${_document!.title}'...")}');
  }

  IconData _getDocumentIcon(String icon) {
    switch (icon) {
      case 'file-text':
        return LucideIcons.fileText;
      case 'table':
        return LucideIcons.table;
      case 'presentation':
        return LucideIcons.presentation;
      case 'image':
        return LucideIcons.image;
      case 'video':
        return LucideIcons.video;
      case 'music':
        return LucideIcons.music;
      case 'code':
        return LucideIcons.code;
      case 'globe':
        return LucideIcons.globe;
      default:
        return LucideIcons.file;
    }
  }

  Color _getStatusColor() {
    if (_document == null) return Colors.grey;
    if (_document!.isReady) return Colors.green;
    if (_document!.isFailed) return Colors.red;
    return Colors.orange;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
        title: Text(_document?.title ?? 'Document'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(LucideIcons.ellipsisVertical),
            onSelected: (value) {
              if (value == 'delete') {
                _deleteDocument();
              } else if (value == 'ask') {
                _askAboutDocument();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'ask',
                child: Row(
                  children: [
                    Icon(LucideIcons.messageCircle, size: 16),
                    SizedBox(width: 8),
                    Text('Ask about this'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(LucideIcons.trash2, size: 16, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Delete', style: TextStyle(color: Colors.red)),
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
              : _document == null
                  ? _buildErrorState()
                  : RefreshIndicator(
                      onRefresh: _loadDocument,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildHeader(),
                            const SizedBox(height: 24),
                            _buildStatusSection(),
                            const SizedBox(height: 24),
                            _buildDetailsSection(),
                            if (_document!.tags?.isNotEmpty == true) ...[
                              const SizedBox(height: 24),
                              _buildTagsSection(),
                            ],
                            if (_document!.subjects?.isNotEmpty == true) ...[
                              const SizedBox(height: 24),
                              _buildSubjectsSection(),
                            ],
                            const SizedBox(height: 32),
                            _buildActions(),
                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
                    ),
    );
  }

  Widget _buildHeader() {
    final dateFormat = DateFormat('MMMM d, yyyy \'at\' h:mm a');

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: context.borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                _getDocumentIcon(_document!.icon),
                color: context.primaryColor,
                size: 40,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _document!.title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _document!.filename,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.textSecondary,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Added ${dateFormat.format(_document!.createdAt)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.textTertiary,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusSection() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: context.borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Processing Status',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getStatusColor().withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _getStatusColor(),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _document!.statusLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: _getStatusColor(),
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_document!.isProcessing) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _document!.processingProgress / 100,
                  minHeight: 8,
                  backgroundColor: context.borderColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${_document!.processingProgress}% complete',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.textSecondary,
                    ),
              ),
              if (_document!.processingStageDescription != null) ...[
                const SizedBox(height: 4),
                Text(
                  _document!.processingStageDescription!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.textTertiary,
                      ),
                ),
              ],
            ],
            if (_document!.isReady) ...[
              const SizedBox(height: 16),
              _buildStatRow(
                icon: LucideIcons.layers,
                label: 'Chunks',
                value: '${_document!.chunksCount}',
              ),
              if (_document!.embeddedChunksCount != null)
                _buildStatRow(
                  icon: LucideIcons.sparkles,
                  label: 'Embedded',
                  value: '${_document!.embeddedChunksCount}',
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: context.textSecondary),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.textSecondary,
                ),
          ),
          const Spacer(),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsSection() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: context.borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Document Details',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 16),
            _buildDetailRow('File Size', _document!.fileSize),
            _buildDetailRow('Content Type', _document!.contentType),
            _buildDetailRow('Collection', _document!.collectionName),
            if (_document!.author != null)
              _buildDetailRow('Author', _document!.author!),
            if (_document!.language != null)
              _buildDetailRow('Language', _document!.language!),
            _buildDetailRow('Version', 'v${_document!.version}'),
            if (_document!.hasTables == true)
              _buildDetailRow('Contains Tables', 'Yes'),
            if (_document!.hasImages == true)
              _buildDetailRow('Contains Images', 'Yes'),
            const Divider(height: 24),
            _buildDetailRow('Views', '${_document!.viewCount}'),
            _buildDetailRow('Downloads', '${_document!.downloadCount}'),
            if (_document!.lastAccessedAt != null)
              _buildDetailRow(
                'Last Accessed',
                DateFormat('MMM d, yyyy').format(_document!.lastAccessedAt!),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.textSecondary,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTagsSection() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: context.borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tags',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: (_document!.tags ?? []).map((tag) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: context.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    tag.name,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.primaryColor,
                        ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubjectsSection() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: context.borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Subjects',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: (_document!.subjects ?? []).map((subject) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    subject.name,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.purple,
                        ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: _askAboutDocument,
          icon: const Icon(LucideIcons.messageCircle),
          label: const Text('Ask About This Document'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _deleteDocument,
          icon: const Icon(LucideIcons.trash2, color: Colors.red),
          label: const Text('Delete Document', style: TextStyle(color: Colors.red)),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            side: const BorderSide(color: Colors.red),
          ),
        ),
      ],
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
              _errorMessage ?? 'Document not found',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.textSecondary,
                  ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadDocument,
              icon: const Icon(LucideIcons.refreshCw),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
