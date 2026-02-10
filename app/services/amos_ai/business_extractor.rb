module AmosAI
  class BusinessExtractor
    attr_reader :user, :entity

    def initialize(user:, entity:)
      @user = user
      @entity = entity
      @claude_service = AiServiceHelper.get_service
    end

    def extract(conversation_context:)
      system_prompt = build_extraction_prompt
      extraction_input = format_extraction_input(conversation_context)

      begin
        claude_response = @claude_service.send_message(system_prompt, extraction_input)
        parse_extraction_response(claude_response)
      rescue => e
        Rails.logger.error "Business extraction failed: #{e.message}"
        default_extraction_response
      end
    end

    private

    def build_extraction_prompt
      <<~PROMPT
        You are an expert business intelligence analyst. Your job is to extract structured business information from natural conversations between a user and an AI marketing assistant.

        Current Business Context:
        #{format_current_business_context}

        Extract the following types of information when mentioned:

        INSIGHT TYPES:
        - company_info: Company name, size, founding year, location, etc.
        - target_audience: Demographics, psychographics, customer segments
        - marketing_challenges: Pain points, obstacles, current problems
        - industry_details: Sector, competition, market conditions#{'  '}
        - contact_preferences: How they like to communicate, follow up preferences
        - tool_usage_patterns: What marketing tools they use, preferences
        - business_goals: Revenue targets, growth goals, objectives
        - pain_points: Specific challenges they're facing

        Response format (JSON only):
        {
          "insights": [
            {
              "type": "company_info|target_audience|marketing_challenges|industry_details|contact_preferences|tool_usage_patterns|business_goals|pain_points",
              "content": "Specific information extracted",
              "confidence": 0.0-1.0,
              "source_text": "The exact text that indicated this information"
            }
          ],
          "business_profile_updates": {
            "industry": "if mentioned",
            "company_size": "if mentioned",#{' '}
            "target_market": "if mentioned"
          }
        }

        Guidelines:
        - Only extract information that's explicitly mentioned or strongly implied
        - High confidence (0.8+) for directly stated facts
        - Medium confidence (0.6-0.8) for clearly implied information
        - Low confidence (0.3-0.6) for weakly implied information
        - Don't extract information that's already known (see current context above)
        - Focus on NEW information not already in the business profile

        Examples:
        - "We're a SaaS company with 50 employees" → company_info, high confidence
        - "Our customers are mostly small businesses" → target_audience, medium confidence
        - "Email marketing isn't working for us" → marketing_challenges, high confidence
      PROMPT
    end

    def format_current_business_context
      context_parts = []

      biz = BusinessContext.for(@user, @entity)
      context_parts << "Business: #{biz.company_name}"
      context_parts << "Industry: #{biz.industry}" if biz.industry.present?
      context_parts << "Description: #{biz.description}" if biz.description.present?
      context_parts << "Target Audience: #{biz.target_audience}" if biz.target_audience.present?

      # Get recent insights to avoid duplicates
      recent_insights = BusinessInsight.where(entity: @entity)
                                     .recent
                                     .limit(10)
                                     .pluck(:insight_type, :content)

      if recent_insights.any?
        insights_summary = recent_insights.map { |type, content| "#{type}: #{content}" }.join("; ")
        context_parts << "Recent Insights: #{insights_summary}"
      end

      context_parts.any? ? context_parts.join("\n") : "No existing business context available."
    end

    def format_extraction_input(conversation_context)
      <<~INPUT
        CONVERSATION TO ANALYZE:
        #{conversation_context}

        Please extract any business information from this conversation that would help build a better understanding of this user's business.
      INPUT
    end

    def parse_extraction_response(response)
      begin
        # Clean up the response to extract JSON
        json_match = response.match(/\{.*\}/m)

        if json_match
          parsed = JSON.parse(json_match[0])

          # Process insights
          insights = (parsed["insights"] || []).map do |insight|
            {
              type: insight["type"],
              content: insight["content"],
              confidence: (insight["confidence"] || 0.0).to_f,
              source_text: insight["source_text"] || ""
            }
          end

          # Process business profile updates
          profile_updates = parsed["business_profile_updates"] || {}

          {
            insights: insights,
            business_profile_updates: profile_updates,
            raw_response: response
          }
        else
          Rails.logger.warn "No valid JSON found in extraction response: #{response}"
          default_extraction_response
        end

      rescue JSON::ParserError => e
        Rails.logger.error "Failed to parse extraction JSON: #{e.message}"
        Rails.logger.error "Response was: #{response}"
        default_extraction_response
      end
    end

    def default_extraction_response
      {
        insights: [],
        business_profile_updates: {},
        raw_response: "Error in extraction"
      }
    end
  end
end
