require 'httparty'
require 'json'

class GrokService
  include HTTParty
  
  MODEL = "grok-4-0709"
  base_uri "https://api.x.ai/v1"
  
  attr_reader :api_key
  
  def initialize
    @api_key = Rails.application.credentials.xai&.api_key || ENV['XAI_API_KEY']
    
    if @api_key.blank?
      raise "xAI API key not found. Please set XAI_API_KEY environment variable or add to credentials."
    end
    
    self.class.headers({
      'Authorization' => "Bearer #{@api_key}",
      'Content-Type' => 'application/json'
    })
  end
  
  # Send a message to Grok 4 using the chat/completions API
  def send_message(system_prompt, messages, model: MODEL, max_tokens: 4000, temperature: 0.7, json_mode: false)
    # Ensure messages is an array and convert to xAI format
    messages_array = case messages
    when Array
      messages
    when String
      [{ role: 'user', content: messages }]
    else
      [{ role: 'user', content: messages.to_s }]
    end
    
    # Validate that all messages have content
    messages_array.each do |msg|
      if msg[:content].blank?
        raise ArgumentError, "All messages must have non-empty content"
      end
    end
    
    # Build the messages array with system prompt first
    formatted_messages = []
    formatted_messages << { role: 'system', content: system_prompt } if system_prompt.present?
    formatted_messages.concat(messages_array)
    
    body = {
      model: model,
      messages: formatted_messages,
      max_tokens: max_tokens,
      temperature: temperature,
      stream: false
    }
    
    # Add JSON mode if requested
    if json_mode
      body[:response_format] = { type: "json_object" }
      Rails.logger.info "🔧 Grok JSON mode enabled"
    end
    
    Rails.logger.info "Sending request to Grok API with #{formatted_messages.length} messages"
    start_time = Time.current
    
    begin
      response = self.class.post('/chat/completions', {
        body: body.to_json
      })
      
      end_time = Time.current
      Rails.logger.info "Grok API response received in #{((end_time - start_time) * 1000).round(2)}ms"
      
      if response.success?
        parsed_response = response.parsed_response
        
        if parsed_response && parsed_response['choices'] && parsed_response['choices'].first
          content = parsed_response['choices'].first['message']['content']
          Rails.logger.info "Grok response: #{content&.length || 0} characters"
          return content
        else
          Rails.logger.error "Grok API: Unexpected response format: #{parsed_response}"
          raise "Grok API returned unexpected format"
        end
      else
        error_msg = "Grok API Error (#{response.code}): #{response.body}"
        Rails.logger.error error_msg
        raise error_msg
      end
      
    rescue HTTParty::Error, SocketError, Timeout::Error => e
      Rails.logger.error "Grok API network error: #{e.message}"
      raise "Failed to connect to Grok API: #{e.message}"
    rescue JSON::ParserError => e
      Rails.logger.error "Grok API JSON parsing error: #{e.message}"
      raise "Failed to parse Grok API response: #{e.message}"
    rescue StandardError => e
      Rails.logger.error "Grok API unexpected error: #{e.class} - #{e.message}"
      raise "Grok API error: #{e.message}"
    end
  end
  
  # Alias for compatibility with existing code
  def generate_response(system_prompt, user_message, **options)
    send_message(system_prompt, user_message, **options)
  end
  
  # Test the connection
  def test_connection
    send_message("You are a helpful assistant.", "Hello, can you respond with just 'OK'?", max_tokens: 10)
  rescue => e
    Rails.logger.error "Grok connection test failed: #{e.message}"
    false
  end
end 