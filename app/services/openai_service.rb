class OpenaiService
  include HTTParty
  base_uri 'https://api.openai.com/v1'
  
  def initialize
    @api_key = ENV['OPENAI_API_KEY']
    @headers = {
      'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{@api_key}"
    }
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
end 