class OnboardingDataExtractionService
  def initialize(user)
    @user = user
    @claude_service = ClaudeService.new
  end
  
  def extract_and_save_business_data(user_message, conversation_context = [])
    # Extract structured data from the user's message
    extracted_data = extract_business_info(user_message, conversation_context)
    
    # Save any extracted data to the business profile
    if extracted_data.any?
      update_business_profile(extracted_data)
    end
    
    # Return what was extracted and current profile completeness
    {
      extracted_data: extracted_data,
      current_profile: get_current_profile_summary,
      missing_fields: get_missing_required_fields,
      completeness_percentage: calculate_completeness_percentage
    }
  end
  
  def calculate_full_profile_completeness_percentage
    profile = @user.business_profile
    return 0 unless profile
    
    # Full profile includes optional fields for comprehensive marketing context
    all_fields = %w[name industry description target_audience founded_year website values tone_of_voice]
    completed_fields = all_fields.count { |field| profile.send(field).present? }
    
    (completed_fields.to_f / all_fields.length * 100).round
  end
  
  private
  
  def extract_business_info(user_message, conversation_context)
    extraction_prompt = build_data_extraction_prompt(user_message, conversation_context)
    
    begin
      # Use Claude specifically for data extraction
      response_text = @claude_service.send_message(extraction_prompt, user_message)
      
      # Clean response by removing markdown code blocks if present
      cleaned_response = response_text.strip
      if cleaned_response.start_with?('```json')
        cleaned_response = cleaned_response.gsub(/^```json\s*/, '').gsub(/\s*```$/, '')
      elsif cleaned_response.start_with?('```')
        cleaned_response = cleaned_response.gsub(/^```\s*/, '').gsub(/\s*```$/, '')
      end
      
      # Parse and validate the JSON response
      parsed_data = JSON.parse(cleaned_response)
      validate_and_clean_extracted_data(parsed_data)
      
    rescue JSON::ParserError => e
      Rails.logger.error "Data extraction JSON parse error: #{e.message}"
      Rails.logger.error "Raw response: #{response_text}"
      {}
    rescue => e
      Rails.logger.error "Data extraction error: #{e.message}"
      {}
    end
  end
  
  def build_data_extraction_prompt(user_message, conversation_context)
    current_profile = get_current_profile_summary
    
    <<~PROMPT
      You are a data extraction specialist. Analyze the user's message and extract any business information that can be stored in a structured format.

      CURRENT BUSINESS PROFILE:
      #{current_profile.map { |k, v| "#{k}: #{v || 'Not provided'}" }.join("\n")}

      CONVERSATION CONTEXT (last few messages):
      #{conversation_context.last(3).map { |msg| "#{msg[:role]}: #{msg[:content]}" }.join("\n")}

      EXTRACTION RULES:
      1. Only extract information explicitly mentioned by the user
      2. Don't make assumptions or infer information not directly stated
      3. Be conservative - if unsure, don't extract
      4. Return valid JSON only, no additional text
      5. Use null for fields that aren't mentioned

      FIELDS TO EXTRACT:
      - industry: Business industry/sector (e.g., "technology", "healthcare", "education")
      - description: What the business does, their mission, value proposition
      - target_audience: Who their customers are (e.g., "police officers", "small businesses")
      - founded_year: Year business was founded (number only)
      - website: Website URL (validate format)
      - values: Company values or principles
      - tone_of_voice: Preferred communication style (e.g., "professional", "casual", "friendly")
      - business_model: How they make money (e.g., "subscription", "one-time purchase")
      - unique_selling_proposition: What makes them different from competitors
      - company_size: Number of employees or size indicator
      - geographic_focus: Where they operate (e.g., "United States", "Global")

      USER MESSAGE TO ANALYZE:
      "#{user_message}"

      Return ONLY a JSON object with extracted information. Example:
      {
        "industry": "education",
        "description": "E-learning platform for police officer training",
        "target_audience": "police officers",
        "business_model": "subscription",
        "unique_selling_proposition": "Netflix-style all-you-can-eat training model with AI-powered courses"
      }
    PROMPT
  end
  
  def validate_and_clean_extracted_data(data)
    cleaned_data = {}
    
    # Validate and clean each field
    data.each do |key, value|
      next if value.nil? || value.to_s.strip.empty?
      
      case key.to_s
      when 'industry'
        cleaned_data['industry'] = value.to_s.strip.downcase if value.to_s.length > 2
      when 'description'
        cleaned_data['description'] = value.to_s.strip if value.to_s.length > 10
      when 'target_audience'
        cleaned_data['target_audience'] = value.to_s.strip if value.to_s.length > 3
      when 'founded_year'
        year = value.to_i
        cleaned_data['founded_year'] = year if year >= 1800 && year <= Date.current.year
      when 'website'
        url = value.to_s.strip
        if url.match?(/\A#{URI::regexp(['http', 'https'])}\z/) || url.match?(/\A[\w\-\.]+\.[a-z]{2,}\z/i)
          cleaned_data['website'] = url.start_with?('http') ? url : "https://#{url}"
        end
      when 'values', 'tone_of_voice', 'business_model', 'unique_selling_proposition', 'geographic_focus'
        cleaned_data[key] = value.to_s.strip if value.to_s.length > 3
      when 'company_size'
        cleaned_data['company_size'] = value.to_s.strip if value.to_s.length > 1
      end
    end
    
    cleaned_data
  end
  
  def update_business_profile(extracted_data)
    profile = @user.business_profile || @user.build_business_profile
    
    # Get business name from entity if profile doesn't have one
    if profile.name.blank?
      # User has 1:1 relationship with entity
      entity = @user.entity
      profile.name = entity&.name if entity
    end
    
    # Ensure required fields have default values during onboarding
    profile.description ||= "Business details to be updated during onboarding"
    profile.industry ||= "Industry to be specified during onboarding"
    
    # Update profile with extracted data
    extracted_data.each do |key, value|
      case key
      when 'industry'
        # Replace default industry with actual user-provided industry
        if value.present? && value != "Industry to be specified during onboarding"
          profile.industry = value
        end
      when 'description'
        # Replace default description with actual user-provided description
        if value.present? && value != "Business details to be updated during onboarding"
          profile.description = value
        end
      when 'target_audience'
        profile.target_audience = value
      when 'founded_year'
        profile.founded_year = value
      when 'website'
        profile.website = value
      when 'values'
        profile.values = value
      when 'tone_of_voice'
        profile.tone_of_voice = value
      when 'business_model', 'unique_selling_proposition', 'company_size', 'geographic_focus'
        # These could be stored in a JSON field or separate model
        # For now, we can append to description or values
        if key == 'business_model' && value.present?
          profile.description = "#{profile.description}\n\nBusiness Model: #{value}".strip
        end
      end
    end
    
    profile.save!
    Rails.logger.info "Updated business profile with: #{extracted_data.keys.join(', ')}"
    profile
  end
  
  def get_current_profile_summary
    profile = @user.business_profile
    return {} unless profile
    
    {
      name: profile.name,
      industry: profile.industry,
      description: profile.description,
      target_audience: profile.target_audience,
      founded_year: profile.founded_year,
      website: profile.website,
      values: profile.values,
      tone_of_voice: profile.tone_of_voice
    }.compact
  end
  
  def get_missing_required_fields
    profile = @user.business_profile
    required_fields = %w[industry description target_audience]
    
    return required_fields unless profile
    
    missing = []
    missing << 'industry' if profile.industry.blank?
    missing << 'description' if profile.description.blank?
    missing << 'target_audience' if profile.target_audience.blank?
    
    missing
  end
  
  def calculate_completeness_percentage
    profile = @user.business_profile
    return 0 unless profile
    
    # Base onboarding completion on required fields only
    required_fields = %w[name industry description target_audience]
    completed_fields = required_fields.count { |field| profile.send(field).present? }
    
    (completed_fields.to_f / required_fields.length * 100).round
  end
end 