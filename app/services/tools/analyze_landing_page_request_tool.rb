module Tools
  class AnalyzeLandingPageRequestTool < BaseTool
    def self.metadata
      {
        name: 'analyze_landing_page_request',
        description: 'Analyze user request to extract business info and design preferences for landing page',
        category: 'landing_page',
        input_schema: {
          type: 'object',
          properties: {
            user_input: {
              type: 'string',
              description: 'The user\'s landing page request or description'
            },
            context: {
              type: 'object',
              description: 'Additional context about the user or business'
            }
          },
          required: ['user_input']
        }
      }
    end
    
    def execute(args)
      log_execution(args)
      
      user_input = get_arg(args, :user_input)
      context = get_arg(args, :context, {})
      
      # Validate required args
      if error = validate_required_args(args, [:user_input])
        return error
      end
      
      begin
        # Use AI to analyze the request
        analysis = analyze_with_ai(user_input, context)
        
        success_response(
          business_info: analysis[:business_info],
          design_preferences: analysis[:design_preferences],
          suggested_sections: analysis[:suggested_sections],
          message: "Successfully analyzed landing page request"
        )
      rescue => e
        Rails.logger.error "Landing page analysis failed: #{e.message}"
        error_response("Failed to analyze request: #{e.message}")
      end
    end
    
    private
    
    def analyze_with_ai(user_input, context)
      prompt = build_analysis_prompt(user_input, context)
      
      # Use appropriate AI service
      ai_service = if ENV['BEDROCK_ACCESS_KEY_ID'].present?
        BedrockService.new
      elsif ENV['OPENAI_API_KEY'].present?
        OpenAiService.new
      else
        raise "No AI service configured"
      end
      
      response = ai_service.generate_completion(
        messages: [
          { role: 'system', content: 'You are a landing page expert analyzing user requirements.' },
          { role: 'user', content: prompt }
        ],
        max_tokens: 1000,
        temperature: 0.7
      )
      
      # Parse the AI response
      parse_ai_analysis(response)
    end
    
    def build_analysis_prompt(user_input, context)
      <<~PROMPT
        Analyze this landing page request and extract key information:
        
        User Request: "#{user_input}"
        
        Business Context:
        - Entity: #{entity.name}
        - Industry: #{context[:industry] || 'Unknown'}
        
        Please provide a JSON response with:
        1. business_info: {
             name: "company name",
             industry: "industry",
             value_proposition: "main value prop",
             target_audience: "who they serve"
           }
        2. design_preferences: {
             style: "modern/classic/minimal/bold",
             color_scheme: "preferred colors",
             tone: "professional/casual/friendly"
           }
        3. suggested_sections: ["hero", "features", "testimonials", etc.]
        
        Return ONLY valid JSON.
      PROMPT
    end
    
    def parse_ai_analysis(ai_response)
      begin
        content = ai_response.dig(:choices, 0, :message, :content) || 
                 ai_response[:message] || 
                 ai_response
        
        parsed = JSON.parse(content)
        
        {
          business_info: parsed['business_info'] || default_business_info,
          design_preferences: parsed['design_preferences'] || default_design_preferences,
          suggested_sections: parsed['suggested_sections'] || default_sections
        }
      rescue JSON::ParserError => e
        Rails.logger.error "Failed to parse AI analysis: #{e.message}"
        
        # Return sensible defaults
        {
          business_info: default_business_info,
          design_preferences: default_design_preferences,
          suggested_sections: default_sections
        }
      end
    end
    
    def default_business_info
      {
        'name' => entity.name,
        'industry' => 'General Business',
        'value_proposition' => 'We provide excellent products and services',
        'target_audience' => 'Businesses and individuals'
      }
    end
    
    def default_design_preferences
      {
        'style' => 'modern',
        'color_scheme' => 'blue and white',
        'tone' => 'professional'
      }
    end
    
    def default_sections
      ['hero', 'features', 'benefits', 'testimonials', 'cta']
    end
  end
end
