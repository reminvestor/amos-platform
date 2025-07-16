class OnboardingScoutService
  def initialize(user, session_id)
    @user = user
    @session_id = session_id
    @claude_service = ClaudeService.new
  end
  
  def process_message(user_message)
    # Get conversation history
    conversation_history = get_conversation_history
    
    # Get current business profile progress
    profile_data = get_current_profile_data
    
    # Build the prompt for Scout
    messages = build_onboarding_messages(conversation_history, profile_data, user_message)
    
    # Get response from Claude
    claude_response = @claude_service.chat(messages)
    assistant_message = claude_response.dig('content', 0, 'text') || 
                       "I'm having trouble processing that. Could you tell me more about your business?"
    
    # Extract and store business data from the conversation
    extracted_data = extract_business_data(conversation_history + [
      { role: 'user', content: user_message },
      { role: 'assistant', content: assistant_message }
    ])
    
    if extracted_data.any?
      update_business_profile(extracted_data)
    end
    
    # Check if onboarding is complete
    profile = @user.business_profile || @user.build_business_profile
    completed = onboarding_complete?(profile)
    
    {
      message: assistant_message,
      completed: completed,
      business_profile_completed: completed
    }
  end
  
  private
  
  def get_conversation_history
    # Get from session (stored in controller)
    Rails.application.routes.default_url_options = { host: 'localhost', port: 3000 } if Rails.env.development?
    session_data = Rails.cache.read("onboarding_#{@session_id}") || []
    
    # For now, we'll rely on the controller's session storage
    # This is a simplification - in production you might want to store in database
    []
  end
  
  def get_current_profile_data
    profile = @user.business_profile
    return {} unless profile
    
    {
      name: profile.name,
      industry: profile.industry,
      description: profile.description,
      founded_year: profile.founded_year,
      website: profile.website,
      values: profile.values,
      target_audience: profile.target_audience,
      tone_of_voice: profile.tone_of_voice
    }.compact
  end
  
  def build_onboarding_messages(conversation_history, profile_data, user_message)
    system_prompt = build_system_prompt(profile_data)
    
    messages = [{ role: 'system', content: system_prompt }]
    
    # Add conversation history
    conversation_history.each do |msg|
      messages << { role: msg[:role], content: msg[:content] }
    end
    
    # Add current user message
    messages << { role: 'user', content: user_message }
    
    messages
  end
  
  def build_system_prompt(profile_data)
    completed_fields = profile_data.keys.map(&:to_s)
    
    prompt = <<~PROMPT
      You are Scout, the AI marketing agent for Crux Marketing. You're conducting a friendly, conversational onboarding interview with #{@user.first_name} to learn about their business.

      Your goal is to collect the following information naturally through conversation:
      - Business name
      - Industry/sector
      - Business description (what they do, their mission)
      - Target audience (who are their customers)
      - Founded year (optional)
      - Website URL (optional)  
      - Company values (optional)
      - Tone of voice preference (professional, casual, friendly, etc.)

      CONVERSATION STYLE:
      - Be warm, friendly, and encouraging
      - Ask ONE question at a time 
      - Keep responses short and conversational (2-3 sentences max)
      - Use emojis sparingly but appropriately
      - Acknowledge their answers before moving to the next question
      - If they give incomplete answers, gently probe for more details
      - Make it feel like a conversation with a knowledgeable friend, not an interrogation

      CURRENT PROGRESS:
      Already collected: #{completed_fields.any? ? completed_fields.join(', ') : 'none yet'}
      Still needed: #{missing_fields(completed_fields).join(', ')}

      IMPORTANT RULES:
      1. Only ask about information you haven't collected yet
      2. If you have all required info (name, industry, description, target_audience), end with congratulations and mention they're ready to start creating campaigns
      3. Don't ask for the same information twice
      4. If they ask about features or capabilities, briefly explain but guide back to completing their profile
      5. Stay focused on the onboarding process

      Current profile data collected:
      #{profile_data.map { |k, v| "#{k}: #{v}" }.join("\n")}

      Remember: You're building trust and getting them excited about using Crux Marketing to grow their business!
    PROMPT
    
    prompt
  end
  
  def missing_fields(completed_fields)
    required_fields = %w[name industry description target_audience]
    required_fields - completed_fields
  end
  
  def extract_business_data(conversation)
    # Use Claude to extract structured business data from the conversation
    extraction_prompt = build_extraction_prompt(conversation)
    
    begin
      claude_response = @claude_service.chat([
        { role: 'system', content: extraction_prompt }
      ])
      
      response_text = claude_response.dig('content', 0, 'text') || '{}'
      
      # Parse JSON response
      JSON.parse(response_text)
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse business data extraction: #{e.message}"
      {}
    rescue => e
      Rails.logger.error "Business data extraction error: #{e.message}"
      {}
    end
  end
  
  def build_extraction_prompt(conversation)
    conversation_text = conversation.map { |msg| "#{msg[:role]}: #{msg[:content]}" }.join("\n\n")
    
    <<~PROMPT
      Extract business profile information from this onboarding conversation. Return ONLY a JSON object with any information you can confidently extract. Use null for missing information.

      Required fields to look for:
      - name: Business name
      - industry: Industry or sector  
      - description: What the business does, their mission
      - target_audience: Who their customers are
      - founded_year: Year business was founded (number)
      - website: Website URL
      - values: Company values or principles
      - tone_of_voice: Preferred communication style

      IMPORTANT: 
      - Only include information explicitly mentioned by the user
      - Don't make assumptions or fill in details not provided
      - Return valid JSON only, no additional text
      - Use exact phrases when possible

      CONVERSATION:
      #{conversation_text}

      JSON OUTPUT:
    PROMPT
  end
  
  def update_business_profile(extracted_data)
    profile = @user.business_profile || @user.build_business_profile
    
    extracted_data.each do |key, value|
      next if value.nil? || value.to_s.strip.empty?
      
      case key.to_s
      when 'name'
        profile.name = value
      when 'industry'
        profile.industry = value
      when 'description'
        profile.description = value
      when 'target_audience'
        profile.target_audience = value
      when 'founded_year'
        profile.founded_year = value.to_i if value.to_s.match?(/\A\d{4}\z/)
      when 'website'
        profile.website = value
      when 'values'
        profile.values = value
      when 'tone_of_voice'
        profile.tone_of_voice = value
      end
    end
    
    profile.save!
  end
  
  def onboarding_complete?(profile)
    return false unless profile.persisted?
    
    # Check if we have the minimum required information
    required_fields = %w[name industry description target_audience]
    required_fields.all? { |field| profile.send(field).present? }
  end
end 