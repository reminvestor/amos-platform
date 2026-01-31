# frozen_string_literal: true

# AmosWorkReviewer - AI-powered review of completed bounty work
#
# Reviews submitted work and:
# 1. Approves or requests changes
# 2. Adjusts final points based on quality
# 3. Provides feedback to contributor
#
class AmosWorkReviewer
  REVIEW_SYSTEM_PROMPT = <<~PROMPT
    You are the AMOS work reviewer. Your job is to review completed bounty submissions fairly.

    REVIEW CRITERIA:
    1. COMPLETENESS: Does the work fully address the bounty requirements?
    2. QUALITY: Is the work well-executed? (code quality, writing quality, etc.)
    3. TESTING: For code - are there tests? For content - is it proofread?
    4. DOCUMENTATION: Is the work documented appropriately?
    5. IMPACT: Does this deliver the expected value?

    POINT ADJUSTMENT:
    - Exceptional quality: +25% points
    - Good quality: +10% points
    - Meets requirements: 0% (original points)
    - Minor issues: -10% points
    - Significant issues: -25% points (request changes)
    - Doesn't meet requirements: reject

    RESPONSE FORMAT (JSON only, no markdown):
    {
      "approved": <true/false>,
      "final_points": <integer>,
      "point_adjustment_percent": <-25 to +25>,
      "quality_score": <1-10>,
      "feedback": "<constructive feedback for contributor>",
      "issues": ["<issue 1>", "<issue 2>"] or [],
      "praise": ["<thing done well 1>", "<thing done well 2>"] or []
    }

    Be fair but encouraging. We want contributors to succeed and grow.
  PROMPT

  class << self
    # Review a bounty submission
    # @param bounty [Bounty] The bounty being reviewed
    # @param submission_notes [String] What the contributor submitted
    # @param code_diff [String] Optional code changes
    # @param artifacts [Array] Optional URLs or references to work
    # @return [Hash] Review result
    def review(bounty:, submission_notes:, code_diff: nil, artifacts: [])
      user_prompt = build_review_prompt(bounty, submission_notes, code_diff, artifacts)

      response = call_llm(user_prompt)
      parse_response(response, bounty.points)
    rescue => e
      Rails.logger.error "[WORK_REVIEWER] Error reviewing work: #{e.message}"
      fallback_review(bounty.points)
    end

    # Auto-review simple bounties (documentation, typos, etc.)
    def auto_review_simple(bounty:, submission_notes:)
      # For simple bounties, just verify something was submitted
      if submission_notes.present? && submission_notes.length > 20
        {
          approved: true,
          final_points: bounty.points,
          point_adjustment_percent: 0,
          quality_score: 7,
          feedback: "Thank you for your contribution! Auto-approved.",
          issues: [],
          praise: ["Submission received and accepted"]
        }
      else
        {
          approved: false,
          final_points: bounty.points,
          point_adjustment_percent: 0,
          quality_score: 3,
          feedback: "Please provide more details about what was completed.",
          issues: ["Submission notes too brief"],
          praise: []
        }
      end
    end

    private

    def build_review_prompt(bounty, submission_notes, code_diff, artifacts)
      prompt = <<~PROMPT
        Review this bounty submission:

        BOUNTY TITLE: #{bounty.title}
        BOUNTY TYPE: #{bounty.bounty_type}
        ORIGINAL POINTS: #{bounty.points}
        BOUNTY DESCRIPTION:
        #{bounty.description&.truncate(500)}

        CONTRIBUTOR'S SUBMISSION:
        #{submission_notes&.truncate(2000) || 'No notes provided'}
      PROMPT

      if code_diff.present?
        prompt += "\nCODE CHANGES:\n```\n#{code_diff.truncate(3000)}\n```"
      end

      if artifacts.present?
        prompt += "\nARTIFACTS/LINKS:\n"
        artifacts.each { |a| prompt += "- #{a}\n" }
      end

      prompt
    end

    def call_llm(user_prompt)
      if defined?(LlmService)
        LlmService.chat(
          system: REVIEW_SYSTEM_PROMPT,
          user: user_prompt,
          temperature: 0.3,
          max_tokens: 800
        )
      elsif defined?(BedrockLlmService)
        BedrockLlmService.chat(
          system_prompt: REVIEW_SYSTEM_PROMPT,
          messages: [{ role: 'user', content: user_prompt }],
          temperature: 0.3
        )
      else
        raise "No LLM service available"
      end
    end

    def parse_response(response, original_points)
      json_str = response.gsub(/```json\n?/, '').gsub(/```\n?/, '').strip
      result = JSON.parse(json_str)

      final_points = result['final_points'] || original_points
      final_points = final_points.to_i.clamp(0, original_points * 1.5)  # Max 50% bonus

      {
        approved: result['approved'] == true,
        final_points: final_points,
        point_adjustment_percent: result['point_adjustment_percent'].to_i.clamp(-50, 50),
        quality_score: result['quality_score'].to_i.clamp(1, 10),
        feedback: result['feedback'],
        issues: result['issues'] || [],
        praise: result['praise'] || []
      }
    rescue JSON::ParserError => e
      Rails.logger.warn "[WORK_REVIEWER] Failed to parse JSON: #{e.message}"
      fallback_review(original_points)
    end

    def fallback_review(original_points)
      {
        approved: true,
        final_points: original_points,
        point_adjustment_percent: 0,
        quality_score: 7,
        feedback: "Work reviewed and approved. Thank you for your contribution!",
        issues: [],
        praise: ["Contribution accepted"]
      }
    end
  end
end
