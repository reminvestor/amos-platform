import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/document.dart';
import 'package:amos_mobile/services/documents_service.dart';
import 'package:amos_mobile/utils/logger.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';

class DocumentListScreen extends ConsumerStatefulWidget {
  const DocumentListScreen({super.key});

  @override
  ConsumerState<DocumentListScreen> createState() => _DocumentListScreenState();
}

class _DocumentListScreenState extends ConsumerState<DocumentListScreen> {
  final DocumentsService _documentsService = DocumentsService();
  final _searchController = TextEditingController();
  List<Document> _documents = [];
  bool _isLoading = true;
  bool _isUploading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadDocuments();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDocuments({String? search}) async {
    AppLogger.info('DocumentListScreen: Loading documents');
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final documents = await _documentsService.getDocuments(search: search);
      if (!mounted) return;
      setState(() => _documents = documents);
      AppLogger.info('DocumentListScreen: Loaded ${documents.length} documents');
    } catch (e, stackTrace) {
      AppLogger.error('DocumentListScreen: Failed to load documents', error: e, stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _errorMessage = 'Failed to load documents. Pull to retry.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _uploadDocument() async {
    try {
      // Pick file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'txt', 'md', 'json', 'csv'],
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.path == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not access file')),
        );
        return;
      }

      setState(() => _isUploading = true);

      await _documentsService.uploadDocument(file.path!, file.name);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document uploaded successfully')),
      );

      _loadDocuments();
    } catch (e) {
      AppLogger.error('Failed to upload document', error: e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to upload: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _deleteDocument(Document document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Document'),
        content: Text('Are you sure you want to delete "${document.title}"?'),
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
      await _documentsService.deleteDocument(document.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document deleted')),
      );
      _loadDocuments();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete: $e'), backgroundColor: Colors.red),
      );
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
        title: const Text('Documents'),
        actions: [
          if (_isUploading)
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
              icon: const Icon(LucideIcons.upload),
              onPressed: _uploadDocument,
              tooltip: 'Upload Document',
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
                hintText: 'Search documents...',
                prefixIcon: const Icon(LucideIcons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (value) {
                _loadDocuments(search: value.isNotEmpty ? value : null);
              },
            ),
          ),

          // Documents List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? _buildErrorState()
                    : _documents.isEmpty
                        ? _buildEmptyState()
                        : RefreshIndicator(
                            onRefresh: _loadDocuments,
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _documents.length,
                              itemBuilder: (context, index) {
                                final document = _documents[index];
                                return _DocumentCard(
                                  document: document,
                                  iconData: _getDocumentIcon(document.icon),
                                  onTap: () => context.pushNamed(
                                    'document-detail',
                                    pathParameters: {'id': document.id},
                                  ),
                                  onDelete: () => _deleteDocument(document),
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
              onPressed: _loadDocuments,
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
              LucideIcons.folderOpen,
              size: 64,
              color: context.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              'No Documents',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Upload documents to build your AI knowledge base.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.textSecondary,
                  ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _uploadDocument,
              icon: const Icon(LucideIcons.upload),
              label: const Text('Upload Document'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentCard extends StatelessWidget {
  final Document document;
  final IconData iconData;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _DocumentCard({
    required this.document,
    required this.iconData,
    required this.onTap,
    required this.onDelete,
  });

  Color _getStatusColor() {
    if (document.isReady) return Colors.green;
    if (document.isFailed) return Colors.red;
    return Colors.orange;
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d, yyyy');

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
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
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  iconData,
                  color: context.primaryColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
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
                          document.statusLabel,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: context.textSecondary,
                              ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          document.fileSize,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: context.textTertiary,
                              ),
                        ),
                      ],
                    ),
                    if (document.isProcessing) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: document.processingProgress / 100,
                          minHeight: 4,
                          backgroundColor: context.borderColor,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      dateFormat.format(document.createdAt),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: context.textTertiary,
                          ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(LucideIcons.ellipsisVertical, color: context.textTertiary),
                onSelected: (value) {
                  if (value == 'delete') {
                    onDelete();
                  } else if (value == 'ask') {
                    context.push('/chat?prompt=${Uri.encodeComponent("Based on the document '${document.title}'...")}');
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
        ),
      ),
    );
  }
}
