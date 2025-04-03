require 'faraday'
require 'json'

class ClaudeService
  # Claude 3.7 Sonnet is the model we'll use
  MODEL = "claude-3-7-sonnet-20250219"
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
  def send_message(system_prompt, user_message, opts = {})
    # Set default options
    options = {
      max_tokens: 4000,
      temperature: 0.5,
      model: MODEL
    }.merge(opts)
    
    # Build the request body
    body = {
      model: options[:model],
      max_tokens: options[:max_tokens],
      temperature: options[:temperature],
      system: system_prompt,
      messages: [
        { role: "user", content: user_message }
      ]
    }
    
    # Make the API request
    begin
      response = connection.post do |req|
        req.url API_URL
        req.headers['Content-Type'] = 'application/json'
        req.headers['x-api-key'] = api_key
        req.headers['anthropic-version'] = '2023-06-01'
        req.body = body.to_json
      end
      
      # Parse and return the response
      json_response = JSON.parse(response.body)
      
      # Check for errors
      if response.status != 200
        error_message = json_response['error'] ? json_response['error']['message'] : "Unknown error"
        raise "Claude API Error: #{error_message}"
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
      conn.options.timeout = 120 # 2 minute timeout
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