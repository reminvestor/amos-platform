# frozen_string_literal: true

# AmosBountyScorer - AI-powered bounty point calculation
#
# Scores bounties based on:
# - Estimated effort (hours)
# - User impact (how many affected)
# - Urgency (time sensitivity)
# - Complexity (technical difficulty)
# - Strategic value (alignment with platform goals)
#
# Returns points in ranges:
# - 10-25: Trivial (typos, tiny bugs)
# - 25-75: Small (docs, minor fixes)
# - 75-200: Medium (features, significant bugs)
# - 200-500: Large (major features)
# - 500-2000: Epic (core infrastructure)
#
class AmosBountyScorer
  SCORING_SYSTEM_PROMPT = <<~PROMPT
    You are the AMOS bounty scoring system. Your job is to assign fair point values to work items.

    SCORING FACTORS (each 1-10):
    1. EFFORT: Estimated hours for a skilled contributor
       - 1-2 = minutes, 3-4 = 1-4 hours, 5-6 = half day, 7-8 = 1-3 days, 9-10 = week+
    2. IMPACT: How many users will benefit
       - 1-3 = internal/few, 4-6 = hundreds, 7-8 = thousands, 9-10 = all users
    3. URGENCY: How soon is this needed
       - 1-3 = nice to have, 4-6 = this month, 7-8 = this week, 9-10 = critical/now
    4. COMPLEXITY: Technical difficulty
       - 1-3 = trivial, 4-6 = moderate, 7-8 = complex, 9-10 = very complex
    5. STRATEGIC: Advances platform goals
       - 1-3 = tangential, 4-6 = helpful, 7-8 = important, 9-10 = critical to mission

    POINT CALCULATION:
    Base = (effort + impact + urgency + complexity + strategic) / 5 * 50
    Adjusted for category:
    - bug/security: +20%
    - feature: +10%
    - documentation: -10%
    - content/marketing: base
    - support: -20%

    POINT RANGES:
    - 10-25 points: Trivial tasks (typos, tiny bugs, simple docs)
    - 25-75 points: Small tasks (minor fixes, documentation updates)
    - 75-200 points: Medium tasks (features, significant bugs)
    - 200-500 points: Large tasks (major features, complex bugs)
    - 500-2000 points: Epic tasks (core infrastructure, platform-wide changes)

    RESPONSE FORMAT (JSON only, no markdown):
    {
      "points": <integer>,
      "effort_score": <1-10>,
      "impact_score": <1-10>,
      "urgency_score": <1-10>,
      "complexity_score": <1-10>,
      "strategic_score": <1-10>,
      "estimated_hours": <number>,
      "rationale": "<1-2 sentence explanation>"
    }
  PROMPT

  class << self
    # Score a bounty description
    # @param title [String] Bounty title
    # @param description [String] Full description
    # @param bounty_type [String] Type of bounty (bug, feature, etc.)
    # @param context [Hash] Additional context (priority, category, etc.)
    # @return [Hash] Scoring result with points and rationale
    def score(title:, description:, bounty_type:, context: {})
      user_prompt = build_scoring_prompt(title, description, bounty_type, context)

      response = call_llm(user_prompt)
      parse_response(response)
    rescue => e
      Rails.logger.error "[BOUNTY_SCORER] Error scoring bounty: #{e.message}"
      fallback_score(bounty_type)
    end

    # Score an existing support ticket
    def score_ticket(ticket)
      context = {
        priority: ticket.priority,
        category: ticket.category,
        error_class: ticket.error_class,
        source: ticket.source
      }

      score(
        title: ticket.title,
        description: ticket.description,
        bounty_type: ticket_to_bounty_type(ticket),
        context: context
      )
    end

    private

    def build_scoring_prompt(title, description, bounty_type, context)
      prompt = <<~PROMPT
        Score this #{bounty_type.upcase} bounty:

        TITLE: #{title}

        DESCRIPTION:
        #{description&.truncate(1000) || 'No description provided'}

        TYPE: #{bounty_type}
      PROMPT

      if context.present?
        prompt += "\nADDITIONAL CONTEXT:\n"
        context.each do |key, value|
          prompt += "- #{key}: #{value}\n" if value.present?
        end
      end

      prompt
    end

    def call_llm(user_prompt)
      # Use whatever LLM service is available
      if defined?(LlmService)
        LlmService.chat(
          system: SCORING_SYSTEM_PROMPT,
          user: user_prompt,
          temperature: 0.3,  # Lower temperature for consistent scoring
          max_tokens: 500
        )
      elsif defined?(BedrockLlmService)
        BedrockLlmService.chat(
          system_prompt: SCORING_SYSTEM_PROMPT,
          messages: [{ role: 'user', content: user_prompt }],
          temperature: 0.3
        )
      else
        raise "No LLM service available"
      end
    end

    def parse_response(response)
      # Extract JSON from response (handle markdown code blocks)
      json_str = response.gsub(/```json\n?/, '').gsub(/```\n?/, '').strip
      result = JSON.parse(json_str)

      {
        points: result['points'].to_i.clamp(10, 2000),
        effort_score: result['effort_score'].to_i.clamp(1, 10),
        impact_score: result['impact_score'].to_i.clamp(1, 10),
        urgency_score: result['urgency_score'].to_i.clamp(1, 10),
        complexity_score: result['complexity_score'].to_i.clamp(1, 10),
        strategic_score: result['strategic_score']&.to_i&.clamp(1, 10),
        estimated_hours: result['estimated_hours'].to_f,
        rationale: result['rationale']
      }
    rescue JSON::ParserError => e
      Rails.logger.warn "[BOUNTY_SCORER] Failed to parse JSON: #{e.message}"
      fallback_score('unknown')
    end

    def fallback_score(bounty_type)
      points = case bounty_type
      when 'bug' then 100
      when 'feature' then 200
      when 'documentation' then 50
      when 'content', 'marketing' then 75
      when 'support' then 25
      when 'infrastructure' then 500
      else 100
      end

      {
        points: points,
        effort_score: 5,
        impact_score: 5,
        urgency_score: 5,
        complexity_score: 5,
        strategic_score: 5,
        estimated_hours: 4,
        rationale: "Fallback score for #{bounty_type} bounty"
      }
    end

    def ticket_to_bounty_type(ticket)
      case ticket.category
      when 'bug', 'performance' then 'bug'
      when 'security' then 'bug'
      when 'feature_request' then 'feature'
      when 'documentation' then 'documentation'
      when 'ui_issue' then 'design'
      else 'bug'
      end
    end
  end
end
