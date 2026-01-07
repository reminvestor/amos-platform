import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/landing_page.dart';
import 'package:amos_mobile/services/landing_pages_service.dart';
import 'package:amos_mobile/utils/logger.dart';
import 'package:intl/intl.dart';

class LandingPageDetailScreen extends ConsumerStatefulWidget {
  final String id;

  const LandingPageDetailScreen({super.key, required this.id});

  @override
  ConsumerState<LandingPageDetailScreen> createState() =>
      _LandingPageDetailScreenState();
}

class _LandingPageDetailScreenState
    extends ConsumerState<LandingPageDetailScreen> {
  final LandingPagesService _service = LandingPagesService();
  bool _isLoading = false;
  bool _isPublishing = false;
  LandingPage? _landingPage;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadLandingPage();
  }

  Future<void> _loadLandingPage() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final page = await _service.getLandingPage(widget.id);
      if (mounted) {
        setState(() {
          _landingPage = page;
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      AppLogger.error('Failed to load landing page', error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load landing page';
        });
      }
    }
  }

  Future<void> _togglePublish() async {
    if (_landingPage == null || _isPublishing) return;

    setState(() => _isPublishing = true);

    try {
      LandingPage updated;
      if (_landingPage!.status == LandingPageStatus.published) {
        updated = await _service.unpublishLandingPage(widget.id);
      } else {
        updated = await _service.publishLandingPage(widget.id);
      }

      if (mounted) {
        setState(() {
          _landingPage = updated;
          _isPublishing = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(updated.status == LandingPageStatus.published
                ? 'Landing page published'
                : 'Landing page unpublished'),
          ),
        );
      }
    } catch (e) {
      AppLogger.error('Failed to toggle publish status', error: e);
      if (mounted) {
        setState(() => _isPublishing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update landing page: $e')),
        );
      }
    }
  }

  Future<void> _previewLandingPage() async {
    if (_landingPage == null) return;

    // Build the preview URL using the API base URL
    final previewUrl = Uri.parse(
      'http://localhost:3000/p/${_landingPage!.slug}',
    );

    try {
      if (await canLaunchUrl(previewUrl)) {
        await launchUrl(previewUrl, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open preview URL')),
          );
        }
      }
    } catch (e) {
      AppLogger.error('Failed to launch URL', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open preview: $e')),
        );
      }
    }
  }

  Future<void> _deleteLandingPage() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Landing Page'),
        content: const Text(
          'Are you sure you want to delete this landing page? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _service.deleteLandingPage(widget.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Landing page deleted')),
        );
        context.pop(true);
      }
    } catch (e) {
      AppLogger.error('Failed to delete landing page', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
      }
    }
  }

  void _showActions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(LucideIcons.externalLink),
              title: const Text('Preview'),
              onTap: () {
                Navigator.pop(context);
                _previewLandingPage();
              },
            ),
            ListTile(
              leading: Icon(
                _landingPage?.status == LandingPageStatus.published
                    ? LucideIcons.eyeOff
                    : LucideIcons.globe,
              ),
              title: Text(
                _landingPage?.status == LandingPageStatus.published
                    ? 'Unpublish'
                    : 'Publish',
              ),
              onTap: () {
                Navigator.pop(context);
                _togglePublish();
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.trash2, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _deleteLandingPage();
              },
            ),
          ],
        ),
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
        title: const Text('Landing Page'),
        actions: [
          if (_landingPage != null)
            IconButton(
              icon: const Icon(LucideIcons.ellipsisVertical),
              onPressed: _showActions,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
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
                _errorMessage!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: context.textSecondary,
                    ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadLandingPage,
                icon: const Icon(LucideIcons.refreshCw),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_landingPage == null) {
      return const Center(child: Text('Landing page not found'));
    }

    final page = _landingPage!;
    final isPublished = page.status == LandingPageStatus.published;
    final dateTimeFormat = DateFormat('MMM d, yyyy at h:mm a');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      page.title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '/${page.slug}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: context.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isPublished
                      ? Colors.green.withOpacity(0.1)
                      : Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isPublished ? Colors.green : Colors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isPublished ? 'Published' : 'Draft',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: isPublished ? Colors.green : Colors.grey,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Stats Cards
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: LucideIcons.eye,
                  label: 'Views',
                  value: '${page.viewCount ?? 0}',
                  color: Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: LucideIcons.userCheck,
                  label: 'Submissions',
                  value: '${page.submissionCount ?? 0}',
                  color: Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Details Section
          Text(
            'Details',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: context.borderColor),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _DetailRow(
                    label: 'Status',
                    value: isPublished ? 'Published' : 'Draft',
                  ),
                  const Divider(),
                  _DetailRow(
                    label: 'Created',
                    value: dateTimeFormat.format(page.createdAt),
                  ),
                  const Divider(),
                  _DetailRow(
                    label: 'Updated',
                    value: dateTimeFormat.format(page.updatedAt),
                  ),
                  if (page.publishedAt != null) ...[
                    const Divider(),
                    _DetailRow(
                      label: 'Published',
                      value: dateTimeFormat.format(page.publishedAt!),
                    ),
                  ],
                  if (page.unreadSubmissionsCount != null &&
                      page.unreadSubmissionsCount! > 0) ...[
                    const Divider(),
                    _DetailRow(
                      label: 'Unread Submissions',
                      value: '${page.unreadSubmissionsCount}',
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Action Buttons
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _previewLandingPage,
              icon: const Icon(LucideIcons.externalLink),
              label: const Text('Preview Landing Page'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isPublishing ? null : _togglePublish,
              icon: _isPublishing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      isPublished ? LucideIcons.eyeOff : LucideIcons.globe,
                    ),
              label: Text(isPublished ? 'Unpublish' : 'Publish'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
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
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.textSecondary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.textSecondary,
                ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
