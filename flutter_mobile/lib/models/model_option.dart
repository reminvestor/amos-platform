/// AI model provider types
enum ModelProvider { anthropic, meta, alibaba }

/// Available AI model options for chat
class ModelOption {
  final String id;
  final String name;
  final String description;
  final bool supportsVision;
  final bool isDefault;
  final String? badge;
  final ModelProvider provider;

  const ModelOption({
    required this.id,
    required this.name,
    required this.description,
    this.supportsVision = false,
    this.isDefault = false,
    this.badge,
    this.provider = ModelProvider.anthropic,
  });

  /// Available models from BedrockService - matches web app order
  static const List<ModelOption> availableModels = [
    // Anthropic - Recommended models first
    ModelOption(
      id: 'claude-sonnet-4-5',
      name: 'Claude Sonnet 4.5',
      description: 'Balanced performance',
      isDefault: true,
      badge: 'Default',
      supportsVision: true,
      provider: ModelProvider.anthropic,
    ),
    ModelOption(
      id: 'claude-haiku-4-5-20251001',
      name: 'Claude Haiku 4.5',
      description: 'Fast & affordable',
      badge: 'Fast',
      supportsVision: true,
      provider: ModelProvider.anthropic,
    ),
    ModelOption(
      id: 'claude-3-5-sonnet',
      name: 'Claude 3.5 Sonnet',
      description: 'Previous generation balanced',
      supportsVision: true,
      provider: ModelProvider.anthropic,
    ),
    ModelOption(
      id: 'claude-3-haiku',
      name: 'Claude 3.5 Haiku',
      description: 'Quick responses, lower cost',
      provider: ModelProvider.anthropic,
    ),
    // Anthropic Premium models
    ModelOption(
      id: 'claude-opus-4-5',
      name: 'Claude Opus 4.5',
      description: 'Maximum reasoning capability',
      badge: 'Premium',
      supportsVision: true,
      provider: ModelProvider.anthropic,
    ),
    ModelOption(
      id: 'claude-opus-4-1',
      name: 'Claude Opus 4.1',
      description: 'Previous gen premium',
      supportsVision: true,
      provider: ModelProvider.anthropic,
    ),
    // Meta Llama
    ModelOption(
      id: 'meta-llama-3-2-90b',
      name: 'Llama 3.2 90B Vision',
      description: 'Open source with vision',
      supportsVision: true,
      provider: ModelProvider.meta,
    ),
    ModelOption(
      id: 'meta-llama-3-3-70b',
      name: 'Llama 3.3 70B',
      description: 'Open source large model',
      provider: ModelProvider.meta,
    ),
    // Alibaba Qwen
    ModelOption(
      id: 'qwen-3-32b',
      name: 'Qwen 3 32B',
      description: 'Efficient multilingual model',
      provider: ModelProvider.alibaba,
    ),
  ];

  /// Get models filtered by provider
  static List<ModelOption> byProvider(ModelProvider provider) {
    return availableModels.where((m) => m.provider == provider).toList();
  }

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
