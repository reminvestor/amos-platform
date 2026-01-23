module AmosAI
  class ConversationEngine
    attr_reader :user, :entity

    def initialize(user:, entity:)
      @user = user
      @entity = entity
      @claude_service = AiServiceHelper.get_service # Now using Claude 4 for enhanced intelligence
    end

    def process(message:, history:, business_context:)
      # Build conversation prompt with context
      system_prompt = build_system_prompt(business_context)
      conversation_messages = build_conversation_messages(history, message)

      # Send to Claude
      claude_response = @claude_service.send_message(system_prompt, conversation_messages)

      # Parse response for actions
      parsed_response = parse_claude_response(claude_response)

      {
        content: parsed_response[:content],
        model: "qwen3-next-80b",
        tokens: estimate_tokens(claude_response),
        confidence: parsed_response[:confidence] || 0.9,
        suggested_action: parsed_response[:action],
        action_payload: parsed_response[:payload]
      }
    end

    private

    def build_system_prompt(business_context)
      current_time = Time.current.in_time_zone('America/Los_Angeles')
      
      <<~PROMPT
        You are Amos, an expert AI marketing consultant assistant for #{business_context[:entity_name] || 'this business'}.

        📅 CURRENT DATE/TIME: #{current_time.strftime("%A, %B %d, %Y at %I:%M %p %Z")}
        Use this for any date-relative queries like "today", "yesterday", "this week", etc.

        Your personality:
        - Highly knowledgeable and experienced in digital marketing with enhanced reasoning
        - Friendly, conversational, and approachable
        - Proactive in offering helpful suggestions with deeper insights
        - Focused on practical, actionable advice backed by strategic thinking

        Business Context:
        #{format_business_context(business_context)}

        Your capabilities:
        - Engage in natural conversation about marketing challenges and goals with enhanced intelligence
        - Provide expert marketing advice and deep strategic insights
        - Suggest specific tools and templates when appropriate with better reasoning
        - Help with landing pages, email campaigns, analytics, and contact management using advanced analysis

        Response Guidelines:
        1. Always respond naturally and conversationally
        2. Ask follow-up questions to better understand their needs
        3. Reference their business context when relevant
        4. If they need a specific tool, you can suggest it by including:
           ACTION_SUGGEST: {template_type: "landing_page|campaign|analytics", context: "why this would help"}
        5. Keep responses helpful but concise (under 150 words usually)
        6. Never be overly formal or robotic

        Remember: You're having a conversation, not just responding to commands. Build rapport and understanding.
      PROMPT
    end

    def format_business_context(context)
      parts = []

      parts << "Company: #{context[:entity_name]}" if context[:entity_name]
      parts << "Industry: #{context[:industry]}" if context[:industry]

      if context[:recent_campaigns]&.any?
        campaign_names = context[:recent_campaigns].map(&:name).compact.first(3)
        parts << "Recent campaigns: #{campaign_names.join(', ')}" if campaign_names.any?
      end

      if context[:recent_landing_pages]&.any?
        page_titles = context[:recent_landing_pages].map(&:title).compact.first(3)
        parts << "Recent landing pages: #{page_titles.join(', ')}" if page_titles.any?
      end

      if context[:insights]&.any?
        insights = context[:insights].map { |i| "#{i.insight_type}: #{i.content}" }.first(3)
        parts << "Business insights: #{insights.join('; ')}" if insights.any?
      end

      parts.any? ? parts.join("\n") : "No specific business context available yet."
    end

    def build_conversation_messages(history, current_message)
      messages = []

      # Add conversation history
      history.each do |msg|
        role = msg[:role] == "user" ? "user" : "assistant"
        messages << {
          role: role,
          content: msg[:content]
        }
      end

      # Add current message
      messages << {
        role: "user",
        content: current_message
      }

      # Keep only recent messages to stay within token limits
      messages.last(10) # Keep last 10 messages
    end

    def parse_claude_response(response)
      content = response.strip
      action = nil
      payload = nil
      confidence = 0.9

      # Look for action suggestions in the response
      if content.match(/ACTION_SUGGEST:\s*\{(.+?)\}/)
        action_match = content.match(/ACTION_SUGGEST:\s*\{(.+?)\}/)

        begin
          # Parse the action suggestion
          action_data = eval("{#{action_match[1]}}")  # Simple eval for now, should use JSON.parse in production

          action = "load_template"
          payload = {
            template_id: action_data[:template_type],
            template_name: template_name_for_type(action_data[:template_type]),
            context: action_data[:context]
          }

          # Remove the action directive from the response content
          content = content.gsub(/ACTION_SUGGEST:\s*\{.+?\}/, "").strip

        rescue => e
          Rails.logger.warn "Failed to parse action suggestion: #{e.message}"
        end
      end

      {
        content: content,
        action: action,
        payload: payload,
        confidence: confidence
      }
    end

    def template_name_for_type(type)
      case type
      when "landing_page"
        "Landing Page Builder"
      when "campaign"
        "Email Campaign Builder"
      when "analytics"
        "Analytics Dashboard"
      else
        "Template"
      end
    end

    def estimate_tokens(text)
      # Rough estimation: ~4 characters per token
      (text.length / 4.0).round
    end
  end
end
