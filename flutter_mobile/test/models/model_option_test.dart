import 'package:flutter_test/flutter_test.dart';
import 'package:amos_mobile/models/model_option.dart';

void main() {
  group('ModelProvider', () {
    test('enum has expected values', () {
      expect(ModelProvider.values, contains(ModelProvider.anthropic));
      expect(ModelProvider.values, contains(ModelProvider.meta));
      expect(ModelProvider.values, contains(ModelProvider.alibaba));
      expect(ModelProvider.values, hasLength(3));
    });
  });

  group('ModelOption', () {
    test('availableModels contains expected models', () {
      expect(ModelOption.availableModels, isNotEmpty);
      expect(
        ModelOption.availableModels.map((m) => m.id),
        contains('claude-sonnet-4-5'),
      );
    });

    test('defaultModel returns model with isDefault true', () {
      final defaultModel = ModelOption.defaultModel;
      expect(defaultModel.isDefault, isTrue);
      expect(defaultModel.id, equals('claude-sonnet-4-5'));
    });

    test('findById returns correct model', () {
      final model = ModelOption.findById('claude-sonnet-4-5');
      expect(model, isNotNull);
      expect(model?.name, equals('Claude Sonnet 4.5'));
    });

    test('findById returns null for unknown id', () {
      final model = ModelOption.findById('unknown-model');
      expect(model, isNull);
    });

    test('byProvider filters by anthropic', () {
      final anthropicModels = ModelOption.byProvider(ModelProvider.anthropic);
      expect(anthropicModels, isNotEmpty);
      expect(
        anthropicModels.every((m) => m.provider == ModelProvider.anthropic),
        isTrue,
      );
    });

    test('byProvider filters by meta', () {
      final metaModels = ModelOption.byProvider(ModelProvider.meta);
      expect(metaModels, isNotEmpty);
      expect(
        metaModels.every((m) => m.provider == ModelProvider.meta),
        isTrue,
      );
    });

    test('byProvider filters by alibaba', () {
      final alibabaModels = ModelOption.byProvider(ModelProvider.alibaba);
      expect(alibabaModels, isNotEmpty);
      expect(
        alibabaModels.every((m) => m.provider == ModelProvider.alibaba),
        isTrue,
      );
    });

    test('model with supportsVision true has vision capability', () {
      final visionModels = ModelOption.availableModels.where((m) => m.supportsVision);
      expect(visionModels, isNotEmpty);
    });

    test('model with badge has badge text', () {
      final modelsWithBadge = ModelOption.availableModels.where((m) => m.badge != null);
      expect(modelsWithBadge, isNotEmpty);
      expect(modelsWithBadge.first.badge, isNotEmpty);
    });

    test('claude-sonnet-4-5 has correct properties', () {
      final model = ModelOption.findById('claude-sonnet-4-5');
      expect(model, isNotNull);
      expect(model?.name, equals('Claude Sonnet 4.5'));
      expect(model?.description, equals('Balanced performance'));
      expect(model?.isDefault, isTrue);
      expect(model?.badge, equals('Default'));
      expect(model?.supportsVision, isTrue);
      expect(model?.provider, equals(ModelProvider.anthropic));
    });

    test('claude-haiku-4-5 has Fast badge', () {
      final model = ModelOption.findById('claude-haiku-4-5-20251001');
      expect(model, isNotNull);
      expect(model?.badge, equals('Fast'));
    });

    test('claude-opus-4-5 has Premium badge', () {
      final model = ModelOption.findById('claude-opus-4-5');
      expect(model, isNotNull);
      expect(model?.badge, equals('Premium'));
    });

    test('llama model has meta provider', () {
      final model = ModelOption.findById('meta-llama-3-2-90b');
      expect(model, isNotNull);
      expect(model?.provider, equals(ModelProvider.meta));
      expect(model?.supportsVision, isTrue);
    });

    test('qwen model has alibaba provider', () {
      final model = ModelOption.findById('qwen-3-32b');
      expect(model, isNotNull);
      expect(model?.provider, equals(ModelProvider.alibaba));
    });
  });
}
