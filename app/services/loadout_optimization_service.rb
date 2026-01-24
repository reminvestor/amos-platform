# frozen_string_literal: true

# LoadoutOptimizationService - Manages loadout performance and auto-optimization
#
# This service:
# 1. Records metrics from loadout interactions
# 2. Detects patterns (hallucinations, failures, etc.)
# 3. Suggests and applies optimizations
# 4. Creates platform evolution tickets for major issues
#
class LoadoutOptimizationService
  attr_reader :entity

  def initialize(entity:)
    @entity = entity
  end

  # ═══════════════════════════════════════════════════════════════
  # METRIC RECORDING
  # ═══════════════════════════════════════════════════════════════

  def record_success(loadout_slug:, user:, canvas:, details: {}, quality: nil, response_time_ms: nil, session_id: nil)
    LoadoutMetric.record_success(
      loadout_slug: loadout_slug,
      entity: entity,
      user: user,
      canvas: canvas,
      details: details,
      quality: quality,
      response_time_ms: response_time_ms,
      session_id: session_id
    )
    Rails.logger.info "📊 [LoadoutOptimization] Recorded success for #{loadout_slug}"
  end

  def record_failure(loadout_slug:, user:, canvas:, details: {}, session_id: nil)
    LoadoutMetric.record_failure(
      loadout_slug: loadout_slug,
      entity: entity,
      user: user,
      canvas: canvas,
      details: details,
      session_id: session_id
    )
    Rails.logger.warn "📊 [LoadoutOptimization] Recorded failure for #{loadout_slug}"
    
    # Check if we need to create a ticket
    check_for_pattern_tickets(loadout_slug)
  end

  def record_hallucination(loadout_slug:, user:, canvas:, details: {}, session_id: nil)
    LoadoutMetric.record_hallucination(
      loadout_slug: loadout_slug,
      entity: entity,
      user: user,
      canvas: canvas,
      details: details,
      session_id: session_id
    )
    Rails.logger.warn "📊 [LoadoutOptimization] Recorded hallucination for #{loadout_slug}"
    
    # Check if we need to create a ticket
    check_for_pattern_tickets(loadout_slug)
  end

  def record_tool_call(loadout_slug:, tool_name:, success:, user: nil, canvas: nil, details: {}, session_id: nil)
    LoadoutMetric.record_tool_call(
      loadout_slug: loadout_slug,
      entity: entity,
      tool_name: tool_name,
      success: success,
      user: user,
      canvas: canvas,
      details: details,
      session_id: session_id
    )
  end

  # ═══════════════════════════════════════════════════════════════
  # ANALYTICS
  # ═══════════════════════════════════════════════════════════════

  def health_summary(loadout_slug:, window: 7.days)
    LoadoutMetric.health_summary(loadout_slug: loadout_slug, entity_id: entity.id, window: window)
  end

  def all_loadouts_health(window: 7.days)
    slugs = LoadoutMetric.for_entity(entity.id).recent(window).distinct.pluck(:loadout_slug)
    slugs.map { |slug| health_summary(loadout_slug: slug, window: window) }
  end

  def struggling_loadouts(window: 7.days, threshold: 70)
    all_loadouts_health(window: window).select do |health|
      health[:success_rate] && health[:success_rate] < threshold
    end
  end

  def high_hallucination_loadouts(window: 7.days, threshold: 10)
    all_loadouts_health(window: window).select do |health|
      health[:hallucination_rate] && health[:hallucination_rate] > threshold
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # PATTERN DETECTION & TICKET CREATION
  # ═══════════════════════════════════════════════════════════════

  # Check for loadout issues and log them
  # NOTE: Loadout issues are NOT platform tickets - they're handled via the loadout admin UI
  # Platform tickets are for code changes to Amos itself (new models, UI fixes, etc.)
  def check_for_pattern_tickets(loadout_slug)
    health = health_summary(loadout_slug: loadout_slug, window: 7.days)
    
    # High hallucination rate - log for admin review
    if health[:hallucination_rate] && health[:hallucination_rate] > 15
      Rails.logger.warn "⚠️ [LoadoutOptimization] #{loadout_slug} has high hallucination rate: #{health[:hallucination_rate]}%"
      # Consider auto-applying anti-hallucination fix if rate is critical
      if health[:hallucination_rate] > 25
        LoadoutHealthMonitor.new(entity: entity).apply_emergency_fix(loadout_slug, fix_type: :anti_hallucination)
      end
    end
    
    # Low success rate - log for admin review
    if health[:success_rate] && health[:success_rate] < 60 && health[:total_interactions] > 10
      Rails.logger.warn "⚠️ [LoadoutOptimization] #{loadout_slug} has low success rate: #{health[:success_rate]}%"
    end
  end

  def detect_uncovered_canvases
    # Find canvases that have activity but no loadout
    # This would query actual canvas usage and compare to CANVAS_TO_PLUGIN_MAP
    uncovered = []
    
    # Get all canvas contexts from metrics
    active_canvases = LoadoutMetric.for_entity(entity.id)
                                   .recent(30.days)
                                   .where(loadout_slug: 'amos_default')
                                   .group(:canvas_context)
                                   .count

    active_canvases.each do |canvas, count|
      next if canvas.blank?
      next if PluginInjectionService::CANVAS_TO_PLUGIN_MAP.key?(canvas)
      
      uncovered << { canvas: canvas, usage_count: count }
    end

    uncovered.each do |data|
      PlatformEvolutionTicket.create_from_pattern(
        entity: entity,
        pattern_type: :uncovered_canvas,
        evidence: data
      )
    end

    uncovered
  end

  def detect_tool_errors(window: 7.days)
    # Find tools with high error rates
    tool_errors = LoadoutMetric.for_entity(entity.id)
                               .recent(window)
                               .where(event_type: 'tool_error')
                               .group("details->>'tool_name'")
                               .count

    tool_errors.each do |tool_name, error_count|
      next if error_count < 5
      
      PlatformEvolutionTicket.create_from_pattern(
        entity: entity,
        pattern_type: :tool_error,
        evidence: { tool_name: tool_name, error_count: error_count }
      )
    end

    tool_errors
  end

  # ═══════════════════════════════════════════════════════════════
  # AUTO-OPTIMIZATION
  # ═══════════════════════════════════════════════════════════════

  def suggest_improvements(loadout_slug)
    health = health_summary(loadout_slug: loadout_slug, window: 7.days)
    loadout = AgentPlugin.find_by(slug: loadout_slug)
    return [] unless loadout

    suggestions = []

    # High hallucination rate - suggest anti-hallucination prompt
    if health[:hallucination_rate] && health[:hallucination_rate] > 10
      suggestions << {
        type: 'prompt_addition',
        priority: 'high',
        change: 'Add stronger anti-hallucination guardrails',
        prompt_addition: "\n\n## CRITICAL: You MUST call tools for any action. NEVER claim to have done something without a tool call."
      }
    end

    # Low success rate - analyze failure patterns
    if health[:success_rate] && health[:success_rate] < 70
      failure_details = LoadoutMetric.for_loadout(loadout_slug)
                                     .for_entity(entity.id)
                                     .failures
                                     .recent(7.days)
                                     .pluck(:details)
      
      common_errors = failure_details.map { |d| d['error_type'] }.compact.tally.sort_by { |_, v| -v }.first(3)
      
      suggestions << {
        type: 'investigate',
        priority: 'medium',
        change: 'Analyze failure patterns',
        evidence: common_errors
      }
    end

    suggestions
  end

  def create_version_snapshot(loadout_slug, change_reason:, changed_by: nil)
    loadout = AgentPlugin.find_by(slug: loadout_slug)
    return nil unless loadout

    LoadoutVersion.create!(
      agent_plugin: loadout,
      system_prompt_snapshot: loadout.system_prompt.to_json,
      tools_snapshot: loadout.agent_tools.pluck(:tool_name),
      change_reason: change_reason,
      changed_by: changed_by,
      performance_before: health_summary(loadout_slug: loadout_slug, window: 7.days),
      is_active: true
    )
  end
end
