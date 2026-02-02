# frozen_string_literal: true

# BountyIntegrationService - Connects bounties to existing platform systems
#
# Integrations:
# 1. Support Tickets → Bounties (high-priority bugs become bounties)
# 2. Living Platform Goals → Bounties (goals needing human work become bounties)
# 3. Platform Anomalies → Bounties (critical anomalies become bounties)
# 4. Feature Requests → Bounties (voted features become bounties)
#
class BountyIntegrationService
  attr_reader :entity

  # Minimum votes for a feature request to become a bounty
  MIN_VOTES_FOR_BOUNTY = 3

  def initialize(entity)
    @entity = entity
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # SUPPORT TICKETS → BOUNTIES
  # ═══════════════════════════════════════════════════════════════════════════

  # Convert high-priority tickets to bounties
  def create_bounties_from_tickets!
    bounties = []

    # Get high-priority tickets without bounties
    # Note: Must filter out NULL support_ticket_ids to avoid SQL NOT IN with NULL issue
    existing_bounty_ticket_ids = Bounty.where(entity: entity)
                                       .where.not(support_ticket_id: nil)
                                       .select(:support_ticket_id)
    
    eligible_tickets = SupportTicket.where(entity: entity)
                                    .where(status: %w[open investigating])
                                    .where(priority: %w[high critical])
                                    .where.not(id: existing_bounty_ticket_ids)
                                    .limit(10)

    Rails.logger.info "[BOUNTY_INTEGRATION] Found #{eligible_tickets.count} eligible tickets"

    eligible_tickets.each do |ticket|
      Rails.logger.info "[BOUNTY_INTEGRATION] Processing ticket #{ticket.id}: #{ticket.title}"
      bounty = create_bounty_from_ticket(ticket)
      Rails.logger.info "[BOUNTY_INTEGRATION] Bounty result: #{bounty.inspect}"
      bounties << bounty if bounty
    end

    Rails.logger.info "[BOUNTY_INTEGRATION] Created #{bounties.count} bounties from tickets"
    bounties
  end

  def create_bounty_from_ticket(ticket)
    Rails.logger.info "[BOUNTY_INTEGRATION] Checking if ticket #{ticket.id} already has a bounty..."
    if ticket.bounty.present?
      Rails.logger.info "[BOUNTY_INTEGRATION] Ticket #{ticket.id} already has bounty"
      return nil
    end

    # Score the ticket
    Rails.logger.info "[BOUNTY_INTEGRATION] Scoring ticket #{ticket.id}..."
    scoring = AmosBountyScorer.score_ticket(ticket)
    Rails.logger.info "[BOUNTY_INTEGRATION] Score result: #{scoring.inspect}"

    # Create the bounty
    Rails.logger.info "[BOUNTY_INTEGRATION] Creating bounty..."
    bounty = Bounty.create_from_ticket!(
      ticket,
      points: scoring[:points],
      scoring_rationale: scoring[:rationale]
    )
    Rails.logger.info "[BOUNTY_INTEGRATION] Bounty created: #{bounty.id}"

    # Update bounty with AI scores
    bounty.update!(
      estimated_hours: scoring[:estimated_hours],
      impact_score: scoring[:impact_score],
      urgency_score: scoring[:urgency_score],
      complexity_score: scoring[:complexity_score]
    )

    # Link ticket to bounty
    ticket.update!(metadata: ticket.metadata.merge(bounty_id: bounty.id))

    Rails.logger.info "[BOUNTY_INTEGRATION] Created bounty ##{bounty.id} from ticket #{ticket.ticket_number}"
    bounty

  rescue => e
    Rails.logger.error "[BOUNTY_INTEGRATION] Failed to create bounty from ticket #{ticket.id}: #{e.message}"
    Rails.logger.error "[BOUNTY_INTEGRATION] #{e.backtrace.first(3).join("\n")}"
    nil
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # LIVING PLATFORM GOALS → BOUNTIES
  # ═══════════════════════════════════════════════════════════════════════════

  # Convert goals that need human work to bounties
  def create_bounties_from_goals!
    return [] unless defined?(AgentGoal)

    bounties = []

    # Goals that agents can't handle → need human contributors
    unhandled_goals = AgentGoal.where(entity: entity)
                               .where(status: 'blocked')  # Blocked means agents couldn't do it
                               .where(human_bounty_id: nil)
                               .limit(10)

    unhandled_goals.each do |goal|
      bounty = create_bounty_from_goal(goal)
      bounties << bounty if bounty
    end

    Rails.logger.info "[BOUNTY_INTEGRATION] Created #{bounties.count} bounties from goals"
    bounties
  end

  def create_bounty_from_goal(goal)
    # Map goal type to bounty type
    bounty_type = case goal.goal_type
    when 'improvement', 'maintenance' then 'bug'
    when 'expansion' then 'feature'
    when 'learning' then 'documentation'
    when 'social' then 'support'
    else 'feature'
    end

    # Score based on goal priority
    scoring = AmosBountyScorer.score(
      title: goal.title,
      description: goal.description,
      bounty_type: bounty_type,
      context: {
        goal_type: goal.goal_type,
        priority: goal.priority,
        suggested_actions: goal.suggested_actions
      }
    )

    bounty = Bounty.create!(
      entity: entity,
      title: goal.title,
      description: "#{goal.description}\n\n**Suggested Actions:**\n#{goal.suggested_actions&.map { |a| "- #{a}" }&.join("\n")}",
      bounty_type: bounty_type,
      points: scoring[:points],
      ai_scoring_rationale: scoring[:rationale],
      source: 'living_platform',
      urgency_score: (goal.priority / 10.0).round,
      metadata: {
        goal_id: goal.id,
        goal_type: goal.goal_type,
        success_criteria: goal.success_criteria
      }
    )

    # Link goal to bounty
    goal.update!(human_bounty_id: bounty.id) if goal.respond_to?(:human_bounty_id)

    bounty

  rescue => e
    Rails.logger.error "[BOUNTY_INTEGRATION] Failed to create bounty from goal #{goal.id}: #{e.message}"
    nil
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PLATFORM ANOMALIES → BOUNTIES
  # ═══════════════════════════════════════════════════════════════════════════

  # Convert critical anomalies to bounties
  def create_bounties_from_anomalies!
    return [] unless defined?(PlatformAnomaly)

    bounties = []

    # Critical anomalies that need human intervention
    critical_anomalies = PlatformAnomaly.where(entity: entity)
                                        .active
                                        .where(severity: %w[critical high])
                                        .where(human_bounty_id: nil)
                                        .limit(5)

    critical_anomalies.each do |anomaly|
      bounty = create_bounty_from_anomaly(anomaly)
      bounties << bounty if bounty
    end

    Rails.logger.info "[BOUNTY_INTEGRATION] Created #{bounties.count} bounties from anomalies"
    bounties
  end

  def create_bounty_from_anomaly(anomaly)
    urgency = anomaly.severity == 'critical' ? 10 : 8

    scoring = AmosBountyScorer.score(
      title: anomaly.title,
      description: anomaly.description,
      bounty_type: 'bug',
      context: {
        severity: anomaly.severity,
        anomaly_type: anomaly.anomaly_type
      }
    )

    bounty = Bounty.create!(
      entity: entity,
      title: "🚨 #{anomaly.title}",
      description: "#{anomaly.description}\n\n**Severity:** #{anomaly.severity.upcase}\n**Detected:** #{anomaly.created_at.strftime('%Y-%m-%d %H:%M')}",
      bounty_type: 'bug',
      points: [scoring[:points], 200].max,  # Minimum 200 points for critical issues
      ai_scoring_rationale: scoring[:rationale],
      source: 'living_platform',
      urgency_score: urgency,
      impact_score: anomaly.severity == 'critical' ? 10 : 8,
      metadata: {
        anomaly_id: anomaly.id,
        anomaly_type: anomaly.anomaly_type,
        severity: anomaly.severity
      }
    )

    # Link anomaly to bounty
    anomaly.update!(human_bounty_id: bounty.id) if anomaly.respond_to?(:human_bounty_id)

    bounty

  rescue => e
    Rails.logger.error "[BOUNTY_INTEGRATION] Failed to create bounty from anomaly #{anomaly.id}: #{e.message}"
    nil
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # FEATURE REQUESTS → BOUNTIES
  # ═══════════════════════════════════════════════════════════════════════════

  # Convert voted feature requests to bounties
  def create_bounties_from_feature_requests!
    bounties = []

    # Approved feature requests with enough votes
    feature_tickets = SupportTicket.where(entity: entity)
                                   .feature_requests
                                   .approved_features
                                   .where.not(id: Bounty.where(entity: entity).select(:support_ticket_id))
                                   .limit(10)

    feature_tickets.each do |ticket|
      # Check vote count in metadata
      votes = ticket.metadata&.dig('votes') || 0
      next if votes < MIN_VOTES_FOR_BOUNTY

      bounty = create_bounty_from_feature_request(ticket, votes)
      bounties << bounty if bounty
    end

    Rails.logger.info "[BOUNTY_INTEGRATION] Created #{bounties.count} bounties from feature requests"
    bounties
  end

  def create_bounty_from_feature_request(ticket, votes)
    scoring = AmosBountyScorer.score(
      title: ticket.title,
      description: ticket.description,
      bounty_type: 'feature',
      context: {
        votes: votes,
        admin_approved: ticket.admin_approved?
      }
    )

    # Boost points based on votes
    vote_bonus = [votes * 10, 200].min
    final_points = scoring[:points] + vote_bonus

    bounty = Bounty.create!(
      entity: entity,
      support_ticket: ticket,
      title: "🌟 #{ticket.title}",
      description: ticket.description,
      bounty_type: 'feature',
      points: final_points,
      ai_scoring_rationale: "#{scoring[:rationale]} (+#{vote_bonus} points for #{votes} community votes)",
      source: 'feature_vote',
      upvotes: votes,
      metadata: { ticket_number: ticket.ticket_number, votes: votes }
    )

    ticket.update!(metadata: ticket.metadata.merge(bounty_id: bounty.id))

    bounty

  rescue => e
    Rails.logger.error "[BOUNTY_INTEGRATION] Failed to create bounty from feature #{ticket.id}: #{e.message}"
    nil
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # SYNC BOUNTY COMPLETION BACK TO SOURCE SYSTEMS
  # ═══════════════════════════════════════════════════════════════════════════

  # When a bounty is approved, update the source system
  def sync_bounty_completion!(bounty)
    # Update linked ticket
    if bounty.support_ticket.present?
      bounty.support_ticket.resolve!(
        notes: "Resolved via bounty ##{bounty.id}",
        resolved_by: bounty.claimed_by
      )
    end

    # Update linked goal
    if bounty.metadata['goal_id'].present? && defined?(AgentGoal)
      goal = AgentGoal.find_by(id: bounty.metadata['goal_id'])
      goal&.complete!
    end

    # Update linked anomaly
    if bounty.metadata['anomaly_id'].present? && defined?(PlatformAnomaly)
      anomaly = PlatformAnomaly.find_by(id: bounty.metadata['anomaly_id'])
      anomaly&.resolve!
    end

    Rails.logger.info "[BOUNTY_INTEGRATION] Synced completion for bounty ##{bounty.id}"
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # RUN ALL INTEGRATIONS
  # ═══════════════════════════════════════════════════════════════════════════

  def sync_all!
    results = {
      from_tickets: create_bounties_from_tickets!,
      from_goals: create_bounties_from_goals!,
      from_anomalies: create_bounties_from_anomalies!,
      from_features: create_bounties_from_feature_requests!
    }

    total = results.values.flatten.count
    Rails.logger.info "[BOUNTY_INTEGRATION] Total bounties created: #{total}"

    results
  end
end
