require "faraday"
require "json"

class ClaudeService
  # Claude 4 Sonnet - upgraded for better performance and intelligence
  MODEL = "qwen3-next-80b"
  API_URL = "https://api.anthropic.com/v1/messages"

  attr_reader :api_key

  def initialize
    @api_key = Rails.application.credentials.anthropic&.api_key || ENV["ANTHROPIC_API_KEY"]

    if @api_key.blank?
      raise "Anthropic API key not found. Please set ANTHROPIC_API_KEY environment variable or add to credentials."
    end
  end

  # Send a message to Claude 3.7 using the Messages API
  def send_message(system_prompt, messages, model: "claude-3-5-sonnet-20241022", max_tokens: 4000, temperature: 0.7, json_mode: false)
    # Ensure messages is an array
    messages_array = case messages
    when Array
      messages
    when String
      [ { role: "user", content: messages } ]
    else
      [ { role: "user", content: messages.to_s } ]
    end

    # Validate that all messages have content
    messages_array.each do |msg|
      if msg[:content].blank?
        raise ArgumentError, "All messages must have non-empty content"
      end
    end

    # Modify system prompt for JSON mode if requested
    final_system_prompt = if json_mode
      Rails.logger.info "🔧 Claude JSON mode enabled - enforcing structured output"
      "#{system_prompt}\n\nCRITICAL: You MUST respond with valid JSON only. Do not include any text before or after the JSON. Your entire response must be a valid JSON object."
    else
      system_prompt
    end

    body = {
      model: model,
      max_tokens: max_tokens,
      temperature: temperature,
      system: final_system_prompt,
      messages: messages_array
    }

    Rails.logger.info "Sending request to Claude API with #{messages_array.length} messages"
    start_time = Time.current

    begin
      response = connection.post do |req|
        req.url API_URL
        req.headers["Content-Type"] = "application/json"
        req.headers["x-api-key"] = @api_key
        req.headers["anthropic-version"] = "2023-06-01"
        req.body = body.to_json
      end

      elapsed_time = Time.current - start_time
      Rails.logger.info "Claude API response received in #{elapsed_time.round(2)}s"

      # Parse and return the response
      json_response = JSON.parse(response.body)

      # Check for errors
      if response.status != 200
        error_message = json_response["error"] ? json_response["error"]["message"] : "Unknown error"
        Rails.logger.error "Claude API Error: #{error_message}"
        raise "Claude API Error: #{error_message}"
      end

      # Check for Claude refusal stop reason
      if json_response["stop_reason"] == "refusal"
        log_error("Claude refused to generate content for safety reasons")
        return "I apologize, but I'm not able to help with that particular request. Is there something else I can assist you with?"
      end

      # Return the response content
      content = json_response["content"].first["text"]
      Rails.logger.info "Claude response: #{content.length} characters"
      content

    rescue Faraday::TimeoutError => e
      log_error("Claude API timeout after #{elapsed_time.round(2)}s: #{e.message}")
      raise "Claude API timeout - the request is taking longer than expected. Please try again."
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
      conn.options.timeout = 180      # 3 minute timeout for read
      conn.options.open_timeout = 30  # 30 seconds for connection
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
