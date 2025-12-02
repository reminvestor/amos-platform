class OnboardingDataExtractionService
  def initialize(user)
    @user = user
    @claude_service = AiServiceHelper.get_service
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
      if cleaned_response.start_with?("```json")
        cleaned_response = cleaned_response.gsub(/^```json\s*/, "").gsub(/\s*```$/, "")
      elsif cleaned_response.start_with?("```")
        cleaned_response = cleaned_response.gsub(/^```\s*/, "").gsub(/\s*```$/, "")
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
      You are a data extraction specialist. Analyze the user's message and extract ALL business information that can be stored in a structured format. Be thorough - extract as much relevant information as possible.

      CURRENT BUSINESS PROFILE:
      #{current_profile.map { |k, v| "#{k}: #{v || 'Not provided'}" }.join("\n")}

      CONVERSATION CONTEXT (last few messages):
      #{conversation_context.last(3).map { |msg| "#{msg[:role]}: #{msg[:content]}" }.join("\n")}

      EXTRACTION RULES:
      1. Extract ALL information explicitly mentioned by the user
      2. Be thorough - if the user mentions competitors, products, services, challenges, goals, etc., extract them
      3. Don't make up information, but DO extract everything that IS mentioned
      4. Return valid JSON only, no additional text
      5. Use null for fields that aren't mentioned at all

      CORE FIELDS TO EXTRACT (REQUIRED FIELDS MARKED):
      - industry: Business industry/sector [REQUIRED] (e.g., "technology", "healthcare", "education", "fitness")
      - description: What the business does, their mission, value proposition [REQUIRED] - be detailed!
      - target_audience: Who their customers are [REQUIRED] (e.g., "police officers", "small businesses", "fitness enthusiasts")
      - values: Company values, principles, or mission [REQUIRED]
      - tone_of_voice: Preferred communication style [REQUIRED] (e.g., "professional", "casual and friendly", "authoritative")
      - founded_year: Year business was founded (number only)
      - website: Website URL (validate format)

      ADDITIONAL BUSINESS CONTEXT (extract if mentioned):
      - business_model: How they make money (e.g., "subscription", "one-time purchase", "marketplace", "SaaS")
      - unique_selling_proposition: What makes them different from competitors
      - company_size: Number of employees or size indicator (e.g., "startup", "10-50 employees", "enterprise")
      - geographic_focus: Where they operate (e.g., "United States", "Global", "Europe")
      - competitors: List of competitors mentioned
      - products_services: Specific products or services offered
      - key_challenges: Business challenges or pain points mentioned
      - goals: Business goals or objectives mentioned
      - technology_stack: Any technologies, platforms, or tools mentioned
      - customer_pain_points: Problems their customers face that they solve
      - pricing_model: Any pricing information mentioned
      - growth_stage: Stage of business (startup, growth, mature, etc.)
      - partnerships: Any partnerships or integrations mentioned
      - certifications: Any certifications, awards, or credentials mentioned

      USER MESSAGE TO ANALYZE:
      "#{user_message}"

      Return ONLY a JSON object with ALL extracted information. Be comprehensive! Example:
      {
        "industry": "fitness technology",
        "description": "AI-powered fitness platform providing personalized training, recovery, and nutrition guidance through wearables and mobile apps",
        "target_audience": "fitness enthusiasts, athletes, health-conscious individuals",
        "business_model": "subscription",
        "competitors": ["Whoop", "Peloton", "Freeletics", "Fitbod"],
        "technology_stack": ["AI", "machine learning", "computer vision", "wearables"],
        "unique_selling_proposition": "Hyper-individualized training plans that adapt daily based on biometric data",
        "products_services": ["personalized training plans", "recovery tracking", "nutrition guidance", "form feedback"]
      }
    PROMPT
  end

  def validate_and_clean_extracted_data(data)
    cleaned_data = {}

    # Validate and clean each field
    data.each do |key, value|
      next if value.nil?
      
      # Handle arrays (like competitors, products_services)
      if value.is_a?(Array)
        cleaned_array = value.map { |v| v.to_s.strip }.reject(&:blank?)
        cleaned_data[key.to_s] = cleaned_array if cleaned_array.any?
        next
      end
      
      next if value.to_s.strip.empty?

      case key.to_s
      when "industry"
        cleaned_data["industry"] = value.to_s.strip.downcase if value.to_s.length > 2
      when "description"
        cleaned_data["description"] = value.to_s.strip if value.to_s.length > 10
      when "target_audience"
        cleaned_data["target_audience"] = value.to_s.strip if value.to_s.length > 3
      when "founded_year"
        year = value.to_i
        cleaned_data["founded_year"] = year if year >= 1800 && year <= Date.current.year
      when "website"
        url = value.to_s.strip
        if url.match?(/\A#{URI.regexp([ 'http', 'https' ])}\z/) || url.match?(/\A[\w\-\.]+\.[a-z]{2,}\z/i)
          cleaned_data["website"] = url.start_with?("http") ? url : "https://#{url}"
        end
      when "values", "tone_of_voice"
        cleaned_data[key.to_s] = value.to_s.strip if value.to_s.length > 3
      when "business_model", "unique_selling_proposition", "geographic_focus", "company_size", 
           "competitors", "products_services", "key_challenges", "goals", "technology_stack",
           "customer_pain_points", "pricing_model", "growth_stage", "partnerships", "certifications"
        # Store these additional fields - they'll go into knowledge_base
        cleaned_data[key.to_s] = value.to_s.strip if value.to_s.length > 2
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

    # Initialize knowledge_base if nil
    profile.knowledge_base ||= {}
    
    # Track additional business context in knowledge_base
    additional_context = {}

    # Update profile with extracted data
    extracted_data.each do |key, value|
      next unless value.present?
      
      case key.to_s
      when "industry"
        # Replace default industry with actual user-provided industry
        if value != "Industry to be specified during onboarding"
          profile.industry = value
        end
      when "description"
        # Replace default description with actual user-provided description
        if value != "Business details to be updated during onboarding"
          profile.description = value
        end
      when "target_audience"
        profile.target_audience = value
      when "founded_year"
        profile.founded_year = value
      when "website"
        profile.website = value
      when "values"
        profile.values = value
      when "tone_of_voice"
        profile.tone_of_voice = value
      when "business_model", "unique_selling_proposition", "company_size", "geographic_focus",
           "competitors", "products_services", "key_challenges", "goals", "technology_stack",
           "customer_pain_points", "pricing_model", "growth_stage", "partnerships", "certifications"
        # Store these in knowledge_base for rich context
        additional_context[key.to_s] = value
      end
    end

    # Merge additional context into knowledge_base
    if additional_context.any?
      existing_business_context = profile.knowledge_base["business_context"] || {}
      profile.knowledge_base = profile.knowledge_base.merge({
        "business_context" => existing_business_context.merge(additional_context),
        "last_updated" => Time.current.iso8601
      })
    end

    profile.save!
    
    # Also update entity settings with key business info if available
    update_entity_settings(extracted_data)
    
    Rails.logger.info "Updated business profile with: #{extracted_data.keys.join(', ')}"
    Rails.logger.info "Knowledge base now contains: #{profile.knowledge_base.keys.join(', ')}"
    profile
  end
  
  def update_entity_settings(extracted_data)
    entity = @user.entity
    return unless entity
    
    # Store key business context in entity settings for quick access
    entity_updates = {}
    
    if extracted_data["industry"].present?
      entity_updates["industry"] = extracted_data["industry"]
    end
    
    if extracted_data["business_model"].present?
      entity_updates["business_model"] = extracted_data["business_model"]
    end
    
    if extracted_data["company_size"].present?
      entity_updates["company_size"] = extracted_data["company_size"]
    end
    
    if extracted_data["geographic_focus"].present?
      entity_updates["geographic_focus"] = extracted_data["geographic_focus"]
    end
    
    if entity_updates.any?
      entity.settings = (entity.settings || {}).merge(entity_updates)
      entity.save!
      Rails.logger.info "Updated entity settings with: #{entity_updates.keys.join(', ')}"
    end
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
    required_fields = %w[industry description target_audience values tone_of_voice]

    return required_fields unless profile

    missing = []
    missing << 'industry' if profile.industry.blank?
    missing << 'description' if profile.description.blank?
    missing << 'target_audience' if profile.target_audience.blank?
    missing << 'values' if profile.values.blank?
    missing << 'tone_of_voice' if profile.tone_of_voice.blank?


    missing
  end

  def calculate_completeness_percentage
    profile = @user.business_profile
    return 0 unless profile

    # Base onboarding completion on required fields only
    required_fields = %w[name industry description target_audience values tone_of_voice]
    completed_fields = required_fields.count { |field| profile.send(field).present? }

    (completed_fields.to_f / required_fields.length * 100).round
  end
end
