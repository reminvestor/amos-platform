import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:amos_mobile/genui/amos_catalog.dart';
import 'package:amos_mobile/utils/logger.dart';

/// GenUI Widget Spec - represents a widget specification parsed from AI response
class GenUIWidgetSpec {
  final String widgetType;
  final Map<String, dynamic> data;

  GenUIWidgetSpec({
    required this.widgetType,
    required this.data,
  });
}

/// Renders GenUI widgets from specifications
/// This widget takes a JSON spec and renders the appropriate UI widget
class GenUISimpleWidget extends StatelessWidget {
  final String widgetType;
  final Map<String, dynamic> data;
  final Function(String action, Map<String, dynamic> data)? onAction;

  const GenUISimpleWidget({
    super.key,
    required this.widgetType,
    required this.data,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    switch (widgetType) {
      case 'CampaignCard':
        return GenUIWidgetBuilder.buildCampaignCard(
          context,
          CampaignCardData.fromJson(data),
          onAction: onAction,
        );
      case 'ContactCard':
        return GenUIWidgetBuilder.buildContactCard(
          context,
          ContactCardData.fromJson(data),
          onAction: onAction,
        );
      case 'StatCard':
        return GenUIWidgetBuilder.buildStatCard(
          context,
          StatCardData.fromJson(data),
          onAction: onAction,
        );
      case 'LandingPagePreview':
        return GenUIWidgetBuilder.buildLandingPagePreview(
          context,
          LandingPagePreviewData.fromJson(data),
          onAction: onAction,
        );
      case 'TaskCard':
        return GenUIWidgetBuilder.buildTaskCard(
          context,
          TaskCardData.fromJson(data),
          onAction: onAction,
        );
      default:
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Unknown widget type: $widgetType'),
          ),
        );
    }
  }
}

/// Helper to parse GenUI JSON from AI responses
class GenUIParser {
  /// Extracts GenUI widget specifications from a message
  /// Looks for ```genui blocks in the content
  ///
  /// Format:
  /// ```genui
  /// {"widget": "CampaignCard", "data": {...}}
  /// ```
  ///
  /// Or multiple widgets:
  /// ```genui
  /// {"widgets": [{"widget": "CampaignCard", "data": {...}}, ...]}
  /// ```
  static List<GenUIWidgetSpec> extractWidgets(String content) {
    final widgets = <GenUIWidgetSpec>[];

    // Look for GenUI JSON blocks in the content
    // Format: ```genui\n{...}\n```
    final regex = RegExp(r'```genui\n(.*?)\n```', dotAll: true);
    final matches = regex.allMatches(content);

    for (final match in matches) {
      try {
        final jsonStr = match.group(1)!;
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;

        if (json.containsKey('widget') && json.containsKey('data')) {
          // Single widget
          widgets.add(GenUIWidgetSpec(
            widgetType: json['widget'] as String,
            data: json['data'] as Map<String, dynamic>,
          ));
        } else if (json.containsKey('widgets')) {
          // Multiple widgets
          final widgetList = json['widgets'] as List;
          for (final w in widgetList) {
            final wMap = w as Map<String, dynamic>;
            widgets.add(GenUIWidgetSpec(
              widgetType: wMap['widget'] as String,
              data: wMap['data'] as Map<String, dynamic>,
            ));
          }
        }
      } catch (e) {
        AppLogger.error('Failed to parse GenUI block', error: e);
      }
    }

    return widgets;
  }

  /// Removes GenUI JSON blocks from content, leaving only text
  static String stripWidgets(String content) {
    return content.replaceAll(RegExp(r'```genui\n.*?\n```', dotAll: true), '').trim();
  }

  /// Checks if content contains GenUI widgets
  static bool hasWidgets(String content) {
    return content.contains('```genui');
  }
}

/// Extension to easily build GenUI widgets from JSON
extension GenUIWidgetExtension on Map<String, dynamic> {
  Widget toGenUIWidget({
    required BuildContext context,
    Function(String action, Map<String, dynamic> data)? onAction,
  }) {
    final widgetType = this['widget'] as String?;
    final data = this['data'] as Map<String, dynamic>?;

    if (widgetType == null || data == null) {
      return const SizedBox.shrink();
    }

    return GenUISimpleWidget(
      widgetType: widgetType,
      data: data,
      onAction: onAction,
    );
  }
}
