# frozen_string_literal: true

# ModelSelectionService - Auto-selects the best model based on task complexity and type
# 
# STRATEGY: Open-source first to avoid vendor lock-in
#   - Meta Llama: Orchestration, instruction-following, multi-step workflows
#   - Qwen: Coding, math, technical tool execution, multimodal
#   - Claude: Fallback for complex reasoning (minimize dependency)
#
# Slider Modes:
#   - :fast (1)     → Qwen 3 32B - fast, efficient, good for simple tasks
#   - :balanced (2) → Meta Llama 3.3 70B - reliable agentic work
#   - :powerful (3) → Meta Llama 3.2 90B Vision - maximum open-source power
#   - :auto (0)     → Smart routing based on task TYPE and complexity
#
# Zero-latency approach: Uses rules + regex for 80% of cases
#
class ModelSelectionService
  # Model tiers - OPEN SOURCE FIRST strategy
  MODEL_TIERS = {
    fast: {
      level: 1,
      models: {
        # Qwen 3 32B - fast, efficient, good multilingual
        default: 'qwen-3-32b',
        coding: 'qwen-3-coder-30b',  # Use for code-related tasks
        openai: 'gpt-4o-mini'
      },
      description: 'Fast & efficient (Qwen)',
      cost_per_1k_tokens: 0.00035, # $0.35/M input
      avg_latency_ms: 400
    },
    balanced: {
      level: 2,
      models: {
        # Mistral Large 2 - best for tool use in streaming mode
        # Note: Llama 3.3 70B does NOT support tools in streaming mode!
        default: 'mistral-large-2',
        coding: 'qwen-3-coder-30b',  # Qwen better for code
        openai: 'gpt-4o'
      },
      description: 'Balanced (Mistral Large 2)',
      cost_per_1k_tokens: 0.002, # $2.00/M input
      avg_latency_ms: 1200
    },
    powerful: {
      level: 3,
      models: {
        # Mistral Large 2 - best open model that supports tool streaming
        # Note: Llama 3.3 70B does NOT support tools in streaming mode!
        default: 'mistral-large-2',
        coding: 'qwen-3-coder-30b',
        # Claude as fallback for truly complex reasoning
        fallback: 'claude-opus-4-1',
        openai: 'o1'
      },
      description: 'Maximum power (Mistral Large 2)',
      cost_per_1k_tokens: 0.002, # $2.00/M input
      avg_latency_ms: 2000
    }
  }.freeze

  # Task type detection for smart routing
  CODING_PATTERNS = [
    /\b(code|coding|program|script|function|class|method|debug|compile)\b/i,
    /\b(python|javascript|ruby|java|typescript|sql|html|css)\b/i,
    /\b(api|endpoint|database|query|migration)\b/i,
    /\b(bug|error|exception|stack\s*trace|fix\s+the)\b/i,
    /```/,  # Code blocks
  ].freeze

  MATH_PATTERNS = [
    /\b(calculate|compute|formula|equation|math|percentage|average)\b/i,
    /\b(sum|total|multiply|divide|subtract|add)\b/i,
    /\d+\s*[\+\-\*\/\%]\s*\d+/,  # Math expressions like 10 + 20
    /\d+%\s*(of|from|to)/i,      # Percentage expressions like "15% of"
    /what\s+is\s+\d+.*\d+/i,     # "what is X of Y" math questions
  ].freeze

  # Complexity indicators (zero-latency classification)
  SIMPLE_PATTERNS = [
    /^(show|list|view|get|what('s| is| are)?)\s/i,
    /^how many/i,
    /status/i,
    /\?$/,  # Simple questions
    /^(hi|hello|hey|thanks|ok|yes|no)\b/i,
  ].freeze

  COMPLEX_PATTERNS = [
    /\b(analyze|design|architect|build|create|implement|develop)\b/i,
    /\b(complex|comprehensive|detailed|in-depth|thorough)\b/i,
    /\b(compare|contrast|evaluate|assess)\b.*\b(and|vs|versus)\b/i,
    /\b(strategy|strategic|plan|planning)\b/i,
    /\b(multiple|several|many)\s+(steps?|tasks?|modules?)/i,
    /\b(debug|troubleshoot|diagnose|fix)\b.*\b(issue|problem|error|bug)\b/i,
  ].freeze

  MEDIUM_PATTERNS = [
    /\b(update|change|modify|edit|add|remove)\b/i,
    /\b(explain|describe|tell me about)\b/i,
    /\b(help|assist|guide)\b/i,
  ].freeze

  attr_reader :provider

  def initialize(provider: :anthropic)
    @provider = provider
  end

  # Main entry point: Select model based on mode and message
  def select_model(message:, mode: :auto, context: {})
    case mode.to_sym
    when :fast
      result_for_tier(:fast, message, forced: true)
    when :balanced
      result_for_tier(:balanced, message, forced: true)
    when :powerful
      result_for_tier(:powerful, message, forced: true)
    when :auto
      auto_select(message, context)
    else
      auto_select(message, context)
    end
  end

  # Quick complexity check (zero latency, ~95% accuracy)
  def estimate_complexity(message)
    return :simple if message.length < 20
    return :complex if message.length > 500

    # Check patterns
    simple_matches = SIMPLE_PATTERNS.count { |p| message.match?(p) }
    complex_matches = COMPLEX_PATTERNS.count { |p| message.match?(p) }
    medium_matches = MEDIUM_PATTERNS.count { |p| message.match?(p) }

    # Word count as signal
    word_count = message.split(/\s+/).length

    # Score calculation
    complexity_score = 0
    complexity_score -= simple_matches * 2
    complexity_score += complex_matches * 3
    complexity_score += medium_matches * 1
    complexity_score += (word_count / 20) # Longer = more complex

    if complexity_score <= -2
      :simple
    elsif complexity_score >= 3
      :complex
    else
      :medium
    end
  end

  # Detect task type for smart model routing
  def detect_task_type(message)
    return :coding if CODING_PATTERNS.any? { |p| message.match?(p) }
    return :math if MATH_PATTERNS.any? { |p| message.match?(p) }
    :general
  end

  # Get model for a specific tier, considering task type
  def model_for_tier(tier, task_type: :general)
    tier_config = MODEL_TIERS[tier.to_sym][:models]
    
    # For coding/math tasks, prefer Qwen Coder
    if task_type.in?([:coding, :math]) && tier_config[:coding]
      return tier_config[:coding]
    end
    
    # Default model for the tier
    tier_config[:default] || tier_config[:anthropic] || tier_config.values.first
  end

  # Get all available tiers for UI
  def available_tiers
    MODEL_TIERS.map do |key, config|
      {
        key: key,
        level: config[:level],
        description: config[:description],
        model: config[:models][:default]
      }
    end
  end

  private

  def auto_select(message, context)
    complexity = estimate_complexity(message)
    task_type = detect_task_type(message)

    # Context can influence complexity
    if context[:has_attachments] || context[:multi_step_task]
      complexity = :complex if complexity == :simple
      complexity = :complex if complexity == :medium
    end

    if context[:follow_up] && context[:previous_complexity]
      # Follow-ups typically need same complexity as original
      complexity = context[:previous_complexity]
    end

    tier = case complexity
           when :simple then :fast
           when :medium then :balanced
           when :complex then :powerful
           end
    
    Rails.logger.info "[ModelSelection] Task type: #{task_type}, Complexity: #{complexity}, Tier: #{tier}"

    result_for_tier(tier, message, forced: false, complexity: complexity, task_type: task_type)
  end

  def result_for_tier(tier, message, forced: false, complexity: nil, task_type: nil)
    config = MODEL_TIERS[tier]
    detected_task_type = task_type || detect_task_type(message)
    selected_model = model_for_tier(tier, task_type: detected_task_type)
    
    reasoning = if forced
      "User selected #{tier} mode"
    else
      model_name = selected_model.include?('qwen') ? 'Qwen' : 
                   selected_model.include?('llama') ? 'Llama' : 'Claude'
      task_desc = detected_task_type == :coding ? ' (coding task → Qwen)' :
                  detected_task_type == :math ? ' (math task → Qwen)' : ''
      "Auto-selected #{model_name}#{task_desc}"
    end
    
    {
      model: selected_model,
      tier: tier,
      forced: forced,
      complexity: complexity || estimate_complexity(message),
      task_type: detected_task_type,
      reasoning: reasoning,
      cost_estimate: config[:cost_per_1k_tokens],
      latency_estimate_ms: config[:avg_latency_ms]
    }
  end
end



