# frozen_string_literal: true

# ExternalAgentMatchingService - Intelligent matching of bounties to external agents
#
# AMOS uses this service to:
# 1. Discover available external agents and their capabilities
# 2. Match bounties to the best-suited agents
# 3. Consider trust levels, reputation, and past performance
# 4. Recommend or auto-assign agents to bounties
#
# Matching criteria:
# - Capability match (agent's declared skills vs bounty type)
# - Trust level (higher trust = more complex work)
# - Reputation score (past performance)
# - Availability (not overloaded with active bounties)
# - Success rate (completions vs rejections)
#
class ExternalAgentMatchingService
  attr_reader :entity

  def initialize(entity)
    @entity = entity
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # DISCOVERY
  # ═══════════════════════════════════════════════════════════════════════════

  # Get all available external agents for this entity
  def available_agents(include_capabilities: false)
    agents = ExternalAgentRegistration.where(entity: entity)
                                      .where(status: 'active')
                                      .where('daily_bounty_limit > 0')
    
    agents.map { |a| agent_profile(a, include_capabilities: include_capabilities) }
  end

  # Get agent capabilities summary for AMOS context
  def agent_capabilities_summary
    agents = ExternalAgentRegistration.where(entity: entity).where(status: 'active')
    
    {
      total_agents: agents.count,
      by_platform: agents.group(:agent_platform).count,
      by_trust_level: agents.group(:trust_level).count,
      capabilities: aggregate_capabilities(agents),
      top_performers: top_performers(limit: 5)
    }
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # MATCHING
  # ═══════════════════════════════════════════════════════════════════════════

  # Find best agents for a specific bounty
  def find_agents_for_bounty(bounty, limit: 5)
    candidates = ExternalAgentRegistration.where(entity: entity)
                                          .where(status: 'active')
    
    scored_agents = candidates.map do |agent|
      score = calculate_match_score(agent, bounty)
      { agent: agent, score: score, reasons: score[:reasons] }
    end

    # Filter out ineligible agents (score < 0)
    eligible = scored_agents.select { |s| s[:score][:total] >= 0 }
    
    # Sort by score descending
    eligible.sort_by { |s| -s[:score][:total] }
            .first(limit)
            .map { |s| agent_match_result(s) }
  end

  # Find best bounties for a specific agent
  def find_bounties_for_agent(agent, limit: 10)
    bounties = Bounty.where(entity: entity)
                     .available
                     .where(bounty_type: agent.allowed_bounty_types)
                     .where('points <= ?', max_points_for_trust_level(agent.trust_level))
    
    scored_bounties = bounties.map do |bounty|
      score = calculate_match_score(agent, bounty)
      { bounty: bounty, score: score }
    end

    scored_bounties.sort_by { |s| -s[:score][:total] }
                   .first(limit)
                   .map { |s| bounty_match_result(s) }
  end

  # Recommend agent for bounty (single best match)
  def recommend_agent(bounty)
    matches = find_agents_for_bounty(bounty, limit: 1)
    return nil if matches.empty?
    
    matches.first
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # SCORING
  # ═══════════════════════════════════════════════════════════════════════════

  def calculate_match_score(agent, bounty)
    reasons = []
    
    # Base eligibility checks
    if !agent.active?
      return { total: -1000, reasons: ['Agent is not active'] }
    end
    
    if agent_at_daily_limit?(agent)
      return { total: -100, reasons: ['Agent at daily bounty limit'] }
    end
    
    if agent_at_concurrent_limit?(agent)
      return { total: -100, reasons: ['Agent at concurrent bounty limit'] }
    end

    # Capability match (0-40 points)
    capability_score = score_capability_match(agent, bounty)
    reasons << capability_score[:reason]
    
    # Trust level vs bounty complexity (0-25 points)
    trust_score = score_trust_match(agent, bounty)
    reasons << trust_score[:reason]
    
    # Reputation (0-20 points)
    reputation_score = score_reputation(agent)
    reasons << reputation_score[:reason]
    
    # Past performance with similar bounties (0-15 points)
    history_score = score_past_performance(agent, bounty)
    reasons << history_score[:reason] if history_score[:score] > 0

    total = capability_score[:score] + trust_score[:score] + 
            reputation_score[:score] + history_score[:score]

    {
      total: total,
      capability: capability_score[:score],
      trust: trust_score[:score],
      reputation: reputation_score[:score],
      history: history_score[:score],
      reasons: reasons.compact
    }
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # AMOS INTEGRATION
  # ═══════════════════════════════════════════════════════════════════════════

  # Context for AMOS thinking sessions
  def context_for_amos
    agents = ExternalAgentRegistration.where(entity: entity).where(status: 'active')
    
    {
      external_agent_count: agents.count,
      external_agents_available: agents.any?,
      agent_summary: agent_capabilities_summary,
      recent_completions: recent_agent_completions(7.days),
      pending_assignments: bounties_awaiting_agents.count,
      
      # Detailed agent list for matching
      agents: agents.map { |a| 
        {
          id: a.id,
          name: a.agent_name,
          platform: a.agent_platform,
          capabilities: a.capabilities.keys,
          trust_level: a.trust_level,
          reputation: a.reputation_score.to_f,
          success_rate: a.success_rate,
          available_slots: a.available_bounty_slots
        }
      }
    }
  end

  # Suggest assignments for open bounties
  def suggest_assignments(limit: 10)
    assignments = []
    
    bounties_awaiting_agents.limit(limit).each do |bounty|
      match = recommend_agent(bounty)
      next unless match
      
      assignments << {
        bounty: {
          id: bounty.id,
          title: bounty.title,
          type: bounty.bounty_type,
          points: bounty.points
        },
        recommended_agent: {
          id: match[:agent].id,
          name: match[:agent].agent_name,
          score: match[:score],
          reasons: match[:reasons]
        },
        confidence: match[:score] >= 70 ? 'high' : (match[:score] >= 40 ? 'medium' : 'low')
      }
    end

    assignments
  end

  # Auto-assign bounties to agents (used by AMOS)
  def auto_assign_bounties!(dry_run: false)
    assignments = suggest_assignments(limit: 20)
    results = []

    assignments.each do |assignment|
      next unless assignment[:confidence].in?(%w[high medium])
      
      if dry_run
        results << { status: 'would_assign', **assignment }
      else
        result = notify_agent_of_bounty(
          agent_id: assignment[:recommended_agent][:id],
          bounty_id: assignment[:bounty][:id],
          match_score: assignment[:recommended_agent][:score]
        )
        results << { status: result ? 'notified' : 'failed', **assignment }
      end
    end

    results
  end

  private

  # ═══════════════════════════════════════════════════════════════════════════
  # SCORING HELPERS
  # ═══════════════════════════════════════════════════════════════════════════

  def score_capability_match(agent, bounty)
    bounty_type = bounty.bounty_type
    
    # Check if agent has declared capability for this type
    if agent.allowed_bounty_types.include?(bounty_type)
      cap = agent.capabilities[bounty_type] || {}
      confidence = cap['confidence'] || 0.5
      
      score = (confidence * 40).round
      { score: score, reason: "Capability match: #{bounty_type} (confidence: #{(confidence * 100).round}%)" }
    elsif agent.capabilities.keys.any? { |k| related_capability?(k, bounty_type) }
      { score: 15, reason: "Related capability match for #{bounty_type}" }
    else
      { score: 0, reason: "No capability declared for #{bounty_type}" }
    end
  end

  def score_trust_match(agent, bounty)
    required_trust = trust_level_for_bounty(bounty)
    
    if agent.trust_level >= required_trust
      gap = agent.trust_level - required_trust
      score = 25 - (gap * 5)  # Slight penalty for overqualified
      score = [score, 15].max  # But still good
      { score: score, reason: "Trust level #{agent.trust_level} meets requirement (#{required_trust})" }
    else
      { score: 0, reason: "Trust level #{agent.trust_level} below required (#{required_trust})" }
    end
  end

  def score_reputation(agent)
    rep = agent.reputation_score.to_f
    
    if rep >= 90
      { score: 20, reason: "Excellent reputation (#{rep.round})" }
    elsif rep >= 75
      { score: 15, reason: "Good reputation (#{rep.round})" }
    elsif rep >= 50
      { score: 10, reason: "Average reputation (#{rep.round})" }
    else
      { score: 5, reason: "Building reputation (#{rep.round})" }
    end
  end

  def score_past_performance(agent, bounty)
    # Check past completions for similar bounty types
    past_completions = ExternalAgentExecution.where(external_agent_registration: agent)
                                             .where(status: 'approved')
                                             .joins(:bounty)
                                             .where(bounties: { bounty_type: bounty.bounty_type })
                                             .count

    if past_completions >= 5
      { score: 15, reason: "#{past_completions} successful similar bounties" }
    elsif past_completions >= 2
      { score: 10, reason: "#{past_completions} successful similar bounties" }
    elsif past_completions >= 1
      { score: 5, reason: "1 successful similar bounty" }
    else
      { score: 0, reason: nil }
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # HELPERS
  # ═══════════════════════════════════════════════════════════════════════════

  def agent_profile(agent, include_capabilities: false)
    profile = {
      id: agent.id,
      name: agent.agent_name,
      platform: agent.agent_platform,
      trust_level: agent.trust_level,
      reputation: agent.reputation_score.to_f,
      success_rate: agent.success_rate,
      bounties_completed: agent.total_bounties_completed,
      tokens_earned: agent.total_tokens_earned.to_f,
      available_slots: agent.available_bounty_slots
    }
    
    if include_capabilities
      profile[:capabilities] = agent.capabilities
      profile[:allowed_types] = agent.allowed_bounty_types
    end
    
    profile
  end

  def agent_match_result(scored)
    {
      agent: agent_profile(scored[:agent]),
      score: scored[:score][:total],
      breakdown: scored[:score].except(:total, :reasons),
      reasons: scored[:reasons]
    }
  end

  def bounty_match_result(scored)
    {
      bounty_id: scored[:bounty].id,
      title: scored[:bounty].title,
      type: scored[:bounty].bounty_type,
      points: scored[:bounty].points,
      score: scored[:score][:total]
    }
  end

  def agent_at_daily_limit?(agent)
    today_count = ExternalAgentExecution.where(external_agent_registration: agent)
                                        .where('created_at > ?', Time.current.beginning_of_day)
                                        .count
    today_count >= agent.daily_bounty_limit
  end

  def agent_at_concurrent_limit?(agent)
    active_count = ExternalAgentExecution.where(external_agent_registration: agent)
                                         .where(status: 'in_progress')
                                         .count
    active_count >= agent.max_concurrent_bounties
  end

  def trust_level_for_bounty(bounty)
    case bounty.points
    when 0..50 then 1
    when 51..150 then 2
    when 151..300 then 3
    when 301..500 then 4
    else 5
    end
  end

  def max_points_for_trust_level(level)
    case level
    when 1 then 50
    when 2 then 150
    when 3 then 300
    when 4 then 500
    else 1000
    end
  end

  def related_capability?(capability, bounty_type)
    related_map = {
      'documentation' => %w[content writing],
      'content' => %w[documentation writing marketing],
      'marketing' => %w[content writing],
      'bug' => %w[testing infrastructure],
      'feature' => %w[bug infrastructure],
      'design' => %w[feature content]
    }
    
    (related_map[bounty_type] || []).include?(capability)
  end

  def aggregate_capabilities(agents)
    caps = Hash.new(0)
    agents.each do |agent|
      agent.capabilities.keys.each { |c| caps[c] += 1 }
    end
    caps.sort_by { |_, v| -v }.to_h
  end

  def top_performers(limit: 5)
    ExternalAgentRegistration.where(entity: entity)
                             .where(status: 'active')
                             .where('total_bounties_completed > 0')
                             .order(reputation_score: :desc)
                             .limit(limit)
                             .map { |a| agent_profile(a) }
  end

  def recent_agent_completions(period)
    ExternalAgentExecution.joins(:external_agent_registration)
                          .where(external_agent_registrations: { entity: entity })
                          .where(status: 'approved')
                          .where('external_agent_executions.created_at > ?', period.ago)
                          .count
  end

  def bounties_awaiting_agents
    Bounty.where(entity: entity)
          .available
          .where.not(id: ExternalAgentExecution.select(:bounty_id))
  end

  def notify_agent_of_bounty(agent_id:, bounty_id:, match_score:)
    agent = ExternalAgentRegistration.find(agent_id)
    bounty = Bounty.find(bounty_id)
    
    # Create a notification/recommendation record
    # The external agent can poll for these or we can webhook
    ExternalAgentNotification.create!(
      external_agent_registration: agent,
      notification_type: 'bounty_recommendation',
      title: "Recommended Bounty: #{bounty.title}",
      message: "AMOS recommends this bounty based on your capabilities (match score: #{match_score})",
      metadata: {
        bounty_id: bounty.id,
        bounty_title: bounty.title,
        bounty_type: bounty.bounty_type,
        points: bounty.points,
        match_score: match_score
      }
    )
    
    true
  rescue => e
    Rails.logger.warn "[ExternalAgentMatching] Failed to notify agent: #{e.message}"
    false
  end
end
