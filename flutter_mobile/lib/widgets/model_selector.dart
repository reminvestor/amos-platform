import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/config/theme.dart';
import 'package:amos_mobile/models/model_option.dart';
import 'package:amos_mobile/providers/app_providers.dart';

/// Brain icon model selector matching web app design
class ModelSelector extends ConsumerWidget {
  const ModelSelector({super.key});

  double _getModelPower(String modelId) {
    if (modelId.contains('opus')) return 1.0;
    if (modelId.contains('sonnet')) return 0.75;
    if (modelId.contains('haiku')) return 0.25;
    if (modelId.contains('llama') || modelId.contains('qwen')) return 0.6;
    return 0.5;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedModelId = ref.watch(selectedModelProvider);
    final power = _getModelPower(selectedModelId);

    return GestureDetector(
      onTap: () => _showModelPicker(context, ref),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.borderColor),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Outline brain (always visible)
            Icon(
              LucideIcons.brain,
              size: 22,
              color: context.textTertiary,
            ),
            // Filled brain (clipped based on power)
            ClipRect(
              clipper: _BrainClipper(power),
              child: Icon(
                LucideIcons.brain,
                size: 22,
                color: context.primaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showModelPicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _ModelPickerSheet(ref: ref),
    );
  }
}

/// Custom clipper for brain fill effect
class _BrainClipper extends CustomClipper<Rect> {
  final double fillPercent;

  _BrainClipper(this.fillPercent);

  @override
  Rect getClip(Size size) {
    // Fill from bottom up
    final clipHeight = size.height * fillPercent;
    return Rect.fromLTWH(0, size.height - clipHeight, size.width, clipHeight);
  }

  @override
  bool shouldReclip(_BrainClipper oldClipper) {
    return fillPercent != oldClipper.fillPercent;
  }
}

class _ModelPickerSheet extends StatefulWidget {
  final WidgetRef ref;

  const _ModelPickerSheet({required this.ref});

  @override
  State<_ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends State<_ModelPickerSheet> {
  ModelProvider _selectedProvider = ModelProvider.anthropic;

  double _getModelPower(String modelId) {
    if (modelId.contains('opus')) return 1.0;
    if (modelId.contains('sonnet')) return 0.75;
    if (modelId.contains('haiku')) return 0.25;
    if (modelId.contains('llama') || modelId.contains('qwen')) return 0.6;
    return 0.5;
  }

  IconData _getProviderIcon(ModelProvider provider) {
    switch (provider) {
      case ModelProvider.anthropic:
        return LucideIcons.sparkles;
      case ModelProvider.meta:
        return LucideIcons.boxes;
      case ModelProvider.alibaba:
        return LucideIcons.cloud;
    }
  }

  @override
  void initState() {
    super.initState();
    // Set initial provider based on currently selected model
    final selectedModelId = widget.ref.read(selectedModelProvider);
    final selectedModel = ModelOption.findById(selectedModelId);
    if (selectedModel != null) {
      _selectedProvider = selectedModel.provider;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedModelId = widget.ref.watch(selectedModelProvider);
    final modelsForProvider = ModelOption.byProvider(_selectedProvider);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(
                  LucideIcons.brain,
                  color: context.primaryColor,
                ),
                const SizedBox(width: 12),
                Text(
                  'Model Selection',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Choose the AI model for your conversation',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.textSecondary,
                  ),
            ),
          ),
          const SizedBox(height: 16),
          // Provider tabs (icons only)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: ModelProvider.values.map((provider) {
                final isSelected = provider == _selectedProvider;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedProvider = provider),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? context.primaryColor.withOpacity(0.1)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected
                              ? context.primaryColor
                              : context.borderColor,
                        ),
                      ),
                      child: Icon(
                        _getProviderIcon(provider),
                        size: 20,
                        color: isSelected
                            ? context.primaryColor
                            : context.textSecondary,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 8),
              itemCount: modelsForProvider.length,
              itemBuilder: (context, index) {
                final model = modelsForProvider[index];
                final isSelected = model.id == selectedModelId;
                final power = _getModelPower(model.id);

                return ListTile(
                  leading: _ModelPowerIndicator(
                    power: power,
                    isSelected: isSelected,
                    primaryColor: context.primaryColor,
                  ),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          model.name,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (model.badge != null) ...[
                        const SizedBox(width: 8),
                        _ModelBadge(badge: model.badge!),
                      ],
                    ],
                  ),
                  subtitle: Row(
                    children: [
                      Flexible(
                        child: Text(
                          model.description,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: context.textSecondary,
                              ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (model.supportsVision) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: context.primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                LucideIcons.eye,
                                size: 10,
                                color: context.primaryColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Vision',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: context.primaryColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  selected: isSelected,
                  onTap: () {
                    widget.ref.read(selectedModelProvider.notifier).setModel(model.id);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Visual power indicator for model selection
class _ModelPowerIndicator extends StatelessWidget {
  final double power;
  final bool isSelected;
  final Color primaryColor;

  const _ModelPowerIndicator({
    required this.power,
    required this.isSelected,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: isSelected ? primaryColor.withOpacity(0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            LucideIcons.brain,
            size: 20,
            color: context.textTertiary,
          ),
          ClipRect(
            clipper: _BrainClipper(power),
            child: Icon(
              LucideIcons.brain,
              size: 20,
              color: isSelected ? primaryColor : primaryColor.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// Badge chip for model labels (Default, Fast, Premium)
class _ModelBadge extends StatelessWidget {
  final String badge;

  const _ModelBadge({required this.badge});

  @override
  Widget build(BuildContext context) {
    Color backgroundColor;
    Color textColor;

    switch (badge.toLowerCase()) {
      case 'default':
        backgroundColor = Colors.blue.withOpacity(0.1);
        textColor = Colors.blue;
        break;
      case 'fast':
        backgroundColor = Colors.green.withOpacity(0.1);
        textColor = Colors.green;
        break;
      case 'premium':
        backgroundColor = Colors.amber.withOpacity(0.15);
        textColor = Colors.amber.shade700;
        break;
      default:
        backgroundColor = context.textTertiary.withOpacity(0.1);
        textColor = context.textSecondary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        badge,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}
