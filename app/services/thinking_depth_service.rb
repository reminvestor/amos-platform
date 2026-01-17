# frozen_string_literal: true

# ThinkingDepthService - Controls Qwen3's reasoning depth via tokens and prompting
#
# STRATEGY:
# Instead of switching between different models, we use ONE model (Qwen3-Next-80B)
# and control its reasoning depth via:
#   - max_tokens: Higher values allow more "thinking" tokens
#   - Temperature: Lower for deeper, more consistent reasoning
#   - Prompt modifiers: /think, /no_think, chain-of-thought instructions
#
# LEVELS:
#   - Quick:    Opt-in only, fastest responses, lowest cost
#   - Standard: Auto mode floor, current default behavior
#   - Deep:     Enhanced reasoning, auto can escalate here
#   - Maximum:  Full chain-of-thought, auto can escalate here
#
# KEY PRINCIPLE: Auto mode NEVER goes below Standard (no downgrade)
#
class ThinkingDepthService
  # Thinking depth configurations
  # Auto mode is handled separately - these are the explicit user-selectable modes
  DEPTH_LEVELS = {
    light: {
      level: 0,
      max_tokens: 8192,
      temperature: 0.8,
      top_p: 0.95,
      prompt_prefix: "",
      prompt_suffix: "",
      description: "Fast responses for simple tasks.",
      auto_eligible: false,  # User must explicitly select
      cost_multiplier: 0.5
    },
    medium: {
      level: 1,
      max_tokens: 16384,
      temperature: 0.7,
      top_p: 0.95,
      prompt_prefix: "",
      prompt_suffix: "",
      description: "Balanced thinking for everyday tasks.",
      auto_eligible: true,  # Auto mode floor
      cost_multiplier: 1.0
    },
    deep: {
      level: 2,
      max_tokens: 32768,
      temperature: 0.6,
      top_p: 0.95,
      prompt_prefix: "",
      prompt_suffix: "\n\nThink through this step-by-step before responding.",
      description: "Enhanced reasoning for complex problems.",
      auto_eligible: true,  # Auto can escalate here
      cost_multiplier: 2.0
    }
  }.freeze

  # Patterns that trigger escalation to DEEP thinking
  DEEP_PATTERNS = [
    /\b(analyze|analysis|evaluate|assessment)\b/i,
    /\b(strategy|strategic|plan|planning)\b/i,
    /\b(compare|contrast|versus|vs\.?)\b/i,
    /\b(recommend|suggestion|advice)\b/i,
    /\b(optimize|optimization|improve)\b/i,
    /\b(review|critique|feedback)\b/i,
    /\b(debug|troubleshoot|diagnose)\b/i,
    /\b(why|how\s+should|what\s+if)\b/i,
  ].freeze

  # Patterns that trigger escalation to MAXIMUM thinking
  MAXIMUM_PATTERNS = [
    /\b(deep\s+think|think\s+deep|think\s+deeply|reason\s+through)\b/i,
    /\bthink\s+(really\s+)?deep(ly)?\b/i,  # "think really deep", "think deeply", etc.
    /\breally\s+(think|reason|analyze)\b/i,  # "really think about this"
    /\b(step.by.step|walk\s+me\s+through)\b/i,
    /\b(break\s+down|decompose|dissect)\b/i,
    /\b(complex|complicated|nuanced|subtle)\b/i,
    /\b(root\s+cause|underlying|fundamental)\b/i,
    /\b(long.term|implications|consequences)\b/i,
    /\b(hypothesis|theory|model|framework)\b/i,
    /\b(comprehensive|thorough|in-depth|detailed)\b/i,
    /\b(architect|design|system)\b.*\b(complex|large|enterprise)\b/i,
    /\b(macro|big\s+picture|holistic|existential)\b/i,  # Macro/philosophical
  ].freeze

  # Context flags that trigger escalation
  ESCALATION_CONTEXT_FLAGS = [
    :complex_multi_step_task,
    :multi_agent_coordination,
    :strategic_planning,
    :debugging_session,
    :code_review,
  ].freeze

  def initialize
    @default_model = 'qwen3-next-80b'
  end

  # Main entry point: Determine thinking depth based on user mode and message
  #
  # @param message [String] The user's message
  # @param user_mode [Symbol] User's selected mode (:auto, :quick, :standard, :deep, :maximum)
  # @param context [Hash] Additional context (flags, previous interactions, etc.)
  # @param llm_hint [Symbol] LLM-suggested depth from IntentClassifierService (optional)
  # @return [Hash] Thinking depth configuration
  #
  def determine_depth(message:, user_mode: :auto, context: {}, llm_hint: nil)
    # If user explicitly selected a specific depth, respect it
    if user_mode != :auto && DEPTH_LEVELS.key?(user_mode.to_sym)
      return build_result(user_mode.to_sym, message, forced: true)
    end

    # AUTO MODE: Floor is :medium, can only escalate UP
    depth = auto_select_depth(message, context, llm_hint)
    build_result(depth, message, forced: false, context: context)
  end

  # Get configuration for a specific depth level
  def config_for(depth)
    DEPTH_LEVELS[depth.to_sym] || DEPTH_LEVELS[:standard]
  end

  # Get all available depth levels for UI
  def available_depths
    DEPTH_LEVELS.map do |key, config|
      {
        key: key,
        level: config[:level],
        description: config[:description],
        auto_eligible: config[:auto_eligible]
      }
    end
  end

  # Apply thinking depth to a system prompt
  def apply_to_prompt(system_prompt, depth)
    config = config_for(depth)
    
    modified_prompt = system_prompt.dup
    
    # Add prefix (e.g., /think or /no_think)
    if config[:prompt_prefix].present?
      Rails.logger.info "[ThinkingDepth] Adding prefix for #{depth}: #{config[:prompt_prefix].strip.first(20)}..."
      modified_prompt = "#{config[:prompt_prefix]}#{modified_prompt}"
    end
    
    # Add suffix (e.g., chain-of-thought instructions)
    if config[:prompt_suffix].present?
      Rails.logger.info "[ThinkingDepth] Adding suffix for #{depth}: #{config[:prompt_suffix].strip.first(50)}..."
      modified_prompt = "#{modified_prompt}#{config[:prompt_suffix]}"
    end
    
    modified_prompt
  end

  # Get inference parameters for a depth level
  def inference_params(depth)
    config = config_for(depth)
    {
      max_tokens: config[:max_tokens],
      temperature: config[:temperature],
      top_p: config[:top_p]
    }
  end

  private

  def auto_select_depth(message, context, llm_hint = nil)
    # Check for deep thinking triggers via regex (complex reasoning, step-by-step, etc.)
    if should_use_deep?(message, context)
      Rails.logger.info "[ThinkingDepth] Escalating to DEEP: complex reasoning detected (regex)"
      return :deep
    end
    
    # If LLM provided a hint (from IntentClassifierService), use it
    # This catches cases where regex missed but user intent is clear from context
    if llm_hint.present? && DEPTH_LEVELS.key?(llm_hint.to_sym)
      llm_depth = llm_hint.to_sym
      # LLM can suggest :deep, but floor is still :medium
      if llm_depth == :deep
        Rails.logger.info "[ThinkingDepth] Escalating to DEEP: LLM classified complex intent"
        return :deep
      elsif llm_depth == :light && context[:user_explicitly_requested_light]
        # Only allow :light if user explicitly requested it
        Rails.logger.info "[ThinkingDepth] Using LIGHT: LLM + user request"
        return :light
      end
    end

    # Auto mode floor is :medium (16k tokens)
    Rails.logger.info "[ThinkingDepth] Using MEDIUM (auto mode floor)"
    :medium
  end

  def should_use_deep?(message, context)
    # Pattern-based detection - combines old DEEP and MAXIMUM patterns
    return true if DEEP_PATTERNS.any? { |p| message.match?(p) }
    return true if MAXIMUM_PATTERNS.any? { |p| message.match?(p) }
    
    # Context-based detection
    return true if context[:complex_multi_step_task]
    return true if context[:multi_agent_coordination]
    return true if context[:strategic_planning]
    return true if context[:debugging_session]
    return true if context[:code_review]
    return true if context[:has_attachments]
    
    # Long, complex messages with reasoning requests
    return true if message.length > 500 && message.match?(/\b(why|how|analyze|think)\b/i)
    
    # Medium-length messages with analytical language
    return true if message.length > 200 && message.match?(/\b(should|would|could|better|best)\b/i)
    
    false
  end

  def build_result(depth, message, forced: false, context: {})
    config = DEPTH_LEVELS[depth]
    
    reasoning = if forced
      "User selected #{depth} mode"
    else
      case depth
      when :deep then "Auto-escalated to Deep (complex reasoning detected)"
      else "Medium mode (auto floor)"
      end
    end

    {
      depth: depth,
      level: config[:level],
      model: @default_model,
      max_tokens: config[:max_tokens],
      temperature: config[:temperature],
      top_p: config[:top_p],
      prompt_prefix: config[:prompt_prefix],
      prompt_suffix: config[:prompt_suffix],
      forced: forced,
      reasoning: reasoning,
      cost_multiplier: config[:cost_multiplier],
      description: config[:description]
    }
  end
end

