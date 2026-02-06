# frozen_string_literal: true

# TicketQualificationService - Ensures tickets are actionable before becoming bounties
#
# PHILOSOPHY: The system already knows most of what it needs. AMOS has access to
# error logs, stack traces, modules, integrations, and user context. Tickets should
# be rich from creation. This service:
#
# 1. ASSESSES readiness (0-100 score) based on structured field completeness
# 2. AUTO-ENRICHES thin tickets with system-available context (no LLM needed for this)
# 3. AI-POLISHES descriptions to be clear for both humans and AI agents
# 4. GATES bounty creation — only tickets above threshold become bounties
#
# Readiness Scoring:
#   0-30:  Insufficient — needs more information
#   31-50: Partial — has basics but missing key details
#   51-70: Good — actionable with some gaps
#   71-90: Strong — well-defined, ready for bounty
#   91-100: Excellent — complete with acceptance criteria
#
class TicketQualificationService
  # Minimum readiness to become a bounty
  BOUNTY_READINESS_THRESHOLD = 60

  # Weights for readiness scoring (must sum to 100)
  SCORING_WEIGHTS = {
    has_title: 5,
    title_quality: 5,           # Descriptive, not vague
    has_description: 10,
    description_quality: 10,    # Specific, not "it's broken"
    has_category: 5,
    has_priority: 3,
    has_reproduction: 15,       # Steps to reproduce (bugs) or user story (features)
    has_expected_behavior: 10,  # What should happen
    has_actual_behavior: 10,    # What actually happens (bugs)
    has_acceptance_criteria: 12, # How to verify the fix/feature is done
    has_scope: 5,               # Affected component/area
    has_approach: 5,            # Suggested fix approach
    has_effort_estimate: 5      # Size estimate
  }.freeze

  class << self
    # Assess and optionally enrich a ticket
    # @param ticket [SupportTicket] The ticket to qualify
    # @param auto_enrich [Boolean] Whether to auto-fill missing fields from system context
    # @return [Hash] { readiness_score:, eligible:, gaps:, enrichments_made: }
    def qualify!(ticket, auto_enrich: true)
      # Step 1: Auto-enrich from system context (no LLM needed)
      enrichments = auto_enrich ? enrich_from_system(ticket) : []

      # Step 2: Score readiness based on current fields
      score_result = calculate_readiness(ticket)

      # Step 3: If score is close but not quite there, AI-polish the description
      if score_result[:score] >= 40 && score_result[:score] < BOUNTY_READINESS_THRESHOLD
        ai_enrichments = ai_polish(ticket, score_result[:gaps])
        enrichments += ai_enrichments
        # Re-score after enrichment
        score_result = calculate_readiness(ticket)
      end

      # Step 4: Update ticket with readiness info
      ticket.update!(
        readiness_score: score_result[:score],
        readiness_assessed_at: Time.current,
        readiness_notes: score_result[:summary],
        bounty_eligible: score_result[:score] >= BOUNTY_READINESS_THRESHOLD,
        bounty_blocked_reason: score_result[:score] < BOUNTY_READINESS_THRESHOLD ? score_result[:gaps].first : nil
      )

      {
        readiness_score: score_result[:score],
        eligible: score_result[:score] >= BOUNTY_READINESS_THRESHOLD,
        gaps: score_result[:gaps],
        strengths: score_result[:strengths],
        enrichments_made: enrichments,
        summary: score_result[:summary]
      }
    end

    # Quick check without modification
    def assess(ticket)
      calculate_readiness(ticket)
    end

    # Batch qualify all unassessed tickets
    def qualify_batch!(entity, limit: 50)
      tickets = SupportTicket.where(entity: entity)
                             .where(readiness_assessed_at: nil)
                             .where(status: %w[open investigating])
                             .order(priority: :desc, created_at: :asc)
                             .limit(limit)

      results = tickets.map { |t| { ticket_id: t.id, **qualify!(t) } }

      eligible_count = results.count { |r| r[:eligible] }
      Rails.logger.info "[TicketQualification] Assessed #{results.count} tickets, #{eligible_count} bounty-eligible"

      results
    end

    private

    # ═══════════════════════════════════════════════════════════════════════════
    # READINESS SCORING
    # ═══════════════════════════════════════════════════════════════════════════

    def calculate_readiness(ticket)
      scores = {}
      gaps = []
      strengths = []

      # Title
      scores[:has_title] = ticket.title.present? ? SCORING_WEIGHTS[:has_title] : 0
      if ticket.title.present?
        title_quality = assess_title_quality(ticket.title)
        scores[:title_quality] = (title_quality * SCORING_WEIGHTS[:title_quality]).round
        strengths << "Clear title" if title_quality >= 0.7
        gaps << "Title is too vague — be specific about what's wrong" if title_quality < 0.4
      else
        scores[:title_quality] = 0
        gaps << "Missing title"
      end

      # Description
      scores[:has_description] = ticket.description.present? ? SCORING_WEIGHTS[:has_description] : 0
      if ticket.description.present?
        desc_quality = assess_description_quality(ticket.description)
        scores[:description_quality] = (desc_quality * SCORING_WEIGHTS[:description_quality]).round
        strengths << "Detailed description" if desc_quality >= 0.7
        gaps << "Description needs more detail — what specifically is the issue?" if desc_quality < 0.4
      else
        scores[:description_quality] = 0
        gaps << "Missing description"
      end

      # Category and priority
      scores[:has_category] = ticket.category.present? ? SCORING_WEIGHTS[:has_category] : 0
      scores[:has_priority] = ticket.priority.present? ? SCORING_WEIGHTS[:has_priority] : 0

      # Reproduction steps / user story
      has_repro = ticket.steps_to_reproduce.present? ||
                  ticket.error_context&.dig('steps_to_reproduce').present? ||
                  ticket.user_story.present?
      scores[:has_reproduction] = has_repro ? SCORING_WEIGHTS[:has_reproduction] : 0
      if has_repro
        strengths << (ticket.is_feature_request? ? "Has user story" : "Has reproduction steps")
      else
        gaps << (ticket.is_feature_request? ? "Missing user story — who needs this and why?" : "Missing steps to reproduce")
      end

      # Expected behavior
      has_expected = ticket.expected_behavior.present?
      scores[:has_expected_behavior] = has_expected ? SCORING_WEIGHTS[:has_expected_behavior] : 0
      strengths << "Expected behavior defined" if has_expected
      gaps << "Missing expected behavior — what should happen?" unless has_expected

      # Actual behavior (bugs only)
      if ticket.is_bug?
        has_actual = ticket.actual_behavior.present? || ticket.error_message.present?
        scores[:has_actual_behavior] = has_actual ? SCORING_WEIGHTS[:has_actual_behavior] : 0
        strengths << "Actual behavior documented" if has_actual
        gaps << "Missing actual behavior — what happens instead?" unless has_actual
      else
        scores[:has_actual_behavior] = SCORING_WEIGHTS[:has_actual_behavior] # N/A for features
      end

      # Acceptance criteria
      has_criteria = ticket.acceptance_criteria.present? && ticket.acceptance_criteria.any?
      scores[:has_acceptance_criteria] = has_criteria ? SCORING_WEIGHTS[:has_acceptance_criteria] : 0
      strengths << "Has acceptance criteria" if has_criteria
      gaps << "Missing acceptance criteria — how do we verify this is done?" unless has_criteria

      # Scope
      has_scope = ticket.affected_component.present? || ticket.scope_summary.present?
      scores[:has_scope] = has_scope ? SCORING_WEIGHTS[:has_scope] : 0

      # Approach
      has_approach = ticket.suggested_approach.present?
      scores[:has_approach] = has_approach ? SCORING_WEIGHTS[:has_approach] : 0

      # Effort estimate
      has_effort = ticket.estimated_effort.present?
      scores[:has_effort_estimate] = has_effort ? SCORING_WEIGHTS[:has_effort_estimate] : 0

      total = scores.values.sum

      {
        score: total,
        scores: scores,
        gaps: gaps,
        strengths: strengths,
        summary: "Readiness: #{total}/100 — #{gaps.count} gaps, #{strengths.count} strengths"
      }
    end

    def assess_title_quality(title)
      return 0.0 if title.blank?

      score = 0.0
      # Length check (5-100 chars is ideal)
      score += 0.2 if title.length.between?(10, 100)
      # Not too short
      score += 0.1 if title.length > 15
      # Contains a verb or action word
      score += 0.2 if title.match?(/\b(fix|add|update|create|remove|improve|change|handle|support|implement|enable)\b/i)
      # Not vague
      score += 0.2 if !title.match?(/\b(broken|doesn.t work|issue|problem|error|bug)\b$/i)
      # Contains a noun (specific component)
      score += 0.2 if title.match?(/\b(page|button|form|api|email|contact|workflow|dashboard|module|login|signup)\b/i)
      # Penalty for very generic titles
      score -= 0.3 if title.match?(/\A(bug|error|fix|issue|problem|help)\z/i)

      score.clamp(0.0, 1.0)
    end

    def assess_description_quality(description)
      return 0.0 if description.blank?

      score = 0.0
      # Has meaningful length
      score += 0.2 if description.length > 50
      score += 0.1 if description.length > 200
      # Has structured content (newlines, lists, headers)
      score += 0.15 if description.include?("\n")
      score += 0.1 if description.match?(/^[-*\d]\.?\s/m)
      # Contains specific details (URLs, error messages, code)
      score += 0.15 if description.match?(/https?:\/\/|`[^`]+`|```/)
      # Contains context words
      score += 0.15 if description.match?(/\b(when|after|before|clicking|navigating|loading|submitting)\b/i)
      # Penalty for very thin descriptions
      score -= 0.3 if description.length < 20

      score.clamp(0.0, 1.0)
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # SYSTEM-BASED ENRICHMENT (No LLM — uses existing data)
    # ═══════════════════════════════════════════════════════════════════════════

    def enrich_from_system(ticket)
      enrichments = []

      # Auto-fill affected component from error context
      if ticket.affected_component.blank? && ticket.error_file.present?
        component = infer_component_from_file(ticket.error_file)
        if component
          ticket.affected_component = component
          enrichments << "Set affected component from error file: #{component}"
        end
      end

      # Auto-fill actual behavior from error message
      if ticket.actual_behavior.blank? && ticket.error_message.present?
        ticket.actual_behavior = "Error: #{ticket.error_message}"
        enrichments << "Set actual behavior from error message"
      end

      # Auto-fill steps to reproduce from error context
      if ticket.steps_to_reproduce.blank? && ticket.error_context&.dig('steps_to_reproduce').present?
        ticket.steps_to_reproduce = ticket.error_context['steps_to_reproduce']
        enrichments << "Set reproduction steps from error context"
      end

      # Auto-fill environment info
      if ticket.environment_info.blank? || ticket.environment_info.empty?
        ticket.environment_info = {
          rails_env: Rails.env,
          ruby_version: RUBY_VERSION,
          rails_version: Rails.version
        }
        enrichments << "Set environment info"
      end

      # Auto-estimate effort from error complexity
      if ticket.estimated_effort.blank?
        ticket.estimated_effort = estimate_effort(ticket)
        enrichments << "Estimated effort: #{ticket.estimated_effort}" if ticket.estimated_effort.present?
      end

      # Auto-fill scope from stack trace
      if ticket.scope_summary.blank? && ticket.stack_trace.present?
        scope = infer_scope_from_stack_trace(ticket.stack_trace)
        if scope
          ticket.scope_summary = scope
          enrichments << "Inferred scope from stack trace"
        end
      end

      ticket.save! if enrichments.any?
      enrichments
    end

    def infer_component_from_file(file_path)
      return nil if file_path.blank?

      case file_path
      when /controllers\/api/ then 'API'
      when /controllers\/scout/ then 'Scout/Chat'
      when /controllers\/build/ then 'Build Portal'
      when /controllers\/admin/ then 'Admin'
      when /services\/tools/ then 'Tools'
      when /services\/amos/ then 'AMOS Core'
      when /services\/workflows/ then 'Workflows'
      when /services\/.*integration/ then 'Integrations'
      when /models\/(.+)\.rb/ then "Model: #{$1.camelize}"
      when /views\/scout/ then 'Scout UI'
      when /views\/build/ then 'Build Portal UI'
      when /jobs/ then 'Background Jobs'
      else nil
      end
    end

    def estimate_effort(ticket)
      if ticket.is_feature_request?
        return 'large' if ticket.description.to_s.length > 500
        return 'medium'
      end

      case ticket.priority
      when 'critical' then 'small'   # Critical = needs fast fix, usually small scope
      when 'high' then 'medium'
      when 'medium' then 'medium'
      when 'low' then 'small'
      else 'medium'
      end
    end

    def infer_scope_from_stack_trace(stack_trace)
      return nil if stack_trace.blank?

      app_files = stack_trace.lines
                             .select { |l| l.include?('app/') || l.include?('lib/') }
                             .map { |l| m = l.match(/(?:app|lib)\/(.+?\.rb)/); m && m[1] }
                             .compact
                             .uniq
                             .first(5)

      return nil if app_files.empty?

      "Affected files: #{app_files.join(', ')}"
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # AI POLISH (Only for tickets that are close to ready)
    # ═══════════════════════════════════════════════════════════════════════════

    def ai_polish(ticket, gaps)
      enrichments = []

      prompt = build_polish_prompt(ticket, gaps)

      response = BedrockService.new.chat(
        messages: [{ role: 'user', content: prompt }],
        system: AI_POLISH_PROMPT,
        model: 'qwen3-next-80b',
        temperature: 0.3,
        max_tokens: 1000
      )

      result = parse_polish_response(response[:content])
      return enrichments unless result

      # Apply AI suggestions
      if result['acceptance_criteria'].present? && (ticket.acceptance_criteria.blank? || ticket.acceptance_criteria.empty?)
        ticket.acceptance_criteria = result['acceptance_criteria']
        enrichments << "AI generated acceptance criteria"
      end

      if result['expected_behavior'].present? && ticket.expected_behavior.blank?
        ticket.expected_behavior = result['expected_behavior']
        enrichments << "AI inferred expected behavior"
      end

      if result['suggested_approach'].present? && ticket.suggested_approach.blank?
        ticket.suggested_approach = result['suggested_approach']
        enrichments << "AI suggested approach"
      end

      if result['scope_summary'].present? && ticket.scope_summary.blank?
        ticket.scope_summary = result['scope_summary']
        enrichments << "AI defined scope"
      end

      if result['steps_to_reproduce'].present? && ticket.steps_to_reproduce.blank?
        ticket.steps_to_reproduce = result['steps_to_reproduce']
        enrichments << "AI inferred reproduction steps"
      end

      ticket.save! if enrichments.any?
      enrichments
    rescue => e
      Rails.logger.warn "[TicketQualification] AI polish failed: #{e.message}"
      []
    end

    AI_POLISH_PROMPT = <<~PROMPT
      You are a ticket qualification system. Your job is to fill in missing fields
      for support tickets so they become actionable bounties.

      You have access to the ticket's existing data (title, description, error info).
      Fill in ONLY the missing fields. Be concise and specific.

      RESPONSE FORMAT (JSON only, no markdown):
      {
        "acceptance_criteria": ["criterion 1", "criterion 2"],
        "expected_behavior": "What should happen",
        "suggested_approach": "How to fix/implement",
        "scope_summary": "What's affected",
        "steps_to_reproduce": "1. Do X\\n2. Do Y\\n3. See Z"
      }

      Only include fields you can reasonably infer. Omit fields you can't determine.
    PROMPT

    def build_polish_prompt(ticket, gaps)
      <<~PROMPT
        Ticket: #{ticket.ticket_number}
        Title: #{ticket.title}
        Category: #{ticket.category}
        Priority: #{ticket.priority}

        Description:
        #{ticket.description}

        #{"Error: #{ticket.error_class}: #{ticket.error_message}" if ticket.error_class.present?}
        #{"Stack trace (first 3 lines):\n#{ticket.stack_trace&.lines&.first(3)&.join}" if ticket.stack_trace.present?}
        #{"Affected file: #{ticket.error_file}" if ticket.error_file.present?}

        MISSING FIELDS (fill these in):
        #{gaps.map { |g| "- #{g}" }.join("\n")}
      PROMPT
    end

    def parse_polish_response(response)
      json_str = response.to_s.gsub(/```json\n?/, '').gsub(/```\n?/, '').strip
      JSON.parse(json_str)
    rescue JSON::ParserError
      nil
    end
  end
end
