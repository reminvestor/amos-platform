# frozen_string_literal: true

module V3
  # IntentEngine - Routes platform_do goals to the Platform Brain
  #
  # Phase 6C: Simplified architecture.
  #
  # The Recipe fast-path has been removed from the routing logic because:
  # - Amos now has direct access to platform_create/platform_update (Phase 6A),
  #   so simple single-object CRUD no longer goes through platform_do at all.
  # - By the time a goal reaches platform_do -> IntentEngine, it's genuinely
  #   complex enough to need the Platform Brain (Claude agent loop).
  # - This eliminates the fragile simple_enough_for_recipe? regex heuristic
  #   and the maintenance burden of keeping recipes in sync with capabilities.
  #
  # The Recipe classes still exist in app/services/v3/recipes/ and can be
  # re-enabled if we identify specific high-frequency operations where the
  # zero-LLM-cost path provides meaningful savings.
  #
  # Flow:
  #   1. Receive a goal + spec from PlatformDoTool
  #   2. Delegate to PlatformBrain (Claude agent loop with platform tools)
  #   3. Return structured result to Amos
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
      spec = normalize_spec(spec)

      Rails.logger.info "[V3::IntentEngine] Processing goal: #{goal}"

      # Delegate to Platform Brain (Claude agent loop)
      execute_with_brain(goal, spec)
    rescue => e
      Rails.logger.error "[V3::IntentEngine] Error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      { success: false, error: "Intent execution failed: #{e.message}" }
    end

    private

    # ═══════════════════════════════════════════════════════════════
    # PLATFORM BRAIN PATH — Claude agent loop with platform tools
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
