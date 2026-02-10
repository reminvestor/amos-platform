require "aws-sdk-bedrockruntime"
require "json"

class BedrockService
  include AgentLightningInstrumentable
  include WorkTokenTrackable

  attr_reader :model_registry
  
  # Sanitize tool use IDs to comply with Bedrock's requirements:
  # - Must be exactly 9 characters
  # - Only alphanumeric (a-z, A-Z, 0-9)
  # Some models (Mistral) generate IDs with underscores or different lengths
  def self.sanitize_tool_id(tool_id)
    return generate_tool_id unless tool_id.present?
    
    # Remove any non-alphanumeric characters
    sanitized = tool_id.to_s.gsub(/[^a-zA-Z0-9]/, '')
    
    # Ensure exactly 9 characters
    if sanitized.length >= 9
      sanitized[0, 9]
    else
      # Pad with random chars if too short
      padding = ('a'..'z').to_a.sample(9 - sanitized.length).join
      (sanitized + padding)[0, 9]
    end
  end
  
  # Generate a valid tool ID (9 alphanumeric characters)
  def self.generate_tool_id
    chars = ('a'..'z').to_a + ('A'..'Z').to_a + ('0'..'9').to_a
    chars.sample(9).join
  end

  # Available Bedrock models with their characteristics
  AVAILABLE_MODELS = {
    'claude-sonnet-4-5' => {
      id: 'global.anthropic.claude-sonnet-4-5-20250929-v1:0',
      name: 'Claude Sonnet 4.5',
      description: 'Latest model, best for complex tasks',
      max_tokens: 25000,
      cost_per_1m_input: 3.00,
      cost_per_1m_output: 15.00,
      supports_vision: false,
      supports_tools: true,
      supports_caching: false,  # Global endpoint limitation
      endpoint_type: 'global'
    },
    'claude-opus-4-1' => {
      id: 'us.anthropic.claude-opus-4-1-20250805-v1:0',
      name: 'Claude Opus 4.1',
      description: 'Most capable, includes vision',
      max_tokens: 25000,
      cost_per_1m_input: 15.00,
      cost_per_1m_output: 75.00,
      supports_vision: true,
      supports_tools: true,
      supports_caching: false,  # AWS SDK doesn't support cachePoint param yet
      endpoint_type: 'regional'
    },
    'claude-opus-4-5' => {
      id: 'global.anthropic.claude-opus-4-5-20251101-v1:0',
      name: 'Claude Opus 4.5',
      description: 'Frontier model, maximum reasoning',
      max_tokens: 30000,
      cost_per_1m_input: 5.00,    # Actual AWS pricing
      cost_per_1m_output: 25.00,
      supports_vision: true,
      supports_tools: true,
      supports_caching: false, # Global endpoint limitation
      endpoint_type: 'global'
    },
    'claude-opus-4-6' => {
      id: 'global.anthropic.claude-opus-4-6-v1',
      name: 'Claude Opus 4.6',
      description: 'Latest frontier model, enhanced reasoning and coding',
      max_tokens: 30000,
      cost_per_1m_input: 5.00,    # Same as Opus 4.5
      cost_per_1m_output: 25.00,
      supports_vision: true,
      supports_tools: true,
      supports_caching: false,
      endpoint_type: 'global'
    },
    'qwen-3-32b' => {
      id: 'qwen.qwen3-32b-v1:0', # ON_DEMAND direct
      name: 'Qwen 3 32B',
      description: 'Latest open weights model',
      max_tokens: 8192,
      context_window: 32768,
      cost_per_1m_input: 0.15,   # Actual AWS pricing
      cost_per_1m_output: 0.60,
      supports_vision: false,
      supports_tools: true,
      supports_caching: false,
      endpoint_type: 'regional'
    },
    'qwen-3-coder-30b' => {
      id: 'qwen.qwen3-coder-30b-a3b-v1:0', # ON_DEMAND direct
      name: 'Qwen 3 Coder 30B',
      description: 'Specialized for code generation',
      max_tokens: 8192,
      context_window: 32768,
      cost_per_1m_input: 0.15,   # Actual AWS pricing
      cost_per_1m_output: 0.60,
      supports_vision: false,
      supports_tools: true,
      supports_caching: false,
      endpoint_type: 'regional'
    },
    'meta-llama-3-3-70b' => {
      id: 'us.meta.llama3-3-70b-instruct-v1:0', # US inference profile
      name: 'Llama 3.3 70B',
      description: 'High performance open model',
      max_tokens: 8192,
      cost_per_1m_input: 0.90,
      cost_per_1m_output: 0.90,
      supports_vision: false,
      supports_tools: true,
      supports_caching: false,
      endpoint_type: 'regional'
    },
    'meta-llama-3-2-90b' => {
      id: 'us.meta.llama3-2-90b-instruct-v1:0', # US inference profile
      name: 'Llama 3.2 90B Vision',
      description: 'Multimodal open model',
      max_tokens: 8192,
      cost_per_1m_input: 0.90,
      cost_per_1m_output: 0.90,
      supports_vision: true,
      supports_tools: true,
      supports_tools_streaming: false,  # Doesn't support tool use in streaming mode!
      supports_caching: false,
      endpoint_type: 'regional'
    },
    'qwen-2-5-coder-32b' => { # Legacy alias, maps to Qwen 3 Coder
      id: 'qwen.qwen3-coder-30b-a3b-v1:0',
      name: 'Qwen 2.5 Coder 32B',
      description: 'Specialized for code generation (legacy alias)',
      max_tokens: 8192, # Output limit (context window is 32K, need room for input)
      context_window: 32768,
      cost_per_1m_input: 0.20,
      cost_per_1m_output: 0.20,
      supports_vision: false,
      supports_tools: true,
      supports_caching: false,
      endpoint_type: 'regional'
    },
    'claude-3-5-sonnet' => {
      id: 'us.anthropic.claude-3-5-sonnet-20241022-v2:0',
      name: 'Claude 3.5 Sonnet',
      description: 'Fast and capable',
      max_tokens: 8192,
      cost_per_1m_input: 3.00,
      cost_per_1m_output: 15.00,
      supports_vision: true,
      supports_tools: true,
      supports_caching: false,  # AWS SDK doesn't support cachePoint param yet
      endpoint_type: 'regional'
    },
    'claude-3-haiku' => {
      id: 'us.anthropic.claude-3-5-haiku-20241022-v1:0',
      name: 'Claude 3.5 Haiku',
      description: 'Fastest, most affordable',
      max_tokens: 8192,
      cost_per_1m_input: 0.80,
      cost_per_1m_output: 4.00,
      supports_vision: false,
      supports_tools: true,
      supports_caching: false,  # AWS SDK doesn't support cachePoint param yet
      endpoint_type: 'regional'
    },
    'claude-haiku-4-5-20251001' => {
      id: 'us.anthropic.claude-3-5-haiku-20241022-v1:0',
      name: 'Claude Haiku 4.5',
      description: 'Fast and efficient',
      max_tokens: 8192,
      cost_per_1m_input: 1.00,   # Actual AWS pricing
      cost_per_1m_output: 5.00,
      supports_vision: false,
      supports_tools: true,
      supports_caching: false,  # AWS SDK doesn't support cachePoint param yet
      endpoint_type: 'regional'
    },
    # Aliases for Claude Haiku 4.5
    'claude-haiku-4-5' => {
      id: 'us.anthropic.claude-3-5-haiku-20241022-v1:0',
      name: 'Claude Haiku 4.5',
      description: 'Fast and efficient',
      max_tokens: 8192,
      cost_per_1m_input: 1.00,   # Actual AWS pricing
      cost_per_1m_output: 5.00,
      supports_vision: false,
      supports_tools: true,
      supports_caching: false,  # AWS SDK doesn't support cachePoint param yet
      endpoint_type: 'regional'
    },
    'claude-4-5-haiku' => {
      id: 'us.anthropic.claude-3-5-haiku-20241022-v1:0',
      name: 'Claude Haiku 4.5',
      description: 'Fast and efficient',
      max_tokens: 8192,
      cost_per_1m_input: 1.00,   # Actual AWS pricing
      cost_per_1m_output: 5.00,
      supports_vision: false,
      supports_tools: true,
      supports_caching: false,  # AWS SDK doesn't support cachePoint param yet
      endpoint_type: 'regional'
    },
    # Mistral models - excellent for reasoning and tool use
    'mistral-large-3' => {
      id: 'mistral.mistral-large-3-675b-instruct',
      name: 'Mistral Large 3',
      description: 'Excellent for tool use, agentic workflows, 128K context',
      max_tokens: 8192,
      context_window: 128000,
      cost_per_1m_input: 0.50,   # Actual AWS pricing - very competitive!
      cost_per_1m_output: 1.50,
      supports_vision: true,
      supports_tools: true,
      supports_tools_streaming: true,
      supports_caching: false,
      endpoint_type: 'regional'
    },
    'mistral-large-2' => {
      id: 'mistral.mistral-large-2407-v1:0',
      name: 'Mistral Large 2',
      description: 'Previous gen - good for reasoning and tool use',
      max_tokens: 8192,
      context_window: 128000,
      cost_per_1m_input: 2.00,
      cost_per_1m_output: 6.00,
      supports_vision: false,
      supports_tools: true,
      supports_tools_streaming: true,
      supports_caching: false,
      endpoint_type: 'regional'
    },
    'mistral-small' => {
      id: 'mistral.mistral-small-2402-v1:0',
      name: 'Mistral Small',
      description: 'Fast and efficient for simple tasks',
      max_tokens: 8192,
      context_window: 32000,
      cost_per_1m_input: 0.10,
      cost_per_1m_output: 0.30,
      supports_vision: false,
      supports_tools: true,
      supports_tools_streaming: true,
      supports_caching: false,
      endpoint_type: 'regional'
    },
    # DeepSeek V3.1 - fast, general purpose (similar price to Mistral Large 3)
    # NOTE: Only available in specific regions (us-east-2)
    'deepseek-v3' => {
      id: 'deepseek.v3-v1:0',
      name: 'DeepSeek V3.1',
      description: 'Fast general purpose - strong for coding and conversation',
      max_tokens: 8192,
      context_window: 131072,  # 128K context
      cost_per_1m_input: 0.58,   # Actual AWS pricing
      cost_per_1m_output: 1.68,
      supports_vision: false,
      supports_tools: true,
      supports_tools_streaming: true,
      supports_caching: false,
      endpoint_type: 'regional',
      region: 'us-east-2'
    },
    # DeepSeek R1 - Advanced reasoning model (thinking tokens visible)
    # Great for analysis, planning, complex reasoning tasks
    # NOTE: R1 requires inference profile - try us-east-2 region with inference profile ID
    'deepseek-r1' => {
      id: 'us.deepseek.r1-v1:0',  # Inference profile format
      name: 'DeepSeek R1',
      description: 'Advanced reasoning - shows thinking process, excellent for analysis',
      max_tokens: 8192,
      context_window: 131072,  # 128K context
      cost_per_1m_input: 1.35,   # Actual AWS pricing
      cost_per_1m_output: 5.40,
      supports_vision: false,
      supports_tools: true,
      supports_tools_streaming: true,
      supports_caching: false,
      endpoint_type: 'cross_region',  # Use cross-region inference profile
      region: 'us-east-2'
    },
    # NVIDIA Nemotron - high efficiency for agentic tasks
    'nemotron-nano-9b' => {
      id: 'nvidia.nemotron-nano-9b-v2',
      name: 'NVIDIA Nemotron Nano 2',
      description: 'Cheapest model - good for simple tasks, reasoning, tool calling',
      max_tokens: 8192,
      context_window: 32768,
      cost_per_1m_input: 0.06,   # Actual AWS pricing - CHEAPEST!
      cost_per_1m_output: 0.23,
      supports_vision: false,
      supports_tools: true,
      supports_tools_streaming: true,
      supports_caching: false,
      endpoint_type: 'regional'
    },
    'nemotron-nano-12b-vl' => {
      id: 'nvidia.nemotron-nano-12b-v2',
      name: 'NVIDIA Nemotron Nano 12B v2 VL',
      description: 'Vision-language model for multimodal agentic tasks',
      max_tokens: 8192,
      context_window: 32768,
      cost_per_1m_input: 0.20,
      cost_per_1m_output: 0.40,
      supports_vision: true,
      supports_tools: true,
      supports_tools_streaming: true,
      supports_caching: false,
      endpoint_type: 'regional'
    },
    # Qwen3-Next - optimized for tool use and agentic workflows (DEFAULT MODEL)
    # NOTE: max_tokens increased to 32768 to support ThinkingDepthService
    # Qwen3 models support high output token counts for chain-of-thought reasoning
    'qwen3-next-80b' => {
      id: 'qwen.qwen3-next-80b-a3b',
      name: 'Qwen3-Next-80B-A3B',
      description: 'Fast inference, optimized for RAG, tool use & agentic workflows',
      max_tokens: 32768,  # High limit for thinking depth (quick=4K, standard=8K, deep=16K, maximum=32K)
      context_window: 131072,  # Ultra-long context (131K)
      cost_per_1m_input: 0.15,   # $0.00015 per 1K tokens
      cost_per_1m_output: 1.20,  # $0.00120 per 1K tokens
      supports_vision: false,
      supports_tools: true,
      supports_tools_streaming: true,
      supports_caching: false,
      endpoint_type: 'regional',
      region: 'us-east-1'  # Must use regional endpoint
    },
    'qwen3-vl-235b' => {
      id: 'qwen.qwen3-vl-235b-a22b',
      name: 'Qwen3-VL-235B-A22B',
      description: 'Multimodal - images, video, UI automation, code from screenshots',
      max_tokens: 8192,
      context_window: 131072,
      cost_per_1m_input: 1.00,
      cost_per_1m_output: 2.00,
      supports_vision: true,
      supports_tools: true,
      supports_tools_streaming: true,
      supports_caching: false,
      endpoint_type: 'regional'
    },
    # Ministral models - edge-optimized
    'ministral-3b' => {
      id: 'mistral.ministral-3-3b-instruct',
      name: 'Ministral 3 3B',
      description: 'Edge-optimized, lightweight real-time applications',
      max_tokens: 8192,
      context_window: 32768,
      cost_per_1m_input: 0.04,
      cost_per_1m_output: 0.12,
      supports_vision: true,
      supports_tools: true,
      supports_tools_streaming: true,
      supports_caching: false,
      endpoint_type: 'regional'
    },
    'ministral-8b' => {
      id: 'mistral.ministral-3-8b-instruct',
      name: 'Ministral 3 8B',
      description: 'Best-in-class for text and vision, agentic use cases',
      max_tokens: 8192,
      context_window: 32768,
      cost_per_1m_input: 0.10,
      cost_per_1m_output: 0.30,
      supports_vision: true,
      supports_tools: true,
      supports_tools_streaming: true,
      supports_caching: false,
      endpoint_type: 'regional'
    }
  }.freeze

  # Model fallback chain: Try models from fastest/cheapest to most robust
  # If a model fails due to throttling, timeout, or unavailability, automatically retry with the next model
  # Priority: Cost-effective models first, then progressively more capable/expensive
  MODEL_FALLBACK_CHAIN = [
    'claude-haiku-4-5-20251001',  # User's preferred model - fast, affordable
    'deepseek-v3',                # DeepSeek V3.1 - 68x cheaper than Opus, excellent quality
    'mistral-large-3',            # Mistral Large 3 - great for tool use, cost-effective
    'qwen-2-5-72b',               # Fast open model
    'claude-3-haiku',             # Fastest Claude
    'claude-3-5-sonnet',          # Fast, capable - good backup
    'claude-sonnet-4-5',          # Latest, powerful - reliable fallback
    'claude-opus-4-1',            # Most robust
    'claude-opus-4-5',            # Maximum capability
    'claude-opus-4-6'             # Latest frontier - last resort
  ].freeze

  def initialize(custom_model_id: nil, user: nil, entity: nil, context: {}, execution: nil)
    @default_region = ENV["AWS_REGION"] || "us-east-1"
    @client = Aws::BedrockRuntime::Client.new(
      region: @default_region,
      # Let AWS SDK use the default credential chain
      # This will automatically find credentials from:
      # 1. Environment variables
      # 2. ECS/EC2 instance profile
      # 3. AWS CLI configuration (~/.aws/credentials)

      # Increase timeout for long-running operations like landing page generation
      # Default is 60 seconds, but landing pages can take 4-5 minutes
      http_read_timeout: 600, # 10 minutes
      http_open_timeout: 30   # 30 seconds to establish connection
    )
    
    # Cache for cross-region clients (some models only available in specific regions)
    @regional_clients = { @default_region => @client }

    # Platform integration
    @model_registry = Agents::Platform::ModelRegistry.instance if defined?(Agents::Platform::ModelRegistry)
    @custom_model_id = custom_model_id
    @user = user
    @entity = entity
    @context = context || {}
    @execution = execution
    @resource_manager = ResourceManager.new(entity) if entity
  end
  
  # Get the appropriate client for a model (supports cross-region models like DeepSeek)
  def client_for_model(model_key)
    config = AVAILABLE_MODELS[model_key.to_s]
    return @client unless config
    
    model_region = config[:region]
    return @client unless model_region && model_region != @default_region
    
    # Create or return cached regional client
    @regional_clients[model_region] ||= begin
      Rails.logger.info "🌍 Creating cross-region Bedrock client for #{model_region} (model: #{model_key})"
      Aws::BedrockRuntime::Client.new(
        region: model_region,
        http_read_timeout: 600,
        http_open_timeout: 30
      )
    end
  end

  # Models ordered by context window size (for context overflow fallback)
  LARGE_CONTEXT_MODELS = [
    { key: 'deepseek-v3', context: 128_000 },      # 128K, cheapest large context
    { key: 'deepseek-r1', context: 128_000 },      # 128K, great for reasoning
    { key: 'qwen3-next-80b', context: 131_072 },   # 131K, fast
    { key: 'qwen3-vl-235b', context: 131_072 },    # 131K, multimodal
    { key: 'claude-haiku-4-5', context: 200_000 }, # 200K, fast Claude
    { key: 'claude-sonnet-4-5', context: 200_000 },# 200K, powerful
    { key: 'claude-opus-4-5', context: 200_000 },  # 200K, most capable
    { key: 'claude-opus-4-6', context: 200_000 },  # 200K, latest frontier
  ].freeze

  # Check if error is a context overflow (input too large for model)
  def context_overflow_error?(error)
    return false unless error.is_a?(Aws::BedrockRuntime::Errors::ValidationException)
    
    message = error.message.to_s.downcase
    message.include?('max_tokens') && (
      message.include?('too large') ||
      message.include?('context length') ||
      message.include?('input tokens')
    )
  end

  # Get a model with larger context window than current
  def get_larger_context_fallback(current_model, attempted_models = [])
    current_config = AVAILABLE_MODELS[current_model.to_s]
    current_context = current_config&.dig(:context_window) || 32_768

    # Find first model with larger context that hasn't been tried
    LARGE_CONTEXT_MODELS.each do |model|
      next if attempted_models.include?(model[:key])
      next if model[:context] <= current_context
      next unless AVAILABLE_MODELS[model[:key]] # Ensure model exists

      Rails.logger.info "📐 Upgrading from #{current_context / 1000}K → #{model[:context] / 1000}K context (#{model[:key]})"
      return model[:key]
    end

    # If no larger context model available, try regular fallback chain
    get_next_fallback_model(current_model, attempted_models)
  end

  # Get the next model in the fallback chain
  # Returns nil if no more fallback options
  def get_next_fallback_model(current_model, attempted_models = [])
    # Normalize current model name
    normalized_current = current_model.to_s.gsub('.', '-')

    # Find current position in chain
    current_index = MODEL_FALLBACK_CHAIN.index(normalized_current)

    # If not in chain or at end of chain, start from beginning
    if current_index.nil?
      # Try to find first model not yet attempted
      next_model = MODEL_FALLBACK_CHAIN.find { |m| !attempted_models.include?(m) }
      return next_model
    end

    # Try next models in chain that haven't been attempted
    ((current_index + 1)...MODEL_FALLBACK_CHAIN.length).each do |i|
      candidate = MODEL_FALLBACK_CHAIN[i]
      return candidate unless attempted_models.include?(candidate)
    end

    # No more fallback options
    nil
  end

  # Main method to send messages to Claude via Bedrock
  def send_message(system_prompt, messages, model: "qwen3-next-80b", max_tokens: 10000, temperature: 0.7, json_mode: false, stream: false, &block)
    # Use custom model if specified
    if @custom_model_id && @model_registry
      return send_via_platform(system_prompt, messages, model: @custom_model_id, max_tokens: max_tokens, temperature: temperature, json_mode: json_mode, stream: stream, &block)
    end

    if stream && block_given?
      send_message_streaming(system_prompt, messages, model: model, max_tokens: max_tokens, temperature: temperature, json_mode: json_mode, &block)
    else
      send_message_non_streaming(system_prompt, messages, model: model, max_tokens: max_tokens, temperature: temperature, json_mode: json_mode)
    end
  end

  # Complete method for simple API
  # Send message with image (for vision/OCR)
  # Uses Claude Opus 4.1 which supports vision (Sonnet 4.5 is text-only)
  def send_message_with_image(prompt, base64_image, media_type = 'image/png')
    messages = [
      {
        role: 'user',
        content: [
          {
            type: 'image',
            source: {
              type: 'base64',
              media_type: media_type,
              data: base64_image
            }
          },
          {
            type: 'text',
            text: prompt
          }
        ]
      }
    ]

    # Use Opus 4.1 for vision (has "Text Vision" capability)
    # Higher token limit for large documents
    complete(messages: messages, max_tokens: 10000, model: 'claude-opus-4-1')
  end

  def complete(messages:, temperature: 0.7, max_tokens: 1000, model: nil)
    model_to_use = @custom_model_id || model || "qwen3-next-80b"

    # Extract system prompt if present
    system_prompt = nil
    user_messages = messages

    if messages.first && messages.first[:role] == "system"
      system_prompt = messages.first[:content]
      user_messages = messages[1..]
    end

    send_message(system_prompt, user_messages, model: model_to_use, max_tokens: max_tokens, temperature: temperature, stream: false)
  end

  private

  def send_message_non_streaming(system_prompt, messages, model: "qwen3-next-80b", max_tokens: 10000, temperature: 0.7, json_mode: false)
    # Non-Claude models need to use the Converse API, not Claude's native invoke_model
    non_claude_models = %w[
      qwen-3-32b qwen-3.32b qwen-3-coder-30b qwen-coder qwen3-next-80b qwen-3-next-80b qwen3-vl-235b
      deepseek-v3 deepseek-v3.1 deepseek deepseek-r1 deepseek-reasoning
      mistral-large-3 mistral-large-2 mistral-large-2407 mistral-small ministral-3b ministral-8b
      meta-llama-3-3-70b llama-3-3-70b meta-llama-3-2-90b llama-3-2-90b
      nemotron-nano-9b nemotron-nano nemotron-nano-12b-vl
    ]
    
    if non_claude_models.include?(model.to_s)
      Rails.logger.info "🔀 Routing #{model} to Converse API (not Claude's native API)"
      # Use Converse API for non-Claude models
      # Format messages for converse if needed
      formatted_messages = messages.map do |msg|
        content = msg[:content]
        {
          role: msg[:role],
          content: content.is_a?(Array) ? content : [{ text: content.to_s }]
        }
      end
      return send_message_converse(system_prompt, formatted_messages, model: model, max_tokens: max_tokens, temperature: temperature, tools: [])
    end
    
    # Map model names to Bedrock model IDs
    # Using global inference profiles for Claude Sonnet 4.5
    model_id = case model
    when "claude-sonnet-4-5", "claude-sonnet-4.5"
      "global.anthropic.claude-sonnet-4-5-20250929-v1:0"
    when "claude-opus-4-1", "claude-opus-4-1-20250805"
      "us.anthropic.claude-opus-4-1-20250805-v1:0"
    when "claude-opus-4-5", "claude-opus-4.5"
      "global.anthropic.claude-opus-4-5-20251101-v1:0" # Opus 4.5 inference profile
    when "claude-opus-4-6", "claude-opus-4.6"
      "global.anthropic.claude-opus-4-6-v1" # Opus 4.6 - cross-region inference profile
    when "qwen-3-32b", "qwen-3.32b"
      "qwen.qwen3-32b-v1:0" # Qwen 3 32B - ON_DEMAND direct
    when "qwen-3-coder-30b", "qwen-coder"
      "qwen.qwen3-coder-30b-a3b-v1:0" # Qwen 3 Coder - ON_DEMAND direct
    when "qwen3-next-80b", "qwen-3-next-80b"
      "qwen.qwen3-next-80b-a3b" # Qwen3-Next - optimized for RAG & tool use
    when "qwen3-vl-235b"
      "qwen.qwen3-vl-235b-a22b" # Qwen3-VL - multimodal
    when "meta-llama-3-3-70b", "llama-3-3-70b"
      "us.meta.llama3-3-70b-instruct-v1:0" # Meta Llama 3.3 inference profile
    when "meta-llama-3-2-90b", "llama-3-2-90b"
      "us.meta.llama3-2-90b-instruct-v1:0" # Meta Llama 3.2 90B inference profile
    when "mistral-large-3"
      "mistral.mistral-large-3-675b-instruct" # Mistral Large 3 - latest
    when "mistral-large-2", "mistral-large-2407"
      "mistral.mistral-large-2407-v1:0" # Mistral Large 2
    when "mistral-small"
      "mistral.mistral-small-2402-v1:0" # Mistral Small
    when "deepseek-v3", "deepseek-v3.1", "deepseek"
      "deepseek.v3-v1:0" # DeepSeek V3.1 - fast, cost-optimized
    when "deepseek-r1", "deepseek-reasoning"
      "us.deepseek.r1-v1:0" # DeepSeek R1 - inference profile format
    when "nemotron-nano-9b", "nemotron-nano"
      "nvidia.nemotron-nano-9b-v2" # NVIDIA Nemotron Nano 9B v2
    when "nemotron-nano-12b-vl"
      "nvidia.nemotron-nano-12b-v2" # NVIDIA Nemotron Nano 12B VL
    when "ministral-3b"
      "mistral.ministral-3-3b-instruct" # Ministral 3B
    when "ministral-8b"
      "mistral.ministral-3-8b-instruct" # Ministral 8B
    when "claude-3-5-sonnet", "claude-3.5-sonnet"
      "us.anthropic.claude-3-5-sonnet-20241022-v2:0"
    when "claude-3-haiku"
      "us.anthropic.claude-3-5-haiku-20241022-v1:0"
    when "claude-haiku-4-5-20251001", "claude-haiku-4-5", "claude-haiku-4.5", "claude-4-5-haiku"
      # Claude Haiku 4.5 - fast and efficient
      "us.anthropic.claude-3-5-haiku-20241022-v1:0"  # Using the latest Haiku model ID
    else
      # Default to Claude Sonnet 4.5 (latest)
      "global.anthropic.claude-sonnet-4-5-20250929-v1:0"
    end

    # Format messages for Claude
    formatted_messages = format_messages_for_claude(messages)

    # Debug the formatted messages
    Rails.logger.info "🔍 Bedrock formatted messages: #{formatted_messages.inspect}"

    # Modify system prompt for JSON mode if requested
    final_system_prompt = if json_mode && system_prompt.present?
      Rails.logger.info "🔧 Bedrock JSON mode enabled - enforcing structured output"
      "#{system_prompt}\n\nCRITICAL: You MUST respond with valid JSON only. Do not include any text before or after the JSON. Your entire response must be a valid JSON object."
    else
      system_prompt
    end

    # Build the request body for Claude
    request_body = {
      anthropic_version: "bedrock-2023-05-31",
      messages: formatted_messages,
      max_tokens: max_tokens,
      temperature: temperature
    }

    # Add system prompt if provided
    request_body[:system] = final_system_prompt if final_system_prompt.present?

    Rails.logger.info "Sending request to Bedrock Claude (#{model_id})"

    # Track timing for Agent Lightning
    start_time = Time.current
    
    # Use regional client if model requires it (e.g., DeepSeek is only in us-east-2)
    client = client_for_model(model)

    begin
      response = client.invoke_model(
        model_id: model_id,
        body: request_body.to_json,
        content_type: "application/json",
        accept: "application/json"
      )

      # Parse the response
      response_body = JSON.parse(response.body.read)
      content = response_body.dig("content", 0, "text")

      # Track token usage if available in response
      if response_body["usage"]
        tokens = {
          input: response_body["usage"]["input_tokens"] || 0,
          output: response_body["usage"]["output_tokens"] || 0
        }

        if @user && @entity
          # Track tokens in resource manager (updates entity total) if available
          if @resource_manager
            @resource_manager.track_tokens(@user, model_id, tokens, {
              stream: false,
              method: "invoke_model",
              timestamp: Time.current
            })
          end

          # Extract short model name from full ID for cleaner logging
          short_model_name = model_id.to_s.match(/claude[^:]+/)&.to_s || model_id

          # Log AI usage for observability and billing
          AiUsageLog.log_usage(
            entity: @entity,
            user: @user,
            model: short_model_name,
            input_tokens: tokens[:input],
            output_tokens: tokens[:output],
            duration_ms: nil,
            request_type: 'chat',
            scout_message: nil,
            metadata: {
              method: 'invoke_model',
              stream: false,
              cache_creation: response_body["usage"]["cache_write_input_tokens"] || 0,
              cache_read: response_body["usage"]["cache_read_input_tokens"] || 0,
              full_model_id: model_id
            }
          )
          
          # Track work tokens for billing
          track_ai_work_tokens(
            input_tokens: tokens[:input],
            output_tokens: tokens[:output],
            model: short_model_name,
            metadata: { method: 'invoke_model', full_model_id: model_id }
          )
        end

        Rails.logger.info "Token usage - Input: #{tokens[:input]}, Output: #{tokens[:output]}"
      end

      Rails.logger.info "Bedrock response received: #{content&.length || 0} characters"

      # Log first 500 chars for debugging multi-step plans
      if content && content.length > 100
        Rails.logger.info "🔍 Response preview: #{content[0..500]}"
      end

      # Record LLM call to Agent Lightning for training data
      if @entity && @user && should_record_lightning_trace?
        latency_ms = ((Time.current - start_time) * 1000).to_i
        parsed_actions = parse_response_actions(content)
        success_score = calculate_success_score(content, "success")
        agent_role = determine_agent_role(role: "executor")

        record_llm_call_to_lightning(
          model: model,
          agent_role: agent_role,
          system_prompt: final_system_prompt,
          user_messages: formatted_messages,
          response_content: content,
          input_tokens: response_body.dig("usage", "input_tokens") || 0,
          output_tokens: response_body.dig("usage", "output_tokens") || 0,
          latency_ms: latency_ms,
          status: "success",
          parsed_actions: parsed_actions,
          success_score: success_score
        )
      end

      content
    rescue Aws::BedrockRuntime::Errors::ThrottlingException => e
      Rails.logger.error "Bedrock throttling: #{e.message}"

      # Record failure to Agent Lightning
      if @entity && @user && should_record_lightning_trace?
        latency_ms = ((Time.current - start_time) * 1000).to_i
        record_llm_call_to_lightning(
          model: model,
          agent_role: "executor",
          system_prompt: final_system_prompt,
          user_messages: formatted_messages,
          response_content: nil,
          input_tokens: 0,
          output_tokens: 0,
          latency_ms: latency_ms,
          status: "error",
          error_message: "Throttling: #{e.message}"
        )
      end

      request_id = e.context&.http_response&.headers&.[]('x-amzn-requestid') rescue nil
      raise AmosErrors::BedrockThrottlingError.new(context: { request_id: request_id })
    rescue Aws::BedrockRuntime::Errors::ServiceUnavailableException => e
      Rails.logger.error "Bedrock unavailable: #{e.message}"

      # Record failure to Agent Lightning
      if @entity && @user && should_record_lightning_trace?
        latency_ms = ((Time.current - start_time) * 1000).to_i
        record_llm_call_to_lightning(
          model: model,
          agent_role: "executor",
          system_prompt: final_system_prompt,
          user_messages: formatted_messages,
          response_content: nil,
          input_tokens: 0,
          output_tokens: 0,
          latency_ms: latency_ms,
          status: "error",
          error_message: "Service unavailable: #{e.message}"
        )
      end

      request_id = e.context&.http_response&.headers&.[]('x-amzn-requestid') rescue nil
      raise AmosErrors::BedrockUnavailableError.new(context: { request_id: request_id })
    rescue Timeout::Error, Seahorse::Client::NetworkingError => e
      Rails.logger.error "Bedrock timeout: #{e.message}"

      # Record failure to Agent Lightning
      if @entity && @user && should_record_lightning_trace?
        latency_ms = ((Time.current - start_time) * 1000).to_i
        record_llm_call_to_lightning(
          model: model,
          agent_role: "executor",
          system_prompt: final_system_prompt,
          user_messages: formatted_messages,
          response_content: nil,
          input_tokens: 0,
          output_tokens: 0,
          latency_ms: latency_ms,
          status: "error",
          error_message: "Timeout: #{e.message}"
        )
      end

      raise AmosErrors::BedrockTimeoutError.new(context: { error: e.class.name })
    rescue Aws::BedrockRuntime::Errors::ServiceError => e
      Rails.logger.error "Bedrock API Error: #{e.message}"

      # Record failure to Agent Lightning
      if @entity && @user && should_record_lightning_trace?
        latency_ms = ((Time.current - start_time) * 1000).to_i
        record_llm_call_to_lightning(
          model: model,
          agent_role: "executor",
          system_prompt: final_system_prompt,
          user_messages: formatted_messages,
          response_content: nil,
          input_tokens: 0,
          output_tokens: 0,
          latency_ms: latency_ms,
          status: "error",
          error_message: "API Error: #{e.message}"
        )
      end

      request_id = e.context&.http_response&.headers&.[]('x-amzn-requestid') rescue nil
      raise AmosErrors::BedrockError.new(e.message, context: { error_code: e.code, request_id: request_id })
    rescue StandardError => e
      Rails.logger.error "Unexpected error from Bedrock: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      # Record failure to Agent Lightning
      if @entity && @user && should_record_lightning_trace?
        latency_ms = ((Time.current - start_time) * 1000).to_i
        record_llm_call_to_lightning(
          model: model,
          agent_role: "executor",
          system_prompt: final_system_prompt,
          user_messages: formatted_messages,
          response_content: nil,
          input_tokens: 0,
          output_tokens: 0,
          latency_ms: latency_ms,
          status: "error",
          error_message: "Unexpected error: #{e.message}"
        )
      end

      raise AmosErrors::BedrockError.new("Unexpected error: #{e.message}", context: { error_class: e.class.name })
    end
  end

  # Generate images using Amazon Titan
  def generate_image(prompt, size: "1024x1024", style: "photographic")
    # Map sizes to Titan's supported dimensions
    width, height = case size
    when "1024x1024"
      [ 1024, 1024 ]
    when "1024x1792", "1792x1024"
      size.include?("1792x1024") ? [ 1792, 1024 ] : [ 1024, 1792 ]
    when "768x768"
      [ 768, 768 ]
    when "512x512"
      [ 512, 512 ]
    else
      [ 1024, 1024 ] # Default
    end

    request_body = {
      taskType: "TEXT_IMAGE",
      textToImageParams: {
        text: prompt
      },
      imageGenerationConfig: {
        numberOfImages: 1,
        height: height,
        width: width,
        cfgScale: 8.0,
        seed: Random.rand(0..2147483647)
      }
    }

    Rails.logger.info "Generating image with Titan: #{prompt[0..100]}..."

    begin
      response = @client.invoke_model(
        model_id: "amazon.titan-image-generator-v2:0",
        body: request_body.to_json,
        content_type: "application/json",
        accept: "application/json"
      )

      response_body = JSON.parse(response.body.read)

      # Titan returns base64 encoded images
      if response_body["images"] && response_body["images"].first
        base64_image = response_body["images"].first
        {
          url: "data:image/png;base64,#{base64_image}",
          base64: base64_image,
          revised_prompt: prompt
        }
      else
        raise "No image generated"
      end
    rescue Aws::BedrockRuntime::Errors::ServiceError => e
      Rails.logger.error "Titan Image Generation Error: #{e.message}"
      raise "Image generation failed: #{e.message}"
    end
  end

  # Analyze an image using Claude with vision capabilities
  def analyze_image(image_url, context = nil)
    # For Bedrock, we need to convert image URLs to base64
    image_data = if image_url.start_with?("data:image")
      # Already base64
      image_url.split(",").last
    else
      # Download and convert to base64
      require "open-uri"
      require "base64"

      image_content = URI.open(image_url).read
      Base64.strict_encode64(image_content)
    end

    messages = [
      {
        role: "user",
        content: [
          {
            type: "text",
            text: "Analyze this image and provide a detailed description suitable for a web designer who needs to understand its content, mood, colors, and key visual elements. #{context ? "Context: #{context}" : ''}"
          },
          {
            type: "image",
            source: {
              type: "base64",
              media_type: "image/jpeg",
              data: image_data
            }
          }
        ]
      }
    ]

    # Use Claude 3.5 Sonnet for vision tasks
    send_message(nil, messages, model: "claude-3-5-sonnet", max_tokens: 300)
  rescue => e
    Rails.logger.error "Failed to analyze image: #{e.message}"
    "Image analysis unavailable"
  end

  public

  # Non-streaming version using converse API (for tool continuation)
  # Returns which tools were actually called during the last send_message_converse
  def tools_called
    @tools_called || []
  end

  def send_message_converse(system_prompt, messages, model: "qwen3-next-80b", max_tokens: 10000, temperature: 0.7, tools: [], options: {})
    @tools_called = []  # Reset tools called tracking for this request
    # Map model names to Bedrock model IDs
    model_id = case model
    when "claude-sonnet-4-5", "claude-sonnet-4.5"
      "global.anthropic.claude-sonnet-4-5-20250929-v1:0"
    when "claude-opus-4-1", "claude-opus-4-1-20250805"
      "us.anthropic.claude-opus-4-1-20250805-v1:0"
    when "claude-opus-4-5", "claude-opus-4.5"
      "global.anthropic.claude-opus-4-5-20251101-v1:0" # Opus 4.5 inference profile
    when "claude-opus-4-6", "claude-opus-4.6"
      "global.anthropic.claude-opus-4-6-v1" # Opus 4.6 - cross-region inference profile
    when "qwen-3-32b", "qwen-3.32b"
      "qwen.qwen3-32b-v1:0" # Qwen 3 32B - ON_DEMAND direct
    when "qwen-3-coder-30b", "qwen-coder"
      "qwen.qwen3-coder-30b-a3b-v1:0" # Qwen 3 Coder - ON_DEMAND direct
    when "qwen3-next-80b", "qwen-3-next-80b"
      "qwen.qwen3-next-80b-a3b" # Qwen3-Next - optimized for RAG & tool use
    when "qwen3-vl-235b"
      "qwen.qwen3-vl-235b-a22b" # Qwen3-VL - multimodal
    when "meta-llama-3-3-70b", "llama-3-3-70b"
      "us.meta.llama3-3-70b-instruct-v1:0" # Meta Llama 3.3 inference profile
    when "meta-llama-3-2-90b", "llama-3-2-90b"
      "us.meta.llama3-2-90b-instruct-v1:0" # Meta Llama 3.2 90B inference profile
    when "mistral-large-3"
      "mistral.mistral-large-3-675b-instruct" # Mistral Large 3 - latest
    when "mistral-large-2", "mistral-large-2407"
      "mistral.mistral-large-2407-v1:0" # Mistral Large 2
    when "mistral-small"
      "mistral.mistral-small-2402-v1:0" # Mistral Small
    when "deepseek-v3", "deepseek-v3.1", "deepseek"
      "deepseek.v3-v1:0" # DeepSeek V3.1 - fast, cost-optimized
    when "deepseek-r1", "deepseek-reasoning"
      "us.deepseek.r1-v1:0" # DeepSeek R1 - inference profile format
    when "nemotron-nano-9b", "nemotron-nano"
      "nvidia.nemotron-nano-9b-v2" # NVIDIA Nemotron Nano 9B v2
    when "nemotron-nano-12b-vl"
      "nvidia.nemotron-nano-12b-v2" # NVIDIA Nemotron Nano 12B VL
    when "ministral-3b"
      "mistral.ministral-3-3b-instruct" # Ministral 3B
    when "ministral-8b"
      "mistral.ministral-3-8b-instruct" # Ministral 8B
    when "claude-3-5-sonnet", "claude-3.5-sonnet"
      "us.anthropic.claude-3-5-sonnet-20241022-v2:0"
    when "claude-3-haiku"
      "us.anthropic.claude-3-5-haiku-20241022-v1:0"
    else
      # Default to Qwen3-Next for cost efficiency
      "qwen.qwen3-next-80b-a3b"
    end

    # Messages are already in converse format from our formatting
    # Just ensure they're properly structured
    # NOTE: Some code paths use { type: "text", text: "..." } (Claude native format)
    # but Converse API requires { text: "..." } only. Normalize here.
    converse_messages = messages.map do |msg|
      content = msg[:content]
      normalized_content = if content.is_a?(Array)
        content.map do |item|
          if item.is_a?(Hash)
            # Handle various formats and normalize to Converse API format
            if item[:text] || item['text']
              # Text content - strip any 'type' key which is Claude-native format
              { text: item[:text] || item['text'] }
            elsif item[:tool_use] || item['tool_use']
              # Tool use - pass through
              { tool_use: item[:tool_use] || item['tool_use'] }
            elsif item[:tool_result] || item['tool_result']
              # Tool result - pass through
              { tool_result: item[:tool_result] || item['tool_result'] }
            elsif item[:image] || item['image']
              # Image - pass through
              { image: item[:image] || item['image'] }
            else
              # Unknown format - try to extract text if there's a type: "text" pattern
              if (item[:type] == 'text' || item['type'] == 'text') && item.key?(:text)
                { text: item[:text] }
              elsif (item[:type] == 'text' || item['type'] == 'text') && item.key?('text')
                { text: item['text'] }
              else
                # Pass through as-is, Bedrock will validate
                item
              end
            end
          else
            # Non-hash item (string, etc) - wrap in text
            { text: item.to_s }
          end
        end
      else
        # String content - wrap in text array
        [ { text: content.to_s } ]
      end
      
      {
        role: msg[:role],
        content: normalized_content
      }
    end

    # Build payload for converse
    payload = {
      model_id: model_id,
      messages: converse_messages,
      inference_config: {
        max_tokens: max_tokens,
        temperature: temperature
      }
    }

    # Add system prompt if present
    if system_prompt.present?
      payload[:system] = [ { text: system_prompt } ]
    end

    # Add tools if provided (required when using tool results)
    if tools.any?
      payload[:tool_config] = {
        tools: format_tools_for_bedrock(tools),
        tool_choice: { auto: {} }
      }
    end

    Rails.logger.info "Sending non-streaming request to Bedrock Claude (#{model_id}) using converse"
    
    # Use regional client if model requires it (e.g., DeepSeek is only in us-east-2)
    client = client_for_model(model)
    
    # Retry configuration for throttling
    max_retries = 3
    retry_count = 0
    base_delay = 2 # seconds

    begin
      # Tool use loop - continue conversation until we get final text response
      # Default 10 turns, but complex agents may need more (passed via options)
      max_turns = options[:max_tool_turns] || 15
      turn_count = 0
      conversation_messages = converse_messages.dup
      
      # Track repeated failures to detect stuck loops
      failed_calls = Hash.new(0)  # { "tool_name:input_hash" => count }
      max_repeated_failures = 2   # Abort after same failure twice

      loop do
        turn_count += 1
        if turn_count > max_turns
          Rails.logger.warn "Tool use loop exceeded max turns (#{max_turns})"
          break
        end

        # Update payload with current messages
        payload[:messages] = conversation_messages

        response = client.converse(payload)

        # Check if response contains tool use
        tool_uses = response.output.message.content.select { |block| block.respond_to?(:tool_use) && block.tool_use }

        if tool_uses.any?
          Rails.logger.info "Agent requested #{tool_uses.length} tool(s)"

          # Add assistant's tool use request to conversation
          conversation_messages << {
            role: "assistant",
            content: response.output.message.content.map do |block|
              if block.respond_to?(:tool_use) && block.tool_use
                { tool_use: { tool_use_id: block.tool_use.tool_use_id, name: block.tool_use.name, input: block.tool_use.input } }
              elsif block.respond_to?(:text) && block.text
                { text: block.text }
              end
            end.compact
          }

          # Execute tools and collect results
          tool_results = []
          @tools_called ||= []  # Track tools actually called for hallucination detection
          
          tool_uses.each do |tool_use_block|
            tool_use = tool_use_block.tool_use
            tool_name = tool_use.name
            tool_input = tool_use.input.to_h

            @tools_called << tool_name  # Track this tool was called
            Rails.logger.info "Executing tool: #{tool_name} with input: #{tool_input.inspect}"

            # Build tool context (similar to Scout's pattern)
            tool_context = {
              canvas_suggestion: nil,
              canvas_data: {},
              execution: @execution, # Explicitly ensure execution is passed
              **@context  # Include agent_plugin, task_session, session_id, etc.
            }

            begin
              # Execute the tool with full context
              catalog = Tools::ToolCatalog.instance
              result = catalog.execute_tool(
                tool_name,
                tool_input,
                user: @user,
                entity: @entity,
                context: tool_context,
                progress_callback: nil  # Agent plugins don't support progress callbacks yet
              )

              Rails.logger.info "Tool #{tool_name} result: #{result.inspect}"

              # Track repeated failures to detect stuck loops
              if result.is_a?(Hash) && result[:success] == false
                call_signature = "#{tool_name}:#{tool_input.to_json.hash}"
                failed_calls[call_signature] += 1
                
                if failed_calls[call_signature] >= max_repeated_failures
                  Rails.logger.error "🔴 REPEATED FAILURE DETECTED: #{tool_name} failed #{failed_calls[call_signature]} times with same input"
                  # Add a stronger message to the result
                  result = result.merge(
                    repeated_failure_warning: "⚠️ YOU HAVE MADE THIS EXACT SAME FAILING CALL #{failed_calls[call_signature]} TIMES. " \
                      "READ THE ERROR MESSAGE ABOVE. DO NOT RETRY THE SAME CALL. " \
                      "Either fix the parameters or try a different approach."
                  )
                end
              end

              # Format result for Bedrock
              tool_results << {
                tool_result: {
                  tool_use_id: tool_use.tool_use_id,
                  content: [{ text: result.to_json }]
                }
              }
            rescue Tools::AskUserTool::ExecutionSuspended => e
              # If any tool suspends execution, we must stop the loop
              # and propagate the suspension.
              
              # First, we need to make sure we return the conversation state up to this point
              # so it can be saved.
              
              # If there were OTHER tools executed successfully in this turn before ask_user,
              # we should capture their results too.
              
              # Capture the pending tool results we've collected so far (excluding the current failed/suspended one)
              # Actually, we don't include the suspended tool result because it's not a "result" yet.
              # But we do need to include the tool_use message that triggered this.
              
              if tool_results.any?
                # Add results of *other* tools that succeeded before this one
                conversation_messages << {
                  role: "user",
                  content: tool_results
                }
              end
              
              # We attach the messages to the exception
              e.instance_variable_set(:@conversation_context, conversation_messages)
              def e.conversation_context; @conversation_context; end
              
              raise e
            rescue => e
              # Check for ExecutionSuspended by name if class matching failed (handling reload issues)
              if e.class.name.include?('ExecutionSuspended')
                if tool_results.any?
                  conversation_messages << {
                    role: "user",
                    content: tool_results
                  }
                end
                
                # Re-attach context if needed (though usually attached at raise time)
                unless e.respond_to?(:conversation_context)
                  e.instance_variable_set(:@conversation_context, conversation_messages)
                  def e.conversation_context; @conversation_context; end
                end
                
                raise e
              end

              # Handle generic tool errors gracefully
              Rails.logger.error "Tool execution failed: #{e.message}"
              tool_results << {
                tool_result: {
                  tool_use_id: tool_use.tool_use_id,
                  content: [{ text: { error: e.message, success: false }.to_json }],
                  status: "error"
                }
              }
            end
          end

          # Add tool results to conversation
          conversation_messages << {
            role: "user",
            content: tool_results
          }

          # Continue loop to get next response
        else
          # No tool use - extract final text response
          content = response.output.message.content.map do |content_block|
            content_block.text if content_block.respond_to?(:text)
          end.compact.join("")

          # Track token usage if available
          if response.respond_to?(:usage) && response.usage
            tokens = {
              input: response.usage.input_tokens || 0,
              output: response.usage.output_tokens || 0
            }
            total_tokens = tokens[:input] + tokens[:output]

            if @user && @entity && @resource_manager
              @resource_manager.track_tokens(@user, model_id, tokens, {
                stream: false,
                method: "converse",
                timestamp: Time.current
              })
            end

            # Track tokens and model on the agent execution if provided
            if @execution
              if @execution.respond_to?(:add_tokens)
                @execution.add_tokens(total_tokens)
              end

              # Track which model was used and token breakdown
              if @execution.respond_to?(:track_model_usage)
                @execution.track_model_usage(model_id, tokens[:input], tokens[:output])
              end
            end

            Rails.logger.info "Token usage - Input: #{tokens[:input]}, Output: #{tokens[:output]} (Model: #{model_id})"
          end

          Rails.logger.info "Bedrock converse response received: #{content.length} characters"

          return content
        end
      end

      # If we exit loop without returning, return what we have
      ""
    rescue Aws::BedrockRuntime::Errors::ThrottlingException => e
      retry_count += 1
      if retry_count <= max_retries
        delay = base_delay * (2 ** (retry_count - 1)) # Exponential backoff: 2, 4, 8 seconds
        Rails.logger.warn "🔄 Bedrock throttling (attempt #{retry_count}/#{max_retries}), retrying in #{delay}s: #{e.message}"
        sleep delay
        retry
      else
        Rails.logger.error "❌ Bedrock throttling after #{max_retries} retries: #{e.message}"
        request_id = e.context&.http_response&.headers&.[]('x-amzn-requestid') rescue nil
        raise AmosErrors::BedrockThrottlingError.new(context: { request_id: request_id, retries_attempted: retry_count })
      end
    rescue Aws::BedrockRuntime::Errors::ServiceUnavailableException => e
      retry_count += 1
      if retry_count <= max_retries
        delay = base_delay * (2 ** (retry_count - 1))
        Rails.logger.warn "🔄 Bedrock unavailable (attempt #{retry_count}/#{max_retries}), retrying in #{delay}s: #{e.message}"
        sleep delay
        retry
      else
        Rails.logger.error "❌ Bedrock unavailable after #{max_retries} retries: #{e.message}"
        request_id = e.context&.http_response&.headers&.[]('x-amzn-requestid') rescue nil
        raise AmosErrors::BedrockUnavailableError.new(context: { request_id: request_id, retries_attempted: retry_count })
      end
    rescue Timeout::Error, Seahorse::Client::NetworkingError => e
      Rails.logger.error "Bedrock timeout: #{e.message}"
      raise AmosErrors::BedrockTimeoutError.new(context: { error: e.class.name })
    rescue Aws::BedrockRuntime::Errors::ServiceError => e
      Rails.logger.error "Bedrock API Error: #{e.message}"
      request_id = e.context&.http_response&.headers&.[]('x-amzn-requestid') rescue nil
      raise AmosErrors::BedrockError.new(e.message, context: { error_code: e.code, request_id: request_id })
    rescue StandardError => e
      # Allow execution suspension to bubble up
      if e.class.name.include?('ExecutionSuspended') || (defined?(Tools::AskUserTool::ExecutionSuspended) && e.is_a?(Tools::AskUserTool::ExecutionSuspended))
        raise e
      end

      Rails.logger.error "Unexpected error from Bedrock: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise AmosErrors::BedrockError.new("Unexpected error: #{e.message}", context: { error_class: e.class.name })
    end
  end

  def send_message_streaming(system_prompt, messages, model: "qwen3-next-80b", max_tokens: 10000, temperature: 0.7, json_mode: false, tools: [], enable_prompt_caching: false, tool_choice: nil, &block)
    # Track attempted models for fallback
    attempted_models = []
    current_model = model
    last_error = nil

    # Retry loop with model fallback
    loop do
      begin
        # Check if prompt caching is enabled (default: false - disabled due to AWS API limitations)
        # The enable_prompt_caching parameter is kept for API compatibility but currently ignored
        caching_enabled = ENV.fetch('BEDROCK_PROMPT_CACHING_ENABLED', 'false') == 'true'

        # Normalize model name (handle variants like "claude-sonnet-4.5")
        normalized_model = current_model.to_s.gsub('.', '-')

        # Track this attempt
        attempted_models << normalized_model unless attempted_models.include?(normalized_model)

        # Get model configuration
        model_config = AVAILABLE_MODELS[normalized_model] || AVAILABLE_MODELS['claude-sonnet-4-5']
        model_id = model_config[:id]

        # Cap max_tokens to the model's limit
        model_max_tokens = model_config[:max_tokens] || 25000
        effective_max_tokens = [max_tokens, model_max_tokens].min

        # Log model selection with caching status
        if caching_enabled && !model_config[:supports_caching]
          Rails.logger.info "⚠️  #{model_config[:name]} doesn't support caching (#{model_config[:endpoint_type]} endpoint)"
        elsif caching_enabled && model_config[:supports_caching]
          Rails.logger.info "💾 Using #{model_config[:name]} with caching enabled"
        else
          Rails.logger.info "✅ Using #{model_config[:name]} (caching disabled)"
        end

        if effective_max_tokens < max_tokens
          Rails.logger.info "⚠️  Requested max_tokens (#{max_tokens}) exceeds model limit (#{model_max_tokens}), using #{effective_max_tokens}"
        end
        
        # Log inference parameters for thinking depth debugging
        Rails.logger.info "🧠 Inference params: max_tokens=#{effective_max_tokens}, temperature=#{temperature}"

        # Format messages for Claude
        formatted_messages = format_messages_for_claude(messages)

        # Filter out messages with empty content arrays
        formatted_messages = formatted_messages.reject do |msg|
          msg[:content].nil? || msg[:content].empty? ||
          (msg[:content].is_a?(Array) && msg[:content].all? { |c|
            # Check if this is a text block with empty text
            c[:type] == "text" && c[:text].to_s.strip.empty?
          })
        end

        # Build the request body
        request_body = {
          anthropic_version: "bedrock-2023-05-31",
          messages: formatted_messages,
          max_tokens: effective_max_tokens,
          temperature: temperature
        }

        request_body[:system] = system_prompt if system_prompt.present?

        Rails.logger.info "Sending streaming request to Bedrock Claude (#{model_id}) using converse_stream"

        # Convert messages to converse API format
      # The converse API expects content to be an array of content blocks
      # where each block is directly the content type (text, image, etc)
      converse_messages = formatted_messages.reject { |msg|
        msg[:content].nil? || msg[:content].empty? ||
        (msg[:content].is_a?(Array) && msg[:content].all? { |c|
          # Check if this is a text block with empty text
          c[:type] == "text" && c[:text].to_s.strip.empty?
        })
      }.map do |msg|
        content_blocks = msg[:content].map do |block|
          case block[:type]
          when "text"
            { text: block[:text] }
          when "tool_use"
            # Convert tool_use format - sanitize ID for Bedrock compatibility
            tool_data = block[:tool_use]
            # Handle both :id and :tool_use_id keys
            tool_id = tool_data[:tool_use_id] || tool_data[:id] || tool_data["tool_use_id"] || tool_data["id"]
            {
              tool_use: {
                tool_use_id: BedrockService.sanitize_tool_id(tool_id),
                name: tool_data[:name] || tool_data["name"],
                input: tool_data[:input] || tool_data["input"] || {}
              }
            }
          when "tool_result"
            # Convert tool_result format - sanitize ID for Bedrock compatibility
            result_data = block[:tool_result]
            {
              tool_result: {
                tool_use_id: BedrockService.sanitize_tool_id(result_data[:tool_use_id]),
                content: result_data[:content].is_a?(Array) ?
                  result_data[:content].map { |c|
                    c[:type] == "text" ? { text: c[:text] } : c
                  } :
                  [ { text: result_data[:content].to_s } ]
              }
            }
          else
            # Handle other content types
            block
          end
        end

        {
          role: msg[:role] == "system" ? "user" : msg[:role],
          content: content_blocks
        }
      end

      Rails.logger.info "🔍 Original formatted messages count: #{formatted_messages.length}"
      Rails.logger.info "🔍 Converse messages count after conversion: #{converse_messages.length}"
      Rails.logger.info "🔍 Converse messages structure: #{converse_messages.to_json}"

      # Build payload for converse_stream
      payload = {
        model_id: model_id,
        messages: converse_messages,
        inference_config: {
          max_tokens: effective_max_tokens,
          temperature: temperature
        }
      }

      # Determine if caching should be used (both enabled AND supported by model)
      use_caching = caching_enabled && model_config[:supports_caching]

      # Add system prompt if present
      if system_prompt.present?
        if use_caching
          # Add cache checkpoint after system prompt (requires 1024+ tokens)
          payload[:system] = [
            { text: system_prompt },
            { cachePoint: { type: "default" } }  # Cache everything up to here
          ]
          Rails.logger.info "💾 Prompt caching enabled for system prompt (~7000 tokens)"
        else
          # No caching - simple array with text
          payload[:system] = [{ text: system_prompt }]
        end
      end

      # Add tools if provided
      if tools.any?
        formatted_tools = format_tools_for_bedrock(tools)

        if use_caching
          # Add cache checkpoint after all tools (Claude supports up to 4 checkpoints)
          formatted_tools << { cachePoint: { type: "default" } }
          Rails.logger.info "💾 Prompt caching enabled for tools (~2500 tokens)"
        end

        # Use provided tool_choice or default to auto
        effective_tool_choice = tool_choice || { auto: {} }

        payload[:tool_config] = {
          tools: formatted_tools,
          tool_choice: effective_tool_choice
        }

        # DEBUG: Log tool names being sent (exclude cache checkpoint if present)
        tool_spec_tools = formatted_tools.select { |t| t.key?(:tool_spec) }
        tool_names = tool_spec_tools.map { |t| t.dig(:tool_spec, :name) }
        caching_status = use_caching ? "with caching" : "no caching"
        choice_mode = effective_tool_choice.keys.first.to_s
        Rails.logger.info "🔧 Sending #{tool_names.length} tools to Claude (#{caching_status}, tool_choice: #{choice_mode}): #{tool_names.join(', ')}"
      end

      # Buffer for accumulating content
      buffer = ""
      start_time = Time.now
      chunk_count = 0
      
      # Use regional client if model requires it (e.g., DeepSeek is only in us-east-2)
      client = client_for_model(normalized_model)

      # Use converse_stream for true streaming
      client.converse_stream(payload) do |stream|
        stream.on_error_event do |event|
          Rails.logger.error "Bedrock stream error: #{event.inspect}"
          raise AmosErrors::BedrockError.new("Streaming error: #{event.error_message || 'Unknown error'}")
        end

        stream.on_event do |event|
          case event.event_type
          when :content_block_delta
            if event.delta.respond_to?(:text) && event.delta.text
              content = event.delta.text
              
              # ENCODING FIX: Ensure proper UTF-8 encoding and remove invalid bytes
              # This fixes issues with Mistral Large 3 sometimes outputting malformed characters
              if content.is_a?(String)
                # Force UTF-8 encoding, replacing invalid/undefined bytes
                content = content.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
                # Also scrub any remaining invalid byte sequences
                content = content.scrub('')
              end
              
              buffer += content

              # Log timing
              chunk_count += 1
              elapsed = (Time.now - start_time).round(3)
              Rails.logger.info "Bedrock chunk ##{chunk_count} at #{elapsed}s: #{content.length} chars"

              # Yield content chunk immediately
              yield(type: :content, content: content)
            elsif event.delta.respond_to?(:tool_use) && event.delta.tool_use
              # Handle tool use chunks
              tool_use = event.delta.tool_use
              yield(type: :tool_use, tool_use: tool_use)
            end
          when :content_block_start
            if event.start && event.start.respond_to?(:tool_use)
              # Tool use is starting - sanitize the ID for Bedrock compatibility
              tool_info = event.start.tool_use
              sanitized_id = BedrockService.sanitize_tool_id(tool_info.tool_use_id)
              yield(type: :tool_use_start, tool_id: sanitized_id, tool_name: tool_info.name)
            end
          when :content_block_stop
            # Content block complete - signal that current tool (if any) is done
            yield(type: :content_block_stop)
          when :message_stop
            # Message complete
            total_elapsed = (Time.now - start_time).round(3)
            Rails.logger.info "Bedrock streaming complete: #{chunk_count} chunks in #{total_elapsed}s"
            yield(type: :complete, content: buffer)
          when :metadata
            # Extract and track token usage if available
            if event.respond_to?(:usage) && event.usage
              usage = event.usage
              tokens = {
                input: usage.input_tokens || 0,
                output: usage.output_tokens || 0
              }

              # Extract cache statistics (AWS Bedrock Converse API field names)
              cache_write = usage.respond_to?(:cache_write_input_tokens_count) ? usage.cache_write_input_tokens_count : 0
              cache_read = usage.respond_to?(:cache_read_input_tokens_count) ? usage.cache_read_input_tokens_count : 0

              # Track tokens if we have user and entity
              if @user && @entity
                # Track tokens in resource manager (updates entity total) if available
                if @resource_manager
                  @resource_manager.track_tokens(@user, model_id, tokens, {
                    stream: true,
                    timestamp: Time.current,
                    cache_write: cache_write,
                    cache_read: cache_read
                  })
                end

                # Log AI usage for observability and billing
                duration_ms = ((Time.now - start_time) * 1000).round
                cache_creation = usage.respond_to?(:cache_write_input_tokens) ? (usage.cache_write_input_tokens || 0) : 0
                cache_read = usage.respond_to?(:cache_read_input_tokens) ? (usage.cache_read_input_tokens || 0) : 0

                # Extract short model name from full ID for cleaner logging
                short_model_name = model_id.to_s.match(/claude[^:]+/)&.to_s || model_id

                AiUsageLog.log_usage(
                  entity: @entity,
                  user: @user,
                  model: short_model_name,
                  input_tokens: tokens[:input],
                  output_tokens: tokens[:output],
                  duration_ms: duration_ms,
                  request_type: 'chat',
                  scout_message: nil,
                  metadata: {
                    method: 'invoke_model_with_response_stream',
                    stream: true,
                    chunks: chunk_count,
                    cache_creation: cache_creation,
                    cache_read: cache_read,
                    full_model_id: model_id
                  }
                )
                
                # Track work tokens for billing
                track_ai_work_tokens(
                  input_tokens: tokens[:input],
                  output_tokens: tokens[:output],
                  model: short_model_name,
                  metadata: { method: 'invoke_model_with_response_stream', full_model_id: model_id, duration_ms: duration_ms }
                )
              end

              # Yield usage info including cache stats and model used (for fallback transparency)
              yield(
                type: :usage,
                tokens: tokens,
                cache_write: cache_write,
                cache_read: cache_read,
                model_used: normalized_model,
                model_name: model_config[:name]
              ) if block_given?

              # Enhanced logging with cache information
              if cache_write > 0 || cache_read > 0
                cache_hit_rate = tokens[:input] > 0 ? (cache_read.to_f / (tokens[:input] + cache_read) * 100).round(1) : 0
                savings = (cache_read * 0.9).round(0)  # 90% discount on cached tokens
                Rails.logger.info "💰 Token usage - Input: #{tokens[:input]}, Output: #{tokens[:output]} | Cache: #{cache_read} read (#{cache_hit_rate}% hit rate), #{cache_write} written | Savings: ~#{savings} tokens ($#{(savings * 0.0000075).round(4)})"
              else
                Rails.logger.info "Token usage - Input: #{tokens[:input]}, Output: #{tokens[:output]}"
              end
            end

            Rails.logger.debug "Bedrock metadata: #{event.inspect}"
          end
        end
      end

      buffer

        # Success! Return the buffer and exit the retry loop
        return buffer

      rescue Aws::BedrockRuntime::Errors::ThrottlingException,
             Aws::BedrockRuntime::Errors::ServiceUnavailableException,
             Aws::BedrockRuntime::Errors::ValidationException,
             Timeout::Error,
             Seahorse::Client::NetworkingError => e

        # These are retryable errors - try to fallback to next model
        last_error = e
        error_type = e.class.name.split('::').last

        Rails.logger.warn "🔄 #{model_config[:name]} #{error_type}: #{e.message}"

        # Check if this is a context overflow error - need a model with larger context
        next_model = if context_overflow_error?(e)
          Rails.logger.info "📐 Context overflow detected - selecting larger context model"
          get_larger_context_fallback(current_model, attempted_models)
        else
          # Try to get next fallback model
          get_next_fallback_model(current_model, attempted_models)
        end

        if next_model
          current_model = next_model
          next_model_config = AVAILABLE_MODELS[next_model]
          Rails.logger.info "♻️  Falling back to #{next_model_config[:name]}..."
          next  # Retry with new model
        else
          # No more fallback options
          Rails.logger.error "❌ All models failed. Attempted: #{attempted_models.join(', ')}"

          # Raise appropriate error based on last error type
          case last_error
          when Aws::BedrockRuntime::Errors::ThrottlingException
            raise AmosErrors::BedrockThrottlingError.new(context: { attempted_models: attempted_models })
          when Aws::BedrockRuntime::Errors::ServiceUnavailableException
            raise AmosErrors::BedrockUnavailableError.new(context: { attempted_models: attempted_models })
          when Timeout::Error, Seahorse::Client::NetworkingError
            raise AmosErrors::BedrockTimeoutError.new(context: { attempted_models: attempted_models })
          else
            raise AmosErrors::BedrockError.new("All models failed: #{last_error.message}", context: { attempted_models: attempted_models })
          end
        end

      rescue Aws::BedrockRuntime::Errors::ServiceError => e
        # Non-retryable AWS error
        Rails.logger.error "Bedrock streaming error: #{e.message}"
        raise AmosErrors::BedrockError.new("Bedrock API Error: #{e.message}")

      rescue StandardError => e
        # Unexpected error - don't retry
        Rails.logger.error "Unexpected Bedrock streaming error: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        raise AmosErrors::BedrockError.new("Unexpected error: #{e.message}")
      end
    end
  end

  private

  def format_tools_for_bedrock(tools)
    tools.map.with_index do |tool, index|
      # Sanitize the schema to fix common JSON Schema 2020-12 issues
      raw_params = tool[:parameters] || { type: "object", properties: {}, required: [] }
      parameters = sanitize_tool_schema(raw_params)
      
      # Validate the sanitized schema before sending
      validate_schema_compliance!(parameters, tool[:name], index)
      
      {
        tool_spec: {
          name: tool[:name],
          description: tool[:description] || "No description provided",
          input_schema: {
            json: parameters
          }
        }
      }
    end
  end
  
  # Validate schema is JSON Schema 2020-12 compliant
  def validate_schema_compliance!(schema, tool_name, index)
    return unless schema.is_a?(Hash)
    
    properties = schema['properties'] || schema[:properties] || {}
    properties.each do |prop_name, prop_def|
      next unless prop_def.is_a?(Hash)
      
      # Check for empty enum (invalid in 2020-12)
      enum_val = prop_def['enum'] || prop_def[:enum]
      if enum_val.is_a?(Array) && enum_val.empty?
        Rails.logger.error "[BedrockService] SCHEMA ERROR: Tool ##{index} '#{tool_name}' property '#{prop_name}' has empty enum!"
        prop_def.delete('enum')
        prop_def.delete(:enum)
      end
      
      # Check for missing type
      has_type = prop_def.key?('type') || prop_def.key?(:type)
      has_ref = prop_def.key?('$ref')
      has_composite = ['anyOf', 'oneOf', 'allOf'].any? { |k| prop_def.key?(k) }
      has_valid_enum = enum_val.is_a?(Array) && enum_val.any?
      
      unless has_type || has_ref || has_composite || has_valid_enum
        Rails.logger.error "[BedrockService] SCHEMA ERROR: Tool ##{index} '#{tool_name}' property '#{prop_name}' missing type!"
        prop_def['type'] = 'string'
      end
      
      # Recursively check nested properties (for object types)
      if prop_def['properties'].is_a?(Hash)
        validate_schema_compliance!(prop_def, "#{tool_name}.#{prop_name}", index)
      end
      
      # Check items in arrays
      if prop_def['items'].is_a?(Hash)
        validate_schema_compliance!({ 'properties' => { 'item' => prop_def['items'] } }, "#{tool_name}.#{prop_name}[]", index)
      end
    end
  end
  
  # Sanitize tool schema to ensure JSON Schema 2020-12 compliance
  def sanitize_tool_schema(schema)
    return { type: "object", properties: {}, required: [] } unless schema.is_a?(Hash)
    
    sanitized = schema.deep_dup.with_indifferent_access
    
    # Ensure type is present
    sanitized[:type] ||= "object"
    
    # Ensure properties is a hash
    sanitized[:properties] ||= {}
    
    # Ensure required is an array
    if sanitized[:required].present? && !sanitized[:required].is_a?(Array)
      sanitized[:required] = []
    end
    sanitized[:required] ||= []
    
    # Sanitize each property
    if sanitized[:properties].is_a?(Hash)
      sanitized[:properties].each do |prop_name, prop_def|
        next unless prop_def.is_a?(Hash)
        
        # Remove empty enum arrays (invalid in JSON Schema 2020-12)
        if prop_def.key?(:enum) || prop_def.key?('enum')
          enum_val = prop_def[:enum] || prop_def['enum']
          if !enum_val.is_a?(Array) || enum_val.empty?
            prop_def.delete(:enum)
            prop_def.delete('enum')
            Rails.logger.warn "[BedrockService] Removed invalid empty enum from tool property '#{prop_name}'"
          end
        end
        
        # Add default type if missing
        has_type = prop_def.key?(:type) || prop_def.key?('type')
        has_ref = prop_def.key?('$ref')
        has_composite = prop_def.key?(:anyOf) || prop_def.key?('anyOf') || 
                       prop_def.key?(:oneOf) || prop_def.key?('oneOf') || 
                       prop_def.key?(:allOf) || prop_def.key?('allOf')
        has_enum = prop_def.key?(:enum) || prop_def.key?('enum')
        
        unless has_type || has_ref || has_composite || has_enum
          prop_def[:type] = 'string'
          Rails.logger.warn "[BedrockService] Added default type 'string' to tool property '#{prop_name}'"
        end
      end
    end
    
    # Convert back to regular hash with string keys (Bedrock expects this)
    sanitized.to_h.deep_stringify_keys
  end

  def format_messages_for_claude(messages)
    # Ensure messages is an array
    messages_array = case messages
    when Array
      messages
    when String
      [ { role: "user", content: messages } ]
    else
      [ { role: "user", content: messages.to_s } ]
    end

    # Claude on Bedrock expects specific format with content as array containing type
    Rails.logger.debug "🔍 format_messages_for_claude input: #{messages_array.inspect}" if Rails.env.development?

    # Check if messages are already properly formatted
    if messages_array.all? { |msg|
      msg.is_a?(Hash) &&
      msg[:content].is_a?(Array) &&
      msg[:content].all? { |item| item.is_a?(Hash) && item[:type] }
    }
      Rails.logger.debug "🔍 Messages already properly formatted, returning as-is" if Rails.env.development?
      return messages_array
    end

    formatted = messages_array.map do |msg|
      content = msg[:content] || msg["content"]

      Rails.logger.debug "🔍 Processing message content: #{content.inspect}" if Rails.env.development?

      # Format content for Bedrock API
      formatted_content = if content.is_a?(Array)
        # Check if array items already have 'type' field, if not fix them
        items = content.map do |item|
          if item.is_a?(Hash) && (item[:type] || item["type"])
            item_type = (item[:type] || item["type"]).to_s
            # Pass through tool_use and tool_result blocks unchanged
            if item_type == "tool_use"
              tool_data = item[:tool_use] || item["tool_use"] || item
              { type: "tool_use", tool_use: tool_data }
            elsif item_type == "tool_result"
              result_data = item[:tool_result] || item["tool_result"] || item
              { type: "tool_result", tool_result: result_data }
            else
              # Text content
              text_content = (item[:text] || item["text"])&.to_s&.strip
              next nil if text_content.blank?
              { type: "text", text: text_content }
            end
          elsif item.is_a?(Hash) && (item[:tool_use] || item["tool_use"])
            # Tool use block without explicit type
            tool_data = item[:tool_use] || item["tool_use"]
            { type: "tool_use", tool_use: tool_data }
          elsif item.is_a?(Hash) && (item[:tool_result] || item["tool_result"])
            # Tool result block without explicit type
            result_data = item[:tool_result] || item["tool_result"]
            { type: "tool_result", tool_result: result_data }
          elsif item.is_a?(Hash) && (item[:text] || item["text"])
            text_value = (item[:text] || item["text"])&.to_s&.strip
            next nil if text_value.blank?
            { type: "text", text: text_value }
          elsif item.is_a?(String)
            text = item.strip
            next nil if text.blank?
            { type: "text", text: text }
          else
            text = item.to_s.strip
            next nil if text.blank?
            { type: "text", text: text }
          end
        end.compact
        
        # If all content was empty, add a placeholder
        items.empty? ? [{ type: "text", text: "(empty message)" }] : items
      elsif content.is_a?(String)
        text = content.strip
        [ { type: "text", text: text.present? ? text : "(empty message)" } ]
      else
        text = content.to_s.strip
        [ { type: "text", text: text.present? ? text : "(empty message)" } ]
      end

      result = {
        role: (msg[:role] || msg["role"] || "user").to_s,
        content: formatted_content
      }

      Rails.logger.debug "🔍 Formatted message: #{result.inspect}" if Rails.env.development?
      result
    end

    # Filter out any messages that ended up with empty content arrays (shouldn't happen now but safety check)
    formatted = formatted.reject { |msg| msg[:content].empty? }
    
    Rails.logger.debug "🔍 Final formatted messages: #{formatted.inspect}" if Rails.env.development?
    formatted
  end

  # Send via platform model registry
  def send_via_platform(system_prompt, messages, model:, max_tokens:, temperature:, json_mode:, stream:, &block)
    prompt_config = {
      system_prompt: system_prompt,
      messages: format_platform_messages(system_prompt, messages),
      max_tokens: max_tokens,
      temperature: temperature,
      json_mode: json_mode
    }

    if stream && block_given?
      @model_registry.invoke_model_stream(model, prompt_config, user: @user, entity: @entity) do |chunk|
        yield chunk[:content] if chunk[:content]
      end
    else
      result = @model_registry.invoke_model(model, prompt_config, user: @user, entity: @entity)

      # Format response to match expected format
      {
        "id" => "platform-#{SecureRandom.hex(16)}",
        "model" => model,
        "choices" => [ {
          "message" => {
            "role" => "assistant",
            "content" => result[:content]
          },
          "finish_reason" => result[:stop_reason] || "stop"
        } ],
        "usage" => result[:usage]
      }
    end
  rescue => e
    Rails.logger.error "Platform model invocation failed: #{e.message}"
    raise AmosErrors::BedrockError.new("Platform model error: #{e.message}")
  end

  # Format messages for platform models
  def format_platform_messages(system_prompt, messages)
    formatted = []

    # Add system prompt as first message if present
    if system_prompt.present?
      formatted << { role: "system", content: system_prompt }
    end

    # Add user messages
    messages.each do |msg|
      formatted << {
        role: msg[:role] || "user",
        content: msg[:content] || msg[:text] || msg.to_s
      }
    end

    formatted
  end
end

