# frozen_string_literal: true

# OnboardingWebsiteAnalyzerService
# Analyzes a website to extract business information for onboarding
#
# Usage:
#   service = OnboardingWebsiteAnalyzerService.new(url: "https://example.com")
#   result = service.analyze
#   # => { success: true, business_name: "...", industry: "...", description: "...", ... }
#
class OnboardingWebsiteAnalyzerService
  attr_reader :url

  INDUSTRIES = {
    'technology' => %w[software saas tech startup app platform cloud ai machine learning],
    'ecommerce' => %w[shop store buy cart checkout products orders retail merchandise],
    'professional_services' => %w[consulting agency firm services solutions advisory],
    'healthcare' => %w[health medical clinic hospital patient care doctor therapy],
    'finance' => %w[bank financial investment insurance trading wealth mortgage loan],
    'education' => %w[school university learning course training education academy],
    'real_estate' => %w[property real estate homes houses apartments rent lease],
    'marketing' => %w[marketing advertising agency creative brand design media],
    'manufacturing' => %w[manufacturing factory production industrial equipment machinery]
  }.freeze

  def initialize(url:)
    @url = normalize_url(url)
  end

  def analyze
    Rails.logger.info "[OnboardingAnalyzer] Analyzing website: #{url}"

    # First, try to capture the website content
    capture_result = capture_website
    
    unless capture_result[:success]
      return {
        success: false,
        error: capture_result[:error] || "Failed to load website",
        url: url
      }
    end

    # Extract business information using AI
    business_info = extract_business_info(capture_result)

    {
      success: true,
      url: url,
      business_name: business_info[:business_name],
      industry: business_info[:industry],
      description: business_info[:description],
      tagline: business_info[:tagline],
      value_proposition: business_info[:value_proposition],
      products_services: business_info[:products_services],
      target_audience: business_info[:target_audience],
      company_size_hint: business_info[:company_size_hint],
      tone_of_voice: business_info[:tone_of_voice],
      values: business_info[:values],
      key_differentiators: business_info[:key_differentiators],
      primary_color: business_info[:primary_color],
      brand_personality: business_info[:brand_personality],
      meta_title: capture_result[:title],
      meta_description: capture_result[:meta_description]
    }
  rescue => e
    Rails.logger.error "[OnboardingAnalyzer] Error analyzing #{url}: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    
    {
      success: false,
      error: "Failed to analyze website: #{e.message}",
      url: url
    }
  end

  private

  def normalize_url(input_url)
    return nil if input_url.blank?
    
    url = input_url.strip.downcase
    url = "https://#{url}" unless url.start_with?('http://', 'https://')
    url
  end

  def capture_website
    # Use the existing WebPageCaptureService
    service = WebPageCaptureService.new(url: url)
    service.capture
  end

  def extract_business_info(capture_result)
    # Combine available text for analysis
    content = build_analysis_content(capture_result)
    
    # Use AI to extract structured business information
    ai_extraction = extract_with_ai(content, capture_result)
    
    # Fallback to heuristic extraction if AI fails
    if ai_extraction[:success]
      ai_extraction
    else
      extract_with_heuristics(capture_result)
    end
  end

  def build_analysis_content(capture_result)
    parts = []
    parts << "Page Title: #{capture_result[:title]}" if capture_result[:title].present?
    parts << "Meta Description: #{capture_result[:meta_description]}" if capture_result[:meta_description].present?
    parts << "Page Content:\n#{capture_result[:text_content]}" if capture_result[:text_content].present?
    parts.join("\n\n")
  end

  def extract_with_ai(content, capture_result)
    return { success: false } if content.blank?

    # Use BedrockService to analyze the content
    bedrock = BedrockService.new(
      system_prompt: build_system_prompt,
      model_name: 'claude-haiku-4-5' # Use fast model for this
    )

    prompt = <<~PROMPT
      Analyze this website content and extract comprehensive business information.
      
      #{content.truncate(8000)}
      
      Respond with a JSON object containing:
      {
        "business_name": "The company/business name",
        "industry": "One of: technology, ecommerce, professional_services, healthcare, finance, education, real_estate, marketing, manufacturing, other",
        "description": "A 2-3 sentence description of what the business does, their core offerings, and value proposition",
        "tagline": "Their tagline or value proposition if visible on the homepage",
        "value_proposition": "What makes them unique? Their key differentiator or main benefit to customers",
        "products_services": ["List", "of", "main", "products/services"],
        "target_audience": "Who they serve (e.g., 'Small businesses', 'Enterprise companies', 'Consumers')",
        "company_size_hint": "Guess: '1' for solo, '2-10' for small team, '11-50' for growing, '51-200' for mid-size, '200+' for large",
        "tone_of_voice": "One of: professional, friendly, bold, warm, technical, casual, authoritative - based on the website's writing style",
        "values": "Core values or principles mentioned on the site, comma-separated",
        "key_differentiators": "What sets them apart from competitors? List 2-3 key differentiators",
        "primary_color": "The primary brand color if identifiable (e.g., 'blue', 'green', '#3B82F6')",
        "brand_personality": "1-2 words describing the brand personality (e.g., 'innovative', 'trustworthy', 'bold')"
      }
      
      Only respond with valid JSON, no markdown or explanation.
    PROMPT

    response = bedrock.send_message_converse(
      build_system_prompt,
      [{ role: 'user', content: prompt }],
      model: 'claude-haiku-4-5',
      max_tokens: 1000,
      temperature: 0.3
    )

    # Parse the JSON response
    json_match = response.match(/\{[\s\S]*\}/)
    if json_match
      parsed = JSON.parse(json_match[0])
      {
        success: true,
        business_name: parsed['business_name'],
        industry: normalize_industry(parsed['industry']),
        description: parsed['description'],
        tagline: parsed['tagline'],
        value_proposition: parsed['value_proposition'],
        products_services: parsed['products_services'],
        target_audience: parsed['target_audience'],
        company_size_hint: parsed['company_size_hint'],
        tone_of_voice: parsed['tone_of_voice'],
        values: parsed['values'],
        key_differentiators: parsed['key_differentiators'],
        primary_color: parsed['primary_color'],
        brand_personality: parsed['brand_personality']
      }
    else
      { success: false }
    end
  rescue => e
    Rails.logger.warn "[OnboardingAnalyzer] AI extraction failed: #{e.message}"
    { success: false }
  end

  def build_system_prompt
    "You are a business analyst extracting company information from website content. Be concise and accurate. Only output valid JSON."
  end

  def normalize_industry(industry)
    return 'other' if industry.blank?
    
    normalized = industry.to_s.downcase.gsub(/[^a-z_]/, '_').gsub(/_+/, '_')
    
    # Map common variations
    case normalized
    when /tech|software|saas|startup/
      'technology'
    when /shop|store|retail|ecommerce|e_commerce/
      'ecommerce'
    when /consult|agency|service|professional/
      'professional_services'
    when /health|medical|clinic/
      'healthcare'
    when /bank|financ|invest|insurance/
      'finance'
    when /school|university|education|learning|course/
      'education'
    when /property|real_estate|homes|realtor/
      'real_estate'
    when /marketing|advertising|creative|design/
      'marketing'
    when /manufactur|factory|industrial/
      'manufacturing'
    else
      INDUSTRIES.keys.include?(normalized) ? normalized : 'other'
    end
  end

  def extract_with_heuristics(capture_result)
    title = capture_result[:title] || ''
    description = capture_result[:meta_description] || ''
    content = capture_result[:text_content] || ''
    all_text = "#{title} #{description} #{content}".downcase

    # Try to extract business name from title
    business_name = extract_business_name_from_title(title)

    # Detect industry from keywords
    industry = detect_industry_from_content(all_text)

    {
      success: true,
      business_name: business_name,
      industry: industry,
      description: description.presence || title,
      tagline: nil,
      products_services: [],
      target_audience: nil,
      company_size_hint: nil
    }
  end

  def extract_business_name_from_title(title)
    return nil if title.blank?
    
    # Common patterns: "Company Name | Tagline" or "Company Name - Tagline"
    # Take the first part before common separators
    name = title.split(/\s*[\|\-–—:]\s*/).first
    name&.strip&.presence
  end

  def detect_industry_from_content(content)
    scores = INDUSTRIES.map do |industry, keywords|
      score = keywords.sum { |keyword| content.scan(/\b#{keyword}\b/i).count }
      [industry, score]
    end.to_h

    best_match = scores.max_by { |_, score| score }
    best_match && best_match[1] > 0 ? best_match[0] : 'other'
  end
end
