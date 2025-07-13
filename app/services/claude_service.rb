require 'faraday'
require 'json'

class ClaudeService
  # Claude 4 Sonnet - upgraded for better performance and intelligence
  MODEL = "claude-sonnet-4-20250514"
  API_URL = "https://api.anthropic.com/v1/messages"
  
  attr_reader :api_key
  
  def initialize(api_key = nil)
    @api_key = api_key || ENV['ANTHROPIC_API_KEY']
    
    # Check if API key exists and is not empty (works in both Rails and non-Rails environments)
    if @api_key.nil? || @api_key.empty?
      raise ArgumentError, "Anthropic API key is required"
    end
  end
  
  # Send a message to Claude 3.7 using the Messages API
  def send_message(system_prompt, user_message_or_conversation, opts = {})
    # Set default options
    options = {
      max_tokens: 4000,
      temperature: 0.5,
      model: MODEL
    }.merge(opts)
    
    # Handle both single messages and conversation arrays
    messages = if user_message_or_conversation.is_a?(Array)
      user_message_or_conversation
    else
      [{ role: "user", content: user_message_or_conversation }]
    end
    
    # Build the request body
    body = {
      model: options[:model],
      max_tokens: options[:max_tokens],
      temperature: options[:temperature],
      system: system_prompt,
      messages: messages
    }
    
    # Make the API request
    begin
      response = connection.post do |req|
        req.url API_URL
        req.headers['Content-Type'] = 'application/json'
        req.headers['x-api-key'] = api_key
        req.headers['anthropic-version'] = '2023-06-01' # Compatible with Claude 4
        req.body = body.to_json
      end
      
      # Parse and return the response
      json_response = JSON.parse(response.body)
      
      # Check for errors
      if response.status != 200
        error_message = json_response['error'] ? json_response['error']['message'] : "Unknown error"
        raise "Claude API Error: #{error_message}"
      end
      
      # Check for Claude 4 refusal stop reason
      if json_response['stop_reason'] == 'refusal'
        log_error("Claude 4 refused to generate content for safety reasons")
        return "I apologize, but I'm not able to help with that particular request. Is there something else I can assist you with?"
      end
      
      # Return the response content
      json_response['content'].first['text']
    rescue Faraday::Error => e
      log_error("Network error when calling Claude API: #{e.message}")
      raise "Claude API connection error: #{e.message}"
    rescue JSON::ParserError => e
      log_error("Error parsing Claude API response: #{e.message}")
      raise "Claude API response parsing error: #{e.message}"
    rescue => e
      log_error("Unexpected error from Claude API: #{e.message}")
      raise "Claude API error: #{e.message}"
    end
  end
  
  private
  
  def connection
    @connection ||= Faraday.new do |conn|
      conn.options.timeout = 120 # 2 minute timeout (suitable for Claude 4)
    end
  end
  
  # Helper method to handle logging in both Rails and non-Rails environments
  def log_error(message)
    if defined?(Rails) && Rails.respond_to?(:logger)
      Rails.logger.error(message)
    else
      puts "ERROR: #{message}"
    end
  end
end 