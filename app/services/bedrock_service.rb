require 'aws-sdk-bedrockruntime'
require 'json'

class BedrockService
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

  def send_message_streaming(system_prompt, messages, model: 'claude-opus-4-1', max_tokens: 4000, temperature: 0.7, json_mode: false, &block)
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

    Rails.logger.info "Sending streaming request to Bedrock Claude (#{model_id})"

    begin
      # Use invoke_model_with_response_stream for streaming
      response = @client.invoke_model_with_response_stream({
        model_id: model_id,
        content_type: "application/json",
        accept: "application/json",
        body: JSON.generate(request_body)
      })

      # Buffer for partial content
      buffer = ""
      
      # Process the streaming response
      response.body.each do |event|
        chunk = JSON.parse(event.bytes)
        
        if chunk['type'] == 'content_block_delta' && chunk['delta']
          content = chunk['delta']['text']
          buffer += content if content
          
          # Yield each chunk of text as it arrives
          yield(type: :content, content: content) if content
        elsif chunk['type'] == 'message_stop'
          # Message complete
          yield(type: :complete, content: buffer)
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

    # Claude on Bedrock expects specific format
    messages_array.map do |msg|
      {
        role: msg[:role] || 'user',
        content: msg[:content]
      }
    end
  end
end
