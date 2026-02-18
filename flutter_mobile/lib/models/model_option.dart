/// Available AI model options for chat - simplified for mobile
class ModelOption {
  final String id;
  final String name;
  final String description;
  final bool supportsVision;
  final bool isDefault;
  final String? badge;

  const ModelOption({
    required this.id,
    required this.name,
    required this.description,
    this.supportsVision = false,
    this.isDefault = false,
    this.badge,
  });

  /// Available models - simplified list matching web defaults
  static const List<ModelOption> availableModels = [
    // Default - Qwen 3 Next (same as web)
    ModelOption(
      id: 'qwen3-next-80b',
      name: 'Qwen 3 Next',
      description: 'Fast reasoning with thinking',
      isDefault: true,
      badge: 'Default',
    ),
    // Vision model for images
    ModelOption(
      id: 'qwen3-vl-235b',
      name: 'Qwen 3 Vision',
      description: 'For images and documents',
      supportsVision: true,
      badge: 'Vision',
    ),
    // Backup Claude model
    ModelOption(
      id: 'claude-haiku-4-5',
      name: 'Claude Haiku 4.5',
      description: 'Fast backup option',
      supportsVision: true,
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
