# frozen_string_literal: true

# LoadoutHealthMonitor - Monitors loadout health and triggers alerts
#
# Run this periodically (e.g., hourly or daily) to:
# 1. Check all loadout health metrics
# 2. Create tickets for struggling loadouts
# 3. Notify admins of critical issues
#
class LoadoutHealthMonitor
  HEALTH_THRESHOLDS = {
    success_rate_warning: 70,
    success_rate_critical: 50,
    hallucination_rate_warning: 10,
    hallucination_rate_critical: 20,
    min_interactions_for_alert: 10
  }.freeze

  attr_reader :entity

  def initialize(entity:)
    @entity = entity
    @optimization_service = LoadoutOptimizationService.new(entity: entity)
  end

  # ═══════════════════════════════════════════════════════════════
  # HEALTH CHECKS
  # ═══════════════════════════════════════════════════════════════

  def run_health_check
    Rails.logger.info "🏥 [LoadoutHealthMonitor] Running health check for entity #{entity.id}"

    all_health = @optimization_service.all_loadouts_health(window: 7.days)
    
    results = {
      timestamp: Time.current,
      entity_id: entity.id,
      loadouts_checked: all_health.count,
      healthy: [],
      warning: [],
      critical: [],
      tickets_created: []
    }

    all_health.each do |health|
      next if health[:total_interactions].to_i < HEALTH_THRESHOLDS[:min_interactions_for_alert]

      status = determine_health_status(health)
      results[status] << health

      # Create tickets for problematic loadouts
      if status == :critical
        ticket = create_critical_ticket(health)
        results[:tickets_created] << ticket.id if ticket
      elsif status == :warning
        ticket = create_warning_ticket(health)
        results[:tickets_created] << ticket.id if ticket
      end
    end

    # Check for uncovered canvases
    uncovered = @optimization_service.detect_uncovered_canvases
    results[:uncovered_canvases] = uncovered.count

    # Check for tool errors
    tool_errors = @optimization_service.detect_tool_errors
    results[:tools_with_errors] = tool_errors.count

    log_health_summary(results)
    results
  end

  def health_score(loadout_slug)
    health = @optimization_service.health_summary(loadout_slug: loadout_slug, window: 7.days)
    
    score = 100.0
    
    # Deduct for low success rate
    if health[:success_rate]
      score -= (100 - health[:success_rate]) * 0.5
    end
    
    # Deduct for hallucinations
    if health[:hallucination_rate]
      score -= health[:hallucination_rate] * 2
    end
    
    # Deduct for low quality
    if health[:avg_quality]
      score -= (1.0 - health[:avg_quality]) * 20
    end

    trend = determine_trend(loadout_slug)

    {
      loadout_slug: loadout_slug,
      score: [score.round, 0].max,
      status: score >= 80 ? :healthy : (score >= 60 ? :warning : :critical),
      trend: trend,
      details: health
    }
  end

  def all_health_scores
    slugs = LoadoutMetric.for_entity(entity.id).recent(7.days).distinct.pluck(:loadout_slug)
    slugs.map { |slug| health_score(slug) }.sort_by { |h| h[:score] }
  end

  # ═══════════════════════════════════════════════════════════════
  # EMERGENCY FIXES
  # ═══════════════════════════════════════════════════════════════

  def apply_emergency_fix(loadout_slug, fix_type:)
    loadout = AgentPlugin.find_by(slug: loadout_slug)
    return { success: false, error: 'Loadout not found' } unless loadout

    # Create version snapshot before changes
    @optimization_service.create_version_snapshot(loadout_slug, change_reason: "emergency_fix_#{fix_type}")

    case fix_type.to_sym
    when :anti_hallucination
      apply_anti_hallucination_fix(loadout)
    when :add_guardrails
      apply_guardrails_fix(loadout)
    when :disable
      disable_loadout(loadout)
    else
      { success: false, error: "Unknown fix type: #{fix_type}" }
    end
  end

  private

  def determine_health_status(health)
    # Critical conditions
    if health[:success_rate] && health[:success_rate] < HEALTH_THRESHOLDS[:success_rate_critical]
      return :critical
    end
    if health[:hallucination_rate] && health[:hallucination_rate] > HEALTH_THRESHOLDS[:hallucination_rate_critical]
      return :critical
    end

    # Warning conditions
    if health[:success_rate] && health[:success_rate] < HEALTH_THRESHOLDS[:success_rate_warning]
      return :warning
    end
    if health[:hallucination_rate] && health[:hallucination_rate] > HEALTH_THRESHOLDS[:hallucination_rate_warning]
      return :warning
    end

    :healthy
  end

  def determine_trend(loadout_slug)
    # Compare last 7 days to previous 7 days
    current = LoadoutMetric.health_summary(loadout_slug: loadout_slug, entity_id: entity.id, window: 7.days)
    previous = LoadoutMetric.for_loadout(loadout_slug)
                            .for_entity(entity.id)
                            .where(created_at: 14.days.ago..7.days.ago)
    
    prev_total = previous.where(event_type: %w[success failure]).count
    return :stable if prev_total < 5

    prev_success = previous.successes.count
    prev_rate = (prev_success.to_f / prev_total * 100).round(1)
    current_rate = current[:success_rate] || 0

    if current_rate > prev_rate + 5
      :improving
    elsif current_rate < prev_rate - 5
      :declining
    else
      :stable
    end
  end

  def create_critical_ticket(health)
    PlatformEvolutionTicket.create_from_pattern(
      entity: entity,
      pattern_type: health[:hallucination_rate].to_f > 20 ? :high_hallucination_rate : :low_success_rate,
      evidence: health.merge(severity: 'critical')
    )
  end

  def create_warning_ticket(health)
    PlatformEvolutionTicket.create_from_pattern(
      entity: entity,
      pattern_type: health[:hallucination_rate].to_f > 10 ? :high_hallucination_rate : :low_success_rate,
      evidence: health.merge(severity: 'warning')
    )
  end

  def apply_anti_hallucination_fix(loadout)
    current_prompt = loadout.system_prompt || {}
    prompt_text = current_prompt['prompt'] || ''
    
    anti_hallucination_block = <<~BLOCK

      ## 🚨 CRITICAL ANTI-HALLUCINATION RULES
      You MUST follow these rules with NO exceptions:
      1. NEVER claim to have performed an action without calling the appropriate tool
      2. NEVER say "I've done X" or "I've completed Y" without a successful tool call
      3. If you cannot find the right tool, ASK the user - do NOT pretend
      4. Every modification requires a tool call - no exceptions
    BLOCK

    updated_prompt = prompt_text + anti_hallucination_block
    loadout.update!(system_prompt: current_prompt.merge('prompt' => updated_prompt))

    { success: true, fix_applied: 'anti_hallucination', loadout: loadout.slug }
  end

  def apply_guardrails_fix(loadout)
    current_prompt = loadout.system_prompt || {}
    guardrails = current_prompt['guardrails'] || []
    
    new_guardrails = [
      'When uncertain, ask clarifying questions instead of guessing',
      'Always verify tool results before reporting success',
      'If a tool call fails, report the failure honestly'
    ]

    loadout.update!(system_prompt: current_prompt.merge('guardrails' => (guardrails + new_guardrails).uniq))

    { success: true, fix_applied: 'guardrails', loadout: loadout.slug }
  end

  def disable_loadout(loadout)
    loadout.update!(status: 'disabled')
    { success: true, fix_applied: 'disabled', loadout: loadout.slug }
  end

  def log_health_summary(results)
    Rails.logger.info <<~LOG
      🏥 [LoadoutHealthMonitor] Health Check Complete
      Entity: #{results[:entity_id]}
      Loadouts Checked: #{results[:loadouts_checked]}
      ✅ Healthy: #{results[:healthy].count}
      ⚠️ Warning: #{results[:warning].count}
      🚨 Critical: #{results[:critical].count}
      📝 Tickets Created: #{results[:tickets_created].count}
      📭 Uncovered Canvases: #{results[:uncovered_canvases]}
      🔧 Tools with Errors: #{results[:tools_with_errors]}
    LOG
  end
end
