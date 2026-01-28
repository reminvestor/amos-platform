import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/canvas.dart';
import 'package:amos_mobile/services/canvas_service.dart';
import 'package:amos_mobile/utils/logger.dart';

/// Canvas for displaying a list of landing pages
class LandingPageListCanvas extends ConsumerStatefulWidget {
  final Canvas canvas;

  const LandingPageListCanvas({super.key, required this.canvas});

  @override
  ConsumerState<LandingPageListCanvas> createState() => _LandingPageListCanvasState();
}

class _LandingPageListCanvasState extends ConsumerState<LandingPageListCanvas> {
  final _canvasService = CanvasService();
  List<Map<String, dynamic>> _landingPages = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLandingPages();
  }

  Future<void> _loadLandingPages() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final pages = await _canvasService.fetchResourceList(
        resourceType: 'landing_pages',
        filters: widget.canvas.data.isNotEmpty ? widget.canvas.data : null,
      );
      setState(() {
        _landingPages = pages;
        _isLoading = false;
      });
    } catch (e) {
      AppLogger.error('Failed to load landing pages', error: e);
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _buildErrorState();
    }

    if (_landingPages.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _loadLandingPages,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _landingPages.length,
        itemBuilder: (context, index) {
          return _LandingPageCard(
            page: _landingPages[index],
            onTap: () => _openLandingPage(_landingPages[index]),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.layoutTemplate,
            size: 48,
            color: context.textTertiary,
          ),
          const SizedBox(height: 16),
          Text(
            'No landing pages yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Ask the AI to create one for you',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.textSecondary,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.circleAlert,
            size: 48,
            color: Colors.red.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'Failed to load landing pages',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _loadLandingPages,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  void _openLandingPage(Map<String, dynamic> page) {
    final id = page['id'];
    if (id != null) {
      context.push('/landing-pages/$id');
    }
  }
}

class _LandingPageCard extends StatelessWidget {
  final Map<String, dynamic> page;
  final VoidCallback onTap;

  const _LandingPageCard({
    required this.page,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = page['name'] ?? page['title'] ?? 'Untitled';
    final status = page['status'] ?? 'draft';
    final updatedAt = page['updated_at'];
    final previewUrl = page['preview_url'] ?? page['screenshot_url'];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Thumbnail
              Container(
                width: 80,
                height: 60,
                decoration: BoxDecoration(
                  color: context.surfaceColor,
                  borderRadius: BorderRadius.circular(8),
                  image: previewUrl != null
                      ? DecorationImage(
                          image: NetworkImage(previewUrl),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: previewUrl == null
                    ? Icon(
                        LucideIcons.image,
                        color: context.textTertiary,
                      )
                    : null,
              ),

              const SizedBox(width: 12),

              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _StatusBadge(status: status),
                        if (updatedAt != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            _formatDate(updatedAt),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: context.textTertiary,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Arrow
              Icon(
                LucideIcons.chevronRight,
                size: 20,
                color: context.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inDays == 0) {
        return 'Today';
      } else if (diff.inDays == 1) {
        return 'Yesterday';
      } else if (diff.inDays < 7) {
        return '${diff.inDays} days ago';
      } else {
        return '${date.month}/${date.day}/${date.year}';
      }
    } catch (_) {
      return '';
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color backgroundColor;
    Color textColor;

    switch (status.toLowerCase()) {
      case 'published':
      case 'active':
        backgroundColor = Colors.green.shade100;
        textColor = Colors.green.shade700;
        break;
      case 'draft':
        backgroundColor = Colors.orange.shade100;
        textColor = Colors.orange.shade700;
        break;
      case 'archived':
        backgroundColor = Colors.grey.shade200;
        textColor = Colors.grey.shade600;
        break;
      default:
        backgroundColor = context.surfaceColor;
        textColor = context.textSecondary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}
