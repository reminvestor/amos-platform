class OnboardingScoutService
  def initialize(user, session_id, conversation_history = [])
    @user = user
    @session_id = session_id
    @conversation_history = conversation_history
    @claude_service = ClaudeService.new
    @data_extraction_service = OnboardingDataExtractionService.new(user)
  end
  
  def process_message(user_message)
    # First, extract and save any business data from the user's message
    extraction_result = @data_extraction_service.extract_and_save_business_data(
      user_message, 
      @conversation_history
    )
    
    # Build the conversation prompt with current profile context
    system_prompt = build_conversation_prompt(extraction_result)
    conversation_messages = build_conversation_messages(@conversation_history, user_message)
    
    # Get Scout's conversational response
    begin
      assistant_message = @claude_service.send_message(system_prompt, conversation_messages)
    rescue => e
      Rails.logger.error "Claude API error: #{e.message}"
      assistant_message = "I'm having trouble processing that right now. Could you tell me more about your business?"
    end
    
    # Check if onboarding is complete based on extracted data
    completed = extraction_result[:missing_fields].empty?
    
    # Log extraction results for debugging
    Rails.logger.info "Extraction result: #{extraction_result[:extracted_data]}" if extraction_result[:extracted_data].any?
    Rails.logger.info "Onboarding completeness: #{extraction_result[:completeness_percentage]}%"
    Rails.logger.info "Full profile completeness: #{@data_extraction_service.calculate_full_profile_completeness_percentage}%"
    Rails.logger.info "Missing required fields: #{extraction_result[:missing_fields].join(', ')}" if extraction_result[:missing_fields].any?
    
    {
      message: assistant_message,
      completed: completed,
      business_profile_completed: completed,
      extracted_data: extraction_result[:extracted_data],
      completeness_percentage: extraction_result[:completeness_percentage]
    }
  end
  
  private
  
  def build_conversation_prompt(extraction_result)
    current_profile = extraction_result[:current_profile]
    missing_fields = extraction_result[:missing_fields]
    completeness = extraction_result[:completeness_percentage]
    # User has 1:1 relationship with entity
    business_name = current_profile[:name] || @user.entity&.name || "your business"
    
    completion_status = if missing_fields.empty?
      "COMPLETE - All required information collected!"
    else
      "#{completeness}% complete - Still need: #{missing_fields.join(', ')}"
    end
    
    prompt = <<~PROMPT
      You are Scout, the AI marketing agent for Crux Marketing. You're conducting a friendly, conversational onboarding interview with #{@user.first_name} to learn about their business.

      BUSINESS PROFILE STATUS: #{completion_status}
      Business Name: #{business_name}

      CURRENT PROFILE DATA:
      #{format_profile_data(current_profile)}

      YOUR CONVERSATION GOALS:
      #{build_conversation_goals(missing_fields, current_profile)}

      CONVERSATION STYLE:
      - Be warm, friendly, and encouraging
      - Ask ONE question at a time to avoid overwhelming them
      - Keep responses short and conversational (2-3 sentences max)
      - Use emojis sparingly but appropriately
      - Acknowledge their answers before moving to the next question
      - Show genuine interest in their business
      - Make it feel like a conversation with a knowledgeable friend
      - Build excitement about using Crux Marketing

      IMPORTANT RULES:
      1. If all required info is collected, congratulate them and let them know they're ready to leverage Scout's full marketing capabilities
      2. If they provide new information, acknowledge it specifically before asking the next question
      3. If they ask about Crux Marketing features, briefly explain but guide back to completing their profile
      4. Stay focused on the onboarding process
      5. Don't repeat questions about information already collected

      Remember: You're building trust and getting them excited about using Crux Marketing to grow their business!
    PROMPT
    
    prompt
  end
  
  def format_profile_data(profile_data)
    if profile_data.empty?
      "No profile data collected yet (just business name)"
    else
      profile_data.map { |k, v| "- #{k.to_s.humanize}: #{v}" }.join("\n")
    end
  end
  
  def build_conversation_goals(missing_fields, current_profile)
    if missing_fields.empty?
      "🎉 ONBOARDING COMPLETE! Thank them and let them know they're ready to unlock Scout's full marketing potential."
    elsif missing_fields.include?('industry') 
      "Focus on understanding what industry they're in and what their business does."
    elsif missing_fields.include?('description')
      "Learn more about what their business does, their mission, and what makes them unique."
    elsif missing_fields.include?('target_audience')
      "Understand who their ideal customers are and who they're trying to reach."
    else
      "Ask about any missing information to complete their profile."
    end
  end
  
  def build_conversation_messages(conversation_history, user_message)
    # Format messages for Claude API - use only the last few to avoid token limits
    messages = []
    
    # Add recent conversation history
    recent_history = conversation_history.last(6) # Keep conversation focused
    recent_history.each do |msg|
      messages << { role: msg[:role], content: msg[:content] }
    end
    
    # Add current user message
    messages << { role: 'user', content: user_message }
    
    messages
  end
end 