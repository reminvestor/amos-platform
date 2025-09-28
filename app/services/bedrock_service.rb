require 'aws-sdk-bedrockruntime'
require 'json'

class BedrockService
  class BedrockError < StandardError; end
  
  def initialize
    @client = Aws::BedrockRuntime::Client.new(
      region: ENV['AWS_REGION'] || 'us-east-1',
      # Let AWS SDK use the default credential chain
      # This will automatically find credentials from:
      # 1. Environment variables
      # 2. ECS/EC2 instance profile  
      # 3. AWS CLI configuration (~/.aws/credentials)
      
      # Increase timeout for long-running operations like landing page generation
      # Default is 60 seconds, but landing pages can take 4-5 minutes
      http_read_timeout: 600, # 10 minutes
      http_open_timeout: 30   # 30 seconds to establish connection
    )
  end

  # Main method to send messages to Claude via Bedrock
  def send_message(system_prompt, messages, model: 'claude-opus-4-1', max_tokens: 4000, temperature: 0.7, json_mode: false, stream: false, &block)
    if stream && block_given?
      send_message_streaming(system_prompt, messages, model: model, max_tokens: max_tokens, temperature: temperature, json_mode: json_mode, &block)
    else
      send_message_non_streaming(system_prompt, messages, model: model, max_tokens: max_tokens, temperature: temperature, json_mode: json_mode)
    end
  end

  private

  def send_message_non_streaming(system_prompt, messages, model: 'claude-opus-4-1', max_tokens: 4000, temperature: 0.7, json_mode: false)
    # Map model names to Bedrock model IDs
    # Using cross-region inference profiles (us. prefix) for better availability
    model_id = case model
    when 'claude-opus-4-1', 'claude-opus-4-1-20250805'
      'us.anthropic.claude-opus-4-1-20250805-v1:0'
    when 'claude-3-5-sonnet', 'claude-3.5-sonnet'
      'us.anthropic.claude-3-5-sonnet-20241022-v2:0'
    when 'claude-3-haiku'
      'us.anthropic.claude-3-5-haiku-20241022-v1:0'
    else
      # Default to Claude 3.5 Sonnet v2
      'us.anthropic.claude-3-5-sonnet-20241022-v2:0'
    end

    # Format messages for Claude
    formatted_messages = format_messages_for_claude(messages)
    
    # Debug the formatted messages
    Rails.logger.info "🔍 Bedrock formatted messages: #{formatted_messages.inspect}"
    
    # Modify system prompt for JSON mode if requested
    final_system_prompt = if json_mode && system_prompt.present?
      Rails.logger.info "🔧 Bedrock JSON mode enabled - enforcing structured output"
      "#{system_prompt}\n\nCRITICAL: You MUST respond with valid JSON only. Do not include any text before or after the JSON. Your entire response must be a valid JSON object."
    else
      system_prompt
    end

    # Build the request body for Claude
    request_body = {
      anthropic_version: "bedrock-2023-05-31",
      messages: formatted_messages,
      max_tokens: max_tokens,
      temperature: temperature
    }

    # Add system prompt if provided
    request_body[:system] = final_system_prompt if final_system_prompt.present?

    Rails.logger.info "Sending request to Bedrock Claude (#{model_id})"
    
    begin
      response = @client.invoke_model(
        model_id: model_id,
        body: request_body.to_json,
        content_type: 'application/json',
        accept: 'application/json'
      )

      # Parse the response
      response_body = JSON.parse(response.body.read)
      content = response_body.dig('content', 0, 'text')
      
      Rails.logger.info "Bedrock response received: #{content&.length || 0} characters"
      
      content
    rescue Aws::BedrockRuntime::Errors::ServiceError => e
      Rails.logger.error "Bedrock API Error: #{e.message}"
      raise "Bedrock API Error: #{e.message}"
    rescue StandardError => e
      Rails.logger.error "Unexpected error from Bedrock: #{e.message}"
      raise "Failed to get response from Bedrock: #{e.message}"
    end
  end

  # Generate images using Amazon Titan
  def generate_image(prompt, size: '1024x1024', style: 'photographic')
    # Map sizes to Titan's supported dimensions
    width, height = case size
    when '1024x1024'
      [1024, 1024]
    when '1024x1792', '1792x1024'
      size.include?('1792x1024') ? [1792, 1024] : [1024, 1792]
    when '768x768'
      [768, 768]
    when '512x512'
      [512, 512]
    else
      [1024, 1024] # Default
    end

    request_body = {
      taskType: "TEXT_IMAGE",
      textToImageParams: {
        text: prompt
      },
      imageGenerationConfig: {
        numberOfImages: 1,
        height: height,
        width: width,
        cfgScale: 8.0,
        seed: Random.rand(0..2147483647)
      }
    }

    Rails.logger.info "Generating image with Titan: #{prompt[0..100]}..."

    begin
      response = @client.invoke_model(
        model_id: 'amazon.titan-image-generator-v2:0',
        body: request_body.to_json,
        content_type: 'application/json',
        accept: 'application/json'
      )

      response_body = JSON.parse(response.body.read)
      
      # Titan returns base64 encoded images
      if response_body['images'] && response_body['images'].first
        base64_image = response_body['images'].first
        {
          url: "data:image/png;base64,#{base64_image}",
          base64: base64_image,
          revised_prompt: prompt
        }
      else
        raise "No image generated"
      end
    rescue Aws::BedrockRuntime::Errors::ServiceError => e
      Rails.logger.error "Titan Image Generation Error: #{e.message}"
      raise "Image generation failed: #{e.message}"
    end
  end

  # Analyze an image using Claude with vision capabilities
  def analyze_image(image_url, context = nil)
    # For Bedrock, we need to convert image URLs to base64
    image_data = if image_url.start_with?('data:image')
      # Already base64
      image_url.split(',').last
    else
      # Download and convert to base64
      require 'open-uri'
      require 'base64'
      
      image_content = URI.open(image_url).read
      Base64.strict_encode64(image_content)
    end

    messages = [
      {
        role: "user",
        content: [
          {
            type: "text",
            text: "Analyze this image and provide a detailed description suitable for a web designer who needs to understand its content, mood, colors, and key visual elements. #{context ? "Context: #{context}" : ''}"
          },
          {
            type: "image",
            source: {
              type: "base64",
              media_type: "image/jpeg",
              data: image_data
            }
          }
        ]
      }
    ]

    # Use Claude 3.5 Sonnet for vision tasks
    send_message(nil, messages, model: 'claude-3-5-sonnet', max_tokens: 300)
  rescue => e
    Rails.logger.error "Failed to analyze image: #{e.message}"
    "Image analysis unavailable"
  end

  public
  
  # Non-streaming version using converse API (for tool continuation)
  def send_message_converse(system_prompt, messages, model: 'claude-opus-4-1', max_tokens: 4000, temperature: 0.7, tools: [])
    # Map model names to Bedrock model IDs
    model_id = case model
    when 'claude-opus-4-1', 'claude-opus-4-1-20250805'
      'us.anthropic.claude-opus-4-1-20250805-v1:0'
    when 'claude-3-5-sonnet', 'claude-3.5-sonnet'
      'us.anthropic.claude-3-5-sonnet-20241022-v2:0'
    when 'claude-3-haiku'
      'us.anthropic.claude-3-5-haiku-20241022-v1:0'
    else
      'us.anthropic.claude-3-5-sonnet-20241022-v2:0'
    end
    
    # Messages are already in converse format from our formatting
    # Just ensure they're properly structured
    converse_messages = messages.map do |msg|
      {
        role: msg[:role],
        content: msg[:content].is_a?(Array) ? msg[:content] : [{ text: msg[:content] }]
      }
    end
    
    # Build payload for converse
    payload = {
      model_id: model_id,
      messages: converse_messages,
      inference_config: {
        max_tokens: max_tokens,
        temperature: temperature
      }
    }
    
    # Add system prompt if present
    if system_prompt.present?
      payload[:system] = [{ text: system_prompt }]
    end
    
    # Add tools if provided (required when using tool results)
    if tools.any?
      payload[:tool_config] = {
        tools: format_tools_for_bedrock(tools),
        tool_choice: { auto: {} }
      }
    end
    
    Rails.logger.info "Sending non-streaming request to Bedrock Claude (#{model_id}) using converse"
    
    begin
      response = @client.converse(payload)
      
      # Extract the text from the response
      content = response.output.message.content.map do |content_block|
        content_block.text if content_block.respond_to?(:text)
      end.compact.join('')
      
      Rails.logger.info "Bedrock converse response received: #{content.length} characters"
      
      content
    rescue Aws::BedrockRuntime::Errors::ServiceError => e
      Rails.logger.error "Bedrock API Error: #{e.message}"
      raise "Bedrock API Error: #{e.message}"
    rescue StandardError => e
      Rails.logger.error "Unexpected error from Bedrock: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise "Failed to get response from Bedrock: #{e.message}"
    end
  end

  def send_message_streaming(system_prompt, messages, model: 'claude-opus-4-1', max_tokens: 4000, temperature: 0.7, json_mode: false, tools: [], &block)
    # Map model names to Bedrock model IDs
    model_id = case model
    when 'claude-opus-4-1', 'claude-opus-4-1-20250805'
      'us.anthropic.claude-opus-4-1-20250805-v1:0'
    when 'claude-3-5-sonnet', 'claude-3.5-sonnet'
      'us.anthropic.claude-3-5-sonnet-20241022-v2:0'
    when 'claude-3-haiku'
      'us.anthropic.claude-3-5-haiku-20241022-v1:0'
    else
      'us.anthropic.claude-3-5-sonnet-20241022-v2:0'
    end

    # Format messages for Claude
    formatted_messages = format_messages_for_claude(messages)
    
    # Build the request body
    request_body = {
      anthropic_version: "bedrock-2023-05-31",
      messages: formatted_messages,
      max_tokens: max_tokens,
      temperature: temperature
    }
    
    request_body[:system] = system_prompt if system_prompt.present?

    Rails.logger.info "Sending streaming request to Bedrock Claude (#{model_id}) using converse_stream"

    begin
      # Format messages for converse API (different format than invoke_model)
      converse_messages = messages.map do |msg|
        {
          role: msg[:role] == 'system' ? 'user' : msg[:role],
          content: msg[:content].is_a?(Array) ? msg[:content] : [{ text: msg[:content] }]
        }
      end
      
      # Build payload for converse_stream
      payload = {
        model_id: model_id,
        messages: converse_messages,
        inference_config: {
          max_tokens: max_tokens,
          temperature: temperature
        }
      }
      
      # Add system prompt if present
      if system_prompt.present?
        payload[:system] = [{ text: system_prompt }]
      end
      
      # Add tools if provided
      if tools.any?
        payload[:tool_config] = {
          tools: format_tools_for_bedrock(tools),
          tool_choice: { auto: {} }
        }
      end

      # Buffer for accumulating content
      buffer = ""
      start_time = Time.now
      chunk_count = 0
      
      # Use converse_stream for true streaming
      @client.converse_stream(payload) do |stream|
        stream.on_error_event do |event|
          Rails.logger.error "Bedrock stream error: #{event.inspect}"
          raise BedrockError, "Streaming error: #{event.error_message || 'Unknown error'}"
        end
        
        stream.on_event do |event|
          case event.event_type
          when :content_block_delta
            if event.delta.respond_to?(:text) && event.delta.text
              content = event.delta.text
              buffer += content
              
              # Log timing
              chunk_count += 1
              elapsed = (Time.now - start_time).round(3)
              Rails.logger.info "Bedrock chunk ##{chunk_count} at #{elapsed}s: #{content.length} chars"
              
              # Yield content chunk immediately
              yield(type: :content, content: content)
            elsif event.delta.respond_to?(:tool_use) && event.delta.tool_use
              # Handle tool use chunks
              tool_use = event.delta.tool_use
              yield(type: :tool_use, tool_use: tool_use)
            end
          when :content_block_start
            if event.start && event.start.respond_to?(:tool_use)
              # Tool use is starting
              tool_info = event.start.tool_use
              yield(type: :tool_use_start, tool_id: tool_info.tool_use_id, tool_name: tool_info.name)
            end
          when :message_stop
            # Message complete
            total_elapsed = (Time.now - start_time).round(3)
            Rails.logger.info "Bedrock streaming complete: #{chunk_count} chunks in #{total_elapsed}s"
            yield(type: :complete, content: buffer)
          when :metadata
            # Can log metadata if needed
            Rails.logger.debug "Bedrock metadata: #{event.inspect}"
          end
        end
      end
      
      buffer
    rescue Aws::BedrockRuntime::Errors::ServiceError => e
      Rails.logger.error "Bedrock streaming error: #{e.message}"
      raise BedrockError, "Bedrock API Error: #{e.message}"
    rescue => e
      Rails.logger.error "Unexpected Bedrock streaming error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise BedrockError, "Unexpected error: #{e.message}"
    end
  end

  private
  
  def format_tools_for_bedrock(tools)
    tools.map do |tool|
      {
        tool_spec: {
          name: tool[:name],
          description: tool[:description],
          input_schema: {
            json: tool[:parameters] || {
              type: "object",
              properties: {},
              required: []
            }
          }
        }
      }
    end
  end
  
  def format_messages_for_claude(messages)
    # Ensure messages is an array
    messages_array = case messages
    when Array
      messages
    when String
      [{ role: 'user', content: messages }]
    else
      [{ role: 'user', content: messages.to_s }]
    end

    # Claude on Bedrock expects specific format with content as array containing type
    Rails.logger.debug "🔍 format_messages_for_claude input: #{messages_array.inspect}" if Rails.env.development?
    
    # Check if messages are already properly formatted
    if messages_array.all? { |msg| 
      msg.is_a?(Hash) && 
      msg[:content].is_a?(Array) && 
      msg[:content].all? { |item| item.is_a?(Hash) && item[:type] }
    }
      Rails.logger.debug "🔍 Messages already properly formatted, returning as-is" if Rails.env.development?
      return messages_array
    end
    
    formatted = messages_array.map do |msg|
      content = msg[:content] || msg['content']
      
      Rails.logger.debug "🔍 Processing message content: #{content.inspect}" if Rails.env.development?
      
      # Format content for Bedrock API
      formatted_content = if content.is_a?(Array)
        # Check if array items already have 'type' field, if not fix them
        content.map do |item|
          if item.is_a?(Hash) && (item[:type] || item['type'])
            # Already correctly formatted - ensure keys are symbols and text is not nil
            text_content = (item[:text] || item['text'])
            { type: (item[:type] || item['type']).to_s, text: text_content || '' }
          elsif item.is_a?(Hash) && (item[:text] || item['text'])
            text_value = (item[:text] || item['text'])
            { type: 'text', text: text_value || '' }  # Fix missing type field
          elsif item.is_a?(String)
            { type: 'text', text: item }
          else
            { type: 'text', text: item.to_s }
          end
        end
      elsif content.is_a?(String)
        # Convert string to required format
        [{ type: 'text', text: content }]
      else
        # Convert other types to string first
        [{ type: 'text', text: content.to_s }]
      end
      
      result = {
        role: (msg[:role] || msg['role'] || 'user').to_s,
        content: formatted_content
      }
      
      Rails.logger.debug "🔍 Formatted message: #{result.inspect}" if Rails.env.development?
      result
    end
    
    Rails.logger.debug "🔍 Final formatted messages: #{formatted.inspect}" if Rails.env.development?
    formatted
  end
end
