require 'httparty'

class OpenaiService
  include HTTParty
  base_uri 'https://api.openai.com/v1'
  
  def initialize
    @api_key = ENV['OPENAI_API_KEY']
    @headers = {
      'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{@api_key}"
    }

    # Extend HTTP timeouts for complex requests
    # HTTParty uses Net::HTTP under the hood; :timeout covers both open/read timeouts
    self.class.default_options.merge!(timeout: 240)
  end
  
  # Unified chat interface to align with ClaudeService/GrokService
  # Returns assistant content string
  def send_message(system_prompt, messages, model: 'gpt-5', max_tokens: 4000, temperature: 0.7, json_mode: false)
    # Ensure messages is an array and normalize to OpenAI schema
    messages_array = case messages
    when Array
      messages
    when String
      [{ role: 'user', content: messages }]
    else
      [{ role: 'user', content: messages.to_s }]
    end

    # Validate non-empty contents
    messages_array.each do |msg|
      if msg[:content].to_s.strip.empty?
        raise ArgumentError, 'All messages must have non-empty content'
      end
    end

    # Prepend system prompt if provided
    formatted_messages = []
    formatted_messages << { role: 'system', content: system_prompt } if system_prompt.present?
    formatted_messages.concat(messages_array)

    body = {
      model: model,
      messages: formatted_messages
    }

    # Only include temperature for models that support it
    unless model.to_s.start_with?('gpt-5')
      body[:temperature] = temperature
    end

    # Some newer models (e.g., GPT-5) require max_completion_tokens instead of max_tokens
    if model.to_s.start_with?('gpt-5')
      body[:max_completion_tokens] = max_tokens
    else
      body[:max_tokens] = max_tokens
    end

    # Enforce JSON mode if requested
    if json_mode
      body[:response_format] = { type: 'json_object' }
      Rails.logger.info '🔧 OpenAI JSON mode enabled'
    end

    Rails.logger.info "Sending request to OpenAI (#{model}) with #{formatted_messages.length} messages"
    start_time = Time.current

    begin
      response = self.class.post('/chat/completions', {
        body: body.to_json,
        headers: @headers,
        timeout: 240 # seconds
      })

      duration_ms = ((Time.current - start_time) * 1000).round(2)
      Rails.logger.info "OpenAI API response received in #{duration_ms}ms"

      if response.success?
        parsed = response.parsed_response
        content = parsed.dig('choices', 0, 'message', 'content')
        Rails.logger.info "OpenAI response: #{content&.length || 0} characters"
        return content
      else
        error_msg = "OpenAI API Error (#{response.code}): #{response.body}"
        Rails.logger.error error_msg
        raise error_msg
      end
    rescue HTTParty::Error, SocketError, Timeout::Error => e
      Rails.logger.error "OpenAI API network error: #{e.message}"
      raise "Failed to connect to OpenAI API: #{e.message}"
    rescue JSON::ParserError => e
      Rails.logger.error "OpenAI API JSON parsing error: #{e.message}"
      raise "Failed to parse OpenAI API response: #{e.message}"
    rescue StandardError => e
      Rails.logger.error "OpenAI API unexpected error: #{e.class} - #{e.message}"
      raise "OpenAI API error: #{e.message}"
    end
  end

  # Alias for compatibility with callers expecting this method name
  def generate_response(system_prompt, user_message, **options)
    send_message(system_prompt, user_message, **options)
  end

  def generate_social_post(business_profile, platform, purpose = nil, prompt = nil)
    messages = [
      {
        role: "system",
        content: system_prompt(business_profile, platform)
      }
    ]
    
    if purpose.present?
      messages << {
        role: "user",
        content: "Create a social media post for the purpose of: #{purpose}"
      }
    elsif prompt.present?
      messages << {
        role: "user",
        content: prompt
      }
    else
      messages << {
        role: "user",
        content: "Create a social media post that would be engaging for my target audience."
      }
    end
    
    response = self.class.post(
      '/chat/completions',
      body: {
        model: 'gpt-3.5-turbo',
        messages: messages,
        temperature: 0.7,
        max_tokens: 500
      }.to_json,
      headers: @headers
    )
    
    if response.success?
      response_data = JSON.parse(response.body)
      response_data.dig('choices', 0, 'message', 'content')
    else
      Rails.logger.error("OpenAI API error: #{response.code} - #{response.body}")
      "Error generating content. Please try again later."
    end
  end
  
  private
  
  def system_prompt(business_profile, platform)
    <<~PROMPT
      You are a professional social media content writer for #{business_profile.name}.

      BUSINESS INFORMATION:
      #{business_profile.llm_context}

      PLATFORM: #{platform}
      
      INSTRUCTIONS:
      1. Create a single social media post appropriate for the #{platform} platform
      2. Follow the brand's tone of voice
      3. Target the appropriate audience
      4. Keep the post within appropriate length limits for the platform
      5. Make the content engaging, shareable, and relevant
      6. Do not include hashtags in brackets, but include them naturally if appropriate
      7. Return only the post content, nothing else
      
      If it's for Instagram, make it visual and include relevant hashtags.
      If it's for LinkedIn, make it professional and insightful.
      If it's for Twitter, make it concise and impactful within the character limit.
      If it's for Facebook, make it conversational and engaging.
    PROMPT
  end

  # Analyze an image and return a description suitable for providing context to LLMs
  def analyze_image(image_url, context = nil)
    messages = [
      {
        role: "user",
        content: [
          {
            type: "text",
            text: "Analyze this image and provide a detailed description suitable for a web designer who needs to understand its content, mood, colors, and key visual elements. #{context ? "Context: #{context}" : ''}"
          },
          {
            type: "image_url",
            image_url: {
              url: image_url
            }
          }
        ]
      }
    ]

    Rails.logger.info "Analyzing image with OpenAI Vision: #{image_url}"
    
    begin
      response = self.class.post('/chat/completions', {
        body: {
          model: 'gpt-4-vision-preview',
          messages: messages,
          max_tokens: 300
        }.to_json,
        headers: @headers,
        timeout: 30
      })

      if response.success?
        parsed = response.parsed_response
        description = parsed.dig('choices', 0, 'message', 'content')
        Rails.logger.info "Image analysis complete: #{description&.length || 0} characters"
        return description
      else
        Rails.logger.error "OpenAI Vision API Error: #{response.body}"
        return "Image at #{image_url} (description unavailable)"
      end
    rescue => e
      Rails.logger.error "Failed to analyze image: #{e.message}"
      return "Image at #{image_url} (analysis failed)"
    end
  end
end 