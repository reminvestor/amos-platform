import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/widgets/model_selector.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/model_option.dart';
import 'package:amos_mobile/providers/app_providers.dart';

void main() {
  Widget createTestWidget(Widget child, {String? initialModel}) {
    return ProviderScope(
      overrides: [
        if (initialModel != null)
          selectedModelProvider.overrideWith(() => _TestSelectedModelNotifier(initialModel)),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: child),
      ),
    );
  }

  group('ModelSelector', () {
    testWidgets('renders correctly with brain icon', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const ModelSelector(),
      ));

      // Should display brain icon
      expect(find.byIcon(LucideIcons.brain), findsWidgets);
    });

    testWidgets('has correct container size', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const ModelSelector(),
      ));

      // Find the container
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(ModelSelector),
          matching: find.byType(Container).first,
        ),
      );

      expect(container.constraints?.maxWidth, equals(40));
      expect(container.constraints?.maxHeight, equals(40));
    });

    testWidgets('opens model picker on tap', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const ModelSelector(),
      ));

      // Tap the selector
      await tester.tap(find.byType(ModelSelector));
      await tester.pumpAndSettle();

      // Should show model selection title
      expect(find.text('Model Selection'), findsOneWidget);
    });

    testWidgets('shows provider tabs in picker sheet', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const ModelSelector(),
      ));

      // Open the picker
      await tester.tap(find.byType(ModelSelector));
      await tester.pumpAndSettle();

      // Should show provider icons (sparkles for Anthropic, boxes for Meta, cloud for Alibaba)
      expect(find.byIcon(LucideIcons.sparkles), findsOneWidget);
      expect(find.byIcon(LucideIcons.boxes), findsOneWidget);
      expect(find.byIcon(LucideIcons.cloud), findsOneWidget);
    });

    testWidgets('displays available models in picker', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const ModelSelector(),
      ));

      // Open the picker
      await tester.tap(find.byType(ModelSelector));
      await tester.pumpAndSettle();

      // Should show Anthropic models by default (Claude Sonnet 4.5 is default)
      expect(find.text('Claude Sonnet 4.5'), findsOneWidget);
    });

    testWidgets('shows default badge on default model', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const ModelSelector(),
      ));

      // Open the picker
      await tester.tap(find.byType(ModelSelector));
      await tester.pumpAndSettle();

      // Should show "Default" badge
      expect(find.text('Default'), findsOneWidget);
    });

    testWidgets('shows vision indicator for vision-capable models', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const ModelSelector(),
      ));

      // Open the picker
      await tester.tap(find.byType(ModelSelector));
      await tester.pumpAndSettle();

      // Should show Vision text for models that support vision
      expect(find.text('Vision'), findsWidgets);
    });

    testWidgets('closes picker when model is selected', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const ModelSelector(),
      ));

      // Open the picker
      await tester.tap(find.byType(ModelSelector));
      await tester.pumpAndSettle();

      // Tap on a model (Claude Haiku 4.5)
      await tester.tap(find.text('Claude Haiku 4.5'));
      await tester.pumpAndSettle();

      // Picker should be closed
      expect(find.text('Model Selection'), findsNothing);
    });

    testWidgets('switches provider tabs correctly', (tester) async {
      await tester.pumpWidget(createTestWidget(
        const ModelSelector(),
      ));

      // Open the picker
      await tester.tap(find.byType(ModelSelector));
      await tester.pumpAndSettle();

      // Switch to Meta tab (boxes icon)
      await tester.tap(find.byIcon(LucideIcons.boxes));
      await tester.pumpAndSettle();

      // Should show Meta models
      expect(find.text('Llama 3.2 90B Vision'), findsOneWidget);
    });
  });

  group('ModelOption', () {
    test('defaultModel returns correct model', () {
      expect(ModelOption.defaultModel.id, equals('claude-sonnet-4-5'));
      expect(ModelOption.defaultModel.isDefault, isTrue);
    });

    test('findById returns correct model', () {
      final model = ModelOption.findById('claude-opus-4-5');
      expect(model, isNotNull);
      expect(model!.name, equals('Claude Opus 4.5'));
    });

    test('findById returns null for unknown id', () {
      final model = ModelOption.findById('unknown-model');
      expect(model, isNull);
    });

    test('byProvider filters correctly', () {
      final anthropicModels = ModelOption.byProvider(ModelProvider.anthropic);
      expect(anthropicModels.every((m) => m.provider == ModelProvider.anthropic), isTrue);
      expect(anthropicModels.isNotEmpty, isTrue);

      final metaModels = ModelOption.byProvider(ModelProvider.meta);
      expect(metaModels.every((m) => m.provider == ModelProvider.meta), isTrue);
    });
  });
}

/// Test notifier that allows setting initial model
class _TestSelectedModelNotifier extends SelectedModelNotifier {
  final String _initialModel;

  _TestSelectedModelNotifier(this._initialModel);

  @override
  String build() => _initialModel;
}
