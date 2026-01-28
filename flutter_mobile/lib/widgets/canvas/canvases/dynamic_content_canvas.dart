import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/canvas.dart';
import 'package:amos_mobile/utils/logger.dart';
import 'package:url_launcher/url_launcher.dart';

/// Canvas for rendering dynamic content like dashboards, documents, images.
/// Handles various content types with native Flutter widgets.
class DynamicContentCanvas extends ConsumerWidget {
  final Canvas canvas;
  final String contentType;

  const DynamicContentCanvas({
    super.key,
    required this.canvas,
    required this.contentType,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (contentType) {
      case 'dashboard':
        return _DashboardContent(canvas: canvas);
      case 'document':
        return _DocumentContent(canvas: canvas);
      case 'image':
        return _ImageContent(canvas: canvas);
      default:
        return _GenericContent(canvas: canvas);
    }
  }
}

/// Dashboard content with stat cards and metrics
class _DashboardContent extends StatelessWidget {
  final Canvas canvas;

  const _DashboardContent({required this.canvas});

  @override
  Widget build(BuildContext context) {
    final stats = canvas.getData<List>('stats') ?? [];
    final charts = canvas.getData<List>('charts') ?? [];
    final title = canvas.getData<String>('title') ?? 'Dashboard';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 16),

          // Stat cards grid
          if (stats.isNotEmpty) ...[
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.5,
              ),
              itemCount: stats.length,
              itemBuilder: (context, index) {
                final stat = stats[index] as Map<String, dynamic>;
                return _StatCard(
                  label: stat['label'] ?? 'Metric',
                  value: stat['value']?.toString() ?? '0',
                  change: stat['change']?.toString(),
                  icon: _getIconForMetric(stat['type'] ?? stat['icon']),
                );
              },
            ),
            const SizedBox(height: 24),
          ],

          // Placeholder for charts
          if (charts.isNotEmpty) ...[
            Text(
              'Analytics',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            ...charts.map((chart) {
              final chartData = chart as Map<String, dynamic>;
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chartData['title'] ?? 'Chart',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 12),
                      Container(
                        height: 150,
                        decoration: BoxDecoration(
                          color: context.surfaceColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                LucideIcons.chartBar,
                                size: 32,
                                color: context.textTertiary,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Chart visualization',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: context.textTertiary,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],

          // If no data, show empty state
          if (stats.isEmpty && charts.isEmpty)
            Center(
              child: Column(
                children: [
                  const SizedBox(height: 48),
                  Icon(
                    LucideIcons.layoutDashboard,
                    size: 48,
                    color: context.textTertiary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No dashboard data available',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: context.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  IconData _getIconForMetric(String? type) {
    switch (type) {
      case 'users':
      case 'contacts':
        return LucideIcons.users;
      case 'revenue':
      case 'money':
        return LucideIcons.dollarSign;
      case 'campaigns':
      case 'email':
        return LucideIcons.mail;
      case 'views':
      case 'pageviews':
        return LucideIcons.eye;
      case 'conversions':
        return LucideIcons.target;
      case 'growth':
        return LucideIcons.trendingUp;
      default:
        return LucideIcons.chartBar;
    }
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? change;
  final IconData icon;

  const _StatCard({
    required this.label,
    required this.value,
    this.change,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final isPositive = change != null && !change!.startsWith('-');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, size: 20, color: context.primaryColor),
                if (change != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isPositive
                          ? Colors.green.withOpacity(0.1)
                          : Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      change!,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isPositive ? Colors.green : Colors.red,
                      ),
                    ),
                  ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.textSecondary,
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Document viewer content
class _DocumentContent extends StatelessWidget {
  final Canvas canvas;

  const _DocumentContent({required this.canvas});

  @override
  Widget build(BuildContext context) {
    final documentUrl = canvas.getData<String>('url') ?? canvas.getData<String>('document_url');
    final documentName = canvas.getData<String>('name') ?? 'Document';
    final documentType = canvas.getData<String>('type') ?? 'pdf';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                _getDocumentIcon(documentType),
                size: 64,
                color: context.primaryColor,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              documentName,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Document preview is not available in the mobile app.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.textSecondary,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (documentUrl != null)
              FilledButton.icon(
                onPressed: () => _openDocument(documentUrl),
                icon: const Icon(LucideIcons.externalLink, size: 16),
                label: const Text('Open Document'),
              ),
          ],
        ),
      ),
    );
  }

  IconData _getDocumentIcon(String type) {
    switch (type.toLowerCase()) {
      case 'pdf':
        return LucideIcons.fileText;
      case 'doc':
      case 'docx':
        return LucideIcons.fileType;
      case 'xls':
      case 'xlsx':
        return LucideIcons.fileSpreadsheet;
      case 'ppt':
      case 'pptx':
        return LucideIcons.presentation;
      default:
        return LucideIcons.file;
    }
  }

  void _openDocument(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      AppLogger.error('Failed to open document', error: e);
    }
  }
}

/// Image viewer content
class _ImageContent extends StatelessWidget {
  final Canvas canvas;

  const _ImageContent({required this.canvas});

  @override
  Widget build(BuildContext context) {
    final imageUrl = canvas.getData<String>('url') ??
        canvas.getData<String>('image_url') ??
        canvas.getData<String>('src');
    final caption = canvas.getData<String>('caption') ?? canvas.getData<String>('alt');

    if (imageUrl == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.imageOff,
              size: 48,
              color: context.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              'No image available',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.textSecondary,
                  ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          // Image with loading indicator
          Image.network(
            imageUrl,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return SizedBox(
                height: 300,
                child: Center(
                  child: CircularProgressIndicator(
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded /
                            loadingProgress.expectedTotalBytes!
                        : null,
                  ),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return SizedBox(
                height: 200,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        LucideIcons.imageOff,
                        size: 48,
                        color: context.textTertiary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Failed to load image',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: context.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // Caption
          if (caption != null) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                caption,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: context.textSecondary,
                    ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Generic content for unknown canvas types
class _GenericContent extends StatelessWidget {
  final Canvas canvas;

  const _GenericContent({required this.canvas});

  @override
  Widget build(BuildContext context) {
    final content = canvas.getData<String>('content') ??
        canvas.getData<String>('html_content') ??
        canvas.getData<String>('text');

    if (content == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.fileSearch,
              size: 48,
              color: context.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              'No content available',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.textSecondary,
                  ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText(
        content,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}
