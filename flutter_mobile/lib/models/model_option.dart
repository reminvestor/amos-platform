/// Available AI model options for chat
class ModelOption {
  final String id;
  final String name;
  final String description;
  final bool supportsVision;
  final bool isDefault;

  const ModelOption({
    required this.id,
    required this.name,
    required this.description,
    this.supportsVision = false,
    this.isDefault = false,
  });

  /// Available models from BedrockService
  static const List<ModelOption> availableModels = [
    ModelOption(
      id: 'claude-sonnet-4-5',
      name: 'Claude Sonnet 4.5',
      description: 'Balanced performance (default)',
      isDefault: true,
    ),
    ModelOption(
      id: 'claude-opus-4-1',
      name: 'Claude Opus 4.1',
      description: 'Most capable, vision support',
      supportsVision: true,
    ),
    ModelOption(
      id: 'claude-3-5-sonnet',
      name: 'Claude 3.5 Sonnet',
      description: 'Fast and capable',
      supportsVision: true,
    ),
    ModelOption(
      id: 'claude-3-5-haiku',
      name: 'Claude 3.5 Haiku',
      description: 'Quick responses',
    ),
    ModelOption(
      id: 'claude-haiku-4-5',
      name: 'Claude Haiku 4.5',
      description: 'Fastest, most affordable',
    ),
  ];

  static ModelOption get defaultModel =>
      availableModels.firstWhere((m) => m.isDefault);

  static ModelOption? findById(String id) {
    try {
      return availableModels.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }
}
