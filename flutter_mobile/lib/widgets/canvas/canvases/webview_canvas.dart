import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:amos_mobile/config/env.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/canvas.dart';
import 'package:amos_mobile/services/api_client.dart';
import 'package:amos_mobile/services/canvas_service.dart';
import 'package:amos_mobile/utils/logger.dart';

/// Canvas that renders HTML content in a WebView.
/// Used for complex canvases like landing page editor, dynamic canvas, etc.
class WebViewCanvas extends ConsumerStatefulWidget {
  final Canvas canvas;
  final String canvasType;

  const WebViewCanvas({
    super.key,
    required this.canvas,
    required this.canvasType,
  });

  @override
  ConsumerState<WebViewCanvas> createState() => _WebViewCanvasState();
}

class _WebViewCanvasState extends ConsumerState<WebViewCanvas> {
  final _canvasService = CanvasService();
  WebViewController? _controller;
  bool _isLoading = true;
  String? _error;
  CanvasContent? _content;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    try {
      // Load canvas content from server
      final content = await _canvasService.loadCanvas(
        canvasType: widget.canvasType,
        canvasData: widget.canvas.data,
      );

      setState(() {
        _content = content;
      });

      // Get auth token for WebView
      final token = await ApiClient.instance.getAuthToken();

      // Create WebView controller
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (url) {
              setState(() => _isLoading = true);
            },
            onPageFinished: (url) {
              setState(() => _isLoading = false);
            },
            onWebResourceError: (error) {
              AppLogger.error('WebView error: ${error.description}');
              setState(() {
                _error = error.description;
                _isLoading = false;
              });
            },
            onNavigationRequest: (request) {
              // Handle internal navigation vs external links
              if (request.url.startsWith(Env.apiBaseUrl)) {
                return NavigationDecision.navigate;
              }
              // TODO: Open external links in browser
              return NavigationDecision.prevent;
            },
          ),
        );

      // Add JavaScript channel for communication with Flutter
      controller.addJavaScriptChannel(
        'FlutterChannel',
        onMessageReceived: (message) {
          _handleJavaScriptMessage(message.message);
        },
      );

      // Inject auth token and base URL into page
      final html = _wrapHtmlWithAuth(content.html, token);
      await controller.loadHtmlString(html, baseUrl: Env.apiBaseUrl);

      setState(() {
        _controller = controller;
      });
    } catch (e) {
      AppLogger.error('Failed to initialize WebView canvas', error: e);
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  String _wrapHtmlWithAuth(String html, String? token) {
    // Wrap the HTML content with proper styling and auth setup
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <style>
    * {
      box-sizing: border-box;
    }
    body {
      margin: 0;
      padding: 16px;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      font-size: 14px;
      line-height: 1.5;
      color: #333;
      background: #fff;
    }
    img {
      max-width: 100%;
      height: auto;
    }
    table {
      width: 100%;
      border-collapse: collapse;
    }
    th, td {
      padding: 8px;
      text-align: left;
      border-bottom: 1px solid #eee;
    }
    .btn, button {
      padding: 8px 16px;
      border-radius: 8px;
      border: none;
      background: #4F46E5;
      color: white;
      font-size: 14px;
      cursor: pointer;
    }
    pre {
      background: #f5f5f5;
      padding: 12px;
      border-radius: 8px;
      overflow-x: auto;
    }
    code {
      font-family: 'SF Mono', Monaco, monospace;
      font-size: 13px;
    }
  </style>
  <script>
    // Auth token for API calls
    window.AMOS_AUTH_TOKEN = '${token ?? ''}';
    window.AMOS_API_BASE = '${Env.apiBaseUrl}';

    // Helper to send messages to Flutter
    function sendToFlutter(action, data) {
      if (window.FlutterChannel) {
        window.FlutterChannel.postMessage(JSON.stringify({ action, data }));
      }
    }

    // Intercept form submissions and link clicks
    document.addEventListener('click', function(e) {
      const link = e.target.closest('a[href]');
      if (link) {
        const href = link.getAttribute('href');
        if (href && !href.startsWith('javascript:')) {
          e.preventDefault();
          sendToFlutter('navigate', { url: href });
        }
      }
    });
  </script>
</head>
<body>
$html
</body>
</html>
''';
  }

  void _handleJavaScriptMessage(String message) {
    try {
      // Parse message from JavaScript
      AppLogger.info('JavaScript message: $message');
      // TODO: Handle navigation, form submissions, etc.
    } catch (e) {
      AppLogger.error('Failed to handle JavaScript message', error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _buildErrorState();
    }

    return Stack(
      children: [
        if (_controller != null)
          WebViewWidget(controller: _controller!),

        // Loading overlay
        if (_isLoading)
          Container(
            color: context.backgroundColor,
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          ),
      ],
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
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
              'Failed to load canvas',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Unknown error',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.textSecondary,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _initWebView,
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
