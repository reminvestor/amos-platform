# frozen_string_literal: true

# AmosReactiveSessionJob - Runs a signal-triggered autonomous session
#
# Two modes:
#   - 'full': Complete autonomous loop (same as nightly, but signal-driven)
#   - 'targeted': Lightweight, focused only on the triggering signals
#
class AmosReactiveSessionJob < ApplicationJob
  queue_as :living_platform

  def perform(entity_id:, trigger_type:, trigger_reason:, signal_ids:, session_mode: 'targeted')
    entity = Entity.find(entity_id)

    Rails.logger.info "[AmosReactive] Starting #{session_mode} session for #{entity.name} " \
                      "(trigger: #{trigger_type}, signals: #{signal_ids.count})"

    signals = AmosSignal.where(id: signal_ids)

    if session_mode == 'full'
      run_full_session(entity, trigger_reason, signals)
    else
      run_targeted_session(entity, trigger_type, trigger_reason, signals)
    end
  rescue => e
    Rails.logger.error "[AmosReactive] Session failed: #{e.message}"
    Rails.logger.error e.backtrace&.first(5)&.join("\n")

    # Mark signals so they get picked up by the next nightly session
    AmosSignal.where(id: signal_ids).update_all(status: 'pending')
  end

  private

  def run_full_session(entity, trigger_reason, signals)
    loop_service = AmosAutonomousLoop.new(entity)
    result = loop_service.run_session!(session_type: 'reactive')

    # Mark signals as acted on
    signals.each do |signal|
      signal.mark_acted_on!(session_id: result[:session]&.id)
    end

    result
  end

  def run_targeted_session(entity, trigger_type, trigger_reason, signals)
    session = AmosThinkingSession.create!(
      entity: entity,
      session_type: 'reactive',
      status: 'running'
    )

    begin
      results = []

      # Group signals by type and handle each group
      signals.group_by(&:signal_type).each do |signal_type, group|
        result = handle_signal_group(entity, signal_type, group, session)
        results << result

        # Mark signals as processed
        group.each { |s| s.mark_acted_on!(session_id: session.id, thought_id: result[:thought_id]) }
      end

      session.complete!(
        summary: "Reactive session (#{trigger_type}): #{trigger_reason}. " \
                 "Processed #{signals.count} signals, #{results.count} actions taken.",
        bounties_created: results.sum { |r| r[:bounties_created] || 0 },
        total_points: results.sum { |r| r[:points] || 0 },
        thinking_log: results.map { |r| r[:log] }.compact.join("\n")
      )

      Rails.logger.info "[AmosReactive] Targeted session complete: #{results.count} actions"

    rescue => e
      session.fail!(e.message)
      raise
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # SIGNAL-SPECIFIC HANDLERS
  # Each signal type has a targeted response that's cheaper than a full session
  # ═══════════════════════════════════════════════════════════════════════════

  def handle_signal_group(entity, signal_type, signals, session)
    case signal_type
    when 'error_spike', 'critical_ticket'
      handle_error_signals(entity, signals)
    when 'integration_failure_rate'
      handle_integration_signals(entity, signals)
    when 'tool_failure_rate'
      handle_tool_failure_signals(entity, signals)
    when 'bounty_unclaimed_surge'
      handle_bounty_signals(entity, signals)
    when 'skill_effectiveness_drop'
      handle_skill_signals(entity, signals)
    when 'resource_limit_warning'
      handle_resource_signals(entity, signals)
    when 'platform_health_issue'
      handle_platform_health_signals(entity, signals)
    else
      handle_generic_signals(entity, signals)
    end
  end

  def handle_error_signals(entity, signals)
    # Create/update a working memory concern about error patterns
    summary = signals.map(&:summary).join('; ')
    thought = AmosWorkingMemory.create!(
      entity: entity,
      thought_type: 'concern',
      topic: 'error_pattern_detected',
      content: "Error signals detected: #{summary}. " \
               "Occurrences: #{signals.sum(&:occurrence_count)}. " \
               "Strength: #{signals.map(&:strength).max}.",
      salience: [signals.map(&:strength).max, 0.8].min,
      confidence: 0.6,
      evidence: signals.map { |s| { type: s.signal_type, data: s.data, time: s.created_at.iso8601 } }
    )

    # If critical, also create a bounty
    bounties_created = 0
    if signals.any? { |s| s.strength >= 0.9 }
      begin
        Bounty.create_from_amos!(
          entity: entity,
          title: "URGENT: #{signals.first.summary.truncate(100)}",
          description: "Auto-generated from critical error signal.\n\n#{summary}",
          bounty_type: 'bug',
          points: 200,
          scoring_rationale: "Auto-scored: critical reactive signal",
          metadata: { signal_ids: signals.map(&:id), trigger: 'reactive' }
        )
        bounties_created = 1
      rescue => e
        Rails.logger.warn "[AmosReactive] Failed to create error bounty: #{e.message}"
      end
    end

    { action: 'error_response', thought_id: thought.id, bounties_created: bounties_created,
      points: bounties_created * 200, log: "Error signal: #{summary}" }
  end

  def handle_integration_signals(entity, signals)
    thought = AmosWorkingMemory.create!(
      entity: entity,
      thought_type: 'observation',
      topic: 'integration_failures',
      content: "Integration failure pattern: #{signals.map(&:summary).join('; ')}",
      salience: signals.map(&:strength).max,
      confidence: 0.7,
      evidence: signals.map { |s| s.data }
    )

    # Check if a skill exists for this integration and flag it for evolution
    integration_name = signals.first&.data&.dig('integration_name')
    if integration_name && defined?(SystemSkill)
      skill = SystemSkill.active.find_integration_skill(integration_name)
      if skill
        skill.record_outcome!(positive: false)
        thought.update!(
          content: thought.content + "\nRelated skill '#{skill.name}' flagged for evolution."
        )
      end
    end

    { action: 'integration_alert', thought_id: thought.id, bounties_created: 0, points: 0,
      log: "Integration failure: #{integration_name}" }
  end

  def handle_tool_failure_signals(entity, signals)
    thought = AmosWorkingMemory.create!(
      entity: entity,
      thought_type: 'concern',
      topic: 'tool_failures',
      content: "Tool failure rate elevated: #{signals.map(&:summary).join('; ')}",
      salience: [signals.map(&:strength).max, 0.7].min,
      confidence: 0.6,
      evidence: signals.map { |s| s.data }
    )

    { action: 'tool_alert', thought_id: thought.id, bounties_created: 0, points: 0,
      log: "Tool failures detected" }
  end

  def handle_bounty_signals(entity, signals)
    # Trigger grooming directly
    grooming = BountyGroomingService.new(entity)
    results = grooming.groom!

    thought = AmosWorkingMemory.create!(
      entity: entity,
      thought_type: 'observation',
      topic: 'bounty_health',
      content: "Reactive grooming triggered: #{results[:demand_boosted]} boosted, #{results[:stale_closed]} closed",
      salience: 0.4,
      confidence: 0.8
    )

    { action: 'bounty_grooming', thought_id: thought.id, bounties_created: 0, points: 0,
      log: "Reactive grooming: #{results.inspect}" }
  end

  def handle_skill_signals(entity, signals)
    # Trigger skill evolution for the specific skills
    if defined?(SkillEvolutionService)
      evolution = SkillEvolutionService.new(entity)
      results = evolution.evolve_skills!

      { action: 'skill_evolution', thought_id: nil, bounties_created: 0, points: 0,
        log: "Reactive skill evolution: #{results[:skills_evolved]} evolved" }
    else
      handle_generic_signals(entity, signals)
    end
  end

  def handle_resource_signals(entity, signals)
    thought = AmosWorkingMemory.create!(
      entity: entity,
      thought_type: 'concern',
      topic: 'resource_limits',
      content: "Resource limit warning: #{signals.map(&:summary).join('; ')}",
      salience: 0.8,
      confidence: 0.9,
      evidence: signals.map { |s| s.data }
    )

    { action: 'resource_alert', thought_id: thought.id, bounties_created: 0, points: 0,
      log: "Resource limit warning" }
  end

  def handle_platform_health_signals(entity, signals)
    summary = signals.map(&:summary).join('; ')
    max_strength = signals.map(&:strength).max

    thought = AmosWorkingMemory.create!(
      entity: entity,
      thought_type: 'concern',
      topic: 'platform_health',
      content: "Platform health issue detected: #{summary}",
      salience: [max_strength, 0.8].min,
      confidence: 0.8,
      evidence: signals.map { |s| { type: s.signal_type, data: s.data, time: s.created_at.iso8601 } }
    )

    bounties_created = 0
    total_points = 0

    # Attempt auto-recovery for recoverable findings, create bounties for the rest
    signals.each do |signal|
      check_data = signal.data || {}
      recoverable = check_data.dig("details", "recoverable")
      action = check_data["suggested_action"]

      if action == "auto_recover" && recoverable
        recovered = attempt_auto_recovery(entity, check_data)
        if recovered
          Rails.logger.info "[AmosReactive] Auto-recovered platform health issue: #{signal.summary}"
          next
        end
      end

      # Create a bounty for actionable issues (high/critical severity)
      severity = check_data["severity"]
      next unless severity.in?(%w[critical high])

      bounty_params = check_data.dig("details", "bounty_params") || check_data["bounty_params"] || {}
      title = bounty_params["title"] || "Platform health: #{signal.summary.truncate(80)}"

      next if Bounty.where(entity: entity, status: 'open')
                     .where("title ILIKE ?", "%#{title.first(60)}%")
                     .exists?

      begin
        points = (bounty_params["points"] || 150).to_i
        Bounty.create_from_amos!(
          entity: entity,
          title: title,
          description: bounty_params["description"] || signal.summary,
          bounty_type: bounty_params["bounty_type"] || "infrastructure",
          points: points,
          scoring_rationale: "Auto-scored: platform health reactive signal (strength: #{signal.strength})",
          metadata: { signal_id: signal.id, check_name: check_data["check_name"], trigger: "reactive" }
        )
        bounties_created += 1
        total_points += points
      rescue => e
        Rails.logger.warn "[AmosReactive] Failed to create platform health bounty: #{e.message}"
      end
    end

    { action: 'platform_health_response', thought_id: thought.id,
      bounties_created: bounties_created, points: total_points,
      log: "Platform health: #{summary}" }
  end

  def attempt_auto_recovery(entity, check_data)
    check_name = check_data["check_name"]
    details = check_data.dig("details") || {}

    case check_name
    when "stuck_modules"
      module_ids = details["module_ids"] || details[:module_ids] || []
      return false if module_ids.empty?

      activated = 0
      AppModule.where(id: module_ids, status: "generating").find_each do |mod|
        has_table = ActiveRecord::Base.connection.table_exists?(mod.slug.pluralize) rescue false
        has_code = mod.module_codes.where(code_type: "model").exists?

        if has_table && has_code
          mod.activate!
          activated += 1
        end
      end
      activated > 0

    when "stale_plans"
      plan_id = details["plan_id"]
      return false unless plan_id

      plan = ApplicationPlan.find_by(id: plan_id)
      return false unless plan

      completed = plan.build_results&.dig("completed_phases") || []
      active_modules = AppModule.where(entity_id: plan.entity_id, status: "active").count

      if completed.include?("modules") && active_modules > 0
        plan.update!(status: "completed", error_message: nil)
        true
      else
        plan.update!(status: "failed", error_message: "Auto-failed: stale plan with no progress")
        true
      end
    else
      false
    end
  rescue => e
    Rails.logger.warn "[AmosReactive] Auto-recovery failed for #{check_data['check_name']}: #{e.message}"
    false
  end

  def handle_generic_signals(entity, signals)
    thought = AmosWorkingMemory.create!(
      entity: entity,
      thought_type: 'observation',
      topic: signals.first&.signal_type || 'unknown',
      content: "Signal detected: #{signals.map(&:summary).join('; ')}",
      salience: signals.map(&:strength).max,
      confidence: 0.5,
      evidence: signals.map { |s| s.data }
    )

    { action: 'observation', thought_id: thought.id, bounties_created: 0, points: 0,
      log: "Generic signal: #{signals.map(&:signal_type).uniq.join(', ')}" }
  end
end
