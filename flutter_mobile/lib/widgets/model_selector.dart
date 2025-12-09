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

class _ModelPickerSheet extends StatelessWidget {
  final WidgetRef ref;

  const _ModelPickerSheet({required this.ref});

  double _getModelPower(String modelId) {
    if (modelId.contains('opus')) return 1.0;
    if (modelId.contains('sonnet')) return 0.75;
    if (modelId.contains('haiku')) return 0.25;
    return 0.5;
  }

  @override
  Widget build(BuildContext context) {
    final selectedModelId = ref.watch(selectedModelProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            const Divider(height: 1),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: ModelOption.availableModels.length,
                itemBuilder: (context, index) {
                final model = ModelOption.availableModels[index];
                final isSelected = model.id == selectedModelId;
                final power = _getModelPower(model.id);

                return ListTile(
                  leading: _ModelPowerIndicator(
                    power: power,
                    isSelected: isSelected,
                    primaryColor: context.primaryColor,
                  ),
                  title: Text(
                    model.name,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  subtitle: Row(
                    children: [
                      Text(
                        model.description,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: context.textSecondary,
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
                    ref.read(selectedModelProvider.notifier).setModel(model.id);
                    Navigator.pop(context);
                  },
                );
              },
              ),
            ),
          ],
        ),
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
