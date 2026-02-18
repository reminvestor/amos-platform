# frozen_string_literal: true

# BountyGroomingService - Sprint-style bounty prioritization and demand adjustment
#
# Performs periodic "sprint grooming" of the bounty backlog:
#
# 1. PRIORITIZE: Rank all open bounties based on urgency, impact, strategic value, and age
# 2. DEMAND ADJUST: Increase points on bounties that aren't getting claimed (supply/demand)
# 3. STALE DETECT: Flag or close bounties that have been open too long
# 4. GROUP: Assign sprint labels and identify related bounties
# 5. REBALANCE: Ensure point distribution is healthy (not all huge, not all tiny)
#
# This runs as part of AMOS's thinking time, but can also be triggered manually.
#
class BountyGroomingService
  # Demand adjustment thresholds
  DEMAND_BOOST_AFTER_DAYS = 7      # Start boosting unclaimed bounties after 7 days
  DEMAND_BOOST_INCREMENT = 0.15    # 15% boost per grooming cycle
  DEMAND_BOOST_MAX = 2.5           # Max 2.5x multiplier (150% boost)
  STALE_THRESHOLD_DAYS = 45        # Consider closing after 45 days unclaimed
  MIN_BOUNTIES_FOR_LLM = 5        # Don't call LLM if fewer than this many open bounties

  attr_reader :entity, :grooming_log

  def initialize(entity)
    @entity = entity
    @grooming_log = []
  end

  # Run a full grooming cycle
  def groom!
    log "Starting bounty grooming for #{entity.name}"

    open_bounties = Bounty.where(entity: entity).open_bounties.order(created_at: :asc)
    log "Found #{open_bounties.count} open bounties"

    return { groomed: 0, message: "No open bounties to groom" } if open_bounties.empty?

    results = {
      total_open: open_bounties.count,
      demand_boosted: 0,
      stale_flagged: 0,
      stale_closed: 0,
      reprioritized: 0,
      sprint_labeled: 0,
      points_adjusted: 0
    }

    # Phase 1: Demand-based point adjustment (no LLM needed)
    open_bounties.each do |bounty|
      adjusted = apply_demand_adjustment!(bounty)
      results[:demand_boosted] += 1 if adjusted
    end

    # Phase 2: Handle stale bounties
    stale_bounties = open_bounties.where('created_at < ?', STALE_THRESHOLD_DAYS.days.ago)
    stale_bounties.each do |bounty|
      handle_stale_bounty!(bounty, results)
    end

    # Phase 3: AI-powered strategic reprioritization (uses LLM)
    if open_bounties.count >= MIN_BOUNTIES_FOR_LLM
      ai_results = ai_reprioritize!(open_bounties.reload)
      results.merge!(ai_results)
    else
      # Simple priority assignment without LLM
      assign_simple_priority!(open_bounties.reload)
      results[:reprioritized] = open_bounties.count
    end

    # Phase 4: Tag grooming timestamp
    Bounty.where(entity: entity).open_bounties.update_all(last_groomed_at: Time.current)

    log "Grooming complete: #{results.inspect}"

    results.merge(grooming_log: @grooming_log)
  end

  private

  # ═══════════════════════════════════════════════════════════════════════════
  # PHASE 1: DEMAND-BASED ADJUSTMENT
  # If nobody is claiming a bounty, it's either:
  #   a) Not valuable enough (raise points)
  #   b) Too vague (AMOS should improve description in next thinking session)
  #   c) Blocked by something (tag as blocked)
  # ═══════════════════════════════════════════════════════════════════════════

  def apply_demand_adjustment!(bounty)
    days_open = ((Time.current - bounty.created_at) / 1.day).round

    return false if days_open < DEMAND_BOOST_AFTER_DAYS
    return false if bounty.claimed_by.present?

    current_multiplier = bounty.demand_multiplier || 1.0
    return false if current_multiplier >= DEMAND_BOOST_MAX

    # Calculate new multiplier based on how long it's been open
    # Faster boost for high-urgency bounties, slower for nice-to-haves
    urgency_factor = (bounty.urgency_score || 5) / 10.0
    boost = DEMAND_BOOST_INCREMENT * (0.5 + urgency_factor)
    new_multiplier = [current_multiplier + boost, DEMAND_BOOST_MAX].min

    # Also factor in community signal
    vote_boost = bounty.vote_score > 3 ? 0.1 : 0
    new_multiplier = [new_multiplier + vote_boost, DEMAND_BOOST_MAX].min

    # Save original points if not already saved
    original = bounty.original_points || bounty.points

    new_points = (original * new_multiplier).round

    bounty.update!(
      demand_multiplier: new_multiplier.round(2),
      original_points: original,
      points: new_points,
      grooming_notes: "Demand boost: #{current_multiplier}x → #{new_multiplier.round(2)}x " \
                      "(#{days_open} days unclaimed, urgency: #{bounty.urgency_score || 'unrated'})"
    )

    log "  💰 Boosted '#{bounty.title}': #{original} → #{new_points} points (#{new_multiplier.round(2)}x)"
    true
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PHASE 2: STALE BOUNTY HANDLING
  # ═══════════════════════════════════════════════════════════════════════════

  def handle_stale_bounty!(bounty, results)
    days_open = ((Time.current - bounty.created_at) / 1.day).round

    # High-urgency stale bounties get flagged, low-urgency get closed
    if (bounty.urgency_score || 5) >= 7
      # Important but unclaimed — flag for human attention
      bounty.update!(
        tags: (bounty.tags || []) | ['stale-needs-attention'],
        grooming_notes: "STALE: #{days_open} days open, high urgency — needs human attention"
      )
      results[:stale_flagged] += 1
      log "  ⚠️ Stale high-priority: '#{bounty.title}' (#{days_open} days)"
    elsif days_open > STALE_THRESHOLD_DAYS * 2 && bounty.vote_score <= 0
      # Very old, low urgency, no community interest — cancel
      bounty.cancel!(reason: "Auto-closed: #{days_open} days unclaimed with no community interest")
      results[:stale_closed] += 1
      log "  🗑️ Auto-closed stale: '#{bounty.title}' (#{days_open} days, #{bounty.vote_score} votes)"
    else
      bounty.update!(
        tags: (bounty.tags || []) | ['stale'],
        grooming_notes: "Aging: #{days_open} days open"
      )
      results[:stale_flagged] += 1
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PHASE 3: AI-POWERED REPRIORITIZATION
  # AMOS looks at all open bounties holistically and decides priority order
  # ═══════════════════════════════════════════════════════════════════════════

  def ai_reprioritize!(bounties)
    results = { reprioritized: 0, sprint_labeled: 0, points_adjusted: 0 }

    # Build context for the LLM
    bounty_summaries = bounties.map do |b|
      {
        id: b.id,
        title: b.title,
        type: b.bounty_type,
        points: b.points,
        urgency: b.urgency_score,
        impact: b.impact_score,
        complexity: b.complexity_score,
        age_days: ((Time.current - b.created_at) / 1.day).round,
        votes: b.vote_score,
        demand_multiplier: b.demand_multiplier || 1.0,
        tags: b.tags || [],
        description_preview: b.description&.truncate(150)
      }
    end

    # Get platform context for strategic prioritization
    platform_context = gather_platform_context

    prompt = build_reprioritization_prompt(bounty_summaries, platform_context)

    begin
      response = call_llm(prompt)
      priorities = parse_priorities(response)

      if priorities.present?
        apply_priorities!(bounties, priorities, results)
      end
    rescue => e
      log "  ❌ AI reprioritization failed: #{e.message}"
      assign_simple_priority!(bounties)
      results[:reprioritized] = bounties.count
    end

    results
  end

  def build_reprioritization_prompt(bounty_summaries, platform_context)
    <<~PROMPT
      You are AMOS performing sprint grooming on the bounty backlog.

      PLATFORM CONTEXT:
      #{platform_context}

      OPEN BOUNTIES (#{bounty_summaries.count} total):
      #{bounty_summaries.map { |b| "  ##{b[:id]}: [#{b[:type]}] #{b[:title]} (#{b[:points]}pts, urgency:#{b[:urgency] || '?'}, age:#{b[:age_days]}d, votes:#{b[:votes]})" }.join("\n")}

      YOUR TASK:
      1. Assign a priority_rank (1 = do first) based on strategic value, urgency, and dependencies
      2. Group related bounties into sprint labels (thematic sprints, e.g. "Sprint: Infrastructure Hardening")
      3. Identify any bounties that should have their points adjusted (too high or too low for the work involved)
      4. Identify any dependency chains (bounty X should be done before bounty Y)

      Consider:
      - What creates the most user value right now?
      - What unblocks other work?
      - What's been waiting too long?
      - What aligns with current platform priorities?
      - Are there natural groupings that would make a good sprint theme?

      RESPONSE FORMAT (JSON only, no markdown):
      {
        "sprint_theme": "A name for the current sprint focus",
        "priorities": [
          {
            "bounty_id": <id>,
            "rank": <1-N>,
            "sprint_label": "<thematic group>",
            "points_adjustment": <null or new points value>,
            "adjustment_reason": "<why points changed, if changed>",
            "blocked_by": [<bounty_ids>],
            "rationale": "<brief why this rank>"
          }
        ],
        "grooming_summary": "<2-3 sentences about the overall backlog health and priorities>"
      }
    PROMPT
  end

  def gather_platform_context
    recent_completions = Bounty.where(entity: entity).completed.where('approved_at > ?', 30.days.ago).count
    recent_tickets = entity.respond_to?(:support_tickets) ? entity.support_tickets.where('created_at > ?', 7.days.ago).count : 0
    active_contributors = Bounty.where(entity: entity).claimed.select(:claimed_by_id).distinct.count

    "Recent completions (30d): #{recent_completions}, " \
      "New support tickets (7d): #{recent_tickets}, " \
      "Active contributors: #{active_contributors}, " \
      "Total open bounties: #{Bounty.where(entity: entity).open_bounties.count}"
  rescue => e
    "Platform context unavailable: #{e.message}"
  end

  def parse_priorities(response)
    return nil if response.blank?

    # Extract JSON from response
    json_str = response.strip
    json_str = json_str[/\{.*\}/m] if json_str.include?('{')
    return nil unless json_str

    data = JSON.parse(json_str)
    data['priorities']
  rescue JSON::ParserError => e
    log "  ⚠️ Failed to parse AI priorities: #{e.message}"
    nil
  end

  def apply_priorities!(bounties, priorities, results)
    bounties_by_id = bounties.index_by(&:id)

    priorities.each do |priority|
      bounty = bounties_by_id[priority['bounty_id']]
      next unless bounty

      attrs = {
        priority_rank: priority['rank'],
        sprint_label: priority['sprint_label'],
        grooming_notes: priority['rationale']
      }

      # Points adjustment
      if priority['points_adjustment'].present? && priority['points_adjustment'] != bounty.points
        attrs[:original_points] = bounty.original_points || bounty.points
        attrs[:points] = priority['points_adjustment']
        results[:points_adjusted] += 1
        log "  📊 Adjusted '#{bounty.title}': #{bounty.points} → #{priority['points_adjustment']} pts (#{priority['adjustment_reason']})"
      end

      # Dependencies
      if priority['blocked_by'].present?
        attrs[:blocked_by_ids] = priority['blocked_by']
      end

      if priority['sprint_label'].present?
        results[:sprint_labeled] += 1
      end

      bounty.update!(attrs)
      results[:reprioritized] += 1
    end
  end

  # Simple priority without LLM — for small backlogs
  def assign_simple_priority!(bounties)
    # Score: urgency * 2 + impact + vote_score + age_bonus
    scored = bounties.map do |b|
      age_days = ((Time.current - b.created_at) / 1.day).round
      age_bonus = [age_days / 7.0, 5].min  # Up to 5 points for age
      score = ((b.urgency_score || 5) * 2) + (b.impact_score || 5) + b.vote_score + age_bonus
      [b, score]
    end

    scored.sort_by { |_, score| -score }.each_with_index do |(bounty, _), idx|
      bounty.update!(priority_rank: idx + 1)
    end
  end

  def call_llm(prompt)
    if defined?(BedrockService)
      # Use Haiku for grooming — it's cheaper and this is a background task
      service = BedrockService.new(entity: entity)
      service.converse(
        messages: [{ role: 'user', content: [{ text: prompt }] }],
        system_prompt: "You are AMOS, an autonomous AI performing sprint grooming. Respond only with valid JSON.",
        model: 'claude-haiku-4-5'  # Cost optimization: use cheaper model for batch work
      )
    elsif defined?(LlmService)
      LlmService.chat(system: "You are AMOS performing sprint grooming. Respond with JSON.", user: prompt, temperature: 0.3)
    else
      raise "No LLM service available"
    end
  end

  def log(message)
    @grooming_log << "[#{Time.current.strftime('%H:%M:%S')}] #{message}"
    Rails.logger.info "[BountyGrooming] #{message}"
  end
end
