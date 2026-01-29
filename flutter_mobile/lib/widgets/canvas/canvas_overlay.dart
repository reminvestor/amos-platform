import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/canvas.dart';
import 'package:amos_mobile/providers/app_providers.dart';
import 'package:amos_mobile/widgets/canvas/canvas_renderer.dart';

/// Full-screen overlay for displaying canvas content.
/// Similar to the web app's "work mode" but full-screen for mobile.
class CanvasOverlay extends ConsumerWidget {
  const CanvasOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canvas = ref.watch(currentCanvasProvider);
    final isVisible = ref.watch(canvasVisibleProvider);

    if (canvas == null || !isVisible) {
      return const SizedBox.shrink();
    }

    return Material(
      color: context.backgroundColor,
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, ref, canvas),
            Expanded(
              child: CanvasRenderer(canvas: canvas),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref, Canvas canvas) {
    final canGoBack = ref.watch(canvasHistoryProvider).isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        border: Border(
          bottom: BorderSide(color: context.borderColor),
        ),
      ),
      child: Row(
        children: [
          // Back button (if there's history)
          if (canGoBack)
            IconButton(
              icon: const Icon(LucideIcons.arrowLeft, size: 20),
              onPressed: () => _handleBack(ref),
              tooltip: 'Back',
            ),

          // Close button
          IconButton(
            icon: const Icon(LucideIcons.x, size: 20),
            onPressed: () => _handleClose(ref),
            tooltip: 'Close',
          ),

          const SizedBox(width: 8),

          // Title
          Expanded(
            child: Text(
              canvas.displayTitle,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Refresh button
          IconButton(
            icon: const Icon(LucideIcons.refreshCw, size: 18),
            onPressed: () => _handleRefresh(ref, canvas),
            tooltip: 'Refresh',
          ),

          // More options
          PopupMenuButton<String>(
            icon: const Icon(LucideIcons.ellipsisVertical, size: 18),
            onSelected: (action) => _handleMenuAction(context, ref, action, canvas),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'open_in_browser',
                child: Row(
                  children: [
                    Icon(LucideIcons.externalLink, size: 16),
                    SizedBox(width: 8),
                    Text('Open in Browser'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'share',
                child: Row(
                  children: [
                    Icon(LucideIcons.share, size: 16),
                    SizedBox(width: 8),
                    Text('Share'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _handleBack(WidgetRef ref) {
    final previousCanvas = ref.read(canvasHistoryProvider.notifier).pop();
    if (previousCanvas != null) {
      ref.read(currentCanvasProvider.notifier).showCanvas(
            previousCanvas.type,
            previousCanvas.data,
          );
    } else {
      _handleClose(ref);
    }
  }

  void _handleClose(WidgetRef ref) {
    ref.read(canvasVisibleProvider.notifier).hide();
    ref.read(currentCanvasProvider.notifier).closeCanvas();
    ref.read(canvasHistoryProvider.notifier).clear();
  }

  void _handleRefresh(WidgetRef ref, Canvas canvas) {
    // Re-trigger canvas load by updating with same data
    ref.read(currentCanvasProvider.notifier).showCanvas(canvas.type, canvas.data);
  }

  void _handleMenuAction(BuildContext context, WidgetRef ref, String action, Canvas canvas) {
    switch (action) {
      case 'open_in_browser':
        // TODO: Open canvas URL in external browser
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Opening in browser...')),
        );
        break;
      case 'share':
        // TODO: Share canvas URL
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sharing...')),
        );
        break;
    }
  }
}

/// Modal bottom sheet style canvas for smaller content
class CanvasBottomSheet extends ConsumerWidget {
  final Canvas canvas;
  final double initialChildSize;
  final double minChildSize;
  final double maxChildSize;

  const CanvasBottomSheet({
    super.key,
    required this.canvas,
    this.initialChildSize = 0.7,
    this.minChildSize = 0.4,
    this.maxChildSize = 0.95,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DraggableScrollableSheet(
      initialChildSize: initialChildSize,
      minChildSize: minChildSize,
      maxChildSize: maxChildSize,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: context.backgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.textTertiary.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              _buildHeader(context, ref),

              // Content
              Expanded(
                child: CanvasRenderer(
                  canvas: canvas,
                  scrollController: scrollController,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.borderColor),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              canvas.displayTitle,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          IconButton(
            icon: const Icon(LucideIcons.x, size: 20),
            onPressed: () => Navigator.of(context).pop(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}
