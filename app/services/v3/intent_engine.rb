# frozen_string_literal: true

module V3
  # IntentEngine - The core of the Intent Architecture
  #
  # Two-tier agent architecture:
  #   Tier 1: Amos (user-facing, cheap model, conversational) → translates intent
  #   Tier 2: Platform Brain (backend, Claude, execution-focused) → accomplishes goals
  #
  # Flow:
  #   1. Receive a goal + spec from PlatformDoTool (Amos's intent translation)
  #   2. Check for a matching Recipe (fast path -- pure Ruby, no LLM, for trivial ops)
  #   3. If no recipe: delegate to PlatformBrain (Claude agent loop with platform tools)
  #   4. Return structured result to Amos
  #
  # Recipes are an OPTIMIZATION, not the primary path. They handle dead-simple
  # operations (single contact create, single delete) where an LLM call is overkill.
  # The PlatformBrain handles everything else -- it's Claude running its own agent
  # loop with the platform CRUD tools, figuring out multi-step plans on the fly.
  #
  # Zero functionality loss: all existing tool functionality is preserved because
  # the Brain uses the same PlatformCreateTool, PlatformUpdateTool, PlatformExecuteTool,
  # and PlatformQueryTool internally.
  #
  class IntentEngine
    attr_reader :user, :entity, :context, :progress_callback

    def initialize(user:, entity:, context: {}, progress_callback: nil)
      @user = user
      @entity = entity
      @context = context
      @progress_callback = progress_callback
    end

    # Main entry point: execute a goal
    # @param goal [String] What to accomplish
    # @param spec [Hash] Parameters and details
    # @return [Hash] Result with { success: true/false, ... }
    def execute(goal:, spec: {})
      normalized_goal = goal.to_s.downcase.strip
      spec = normalize_spec(spec)

      Rails.logger.info "[V3::IntentEngine] Processing goal: #{goal}"

      # Step 1: Try recipe lookup (fast path for trivial operations)
      recipe_class = V3::Recipes::Registry.find(normalized_goal, spec)

      if recipe_class && simple_enough_for_recipe?(normalized_goal, spec)
        Rails.logger.info "[V3::IntentEngine] Recipe fast-path: #{recipe_class.recipe_name}"
        result = execute_recipe(recipe_class, goal, spec)

        # Recipe can signal that it needs the Brain for multi-step work
        if result.is_a?(Hash) && result[:route_to_brain]
          Rails.logger.info "[V3::IntentEngine] Recipe requested Brain routing: #{result[:reason]}"
          # Fall through to Brain below
        elsif result.is_a?(Hash) && result[:success] != false
          return result
        else
          Rails.logger.info "[V3::IntentEngine] Recipe failed, falling through to Platform Brain"
        end
      end

      # Step 2: Platform Brain (primary path -- Claude agent loop)
      Rails.logger.info "[V3::IntentEngine] Delegating to Platform Brain"
      execute_with_brain(goal, spec)
    rescue => e
      Rails.logger.error "[V3::IntentEngine] Error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      { success: false, error: "Intent execution failed: #{e.message}" }
    end

    private

    # ═══════════════════════════════════════════════════════════════
    # RECIPE PATH (fast, no LLM -- for trivial operations only)
    # ═══════════════════════════════════════════════════════════════

    # Recipes should only be used for dead-simple, single-step operations
    # where calling Claude would be wasteful. Multi-step or complex goals
    # always go to the Platform Brain.
    def simple_enough_for_recipe?(goal, spec)
      # Single-object CRUD operations are recipe-worthy
      simple_patterns = [
        /\b(create|add|new|delete|remove)\s+(a\s+)?(single\s+)?(contact|group|template)\b/,
        /\bdelete\s+(a\s+|the\s+)?\w+/,
        /\bpublish\s+/,
        /\bsend\s+(a\s+|the\s+)?campaign/,
        /\bgenerate\s+(a\s+)?(csv|excel|pdf|image)/,
        /\brun\s+integration/,
      ]

      simple_patterns.any? { |p| goal.match?(p) }
    end

    def execute_recipe(recipe_class, original_goal, spec)
      recipe = recipe_class.new(
        user: user,
        entity: entity,
        context: context.merge(original_goal: original_goal),
        progress_callback: progress_callback
      )

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = recipe.execute(spec: spec)
      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      latency_ms = ((end_time - start_time) * 1000).round

      Rails.logger.info "[V3::IntentEngine] Recipe '#{recipe_class.recipe_name}' completed in #{latency_ms}ms"

      # Tag the result with engine metadata
      if result.is_a?(Hash)
        result[:_engine] = {
          path: "recipe",
          recipe: recipe_class.recipe_name,
          latency_ms: latency_ms
        }
      end

      record_analytics(
        goal: original_goal,
        path: "recipe",
        recipe: recipe_class.recipe_name,
        success: result.is_a?(Hash) ? result[:success] != false : true,
        latency_ms: latency_ms
      )

      result
    end

    # ═══════════════════════════════════════════════════════════════
    # PLATFORM BRAIN PATH (primary -- Claude agent loop)
    # ═══════════════════════════════════════════════════════════════

    def execute_with_brain(goal, spec)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      brain = V3::PlatformBrain.new(
        user: user,
        entity: entity,
        context: context,
        progress_callback: progress_callback
      )

      result = brain.execute(goal: goal, spec: spec)

      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      latency_ms = ((end_time - start_time) * 1000).round

      Rails.logger.info "[V3::IntentEngine] Platform Brain completed in #{latency_ms}ms"

      record_analytics(
        goal: goal,
        path: "platform_brain",
        success: result.is_a?(Hash) ? result[:success] != false : true,
        latency_ms: latency_ms,
        tool_calls: result.is_a?(Hash) ? result[:tools_used]&.length : 0
      )

      result
    end

    # ═══════════════════════════════════════════════════════════════
    # HELPERS
    # ═══════════════════════════════════════════════════════════════

    def normalize_spec(spec)
      return {} if spec.blank?
      spec.is_a?(Hash) ? spec.with_indifferent_access : {}
    end

    def record_analytics(goal:, path:, success:, latency_ms:, **extra)
      return unless defined?(ToolUsageMetric)

      ToolUsageMetric.record(
        tool_name: "platform_do",
        user: user,
        entity: entity,
        tool_type: "v3_intent_engine",
        success: success,
        latency_ms: latency_ms,
        context: "intent_engine",
        metadata: { goal: goal, path: path, **extra }
      )
    rescue => e
      Rails.logger.debug "[V3::IntentEngine] Analytics recording failed: #{e.message}"
    end
  end
end
