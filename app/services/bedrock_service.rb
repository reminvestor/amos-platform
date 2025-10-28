require "aws-sdk-bedrockruntime"
require "json"

class BedrockService

  attr_reader :model_registry

  # Available Bedrock models with their characteristics
  AVAILABLE_MODELS = {
    'claude-sonnet-4-5' => {
      id: 'global.anthropic.claude-sonnet-4-5-20250929-v1:0',
      name: 'Claude Sonnet 4.5',
      description: 'Latest model, best for complex tasks',
      max_tokens: 25000,
      cost_per_1m_input: 3.00,
      cost_per_1m_output: 15.00,
      supports_vision: false,
      supports_tools: true,
      supports_caching: false,  # Global endpoint limitation
      endpoint_type: 'global'
    },
    'claude-opus-4-1' => {
      id: 'us.anthropic.claude-opus-4-1-20250805-v1:0',
      name: 'Claude Opus 4.1',
      description: 'Most capable, includes vision',
      max_tokens: 25000,
      cost_per_1m_input: 15.00,
      cost_per_1m_output: 75.00,
      supports_vision: true,
      supports_tools: true,
      supports_caching: true,
      endpoint_type: 'regional'
    },
    'claude-3-5-sonnet' => {
      id: 'us.anthropic.claude-3-5-sonnet-20241022-v2:0',
      name: 'Claude 3.5 Sonnet',
      description: 'Fast and capable, supports caching',
      max_tokens: 8192,
      cost_per_1m_input: 3.00,
      cost_per_1m_output: 15.00,
      supports_vision: true,
      supports_tools: true,
      supports_caching: true,
      endpoint_type: 'regional'
    },
    'claude-3-haiku' => {
      id: 'us.anthropic.claude-3-5-haiku-20241022-v1:0',
      name: 'Claude 3.5 Haiku',
      description: 'Fastest, most affordable',
      max_tokens: 8192,
      cost_per_1m_input: 0.80,
      cost_per_1m_output: 4.00,
      supports_vision: false,
      supports_tools: true,
      supports_caching: true,
      endpoint_type: 'regional'
    }
  }.freeze

  # Model fallback chain: Try models from fastest to most robust
  # If a model fails due to throttling, timeout, or unavailability, automatically retry with the next model
  MODEL_FALLBACK_CHAIN = [
    'claude-3-haiku',      # Fastest, cheapest - try first
    'claude-3-5-sonnet',   # Fast, capable - good backup
    'claude-sonnet-4-5',   # Latest, powerful - reliable fallback
    'claude-opus-4-1'      # Most robust - last resort
  ].freeze

  def initialize(custom_model_id: nil, user: nil, entity: nil)
    @client = Aws::BedrockRuntime::Client.new(
      region: ENV["AWS_REGION"] || "us-east-1",
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

    # Platform integration
    @model_registry = Agents::Platform::ModelRegistry.instance if defined?(Agents::Platform::ModelRegistry)
    @custom_model_id = custom_model_id
    @user = user
    @entity = entity
    @resource_manager = ResourceManager.new(entity) if entity
  end

  # Get the next model in the fallback chain
  # Returns nil if no more fallback options
  def get_next_fallback_model(current_model, attempted_models = [])
    # Normalize current model name
    normalized_current = current_model.to_s.gsub('.', '-')

    # Find current position in chain
    current_index = MODEL_FALLBACK_CHAIN.index(normalized_current)

    # If not in chain or at end of chain, start from beginning
    if current_index.nil?
      # Try to find first model not yet attempted
      next_model = MODEL_FALLBACK_CHAIN.find { |m| !attempted_models.include?(m) }
      return next_model
    end

    # Try next models in chain that haven't been attempted
    ((current_index + 1)...MODEL_FALLBACK_CHAIN.length).each do |i|
      candidate = MODEL_FALLBACK_CHAIN[i]
      return candidate unless attempted_models.include?(candidate)
    end

    # No more fallback options
    nil
  end

  # Main method to send messages to Claude via Bedrock
  def send_message(system_prompt, messages, model: "claude-sonnet-4-5", max_tokens: 10000, temperature: 0.7, json_mode: false, stream: false, &block)
    # Use custom model if specified
    if @custom_model_id && @model_registry
      return send_via_platform(system_prompt, messages, model: @custom_model_id, max_tokens: max_tokens, temperature: temperature, json_mode: json_mode, stream: stream, &block)
    end

    if stream && block_given?
      send_message_streaming(system_prompt, messages, model: model, max_tokens: max_tokens, temperature: temperature, json_mode: json_mode, &block)
    else
      send_message_non_streaming(system_prompt, messages, model: model, max_tokens: max_tokens, temperature: temperature, json_mode: json_mode)
    end
  end

  # Complete method for simple API
  # Send message with image (for vision/OCR)
  # Uses Claude Opus 4.1 which supports vision (Sonnet 4.5 is text-only)
  def send_message_with_image(prompt, base64_image, media_type = 'image/png')
    messages = [
      {
        role: 'user',
        content: [
          {
            type: 'image',
            source: {
              type: 'base64',
              media_type: media_type,
              data: base64_image
            }
          },
          {
            type: 'text',
            text: prompt
          }
        ]
      }
    ]

    # Use Opus 4.1 for vision (has "Text Vision" capability)
    # Higher token limit for large documents
    complete(messages: messages, max_tokens: 10000, model: 'claude-opus-4-1')
  end

  def complete(messages:, temperature: 0.7, max_tokens: 1000, model: nil)
    model_to_use = @custom_model_id || model || "claude-3-sonnet"

    # Extract system prompt if present
    system_prompt = nil
    user_messages = messages

    if messages.first && messages.first[:role] == "system"
      system_prompt = messages.first[:content]
      user_messages = messages[1..]
    end

    send_message(system_prompt, user_messages, model: model_to_use, max_tokens: max_tokens, temperature: temperature, stream: false)
  end

  private

  def send_message_non_streaming(system_prompt, messages, model: "claude-sonnet-4-5", max_tokens: 10000, temperature: 0.7, json_mode: false)
    # Map model names to Bedrock model IDs
    # Using global inference profiles for Claude Sonnet 4.5
    model_id = case model
    when "claude-sonnet-4-5", "claude-sonnet-4.5"
      "global.anthropic.claude-sonnet-4-5-20250929-v1:0"
    when "claude-opus-4-1", "claude-opus-4-1-20250805"
      "us.anthropic.claude-opus-4-1-20250805-v1:0"
    when "claude-3-5-sonnet", "claude-3.5-sonnet"
      "us.anthropic.claude-3-5-sonnet-20241022-v2:0"
    when "claude-3-haiku"
      "us.anthropic.claude-3-5-haiku-20241022-v1:0"
    else
      # Default to Claude Sonnet 4.5 (latest)
      "global.anthropic.claude-sonnet-4-5-20250929-v1:0"
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
        content_type: "application/json",
        accept: "application/json"
      )

      # Parse the response
      response_body = JSON.parse(response.body.read)
      content = response_body.dig("content", 0, "text")

      # Track token usage if available in response
      if response_body["usage"]
        tokens = {
          input: response_body["usage"]["input_tokens"] || 0,
          output: response_body["usage"]["output_tokens"] || 0
        }

        if @user && @entity && @resource_manager
          # Track tokens in resource manager (updates entity total)
          @resource_manager.track_tokens(@user, model_id, tokens, {
            stream: false,
            method: "invoke_model",
            timestamp: Time.current
          })
          
          # Log AI usage for observability and billing
          AiUsageLog.log_usage(
            entity: @entity,
            user: @user,
            model: model_id,
            input_tokens: tokens[:input],
            output_tokens: tokens[:output],
            duration_ms: nil, # Will add timing in next iteration
            request_type: 'chat',
            scout_message: nil, # Will link to scout_message if available
            metadata: {
              method: 'invoke_model',
              stream: false,
              cache_creation: response_body["usage"]["cache_write_input_tokens"] || 0,
              cache_read: response_body["usage"]["cache_read_input_tokens"] || 0
            }
          )
        end

        Rails.logger.info "Token usage - Input: #{tokens[:input]}, Output: #{tokens[:output]}"
      end

      Rails.logger.info "Bedrock response received: #{content&.length || 0} characters"

      # Log first 500 chars for debugging multi-step plans
      if content && content.length > 100
        Rails.logger.info "🔍 Response preview: #{content[0..500]}"
      end

      content
    rescue Aws::BedrockRuntime::Errors::ThrottlingException => e
      Rails.logger.error "Bedrock throttling: #{e.message}"
      raise AmosErrors::BedrockThrottlingError.new(context: { request_id: e.context&.request_id })
    rescue Aws::BedrockRuntime::Errors::ServiceUnavailableException => e
      Rails.logger.error "Bedrock unavailable: #{e.message}"
      raise AmosErrors::BedrockUnavailableError.new(context: { request_id: e.context&.request_id })
    rescue Timeout::Error, Seahorse::Client::NetworkingError => e
      Rails.logger.error "Bedrock timeout: #{e.message}"
      raise AmosErrors::BedrockTimeoutError.new(context: { error: e.class.name })
    rescue Aws::BedrockRuntime::Errors::ServiceError => e
      Rails.logger.error "Bedrock API Error: #{e.message}"
      raise AmosErrors::BedrockError.new(e.message, context: { error_code: e.code, request_id: e.context&.request_id })
    rescue StandardError => e
      Rails.logger.error "Unexpected error from Bedrock: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise AmosErrors::BedrockError.new("Unexpected error: #{e.message}", context: { error_class: e.class.name })
    end
  end

  # Generate images using Amazon Titan
  def generate_image(prompt, size: "1024x1024", style: "photographic")
    # Map sizes to Titan's supported dimensions
    width, height = case size
    when "1024x1024"
      [ 1024, 1024 ]
    when "1024x1792", "1792x1024"
      size.include?("1792x1024") ? [ 1792, 1024 ] : [ 1024, 1792 ]
    when "768x768"
      [ 768, 768 ]
    when "512x512"
      [ 512, 512 ]
    else
      [ 1024, 1024 ] # Default
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
        model_id: "amazon.titan-image-generator-v2:0",
        body: request_body.to_json,
        content_type: "application/json",
        accept: "application/json"
      )

      response_body = JSON.parse(response.body.read)

      # Titan returns base64 encoded images
      if response_body["images"] && response_body["images"].first
        base64_image = response_body["images"].first
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
    image_data = if image_url.start_with?("data:image")
      # Already base64
      image_url.split(",").last
    else
      # Download and convert to base64
      require "open-uri"
      require "base64"

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
    send_message(nil, messages, model: "claude-3-5-sonnet", max_tokens: 300)
  rescue => e
    Rails.logger.error "Failed to analyze image: #{e.message}"
    "Image analysis unavailable"
  end

  public

  # Non-streaming version using converse API (for tool continuation)
  def send_message_converse(system_prompt, messages, model: "claude-sonnet-4-5", max_tokens: 10000, temperature: 0.7, tools: [])
    # Map model names to Bedrock model IDs
    model_id = case model
    when "claude-sonnet-4-5", "claude-sonnet-4.5"
      "global.anthropic.claude-sonnet-4-5-20250929-v1:0"
    when "claude-opus-4-1", "claude-opus-4-1-20250805"
      "us.anthropic.claude-opus-4-1-20250805-v1:0"
    when "claude-3-5-sonnet", "claude-3.5-sonnet"
      "us.anthropic.claude-3-5-sonnet-20241022-v2:0"
    when "claude-3-haiku"
      "us.anthropic.claude-3-5-haiku-20241022-v1:0"
    else
      "global.anthropic.claude-sonnet-4-5-20250929-v1:0"
    end

    # Messages are already in converse format from our formatting
    # Just ensure they're properly structured
    converse_messages = messages.map do |msg|
      {
        role: msg[:role],
        content: msg[:content].is_a?(Array) ? msg[:content] : [ { text: msg[:content] } ]
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
      payload[:system] = [ { text: system_prompt } ]
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
      end.compact.join("")

      # Track token usage if available
      if response.respond_to?(:usage) && response.usage
        tokens = {
          input: response.usage.input_tokens || 0,
          output: response.usage.output_tokens || 0
        }

        if @user && @entity && @resource_manager
          @resource_manager.track_tokens(@user, model_id, tokens, {
            stream: false,
            method: "converse",
            timestamp: Time.current
          })
        end

        Rails.logger.info "Token usage - Input: #{tokens[:input]}, Output: #{tokens[:output]}"
      end

      Rails.logger.info "Bedrock converse response received: #{content.length} characters"

      content
    rescue Aws::BedrockRuntime::Errors::ThrottlingException => e
      Rails.logger.error "Bedrock throttling: #{e.message}"
      raise AmosErrors::BedrockThrottlingError.new(context: { request_id: e.context&.request_id })
    rescue Aws::BedrockRuntime::Errors::ServiceUnavailableException => e
      Rails.logger.error "Bedrock unavailable: #{e.message}"
      raise AmosErrors::BedrockUnavailableError.new(context: { request_id: e.context&.request_id })
    rescue Timeout::Error, Seahorse::Client::NetworkingError => e
      Rails.logger.error "Bedrock timeout: #{e.message}"
      raise AmosErrors::BedrockTimeoutError.new(context: { error: e.class.name })
    rescue Aws::BedrockRuntime::Errors::ServiceError => e
      Rails.logger.error "Bedrock API Error: #{e.message}"
      raise AmosErrors::BedrockError.new(e.message, context: { error_code: e.code, request_id: e.context&.request_id })
    rescue StandardError => e
      Rails.logger.error "Unexpected error from Bedrock: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise AmosErrors::BedrockError.new("Unexpected error: #{e.message}", context: { error_class: e.class.name })
    end
  end

  def send_message_streaming(system_prompt, messages, model: "claude-sonnet-4-5", max_tokens: 10000, temperature: 0.7, json_mode: false, tools: [], enable_prompt_caching: false, &block)
    # Track attempted models for fallback
    attempted_models = []
    current_model = model
    last_error = nil

    # Retry loop with model fallback
    loop do
      begin
        # Check if prompt caching is enabled (default: false - disabled due to AWS API limitations)
        # The enable_prompt_caching parameter is kept for API compatibility but currently ignored
        caching_enabled = ENV.fetch('BEDROCK_PROMPT_CACHING_ENABLED', 'false') == 'true'

        # Normalize model name (handle variants like "claude-sonnet-4.5")
        normalized_model = current_model.to_s.gsub('.', '-')

        # Track this attempt
        attempted_models << normalized_model unless attempted_models.include?(normalized_model)

        # Get model configuration
        model_config = AVAILABLE_MODELS[normalized_model] || AVAILABLE_MODELS['claude-sonnet-4-5']
        model_id = model_config[:id]

        # Cap max_tokens to the model's limit
        model_max_tokens = model_config[:max_tokens] || 25000
        effective_max_tokens = [max_tokens, model_max_tokens].min

        # Log model selection with caching status
        if caching_enabled && !model_config[:supports_caching]
          Rails.logger.info "⚠️  #{model_config[:name]} doesn't support caching (#{model_config[:endpoint_type]} endpoint)"
        elsif caching_enabled && model_config[:supports_caching]
          Rails.logger.info "💾 Using #{model_config[:name]} with caching enabled"
        else
          Rails.logger.info "✅ Using #{model_config[:name]} (caching disabled)"
        end

        if effective_max_tokens < max_tokens
          Rails.logger.info "⚠️  Requested max_tokens (#{max_tokens}) exceeds model limit (#{model_max_tokens}), using #{effective_max_tokens}"
        end

        # Format messages for Claude
        formatted_messages = format_messages_for_claude(messages)

        # Filter out messages with empty content arrays
        formatted_messages = formatted_messages.reject do |msg|
          msg[:content].nil? || msg[:content].empty? ||
          (msg[:content].is_a?(Array) && msg[:content].all? { |c|
            # Check if this is a text block with empty text
            c[:type] == "text" && c[:text].to_s.strip.empty?
          })
        end

        # Build the request body
        request_body = {
          anthropic_version: "bedrock-2023-05-31",
          messages: formatted_messages,
          max_tokens: effective_max_tokens,
          temperature: temperature
        }

        request_body[:system] = system_prompt if system_prompt.present?

        Rails.logger.info "Sending streaming request to Bedrock Claude (#{model_id}) using converse_stream"

        # Convert messages to converse API format
      # The converse API expects content to be an array of content blocks
      # where each block is directly the content type (text, image, etc)
      converse_messages = formatted_messages.reject { |msg|
        msg[:content].nil? || msg[:content].empty? ||
        (msg[:content].is_a?(Array) && msg[:content].all? { |c|
          # Check if this is a text block with empty text
          c[:type] == "text" && c[:text].to_s.strip.empty?
        })
      }.map do |msg|
        content_blocks = msg[:content].map do |block|
          case block[:type]
          when "text"
            { text: block[:text] }
          when "tool_use"
            # Convert tool_use format
            tool_data = block[:tool_use]
            {
              tool_use: {
                tool_use_id: tool_data[:id],
                name: tool_data[:name],
                input: tool_data[:input]
              }
            }
          when "tool_result"
            # Convert tool_result format
            result_data = block[:tool_result]
            {
              tool_result: {
                tool_use_id: result_data[:tool_use_id],
                content: result_data[:content].is_a?(Array) ?
                  result_data[:content].map { |c|
                    c[:type] == "text" ? { text: c[:text] } : c
                  } :
                  [ { text: result_data[:content].to_s } ]
              }
            }
          else
            # Handle other content types
            block
          end
        end

        {
          role: msg[:role] == "system" ? "user" : msg[:role],
          content: content_blocks
        }
      end

      Rails.logger.info "🔍 Original formatted messages count: #{formatted_messages.length}"
      Rails.logger.info "🔍 Converse messages count after conversion: #{converse_messages.length}"
      Rails.logger.info "🔍 Converse messages structure: #{converse_messages.to_json}"

      # Build payload for converse_stream
      payload = {
        model_id: model_id,
        messages: converse_messages,
        inference_config: {
          max_tokens: effective_max_tokens,
          temperature: temperature
        }
      }

      # Determine if caching should be used (both enabled AND supported by model)
      use_caching = caching_enabled && model_config[:supports_caching]

      # Add system prompt if present
      if system_prompt.present?
        if use_caching
          # Add cache checkpoint after system prompt (requires 1024+ tokens)
          payload[:system] = [
            { text: system_prompt },
            { cachePoint: { type: "default" } }  # Cache everything up to here
          ]
          Rails.logger.info "💾 Prompt caching enabled for system prompt (~7000 tokens)"
        else
          # No caching - simple array with text
          payload[:system] = [{ text: system_prompt }]
        end
      end

      # Add tools if provided
      if tools.any?
        formatted_tools = format_tools_for_bedrock(tools)

        if use_caching
          # Add cache checkpoint after all tools (Claude supports up to 4 checkpoints)
          formatted_tools << { cachePoint: { type: "default" } }
          Rails.logger.info "💾 Prompt caching enabled for tools (~2500 tokens)"
        end

        payload[:tool_config] = {
          tools: formatted_tools,
          tool_choice: { auto: {} }
        }

        # DEBUG: Log tool names being sent (exclude cache checkpoint if present)
        tool_spec_tools = formatted_tools.select { |t| t.key?(:tool_spec) }
        tool_names = tool_spec_tools.map { |t| t.dig(:tool_spec, :name) }
        caching_status = use_caching ? "with caching" : "no caching"
        Rails.logger.info "🔧 Sending #{tool_names.length} tools to Claude (#{caching_status}): #{tool_names.join(', ')}"
      end

      # Buffer for accumulating content
      buffer = ""
      start_time = Time.now
      chunk_count = 0

      # Use converse_stream for true streaming
      @client.converse_stream(payload) do |stream|
        stream.on_error_event do |event|
          Rails.logger.error "Bedrock stream error: #{event.inspect}"
          raise AmosErrors::BedrockError.new("Streaming error: #{event.error_message || 'Unknown error'}")
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
            # Extract and track token usage if available
            if event.respond_to?(:usage) && event.usage
              usage = event.usage
              tokens = {
                input: usage.input_tokens || 0,
                output: usage.output_tokens || 0
              }

              # Extract cache statistics (AWS Bedrock Converse API field names)
              cache_write = usage.respond_to?(:cache_write_input_tokens_count) ? usage.cache_write_input_tokens_count : 0
              cache_read = usage.respond_to?(:cache_read_input_tokens_count) ? usage.cache_read_input_tokens_count : 0

              # Track tokens if we have user and entity
              if @user && @entity && @resource_manager
                # Track tokens in resource manager (updates entity total)
                @resource_manager.track_tokens(@user, model_id, tokens, {
                  stream: true,
                  timestamp: Time.current,
                  cache_write: cache_write,
                  cache_read: cache_read
                })
                
                # Log AI usage for observability and billing
                duration_ms = ((Time.now - start_time) * 1000).round
                cache_creation = usage.respond_to?(:cache_write_input_tokens) ? (usage.cache_write_input_tokens || 0) : 0
                cache_read = usage.respond_to?(:cache_read_input_tokens) ? (usage.cache_read_input_tokens || 0) : 0
                
                AiUsageLog.log_usage(
                  entity: @entity,
                  user: @user,
                  model: model_id,
                  input_tokens: tokens[:input],
                  output_tokens: tokens[:output],
                  duration_ms: duration_ms,
                  request_type: 'chat',
                  scout_message: nil,
                  metadata: {
                    method: 'invoke_model_with_response_stream',
                    stream: true,
                    chunks: chunk_count,
                    cache_creation: cache_creation,
                    cache_read: cache_read
                  }
                )
              end

              # Yield usage info including cache stats and model used (for fallback transparency)
              Rails.logger.info "🔍 BEDROCK: About to yield usage chunk with model_used=#{normalized_model.inspect}, model_name=#{model_config[:name].inspect}"
              yield(
                type: :usage,
                tokens: tokens,
                cache_write: cache_write,
                cache_read: cache_read,
                model_used: normalized_model,
                model_name: model_config[:name]
              ) if block_given?
              Rails.logger.info "🔍 BEDROCK: Usage chunk yielded successfully"

              # Enhanced logging with cache information
              if cache_write > 0 || cache_read > 0
                cache_hit_rate = tokens[:input] > 0 ? (cache_read.to_f / (tokens[:input] + cache_read) * 100).round(1) : 0
                savings = (cache_read * 0.9).round(0)  # 90% discount on cached tokens
                Rails.logger.info "💰 Token usage - Input: #{tokens[:input]}, Output: #{tokens[:output]} | Cache: #{cache_read} read (#{cache_hit_rate}% hit rate), #{cache_write} written | Savings: ~#{savings} tokens ($#{(savings * 0.0000075).round(4)})"
              else
                Rails.logger.info "Token usage - Input: #{tokens[:input]}, Output: #{tokens[:output]}"
              end
            end

            Rails.logger.debug "Bedrock metadata: #{event.inspect}"
          end
        end
      end

      buffer

        # Success! Return the buffer and exit the retry loop
        return buffer

      rescue Aws::BedrockRuntime::Errors::ThrottlingException,
             Aws::BedrockRuntime::Errors::ServiceUnavailableException,
             Timeout::Error,
             Seahorse::Client::NetworkingError => e

        # These are retryable errors - try to fallback to next model
        last_error = e
        error_type = e.class.name.split('::').last

        Rails.logger.warn "🔄 #{model_config[:name]} #{error_type}: #{e.message}"

        # Try to get next fallback model
        next_model = get_next_fallback_model(current_model, attempted_models)

        if next_model
          current_model = next_model
          next_model_config = AVAILABLE_MODELS[next_model]
          Rails.logger.info "♻️  Falling back to #{next_model_config[:name]}..."
          next  # Retry with new model
        else
          # No more fallback options
          Rails.logger.error "❌ All models failed. Attempted: #{attempted_models.join(', ')}"

          # Raise appropriate error based on last error type
          case last_error
          when Aws::BedrockRuntime::Errors::ThrottlingException
            raise AmosErrors::BedrockThrottlingError.new(context: { attempted_models: attempted_models })
          when Aws::BedrockRuntime::Errors::ServiceUnavailableException
            raise AmosErrors::BedrockUnavailableError.new(context: { attempted_models: attempted_models })
          when Timeout::Error, Seahorse::Client::NetworkingError
            raise AmosErrors::BedrockTimeoutError.new(context: { attempted_models: attempted_models })
          else
            raise AmosErrors::BedrockError.new("All models failed: #{last_error.message}", context: { attempted_models: attempted_models })
          end
        end

      rescue Aws::BedrockRuntime::Errors::ServiceError => e
        # Non-retryable AWS error
        Rails.logger.error "Bedrock streaming error: #{e.message}"
        raise AmosErrors::BedrockError.new("Bedrock API Error: #{e.message}")

      rescue StandardError => e
        # Unexpected error - don't retry
        Rails.logger.error "Unexpected Bedrock streaming error: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        raise AmosErrors::BedrockError.new("Unexpected error: #{e.message}")
      end
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
      [ { role: "user", content: messages } ]
    else
      [ { role: "user", content: messages.to_s } ]
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
      content = msg[:content] || msg["content"]

      Rails.logger.debug "🔍 Processing message content: #{content.inspect}" if Rails.env.development?

      # Format content for Bedrock API
      formatted_content = if content.is_a?(Array)
        # Check if array items already have 'type' field, if not fix them
        content.map do |item|
          if item.is_a?(Hash) && (item[:type] || item["type"])
            # Already correctly formatted - ensure keys are symbols and text is not nil
            text_content = (item[:text] || item["text"])
            { type: (item[:type] || item["type"]).to_s, text: text_content || "" }
          elsif item.is_a?(Hash) && (item[:text] || item["text"])
            text_value = (item[:text] || item["text"])
            { type: "text", text: text_value || "" }  # Fix missing type field
          elsif item.is_a?(String)
            { type: "text", text: item }
          else
            { type: "text", text: item.to_s }
          end
        end
      elsif content.is_a?(String)
        # Convert string to required format
        [ { type: "text", text: content } ]
      else
        # Convert other types to string first
        [ { type: "text", text: content.to_s } ]
      end

      result = {
        role: (msg[:role] || msg["role"] || "user").to_s,
        content: formatted_content
      }

      Rails.logger.debug "🔍 Formatted message: #{result.inspect}" if Rails.env.development?
      result
    end

    Rails.logger.debug "🔍 Final formatted messages: #{formatted.inspect}" if Rails.env.development?
    formatted
  end

  # Send via platform model registry
  def send_via_platform(system_prompt, messages, model:, max_tokens:, temperature:, json_mode:, stream:, &block)
    prompt_config = {
      system_prompt: system_prompt,
      messages: format_platform_messages(system_prompt, messages),
      max_tokens: max_tokens,
      temperature: temperature,
      json_mode: json_mode
    }

    if stream && block_given?
      @model_registry.invoke_model_stream(model, prompt_config, user: @user, entity: @entity) do |chunk|
        yield chunk[:content] if chunk[:content]
      end
    else
      result = @model_registry.invoke_model(model, prompt_config, user: @user, entity: @entity)

      # Format response to match expected format
      {
        "id" => "platform-#{SecureRandom.hex(16)}",
        "model" => model,
        "choices" => [ {
          "message" => {
            "role" => "assistant",
            "content" => result[:content]
          },
          "finish_reason" => result[:stop_reason] || "stop"
        } ],
        "usage" => result[:usage]
      }
    end
  rescue => e
    Rails.logger.error "Platform model invocation failed: #{e.message}"
    raise AmosErrors::BedrockError.new("Platform model error: #{e.message}")
  end

  # Format messages for platform models
  def format_platform_messages(system_prompt, messages)
    formatted = []

    # Add system prompt as first message if present
    if system_prompt.present?
      formatted << { role: "system", content: system_prompt }
    end

    # Add user messages
    messages.each do |msg|
      formatted << {
        role: msg[:role] || "user",
        content: msg[:content] || msg[:text] || msg.to_s
      }
    end

    formatted
  end
end
