module ScoutAI
  class IntentAnalyzer
    attr_reader :user, :entity
    
    def initialize(user:, entity:)
      @user = user
      @entity = entity
      @claude_service = ClaudeService.new
    end
    
    def analyze(conversation_context:, ai_response:)
      system_prompt = build_intent_analysis_prompt
      
      analysis_input = format_analysis_input(conversation_context, ai_response)
      
      begin
        claude_response = @claude_service.send_message(system_prompt, analysis_input)
        parse_intent_response(claude_response)
      rescue => e
        Rails.logger.error "Intent analysis failed: #{e.message}"
        default_intent_response
      end
    end
    
    private
    
    def build_intent_analysis_prompt
      <<~PROMPT
        You are an expert conversation analyst for a marketing platform. Your job is to analyze conversations between a user and an AI marketing assistant to determine if the user would benefit from specific marketing tools or templates.
        
        Available Tools:
        - landing_page: Landing page creation and editing
        - campaign: Email campaign management  
        - analytics: Performance analytics and reporting
        - contacts: Contact and audience management
        
        Your task:
        1. Analyze the conversation context and AI response
        2. Determine if the user would benefit from any specific tools
        3. Respond with a JSON object containing your analysis
        
        Response format (JSON only):
        {
          "intent_detected": true/false,
          "suggested_template": "landing_page|campaign|analytics|contacts|none",
          "confidence": 0.0-1.0,
          "reasoning": "Brief explanation of why this tool would help",
          "trigger_phrases": ["specific phrases that indicated this need"]
        }
        
        Guidelines:
        - Only suggest tools when there's a clear need expressed
        - Don't suggest tools for casual conversation or general questions
        - High confidence (0.8+) only when the user explicitly asks for or needs the tool
        - Medium confidence (0.6-0.8) when the conversation suggests they could benefit
        - Low confidence (0.3-0.6) when there are weak indicators
        - No suggestion (0.0-0.3) for general conversation
        
        Examples of clear needs:
        - "I need to create a landing page" → landing_page, high confidence
        - "My email campaigns aren't working" → campaign, medium confidence  
        - "How are my campaigns performing?" → analytics, high confidence
        - "I need to organize my contacts" → contacts, medium confidence
      PROMPT
    end
    
    def format_analysis_input(conversation_context, ai_response)
      <<~INPUT
        CONVERSATION CONTEXT:
        #{conversation_context}
        
        AI RESPONSE:
        #{ai_response}
        
        Please analyze this conversation and determine if the user would benefit from any specific marketing tools.
      INPUT
    end
    
    def parse_intent_response(response)
      begin
        # Clean up the response to extract JSON
        json_match = response.match(/\{.*\}/m)
        
        if json_match
          parsed = JSON.parse(json_match[0])
          
          {
            intent_detected: parsed['intent_detected'] || false,
            suggested_template: parsed['suggested_template'] || 'none',
            confidence: (parsed['confidence'] || 0.0).to_f,
            reasoning: parsed['reasoning'] || '',
            trigger_phrases: parsed['trigger_phrases'] || [],
            raw_response: response
          }
        else
          Rails.logger.warn "No valid JSON found in intent analysis response: #{response}"
          default_intent_response
        end
        
      rescue JSON::ParserError => e
        Rails.logger.error "Failed to parse intent analysis JSON: #{e.message}"
        Rails.logger.error "Response was: #{response}"
        default_intent_response
      end
    end
    
    def default_intent_response
      {
        intent_detected: false,
        suggested_template: 'none',
        confidence: 0.0,
        reasoning: 'Analysis failed, no intent detected',
        trigger_phrases: [],
        raw_response: 'Error in analysis'
      }
    end
  end
end 