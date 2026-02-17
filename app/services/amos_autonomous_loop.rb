# frozen_string_literal: true

# AmosAutonomousLoop - The "brain behind the brain"
#
# This is AMOS's autonomous cognitive loop. Unlike the rigid phase-based
# thinking service, this loop is ATTENTION-DRIVEN: AMOS decides what to
# focus on based on what matters most right now.
#
# Architecture:
#
#   ┌─────────────────────────────────────────────────────┐
#   │                   PERCEPTION                         │
#   │  Gather signals: errors, metrics, user feedback,     │
#   │  stale bounties, skill effectiveness, memory state   │
#   └──────────────────────┬──────────────────────────────┘
#                          ▼
#   ┌─────────────────────────────────────────────────────┐
#   │                   ATTENTION                          │
#   │  Score all possible focus areas by urgency/value.    │
#   │  Pick the top N things to think about this session.  │
#   │  Log what was chosen and what was deferred.          │
#   └──────────────────────┬──────────────────────────────┘
#                          ▼
#   ┌─────────────────────────────────────────────────────┐
#   │                   COGNITION                          │
#   │  For each focus area:                                │
#   │  - Retrieve relevant working memory                  │
#   │  - Think (LLM call) about what to do                 │
#   │  - Update working memory with new thoughts           │
#   │  - Execute actions if confidence is high enough       │
#   └──────────────────────┬──────────────────────────────┘
#                          ▼
#   ┌─────────────────────────────────────────────────────┐
#   │                   META-COGNITION                     │
#   │  Reflect on the session itself:                      │
#   │  - Was this a good use of attention?                 │
#   │  - What patterns am I seeing across sessions?        │
#   │  - What am I consistently ignoring?                  │
#   │  - Adjust attention weights for next time            │
#   └─────────────────────────────────────────────────────┘
#
# Key difference from AmosThinkingService:
#   - AmosThinkingService: "Run phase 1, 2, 3, 4 in order"
#   - AmosAutonomousLoop: "What's most important right now? Think about that."
#
# The existing AmosThinkingService is still useful for structured bounty
# generation. This loop wraps it and other services, deciding WHEN and
# WHETHER to invoke each one.
#
class AmosAutonomousLoop
  # How many focus areas per session (controls cost)
  MAX_FOCUS_AREAS = 3

  # Token budget per session (prevents runaway costs)
  TOKEN_BUDGET = 30_000

  # Minimum signal strength to warrant attention
  MIN_SIGNAL_STRENGTH = 0.3

  # Action types AMOS can take
  ACTIONS = {
    create_bounty: { cost: :medium, description: "Create a new bounty for the community" },
    groom_bounties: { cost: :medium, description: "Reprioritize and adjust bounty backlog" },
    evolve_skill: { cost: :medium, description: "Improve a skill file based on execution data" },
    investigate: { cost: :low, description: "Dig deeper into an observation (creates working memory)" },
    resolve_thought: { cost: :low, description: "Mark a working memory thought as addressed" },
    connect_dots: { cost: :low, description: "Link related observations together" },
    flag_for_humans: { cost: :free, description: "Create a note for human attention" },
    defer: { cost: :free, description: "Acknowledge but defer to a future session" }
  }.freeze

  attr_reader :entity, :session, :attention_log, :tokens_used

  def initialize(entity)
    @entity = entity
    @attention_log = []
    @tokens_used = 0
    @session_thoughts = []
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # MAIN LOOP
  # ═══════════════════════════════════════════════════════════════════════════

  def run_session!(session_type: 'autonomous')
    @session = AmosThinkingSession.create!(
      entity: entity,
      session_type: session_type,
      status: 'running'
    )

    begin
      log "🧠 Starting autonomous session"

      # ── PHASE 1: PERCEPTION ──
      signals = perceive
      log "📡 Perceived #{signals.count} signals"

      # ── PHASE 2: ATTENTION ──
      focus_areas = allocate_attention(signals)
      log "🎯 Focusing on #{focus_areas.count} areas: #{focus_areas.map { |f| f[:label] }.join(', ')}"

      # ── PHASE 3: COGNITION ──
      results = focus_areas.map do |focus|
        break if @tokens_used >= TOKEN_BUDGET

        think_about(focus)
      end.compact

      # ── PHASE 3.5: SYNC TICKETS → BOUNTIES ──
      sync_results = sync_tickets_to_bounties!
      bounties_from_sync = sync_results[:total_created] || 0
      log "🔄 Ticket sync: #{bounties_from_sync} bounties created from qualified tickets"

      # ── PHASE 4: META-COGNITION ──
      meta = reflect_on_session(focus_areas, results)

      # ── PHASE 5: MEMORY MAINTENANCE ──
      maintain_memory!

      # Complete session
      total_bounties = results.sum { |r| r[:bounties_created] || 0 } + bounties_from_sync
      @session.complete!(
        summary: meta[:session_summary],
        bounties_created: total_bounties,
        total_points: results.sum { |r| r[:points_allocated] || 0 },
        thinking_log: build_session_log(focus_areas, results, meta)
      )

      log "✅ Session complete (#{@tokens_used} tokens used)"

      {
        session: @session,
        focus_areas: focus_areas.map { |f| f[:label] },
        results: results,
        meta: meta,
        tokens_used: @tokens_used
      }

    rescue => e
      log "❌ Session failed: #{e.message}"
      @session.fail!(e.message)
      raise
    end
  end

  private

  # ═══════════════════════════════════════════════════════════════════════════
  # PHASE 1: PERCEPTION
  # Gather all signals that might warrant attention
  # ═══════════════════════════════════════════════════════════════════════════

  def perceive
    signals = []

    # Signal 1: Critical errors/tickets
    signals += perceive_critical_issues

    # Signal 2: Stale/unclaimed bounties
    signals += perceive_bounty_health

    # Signal 3: Skill effectiveness changes
    signals += perceive_skill_health

    # Signal 4: Working memory (unresolved thoughts from previous sessions)
    signals += perceive_working_memory

    # Signal 5: User activity patterns
    signals += perceive_user_patterns

    # Signal 6: Integration health
    signals += perceive_integration_health

    # Signal 7: Recent agent execution quality
    signals += perceive_execution_quality

    # Filter by minimum strength
    signals.select { |s| s[:strength] >= MIN_SIGNAL_STRENGTH }
           .sort_by { |s| -s[:strength] }
  end

  def perceive_critical_issues
    signals = []

    # Critical support tickets
    critical_count = SupportTicket.where(entity: entity).critical.open_tickets.count
    if critical_count > 0
      signals << {
        type: :critical_issues,
        label: "#{critical_count} critical tickets",
        strength: [0.9 + (critical_count * 0.02), 1.0].min,
        data: { count: critical_count },
        suggested_action: :create_bounty
      }
    end

    # Recent errors (last 6 hours - more responsive than the old 24h window)
    recent_errors = SupportTicket.where(entity: entity)
                                  .where(source: 'log_monitor')
                                  .where('created_at > ?', 6.hours.ago)
                                  .count
    if recent_errors > 3
      signals << {
        type: :error_surge,
        label: "#{recent_errors} errors in last 6 hours",
        strength: [0.6 + (recent_errors * 0.05), 0.95].min,
        data: { count: recent_errors },
        suggested_action: :investigate
      }
    end

    signals
  rescue => e
    log "⚠️ Critical issue perception failed: #{e.message}"
    []
  end

  def perceive_bounty_health
    signals = []

    open_count = Bounty.where(entity: entity).open_bounties.count
    stale_count = Bounty.where(entity: entity).open_bounties.where('created_at < ?', 14.days.ago).count
    unclaimed_high_value = Bounty.where(entity: entity).open_bounties.high_value.where('created_at < ?', 7.days.ago).count

    # Stale backlog
    if stale_count > 5
      signals << {
        type: :stale_bounties,
        label: "#{stale_count} stale bounties (14+ days)",
        strength: [0.5 + (stale_count * 0.03), 0.85].min,
        data: { stale: stale_count, total: open_count },
        suggested_action: :groom_bounties
      }
    end

    # High-value bounties nobody wants
    if unclaimed_high_value > 0
      signals << {
        type: :unclaimed_high_value,
        label: "#{unclaimed_high_value} unclaimed high-value bounties",
        strength: [0.6 + (unclaimed_high_value * 0.1), 0.9].min,
        data: { count: unclaimed_high_value },
        suggested_action: :groom_bounties
      }
    end

    # No bounties at all
    if open_count == 0
      signals << {
        type: :empty_backlog,
        label: "No open bounties — need to generate work",
        strength: 0.7,
        data: {},
        suggested_action: :create_bounty
      }
    end

    signals
  rescue => e
    log "⚠️ Bounty health perception failed: #{e.message}"
    []
  end

  def perceive_skill_health
    signals = []

    return signals unless defined?(SystemSkill)

    # Skills with low effectiveness
    low_performers = SystemSkill.active.where('effectiveness_score < ? AND injection_count > ?', 0.4, 5)
    if low_performers.exists?
      signals << {
        type: :low_skill_effectiveness,
        label: "#{low_performers.count} skills underperforming",
        strength: [0.5 + (low_performers.count * 0.05), 0.8].min,
        data: { skills: low_performers.pluck(:name, :effectiveness_score) },
        suggested_action: :evolve_skill
      }
    end

    signals
  rescue => e
    log "⚠️ Skill health perception failed: #{e.message}"
    []
  end

  def perceive_working_memory
    signals = []

    # High-salience unresolved thoughts
    urgent_thoughts = AmosWorkingMemory.top_of_mind(entity, limit: 5)
    urgent_thoughts.each do |thought|
      signals << {
        type: :working_memory,
        label: "Thought: #{thought.topic} (#{thought.thought_type})",
        strength: thought.salience,
        data: { thought_id: thought.id, thought_type: thought.thought_type, revisits: thought.times_revisited },
        suggested_action: thought.thought_type == 'concern' ? :investigate : :connect_dots
      }
    end

    signals
  rescue => e
    log "⚠️ Working memory perception failed: #{e.message}"
    []
  end

  def perceive_user_patterns
    signals = []

    # Active user decline
    active_7d = User.joins(:entity_users).where(entity_users: { entity_id: entity.id }).where('last_sign_in_at > ?', 7.days.ago).count
    active_30d = User.joins(:entity_users).where(entity_users: { entity_id: entity.id }).where('last_sign_in_at > ?', 30.days.ago).count

    if active_30d > 10 && active_7d < active_30d * 0.3
      signals << {
        type: :user_decline,
        label: "User engagement declining (#{active_7d}/#{active_30d} active 7d vs 30d)",
        strength: 0.6,
        data: { active_7d: active_7d, active_30d: active_30d },
        suggested_action: :investigate
      }
    end

    signals
  rescue => e
    log "⚠️ User pattern perception failed: #{e.message}"
    []
  end

  def perceive_integration_health
    signals = []

    # Failed integration calls in last 24h
    if defined?(IntegrationLog)
      failed = IntegrationLog.where('created_at > ?', 24.hours.ago).where(success: false).count
      total = IntegrationLog.where('created_at > ?', 24.hours.ago).count

      if total > 10 && failed > total * 0.2
        signals << {
          type: :integration_failures,
          label: "Integration failure rate: #{(failed.to_f / total * 100).round}% (#{failed}/#{total})",
          strength: [0.6 + (failed.to_f / total * 0.3), 0.9].min,
          data: { failed: failed, total: total },
          suggested_action: :investigate
        }
      end
    end

    signals
  rescue => e
    log "⚠️ Integration health perception failed: #{e.message}"
    []
  end

  def perceive_execution_quality
    signals = []

    if defined?(AgentToolExecution)
      recent_execs = AgentToolExecution.where('created_at > ?', 24.hours.ago)
      total = recent_execs.count
      failed = recent_execs.where(success: false).count

      if total > 20 && failed > total * 0.3
        signals << {
          type: :execution_quality,
          label: "Tool execution failures: #{(failed.to_f / total * 100).round}% (#{failed}/#{total})",
          strength: [0.5 + (failed.to_f / total * 0.4), 0.85].min,
          data: { failed: failed, total: total },
          suggested_action: :evolve_skill
        }
      end
    end

    signals
  rescue => e
    log "⚠️ Execution quality perception failed: #{e.message}"
    []
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PHASE 2: ATTENTION ALLOCATION
  # Decide what to focus on this session
  # ═══════════════════════════════════════════════════════════════════════════

  def allocate_attention(signals)
    return [] if signals.empty?

    # Group signals by suggested action to avoid redundant work
    grouped = signals.group_by { |s| s[:suggested_action] }

    # Score each group
    scored_groups = grouped.map do |action, group_signals|
      max_strength = group_signals.map { |s| s[:strength] }.max
      total_signals = group_signals.count
      action_cost = ACTIONS.dig(action, :cost) || :medium

      # Priority score: strength * count bonus * cost efficiency
      cost_factor = case action_cost
                    when :free then 1.3
                    when :low then 1.1
                    when :medium then 1.0
                    when :high then 0.8
                    else 1.0
                    end

      priority = max_strength * (1 + Math.log(total_signals + 1) * 0.2) * cost_factor

      {
        action: action,
        label: group_signals.first[:label],
        priority: priority.round(3),
        signals: group_signals,
        strength: max_strength,
        cost: action_cost
      }
    end

    # Pick top focus areas within budget
    selected = scored_groups.sort_by { |g| -g[:priority] }.first(MAX_FOCUS_AREAS)

    # Log what was deferred
    deferred = scored_groups - selected
    deferred.each do |area|
      record_attention_decision!(
        focus_area: area[:label],
        reasoning: "Deferred: lower priority (#{area[:priority]}) than selected areas",
        alternatives: selected.map { |s| s[:label] },
        outcome: 'deferred'
      )
    end

    # Log what was selected
    selected.each do |area|
      record_attention_decision!(
        focus_area: area[:label],
        reasoning: "Selected: priority #{area[:priority]} (strength: #{area[:strength]}, signals: #{area[:signals].count})",
        alternatives: deferred.map { |d| d[:label] },
        outcome: 'acted'
      )
    end

    selected
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PHASE 3: COGNITION
  # Actually think about each focus area
  # ═══════════════════════════════════════════════════════════════════════════

  def think_about(focus)
    log "💭 Thinking about: #{focus[:label]}"
    started_at = Time.current

    result = case focus[:action]
             when :create_bounty
               think_and_create_bounties(focus)
             when :groom_bounties
               think_and_groom(focus)
             when :evolve_skill
               think_and_evolve_skills(focus)
             when :investigate
               think_and_investigate(focus)
             when :connect_dots
               think_and_connect(focus)
             when :flag_for_humans
               flag_for_attention(focus)
             when :defer
               defer_thought(focus)
             else
               think_and_investigate(focus) # Default: investigate
             end

    duration_ms = ((Time.current - started_at) * 1000).round
    log "  Completed in #{duration_ms}ms"

    result.merge(duration_ms: duration_ms)
  rescue => e
    log "  ❌ Failed: #{e.message}"
    { action: focus[:action], success: false, error: e.message, bounties_created: 0, points_allocated: 0 }
  end

  def think_and_create_bounties(focus)
    # Delegate to the existing thinking service for bounty generation
    thinking_service = AmosThinkingService.new(entity)
    context = thinking_service.gather_context
    reflection = thinking_service.send(:reflect, context)
    bounties = thinking_service.send(:create_bounties_from_reflection, reflection)

    # Record in working memory
    create_thought!(
      type: 'observation',
      topic: 'bounty_generation',
      content: "Generated #{bounties.count} bounties. Reflection: #{reflection[:reflection_summary]&.truncate(300)}"
    )

    { action: :create_bounty, success: true, bounties_created: bounties.count,
      points_allocated: bounties.sum(&:points) }
  rescue => e
    log "  ⚠️ Bounty creation fell back to simple: #{e.message}"
    { action: :create_bounty, success: false, error: e.message, bounties_created: 0, points_allocated: 0 }
  end

  def think_and_groom(focus)
    grooming_service = BountyGroomingService.new(entity)
    results = grooming_service.groom!

    create_thought!(
      type: 'observation',
      topic: 'bounty_grooming',
      content: "Groomed #{results[:total_open]} bounties: #{results[:demand_boosted]} boosted, " \
               "#{results[:stale_closed]} closed, #{results[:reprioritized]} reprioritized"
    )

    { action: :groom_bounties, success: true, bounties_created: 0, points_allocated: 0,
      grooming_results: results }
  end

  def think_and_evolve_skills(focus)
    return { action: :evolve_skill, success: false, error: "SkillEvolutionService not available" } unless defined?(SkillEvolutionService)

    evolution_service = SkillEvolutionService.new(entity)
    results = evolution_service.evolve_skills!

    if results[:skills_evolved] > 0
      create_thought!(
        type: 'insight',
        topic: 'skill_evolution',
        content: "Evolved #{results[:skills_evolved]} skills based on execution data. " \
                 "Analyzed: #{results[:skills_analyzed]}",
        salience: 0.6
      )
    end

    { action: :evolve_skill, success: true, bounties_created: 0, points_allocated: 0,
      skills_evolved: results[:skills_evolved] }
  end

  def think_and_investigate(focus)
    # Check if there's an existing thought about this topic
    existing = AmosWorkingMemory.active.where(entity: entity)
                                 .where("topic LIKE ?", "%#{focus[:signals].first[:type]}%")
                                 .first

    if existing
      # Revisit existing thought with new evidence
      existing.revisit!(
        new_evidence: focus[:signals].map { |s| { type: s[:type], label: s[:label], strength: s[:strength], observed_at: Time.current.iso8601 } },
        salience_delta: 0.1
      )

      { action: :investigate, success: true, bounties_created: 0, points_allocated: 0,
        thought_updated: existing.id }
    else
      # Create a new thought
      thought = create_thought!(
        type: focus[:signals].first[:type] == :critical_issues ? 'concern' : 'observation',
        topic: focus[:signals].first[:type].to_s,
        content: "Detected: #{focus[:label]}. Signals: #{focus[:signals].map { |s| s[:label] }.join('; ')}",
        salience: focus[:strength]
      )

      { action: :investigate, success: true, bounties_created: 0, points_allocated: 0,
        thought_created: thought.id }
    end
  end

  def think_and_connect(focus)
    # Find the working memory thought referenced
    thought_signal = focus[:signals].find { |s| s[:type] == :working_memory }
    return defer_thought(focus) unless thought_signal

    thought = AmosWorkingMemory.find_by(id: thought_signal[:data][:thought_id])
    return defer_thought(focus) unless thought

    # Look for related thoughts
    related = AmosWorkingMemory.active.where(entity: entity)
                                .where.not(id: thought.id)
                                .where("topic LIKE ? OR thought_type = ?", "%#{thought.topic.split('_').first}%", thought.thought_type)
                                .limit(5)

    connected = 0
    related.each do |other|
      thought.connect_to!(other)
      connected += 1
    end

    # Revisit the thought
    thought.revisit!(salience_delta: 0.05)

    { action: :connect_dots, success: true, bounties_created: 0, points_allocated: 0,
      connections_made: connected }
  end

  def flag_for_attention(focus)
    create_thought!(
      type: 'concern',
      topic: focus[:signals].first[:type].to_s,
      content: "Flagged for human attention: #{focus[:label]}",
      salience: 0.8
    )

    { action: :flag_for_humans, success: true, bounties_created: 0, points_allocated: 0 }
  end

  def defer_thought(focus)
    create_thought!(
      type: 'observation',
      topic: focus[:signals].first[:type].to_s,
      content: "Deferred: #{focus[:label]} (will revisit in future session)",
      salience: [focus[:strength] - 0.1, 0.2].max
    )

    { action: :defer, success: true, bounties_created: 0, points_allocated: 0 }
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PHASE 4: META-COGNITION
  # Think about the thinking
  # ═══════════════════════════════════════════════════════════════════════════

  def reflect_on_session(focus_areas, results)
    active_thoughts = AmosWorkingMemory.active.where(entity: entity).count
    resolved_today = AmosWorkingMemory.where(entity: entity, status: 'resolved')
                                       .where('resolved_at > ?', 24.hours.ago).count

    session_summary = "Autonomous session: focused on #{focus_areas.count} areas " \
                      "(#{focus_areas.map { |f| f[:label] }.join(', ')}). " \
                      "#{results.count(&:present?)} actions completed. " \
                      "Working memory: #{active_thoughts} active thoughts, #{resolved_today} resolved today. " \
                      "Token cost: ~#{@tokens_used} tokens."

    # Check for blind spots — things we consistently defer
    deferred_topics = AmosAttentionLog.where(entity: entity, outcome: 'deferred')
                                       .where('created_at > ?', 7.days.ago)
                                       .group(:focus_area)
                                       .count
                                       .sort_by { |_, count| -count }
                                       .first(3)

    if deferred_topics.any? { |_, count| count >= 3 }
      blind_spots = deferred_topics.select { |_, count| count >= 3 }.map(&:first)
      session_summary += " BLIND SPOT WARNING: Consistently deferring: #{blind_spots.join(', ')}."

      create_thought!(
        type: 'concern',
        topic: 'meta_blind_spots',
        content: "I keep deferring these topics: #{blind_spots.join(', ')}. " \
                 "Either they're truly low priority or I'm avoiding them. Should investigate.",
        salience: 0.7
      )
    end

    {
      session_summary: session_summary,
      active_thoughts: active_thoughts,
      resolved_today: resolved_today,
      blind_spots: deferred_topics.first(3).to_h,
      tokens_used: @tokens_used
    }
  rescue => e
    log "⚠️ Meta-cognition failed: #{e.message}"
    { session_summary: "Session completed with #{results&.count || 0} actions", tokens_used: @tokens_used }
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PHASE 5: MEMORY MAINTENANCE
  # Decay old thoughts, archive stale ones
  # ═══════════════════════════════════════════════════════════════════════════

  def maintain_memory!
    AmosWorkingMemory.apply_salience_decay!(entity)

    # Count what changed
    archived = AmosWorkingMemory.where(entity: entity, status: 'archived')
                                 .where('updated_at > ?', 1.minute.ago).count
    log "🧹 Memory maintenance: #{archived} thoughts archived due to salience decay"
  rescue => e
    log "⚠️ Memory maintenance failed: #{e.message}"
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # HELPERS
  # ═══════════════════════════════════════════════════════════════════════════

  # ═══════════════════════════════════════════════════════════════════════════
  # PHASE 3.5: TICKET → BOUNTY SYNC
  # Ensure qualified tickets are always converted to bounties
  # ═══════════════════════════════════════════════════════════════════════════

  def sync_tickets_to_bounties!
    integration = BountyIntegrationService.new(entity)
    results = integration.sync_all!

    total = results.values.flatten.compact.count
    {
      total_created: total,
      from_tickets: results[:from_tickets]&.count || 0,
      from_goals: results[:from_goals]&.count || 0,
      from_anomalies: results[:from_anomalies]&.count || 0,
      from_features: results[:from_features]&.count || 0
    }
  rescue => e
    log "⚠️ Ticket-to-bounty sync failed: #{e.message}"
    { total_created: 0 }
  end

  def create_thought!(type:, topic:, content:, salience: 0.5)
    thought = AmosWorkingMemory.create!(
      entity: entity,
      thought_type: type,
      topic: topic,
      content: content,
      salience: salience,
      confidence: 0.5
    )

    @session_thoughts << thought
    thought
  end

  def record_attention_decision!(focus_area:, reasoning:, alternatives:, outcome:)
    AmosAttentionLog.create!(
      entity: entity,
      amos_thinking_session: @session,
      focus_area: focus_area,
      reasoning: reasoning,
      alternatives_considered: alternatives,
      outcome: outcome,
      token_cost: 0 # Updated after cognition phase
    )
  rescue => e
    log "⚠️ Failed to log attention decision: #{e.message}"
  end

  def build_session_log(focus_areas, results, meta)
    parts = []
    parts << "=== AMOS Autonomous Session ==="
    parts << "Time: #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}"
    parts << ""
    parts << "--- FOCUS AREAS ---"
    focus_areas.each_with_index do |area, i|
      parts << "#{i + 1}. #{area[:label]} (priority: #{area[:priority]}, strength: #{area[:strength]})"
    end
    parts << ""
    parts << "--- RESULTS ---"
    results.compact.each do |result|
      parts << "  #{result[:action]}: #{result[:success] ? '✅' : '❌'}" \
               "#{result[:error] ? " (#{result[:error]})" : ''}"
    end
    parts << ""
    parts << "--- META ---"
    parts << meta[:session_summary]
    parts << ""
    parts << "--- ATTENTION LOG ---"
    @attention_log.each { |entry| parts << entry }

    parts.join("\n")
  end

  def log(message)
    entry = "[#{Time.current.strftime('%H:%M:%S')}] #{message}"
    @attention_log << entry
    Rails.logger.info "[AMOS_AUTONOMOUS] #{entry}"
  end
end
