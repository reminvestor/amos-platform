/// Represents a canvas that can be displayed in the app.
/// Canvases are work views that display rich content like editors, viewers, and dashboards.
class Canvas {
  final String type;
  final String? title;
  final Map<String, dynamic> data;
  final DateTime loadedAt;

  const Canvas({
    required this.type,
    this.title,
    this.data = const {},
    required this.loadedAt,
  });

  /// Common canvas types
  static const String landingPageEditor = 'landing_page_editor';
  static const String landingPageViewer = 'landing_page_viewer';
  static const String campaignViewer = 'campaign_viewer';
  static const String emailCampaignViewer = 'email_campaign_viewer';
  static const String contactViewer = 'contact_viewer';
  static const String contactDetail = 'contact_detail';
  static const String pipelineViewer = 'pipeline_viewer';
  static const String taskProgress = 'task_progress';
  static const String dynamicCanvas = 'dynamic_canvas';
  static const String freeformCanvas = 'freeform_canvas';
  static const String dashboard = 'dashboard';
  static const String analyticsCanvas = 'analytics_dashboard';
  static const String documentViewer = 'document_viewer';
  static const String imageViewer = 'image_viewer';
  static const String webPageViewer = 'web_page_viewer';
  static const String parallelTasks = 'parallel_tasks';

  /// Canvas types that should use WebView for rendering
  static const Set<String> webViewCanvasTypes = {
    landingPageEditor,
    freeformCanvas,
    dynamicCanvas,
  };

  /// Canvas types that can be rendered natively in Flutter
  static const Set<String> nativeCanvasTypes = {
    landingPageViewer,
    campaignViewer,
    emailCampaignViewer,
    contactViewer,
    contactDetail,
    pipelineViewer,
    taskProgress,
    dashboard,
    analyticsCanvas,
    documentViewer,
    imageViewer,
    parallelTasks,
  };

  /// Whether this canvas should use WebView for rendering
  bool get requiresWebView => webViewCanvasTypes.contains(type);

  /// Get the display title for this canvas type
  String get displayTitle {
    if (title != null) return title!;

    switch (type) {
      case landingPageEditor:
        return 'Landing Page Editor';
      case landingPageViewer:
        return 'Landing Pages';
      case campaignViewer:
      case emailCampaignViewer:
        return 'Email Campaigns';
      case contactViewer:
        return 'Contacts';
      case contactDetail:
        return 'Contact Details';
      case pipelineViewer:
        return 'Sales Pipeline';
      case taskProgress:
        return 'Task Progress';
      case dynamicCanvas:
        return 'Report';
      case freeformCanvas:
        return 'Canvas';
      case dashboard:
        return 'Dashboard';
      case analyticsCanvas:
        return 'Analytics';
      case documentViewer:
        return 'Document';
      case imageViewer:
        return 'Image';
      case webPageViewer:
        return 'Web Page';
      case parallelTasks:
        return 'Parallel Tasks';
      default:
        // Handle module canvases (format: module_<slug>)
        if (type.startsWith('module_')) {
          return _formatModuleName(type.substring(7));
        }
        return 'Canvas';
    }
  }

  String _formatModuleName(String slug) {
    return slug
        .split('_')
        .map((word) => word.isNotEmpty
            ? '${word[0].toUpperCase()}${word.substring(1)}'
            : '')
        .join(' ');
  }

  /// Create from SSE event data
  factory Canvas.fromEvent(String canvasType, dynamic data) {
    return Canvas(
      type: canvasType,
      data: data is Map<String, dynamic> ? data : {},
      loadedAt: DateTime.now(),
    );
  }

  /// Get a specific data value
  T? getData<T>(String key) {
    final value = data[key];
    if (value is T) return value;
    return null;
  }

  @override
  String toString() => 'Canvas(type: $type, title: $displayTitle, data: $data)';
}
