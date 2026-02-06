# frozen_string_literal: true

# AmosThinkingService - AMOS's autonomous reflection and bounty generation
#
# Inspired by OpenClaw's agent loop concept, this service enables AMOS to:
# 1. PERCEIVE: Analyze platform state (logs, errors, metrics, feedback)
# 2. REFLECT: Think about what could be improved
# 3. IDEATE: Generate specific improvement ideas
# 4. SCORE: Assign point values to each idea
# 5. CREATE: Generate bounties for contributors
#
class AmosThinkingService
  REFLECTION_PROMPT = <<~PROMPT
    You are AMOS, the autonomous intelligence of a contributor-owned AI platform.
    
    Tonight you are reflecting on the platform's state and thinking about how to improve it.
    
    Your goals:
    1. Keep the platform stable and bug-free
    2. Add features that users want
    3. Grow the contributor and user community
    4. Create valuable work opportunities for contributors
    5. Advance the mission of distributed AI ownership
    
    Based on the context provided, generate a reflection that includes:
    1. OBSERVATIONS: What patterns do you see? What's working? What's not?
    2. PRIORITIES: What's most important to address right now?
    3. OPPORTUNITIES: What improvements would create the most value?
    4. BOUNTY IDEAS: Specific, ACTIONABLE work items for contributors
    
    CRITICAL: Bounties must be WELL-DEFINED and ACTIONABLE. External AI agents and
    human contributors will work on these. The better the bounty, the better the results.
    
    For each bounty idea, you MUST specify:
    - Title: Clear, specific (not vague like "fix bugs")
    - Description: Detailed explanation of the problem/opportunity
    - Type: bug, feature, documentation, content, marketing, support, design, testing, infrastructure
    - Acceptance criteria: How to verify the work is complete (list of checkable items)
    - Scope: What's affected, what files/components are involved
    - Suggested approach: How a contributor should tackle this
    - Estimated effort: trivial, small, medium, large, epic
    - Rationale: Why this matters to the platform
    
    Be creative but practical. Think about both technical and non-technical opportunities.
    Marketing, content, documentation, and community work are just as valuable as code.
    
    RESPONSE FORMAT (JSON):
    {
      "reflection_summary": "<2-3 paragraph summary of your thinking>",
      "observations": ["<observation 1>", "<observation 2>", ...],
      "priorities": ["<priority 1>", "<priority 2>", ...],
      "bounty_ideas": [
        {
          "title": "<specific actionable title>",
          "description": "<detailed description with context>",
          "type": "<bug|feature|documentation|content|marketing|support|design|testing|infrastructure>",
          "acceptance_criteria": ["<criterion 1>", "<criterion 2>", ...],
          "scope": "<what files/components are affected>",
          "suggested_approach": "<how to tackle this>",
          "estimated_effort": "<trivial|small|medium|large|epic>",
          "rationale": "<why this matters>"
        },
        ...
      ]
    }
  PROMPT

  def initialize(entity)
    @entity = entity
    @thinking_log = []
  end

  # Run a full thinking session
  def think!
    session = AmosThinkingSession.create!(
      entity: @entity,
      session_type: 'nightly',
      status: 'running'
    )

    begin
      log("Starting AMOS thinking session for #{@entity.name}")

      # Phase 1: Gather context
      log("Phase 1: Gathering context...")
      context = gather_context
      session.update!(context_analyzed: context.slice(:summary))

      # Phase 2: Sync existing systems → bounties
      log("Phase 2: Syncing existing systems to bounties...")
      integration_bounties = sync_existing_systems_to_bounties

      # Phase 3: Reflect
      log("Phase 3: Reflecting...")
      reflection = reflect(context)

      # Phase 4: Generate and score new bounties
      log("Phase 4: Generating new bounties from reflection...")
      ai_bounties = create_bounties_from_reflection(reflection)

      # Phase 5: Match bounties to external agents
      log("Phase 5: Matching bounties to external agents...")
      agent_assignments = match_bounties_to_external_agents

      # Combine all bounties
      bounties = integration_bounties + ai_bounties

      # Complete session
      total_points = bounties.sum(&:points)
      session.complete!(
        summary: reflection[:reflection_summary],
        bounties_created: bounties.count,
        total_points: total_points,
        thinking_log: @thinking_log.join("\n") + "\n\nAgent Assignments: #{agent_assignments.count}"
      )

      log("Session complete: #{bounties.count} bounties created, #{total_points} total points")

      {
        session: session,
        bounties: bounties,
        reflection: reflection
      }

    rescue => e
      log("ERROR: #{e.message}")
      session.fail!(e.message)
      raise
    end
  end

  # Sync existing platform systems to bounties
  def sync_existing_systems_to_bounties
    integration = BountyIntegrationService.new(@entity)
    results = integration.sync_all!

    all_bounties = results.values.flatten
    log("Synced #{all_bounties.count} bounties from existing systems:")
    log("  - #{results[:from_tickets].count} from tickets")
    log("  - #{results[:from_goals].count} from goals")
    log("  - #{results[:from_anomalies].count} from anomalies")
    log("  - #{results[:from_features].count} from feature requests")

    all_bounties
  rescue => e
    log("WARNING: Integration sync failed: #{e.message}")
    []
  end

  # Match open bounties to external agents
  def match_bounties_to_external_agents
    matching_service = ExternalAgentMatchingService.new(@entity)
    
    # Check if we have any external agents
    available_agents = matching_service.available_agents
    if available_agents.empty?
      log("No external agents available for matching")
      return []
    end
    
    log("Found #{available_agents.count} external agents available")
    
    # Get suggestions and send notifications
    results = matching_service.auto_assign_bounties!(dry_run: false)
    
    notified = results.count { |r| r[:status] == 'notified' }
    log("Notified #{notified} agents about matching bounties")
    
    results.each do |result|
      if result[:status] == 'notified'
        log("  → Recommended '#{result[:bounty][:title]}' to #{result[:recommended_agent][:name]} (#{result[:confidence]})")
      end
    end
    
    results
  rescue => e
    log("WARNING: External agent matching failed: #{e.message}")
    []
  end

  # Gather all context for reflection
  def gather_context
    lookback = 24.hours.ago

    context = {
      # Errors and issues
      errors: gather_recent_errors(lookback),
      open_tickets: SupportTicket.where(entity: @entity).open_tickets.count,
      critical_tickets: SupportTicket.where(entity: @entity).critical.open_tickets.to_a,

      # Feature requests
      feature_requests: gather_feature_requests,

      # Platform metrics
      metrics: gather_platform_metrics,

      # Recent activity
      recent_contributions: Contribution.where(entity: @entity).where('created_at > ?', lookback).count,
      recent_users: User.where(entity: @entity).where('created_at > ?', lookback).count,

      # Existing bounties
      open_bounties: Bounty.where(entity: @entity).open_bounties.count,
      completed_bounties_today: Bounty.where(entity: @entity).completed.where('approved_at > ?', lookback).count,

      # External agents (OpenClaw bots, etc.)
      external_agents: gather_external_agent_context(lookback)
    }

    # Add summary for LLM
    context[:summary] = build_context_summary(context)
    context
  end

  # Gather context about available external agents
  def gather_external_agent_context(lookback)
    matching_service = ExternalAgentMatchingService.new(@entity)
    
    {
      # Summary for AMOS
      summary: matching_service.context_for_amos,
      
      # Suggested assignments
      suggested_assignments: matching_service.suggest_assignments(limit: 5),
      
      # Recent performance
      agent_completions_today: ExternalAgentExecution
                                .joins(:external_agent_registration)
                                .where(external_agent_registrations: { entity: @entity })
                                .where(status: 'approved')
                                .where('external_agent_executions.created_at > ?', lookback)
                                .count,
      
      agent_rejections_today: ExternalAgentExecution
                               .joins(:external_agent_registration)
                               .where(external_agent_registrations: { entity: @entity })
                               .where(status: 'rejected')
                               .where('external_agent_executions.created_at > ?', lookback)
                               .count
    }
  rescue => e
    log("WARNING: Failed to gather external agent context: #{e.message}")
    { summary: {}, suggested_assignments: [], error: e.message }
  end

  private

  def gather_recent_errors(since)
    errors = []

    # From support tickets
    SupportTicket.where(entity: @entity)
                 .where('created_at > ?', since)
                 .where(source: 'log_monitor')
                 .limit(10)
                 .each do |ticket|
      errors << {
        title: ticket.title,
        error_class: ticket.error_class,
        priority: ticket.priority,
        count: ticket.debug_session_count
      }
    end

    # From platform anomalies if available
    if defined?(PlatformAnomaly)
      PlatformAnomaly.where(entity: @entity)
                     .where('created_at > ?', since)
                     .limit(10)
                     .each do |anomaly|
        errors << {
          title: anomaly.description,
          type: anomaly.anomaly_type,
          severity: anomaly.severity
        }
      end
    end

    errors
  end

  def gather_feature_requests
    SupportTicket.where(entity: @entity)
                 .feature_requests
                 .open_tickets
                 .order(created_at: :desc)
                 .limit(10)
                 .map do |ticket|
      {
        title: ticket.title,
        description: ticket.description&.truncate(200),
        votes: ticket.metadata&.dig('votes') || 0,
        created_at: ticket.created_at
      }
    end
  end

  def gather_platform_metrics
    # Basic metrics - extend based on what's available
    {
      total_users: User.where(entity: @entity).count,
      active_users_today: User.where(entity: @entity).where('last_sign_in_at > ?', 24.hours.ago).count,
      total_contributions: Contribution.where(entity: @entity).accepted.count,
      total_bounties_completed: Bounty.where(entity: @entity).completed.count
    }
  end

  def build_context_summary(context)
    summary = <<~SUMMARY
      PLATFORM STATE SUMMARY:
      
      ISSUES:
      - #{context[:open_tickets]} open tickets (#{context[:critical_tickets].count} critical)
      - #{context[:errors].count} recent errors detected
      
      FEATURE REQUESTS:
      #{context[:feature_requests].map { |f| "- #{f[:title]}" }.join("\n")}
      
      ACTIVITY:
      - #{context[:recent_contributions]} contributions in last 24h
      - #{context[:recent_users]} new users in last 24h
      - #{context[:completed_bounties_today]} bounties completed today
      - #{context[:open_bounties]} bounties currently open
      
      METRICS:
      - #{context[:metrics][:total_users]} total users
      - #{context[:metrics][:active_users_today]} active today
    SUMMARY

    # Add external agent info
    if context[:external_agents].present? && context[:external_agents][:summary].present?
      agent_summary = context[:external_agents][:summary]
      if agent_summary[:total_agents].to_i > 0
        summary += <<~AGENTS
          
          EXTERNAL AGENTS (OpenClaw bots, etc.):
          - #{agent_summary[:total_agents]} registered agents available
          - #{context[:external_agents][:agent_completions_today] || 0} bounties completed by agents today
          - #{context[:external_agents][:agent_rejections_today] || 0} bounties rejected today
          - Capabilities: #{agent_summary[:capabilities]&.keys&.first(5)&.join(', ') || 'none declared'}
          
          TOP PERFORMING AGENTS:
          #{agent_summary[:top_performers]&.first(3)&.map { |a| "- #{a[:name]} (#{a[:platform]}) - #{a[:bounties_completed]} completed, #{a[:reputation].round}% rep" }&.join("\n") || 'No completions yet'}
          
          SUGGESTED AGENT ASSIGNMENTS:
          #{context[:external_agents][:suggested_assignments]&.first(3)&.map { |a| "- #{a[:bounty][:title]} → #{a[:recommended_agent][:name]} (#{a[:confidence]} confidence)" }&.join("\n") || 'No suggestions'}
        AGENTS
      end
    end

    # Add critical issues
    if context[:critical_tickets].any?
      summary += "\n\nCRITICAL ISSUES:\n"
      context[:critical_tickets].each do |ticket|
        summary += "- [#{ticket.ticket_number}] #{ticket.title}\n"
      end
    end

    summary
  end

  def reflect(context)
    user_prompt = <<~PROMPT
      Here is the current state of the platform:
      
      #{context[:summary]}
      
      Based on this, reflect on what's happening and generate bounty ideas.
      Consider ALL types of work: bugs, features, documentation, marketing content, tutorials, etc.
      Generate 3-10 bounty ideas based on what you observe.
    PROMPT

    response = call_llm(user_prompt)
    parse_reflection_response(response)
  end

  def parse_reflection_response(response)
    json_str = response.gsub(/```json\n?/, '').gsub(/```\n?/, '').strip
    result = JSON.parse(json_str, symbolize_names: true)

    {
      reflection_summary: result[:reflection_summary],
      observations: result[:observations] || [],
      priorities: result[:priorities] || [],
      bounty_ideas: result[:bounty_ideas] || []
    }
  rescue JSON::ParserError => e
    log("Failed to parse reflection response: #{e.message}")
    {
      reflection_summary: "Failed to parse AI response",
      observations: [],
      priorities: [],
      bounty_ideas: []
    }
  end

  def create_bounties_from_reflection(reflection)
    bounties = []

    reflection[:bounty_ideas].each do |idea|
      # Score the bounty
      scoring = AmosBountyScorer.score(
        title: idea[:title],
        description: idea[:description],
        bounty_type: idea[:type],
        context: { rationale: idea[:rationale] }
      )

      log("Scoring '#{idea[:title]}': #{scoring[:points]} points")

      # Build rich description with all structured context
      description = build_rich_bounty_description(idea)

      # Create the bounty
      bounty = Bounty.create_from_amos!(
        entity: @entity,
        title: idea[:title],
        description: description,
        bounty_type: normalize_bounty_type(idea[:type]),
        points: scoring[:points],
        scoring_rationale: scoring[:rationale],
        metadata: {
          ai_scores: scoring.slice(:effort_score, :impact_score, :urgency_score, :complexity_score),
          estimated_hours: scoring[:estimated_hours],
          acceptance_criteria: idea[:acceptance_criteria],
          scope: idea[:scope],
          suggested_approach: idea[:suggested_approach],
          estimated_effort: idea[:estimated_effort]
        }
      )

      # Store scores
      bounty.update!(
        estimated_hours: scoring[:estimated_hours],
        impact_score: scoring[:impact_score],
        urgency_score: scoring[:urgency_score],
        complexity_score: scoring[:complexity_score]
      )

      bounties << bounty
    end

    bounties
  end

  def build_rich_bounty_description(idea)
    parts = [idea[:description]]

    if idea[:scope].present?
      parts << "\n\n### Scope\n#{idea[:scope]}"
    end

    if idea[:suggested_approach].present?
      parts << "\n\n### Suggested Approach\n#{idea[:suggested_approach]}"
    end

    if idea[:acceptance_criteria].present? && idea[:acceptance_criteria].is_a?(Array)
      criteria = idea[:acceptance_criteria].map { |c| "- [ ] #{c}" }.join("\n")
      parts << "\n\n### Acceptance Criteria\n#{criteria}"
    end

    if idea[:estimated_effort].present?
      parts << "\n\n**Estimated Effort:** #{idea[:estimated_effort].to_s.titleize}"
    end

    if idea[:rationale].present?
      parts << "\n\n**Why this matters:** #{idea[:rationale]}"
    end

    parts.join
  end

  def normalize_bounty_type(type)
    type = type.to_s.downcase
    return type if Bounty::BOUNTY_TYPES.include?(type)

    # Map common variations
    case type
    when 'code', 'coding' then 'feature'
    when 'docs', 'doc' then 'documentation'
    when 'blog', 'article' then 'content'
    when 'ads', 'advertising' then 'marketing'
    when 'help', 'community' then 'support'
    when 'ui', 'ux' then 'design'
    when 'test', 'qa' then 'testing'
    when 'devops', 'infra' then 'infrastructure'
    else 'feature'
    end
  end

  def call_llm(user_prompt)
    if defined?(LlmService)
      LlmService.chat(
        system: REFLECTION_PROMPT,
        user: user_prompt,
        temperature: 0.7,  # Higher temperature for creativity
        max_tokens: 3000
      )
    elsif defined?(BedrockLlmService)
      BedrockLlmService.chat(
        system_prompt: REFLECTION_PROMPT,
        messages: [{ role: 'user', content: user_prompt }],
        temperature: 0.7
      )
    else
      raise "No LLM service available"
    end
  end

  def log(message)
    timestamp = Time.current.strftime('%H:%M:%S')
    entry = "[#{timestamp}] #{message}"
    @thinking_log << entry
    Rails.logger.info "[AMOS_THINKING] #{entry}"
  end
end
