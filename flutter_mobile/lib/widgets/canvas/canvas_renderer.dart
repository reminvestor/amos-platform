import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/canvas.dart';
import 'package:amos_mobile/widgets/canvas/canvases/landing_page_canvas.dart';
import 'package:amos_mobile/widgets/canvas/canvases/campaign_canvas.dart';
import 'package:amos_mobile/widgets/canvas/canvases/contact_canvas.dart';
import 'package:amos_mobile/widgets/canvas/canvases/task_progress_canvas.dart';
import 'package:amos_mobile/widgets/canvas/canvases/webview_canvas.dart';
import 'package:amos_mobile/widgets/canvas/canvases/dynamic_content_canvas.dart';

/// Main canvas renderer that dispatches to specific canvas widgets based on type.
class CanvasRenderer extends ConsumerWidget {
  final Canvas canvas;
  final ScrollController? scrollController;

  const CanvasRenderer({
    super.key,
    required this.canvas,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Route to appropriate canvas widget based on type
    switch (canvas.type) {
      // Landing Pages
      case Canvas.landingPageEditor:
        return WebViewCanvas(
          canvas: canvas,
          canvasType: 'landing_page_editor',
        );
      case Canvas.landingPageViewer:
        return LandingPageListCanvas(canvas: canvas);

      // Campaigns
      case Canvas.campaignViewer:
      case Canvas.emailCampaignViewer:
        return CampaignListCanvas(canvas: canvas);

      // Contacts
      case Canvas.contactViewer:
        return ContactListCanvas(canvas: canvas);
      case Canvas.contactDetail:
        return ContactDetailCanvas(canvas: canvas);

      // Tasks
      case Canvas.taskProgress:
      case Canvas.parallelTasks:
        return TaskProgressCanvas(canvas: canvas);

      // Dynamic/Freeform content (requires WebView)
      case Canvas.dynamicCanvas:
      case Canvas.freeformCanvas:
        return WebViewCanvas(
          canvas: canvas,
          canvasType: canvas.type,
        );

      // Dashboard and analytics
      case Canvas.dashboard:
      case Canvas.analyticsCanvas:
        return DynamicContentCanvas(
          canvas: canvas,
          contentType: 'dashboard',
        );

      // Document/Image viewers
      case Canvas.documentViewer:
        return DynamicContentCanvas(
          canvas: canvas,
          contentType: 'document',
        );
      case Canvas.imageViewer:
        return DynamicContentCanvas(
          canvas: canvas,
          contentType: 'image',
        );
      case Canvas.webPageViewer:
        return WebViewCanvas(
          canvas: canvas,
          canvasType: 'web_page_viewer',
        );

      default:
        // Handle module canvases and unknown types
        if (canvas.type.startsWith('module_')) {
          return WebViewCanvas(
            canvas: canvas,
            canvasType: canvas.type,
          );
        }
        return _buildUnsupportedCanvas(context);
    }
  }

  Widget _buildUnsupportedCanvas(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                LucideIcons.layoutTemplate,
                size: 48,
                color: context.primaryColor,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Canvas: ${canvas.type}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'This canvas type is not yet supported in the mobile app.\n'
              'Open the web app to view this content.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.textSecondary,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                // TODO: Open in web browser
              },
              icon: const Icon(LucideIcons.externalLink, size: 16),
              label: const Text('Open in Web App'),
            ),
          ],
        ),
      ),
    );
  }
}
