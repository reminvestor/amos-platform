# frozen_string_literal: true

# ModelSelectionService - SIMPLIFIED Qwen-first model selection
# 
# STRATEGY (based on comprehensive benchmarks):
#
# Qwen 3 32B is the DEFAULT for EVERYTHING:
#   - 100% tool success (DeepSeek can't use tools at all!)
#   - 376ms avg (fastest)
#   - 7.8/10 content (only 0.3 behind DeepSeek's 8.1)
#   - 9.0/10 instruction following
#
# DeepSeek R1 ONLY for complex reasoning:
#   - 7.3/10 reasoning vs Qwen's 6.0 (22% better!)
#   - No tools needed for reasoning anyway
#
# NO HANDOFF LOGIC - Qwen handles tools natively!
#
class ModelSelectionService
  # Model tiers - Simplified Qwen-first
  # 
  # Model roles:
  #   - qwen3-next-80b: DEFAULT for everything (9.2/10 overall, 100% tools, 131K context)
  #   - deepseek-r1:    Complex reasoning only
  #
  MODEL_TIERS = {
    fast: {
      level: 1,
      models: {
        default: 'qwen3-next-80b',    # Best overall (9.2/10), same price as Qwen 32B
        coding: 'qwen3-next-80b',     # Great code gen (9.0/10)
        reasoning: 'qwen3-next-80b',  # Fast tier uses Next for speed (8.0/10 reasoning)
        tools: 'qwen3-next-80b',      # 100% tool success
        openai: 'gpt-4o-mini'
      },
      description: 'Fast & efficient (Qwen3-Next-80B)',
      cost_per_1k_tokens: 0.00015,    # $0.15/M input - same as Qwen 32B!
      avg_latency_ms: 770
    },
    balanced: {
      level: 2,
      models: {
        default: 'qwen3-next-80b',    # Best overall for most tasks
        coding: 'qwen3-next-80b',     # Great code gen
        reasoning: 'deepseek-r1',     # R1 for complex analysis
        tools: 'qwen3-next-80b',      # 100% tool success
        cost_optimized: 'qwen3-next-80b',
        openai: 'gpt-4o'
      },
      description: 'Balanced (Qwen3-Next + R1 for reasoning)',
      cost_per_1k_tokens: 0.00050,
      avg_latency_ms: 800
    },
    powerful: {
      level: 3,
      models: {
        default: 'qwen3-next-80b',    # Qwen3-Next for most tasks
        coding: 'qwen3-next-80b',     # Great code gen
        reasoning: 'deepseek-r1',     # R1 for complex reasoning
        tools: 'qwen3-next-80b',      # 100% tool success
        cost_optimized: 'qwen3-next-80b',
        fallback: 'claude-sonnet-4-5',  # Premium fallback
        openai: 'o1'
      },
      description: 'Full power (Qwen3-Next + R1 reasoning + Sonnet fallback)',
      cost_per_1k_tokens: 0.00135,
      avg_latency_ms: 900
    }
  }.freeze

  # Task type detection for smart routing
  CODING_PATTERNS = [
    /\b(code|coding|program|script|function|class|method|debug|compile)\b/i,
    /\b(python|javascript|ruby|java|typescript|sql|html|css)\b/i,
    /\b(api|endpoint|database|query|migration)\b/i,
    /\b(bug|error|exception|stack\s*trace|fix\s+the)\b/i,
    /```/,  # Code blocks
    # Visualization/canvas requests need clean HTML/CSS/JS generation
    /\b(freeform|visualization|canvas)\b.*\b(show|display|create)\b/i,
    /\b(show|display|create)\b.*\b(freeform|visualization|canvas)\b/i,
    /\bon\s+the\s+freeform\s+canvas\b/i,
  ].freeze

  MATH_PATTERNS = [
    /\b(calculate|compute|formula|equation|math|percentage|average)\b/i,
    /\b(sum|total|multiply|divide|subtract|add)\b/i,
    /\d+\s*[\+\-\*\/\%]\s*\d+/,  # Math expressions like 10 + 20
    /\d+%\s*(of|from|to)/i,      # Percentage expressions like "15% of"
    /what\s+is\s+\d+.*\d+/i,     # "what is X of Y" math questions
  ].freeze

  # Bulk operation patterns - trigger cost_optimized mode
  BULK_PATTERNS = [
    /\b(bulk|batch|all|every|each)\b.*\b(import|export|update|process|create|sync)\b/i,
    /\b(import|export|update|process|create|sync)\b.*\b(bulk|batch|all|every|each)\b/i,
    /\b(all|every)\s+(contacts?|records?|items?|entries?|data)\b/i,
    /\b(thousands?|hundreds?|many|lots?\s+of)\b/i,
    /\bcsv\b/i,  # CSV operations are typically bulk
    /\bspreadsheet\b/i,
  ].freeze

  # Reasoning/analysis patterns - trigger DeepSeek R1
  REASONING_PATTERNS = [
    /\b(analyze|analysis|evaluate|assessment)\b/i,
    /\b(strategy|strategic|plan|planning|roadmap)\b/i,
    /\b(think\s+through|reason|reasoning|consider)\b/i,
    /\b(pros?\s+and\s+cons?|trade-?offs?|weigh)\b/i,
    /\b(compare|contrast|versus|vs\.?)\b/i,
    /\b(why|how\s+should|what\s+if|implications?)\b/i,
    /\b(recommend|suggestion|advice|advise)\b/i,
    /\b(decision|decide|choose|which\s+is\s+better)\b/i,
    /\b(gtm|go.to.market|business\s+plan|growth)\b/i,
    /\b(optimize|optimization|improve|improvement)\b/i,
    /\b(review|critique|feedback)\b/i,
    # Deep thinking triggers
    /\b(deep\s+think|think\s+deeply|reason\s+through)\b/i,
    /\b(step.by.step|walk\s+me\s+through)\b/i,
    /\b(break\s+down|decompose|dissect)\b/i,
    /\b(complex|complicated|nuanced|subtle)\b/i,
    /\b(hypothesis|theory|model|framework)\b/i,
    /\b(root\s+cause|underlying|fundamental)\b/i,
    /\b(long.term|implications|consequences)\b/i,
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
    return :reasoning if REASONING_PATTERNS.any? { |p| message.match?(p) }
    return :bulk if BULK_PATTERNS.any? { |p| message.match?(p) }
    :general
  end

  # Get model for a specific tier, considering task type
  def model_for_tier(tier, task_type: :general, cost_sensitive: false)
    tier_config = MODEL_TIERS[tier.to_sym][:models]
    
    # For reasoning/analysis tasks, prefer DeepSeek R1
    if task_type == :reasoning && tier_config[:reasoning]
      return tier_config[:reasoning]
    end
    
    # For coding/math tasks, prefer DeepSeek V3 (excellent code gen + proper tool calls)
    if task_type.in?([:coding, :math]) && tier_config[:coding]
      return tier_config[:coding]
    end
    
    # For bulk operations or cost-sensitive tasks, use cost_optimized model (DeepSeek V3.1)
    # This provides good reasoning at ~68x lower cost than premium models
    if (task_type == :bulk || cost_sensitive) && tier_config[:cost_optimized]
      return tier_config[:cost_optimized]
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

    # Cost sensitivity detection:
    # 1. Explicit flag from context (user settings, billing status)
    # 2. Bulk operations automatically trigger cost-optimized
    cost_sensitive = context[:cost_sensitive] || 
                     context[:low_balance] ||       # User billing account is low
                     context[:bulk_operation] ||    # Explicit bulk flag
                     task_type == :bulk             # Auto-detected bulk operation

    tier = case complexity
           when :simple then :fast
           when :medium then :balanced
           when :complex then :powerful
           end
    
    Rails.logger.info "[ModelSelection] Task type: #{task_type}, Complexity: #{complexity}, Tier: #{tier}, Cost-sensitive: #{cost_sensitive}"

    result_for_tier(tier, message, forced: false, complexity: complexity, task_type: task_type, cost_sensitive: cost_sensitive)
  end

  def result_for_tier(tier, message, forced: false, complexity: nil, task_type: nil, cost_sensitive: false)
    config = MODEL_TIERS[tier]
    detected_task_type = task_type || detect_task_type(message)
    selected_model = model_for_tier(tier, task_type: detected_task_type, cost_sensitive: cost_sensitive)
    
    reasoning = if forced
      "User selected #{tier} mode"
    else
      model_name = if selected_model.include?('deepseek')
                     'DeepSeek'
                   elsif selected_model.include?('qwen')
                     'Qwen'
                   elsif selected_model.include?('llama')
                     'Llama'
                   elsif selected_model.include?('mistral')
                     'Mistral'
                   else
                     'Claude'
                   end
      task_desc = case detected_task_type
                  when :coding then ' (coding task → DeepSeek)'
                  when :math then ' (math task → DeepSeek)'
                  when :bulk then ' (bulk operation → DeepSeek cost-optimized)'
                  else ''
                  end
      task_desc = ' (cost-sensitive → DeepSeek)' if cost_sensitive && !task_desc.include?('bulk')
      "Auto-selected #{model_name}#{task_desc}"
    end
    
    {
      model: selected_model,
      tier: tier,
      forced: forced,
      complexity: complexity || estimate_complexity(message),
      task_type: detected_task_type,
      cost_sensitive: cost_sensitive,
      reasoning: reasoning,
      cost_estimate: config[:cost_per_1k_tokens],
      latency_estimate_ms: config[:avg_latency_ms]
    }
  end
end



