require "httparty"
require "json"

class OpenrouterService
  include HTTParty
  include WorkTokenTrackable

  base_uri "https://openrouter.ai/api/v1"

  # Cache TTL for dynamic model list
  MODELS_CACHE_TTL = 1.hour

  # Curated top models - Updated December 2025 with latest flagship models
  # These are used as primary council members for research
  MODELS = {
    openai: {
      id: "openai/gpt-4.1",
      name: "GPT-4.1",
      provider: "OpenAI",
      cost_per_1m_input: 2.00,
      cost_per_1m_output: 8.00
    },
    anthropic: {
      id: "anthropic/claude-sonnet-4.6",
      name: "Claude Sonnet 4.6",
      provider: "Anthropic",
      cost_per_1m_input: 3.00,
      cost_per_1m_output: 15.00
    },
    google: {
      id: "google/gemini-2.5-pro",
      name: "Gemini 2.5 Pro",
      provider: "Google",
      cost_per_1m_input: 1.25,
      cost_per_1m_output: 10.00
    },
    meta: {
      id: "meta-llama/llama-4-scout",
      name: "Llama 4 Scout",
      provider: "Meta",
      cost_per_1m_input: 0.15,
      cost_per_1m_output: 0.60
    },
    xai: {
      id: "x-ai/grok-3",
      name: "Grok 3",
      provider: "xAI",
      cost_per_1m_input: 3.00,
      cost_per_1m_output: 15.00
    },
    deepseek: {
      id: "deepseek/deepseek-r1",
      name: "DeepSeek R1",
      provider: "DeepSeek",
      cost_per_1m_input: 0.55,
      cost_per_1m_output: 2.19
    },
    # Additional reasoning models
    qwq: {
      id: "qwen/qwq-32b",
      name: "QwQ 32B",
      provider: "Alibaba",
      cost_per_1m_input: 0.12,
      cost_per_1m_output: 0.18
    },
    deepseek_v3: {
      id: "deepseek/deepseek-chat",
      name: "DeepSeek V3",
      provider: "DeepSeek",
      cost_per_1m_input: 0.14,
      cost_per_1m_output: 0.28
    },
    # Fallback models (used when primary models fail)
    openai_fallback: {
      id: "openai/gpt-4o",
      name: "GPT-4o",
      provider: "OpenAI",
      cost_per_1m_input: 2.50,
      cost_per_1m_output: 10.00
    },
    anthropic_fallback: {
      id: "anthropic/claude-sonnet-4.6",
      name: "Claude Sonnet 4.6",
      provider: "Anthropic",
      cost_per_1m_input: 3.00,
      cost_per_1m_output: 15.00
    },
    google_fallback: {
      id: "google/gemini-2.0-flash-001",
      name: "Gemini 2.0 Flash",
      provider: "Google",
      cost_per_1m_input: 0.10,
      cost_per_1m_output: 0.40
    },
    meta_fallback: {
      id: "meta-llama/llama-3.3-70b-instruct",
      name: "Llama 3.3 70B",
      provider: "Meta",
      cost_per_1m_input: 0.40,
      cost_per_1m_output: 0.40
    },
    xai_fallback: {
      id: "x-ai/grok-2-1212",
      name: "Grok 2",
      provider: "xAI",
      cost_per_1m_input: 2.00,
      cost_per_1m_output: 10.00
    },
    mistral: {
      id: "mistralai/mistral-large-2411",
      name: "Mistral Large",
      provider: "Mistral",
      cost_per_1m_input: 2.00,
      cost_per_1m_output: 6.00
    }
  }.freeze

  # Fallback chain for each primary model - tries these in order if primary fails
  FALLBACK_CHAINS = {
    openai: [:openai_fallback, :mistral],
    anthropic: [:anthropic_fallback, :mistral],
    google: [:google_fallback, :mistral],
    meta: [:meta_fallback, :mistral],
    xai: [:xai_fallback, :mistral],
    deepseek: [:mistral, :google_fallback]
  }.freeze

  attr_reader :api_key, :user, :entity

  def initialize(user: nil, entity: nil)
    @api_key = Rails.application.credentials.openrouter&.api_key || ENV["OPENROUTER_API_KEY"]
    @user = user
    @entity = entity

    if @api_key.blank?
      raise "OpenRouter API key not found. Please set OPENROUTER_API_KEY environment variable or add to credentials."
    end

    self.class.default_options.merge!(timeout: 120)
  end

  # Send a message to a specific model via OpenRouter
  def send_message(system_prompt, messages, model_key: :openai, max_tokens: 4000, temperature: 0.7)
    model_config = MODELS[model_key.to_sym]
    raise ArgumentError, "Unknown model: #{model_key}. Available: #{MODELS.keys.join(', ')}" unless model_config

    # Normalize messages to array format
    messages_array = case messages
    when Array
      messages
    when String
      [{ role: "user", content: messages }]
    else
      [{ role: "user", content: messages.to_s }]
    end

    # Build formatted messages with system prompt
    formatted_messages = []
    formatted_messages << { role: "system", content: system_prompt } if system_prompt.present?
    formatted_messages.concat(messages_array)

    body = {
      model: model_config[:id],
      messages: formatted_messages,
      max_tokens: max_tokens,
      temperature: temperature
    }

    headers = {
      "Authorization" => "Bearer #{@api_key}",
      "Content-Type" => "application/json",
      "HTTP-Referer" => ENV.fetch("APP_HOST", "https://agentmarketplace.ai"),
      "X-Title" => "Scout Research Council"
    }

    Rails.logger.info "📡 OpenRouter request to #{model_config[:name]} (#{model_config[:id]})"
    start_time = Time.current

    begin
      response = self.class.post("/chat/completions", {
        body: body.to_json,
        headers: headers,
        timeout: 120
      })

      duration_ms = ((Time.current - start_time) * 1000).round(2)
      Rails.logger.info "✅ OpenRouter #{model_config[:name]} responded in #{duration_ms}ms"

      if response.success?
        parsed = response.parsed_response
        content = parsed.dig("choices", 0, "message", "content")
        usage = parsed["usage"] || {}

        # Track token usage for billing if user is set
        input_tokens = usage["prompt_tokens"] || 0
        output_tokens = usage["completion_tokens"] || 0

        if input_tokens > 0 || output_tokens > 0
          track_ai_work_tokens(
            input_tokens: input_tokens,
            output_tokens: output_tokens,
            model: model_config[:id],
            source: "openrouter_council_research",
            metadata: {
              model_key: model_key,
              model_name: model_config[:name],
              provider: model_config[:provider],
              duration_ms: duration_ms
            }
          )
        end

        {
          success: true,
          content: content,
          model: model_key,
          model_name: model_config[:name],
          provider: model_config[:provider],
          tokens: {
            input: input_tokens,
            output: output_tokens,
            total: usage["total_tokens"]
          },
          duration_ms: duration_ms,
          cost_estimate: calculate_cost(usage, model_config)
        }
      else
        error_msg = parse_error(response)
        Rails.logger.error "❌ OpenRouter #{model_config[:name]} error: #{error_msg}"

        {
          success: false,
          error: error_msg,
          model: model_key,
          model_name: model_config[:name],
          provider: model_config[:provider],
          duration_ms: duration_ms
        }
      end
    rescue HTTParty::Error, SocketError, Timeout::Error => e
      duration_ms = ((Time.current - start_time) * 1000).round(2)
      Rails.logger.error "❌ OpenRouter #{model_config[:name]} network error: #{e.message}"

      {
        success: false,
        error: "Network error: #{e.message}",
        model: model_key,
        model_name: model_config[:name],
        provider: model_config[:provider],
        duration_ms: duration_ms
      }
    rescue StandardError => e
      duration_ms = ((Time.current - start_time) * 1000).round(2)
      Rails.logger.error "❌ OpenRouter #{model_config[:name]} unexpected error: #{e.class} - #{e.message}"

      {
        success: false,
        error: "Unexpected error: #{e.message}",
        model: model_key,
        model_name: model_config[:name],
        provider: model_config[:provider],
        duration_ms: duration_ms
      }
    end
  end

  # Send a message with automatic fallback to other models if primary fails
  # Returns the first successful response, trying fallback models in order
  def send_message_with_fallback(system_prompt, messages, model_key:, max_tokens: 4000, temperature: 0.7)
    # Build the chain: primary model + its fallbacks
    models_to_try = [model_key.to_sym]
    models_to_try.concat(FALLBACK_CHAINS[model_key.to_sym] || [])

    last_error = nil
    total_duration_ms = 0

    models_to_try.each_with_index do |try_model_key, index|
      is_fallback = index > 0
      model_config = MODELS[try_model_key]
      next unless model_config

      if is_fallback
        Rails.logger.info "🔄 Falling back to #{model_config[:name]} after #{MODELS[models_to_try[index - 1]]&.dig(:name)} failed"
      end

      result = send_message(system_prompt, messages, model_key: try_model_key, max_tokens: max_tokens, temperature: temperature)
      total_duration_ms += result[:duration_ms] || 0

      if result[:success]
        # Add metadata about fallback if used
        if is_fallback
          result[:used_fallback] = true
          result[:original_model_key] = model_key
          result[:original_model_name] = MODELS[model_key.to_sym]&.dig(:name)
          Rails.logger.info "✅ Fallback successful: #{model_config[:name]} responded for #{MODELS[model_key.to_sym]&.dig(:name)}"
        end
        result[:total_duration_ms] = total_duration_ms
        return result
      else
        last_error = result[:error]
        Rails.logger.warn "⚠️ #{model_config[:name]} failed: #{last_error}"
      end
    end

    # All models failed - return the last error
    primary_config = MODELS[model_key.to_sym] || MODELS[:openai]
    {
      success: false,
      error: "All models failed. Last error: #{last_error}",
      model: model_key,
      model_name: primary_config[:name],
      provider: primary_config[:provider],
      duration_ms: total_duration_ms,
      all_fallbacks_failed: true
    }
  end

  # Query multiple models in parallel using threads (with automatic fallback)
  # Each model slot will automatically try fallbacks if the primary model fails
  def query_models(system_prompt, user_message, model_keys: [:openai, :anthropic], max_tokens: 4000, temperature: 0.7)
    results = {}
    threads = []

    model_keys.each do |model_key|
      threads << Thread.new do
        Thread.current[:model_key] = model_key
        begin
          # Use fallback-enabled method for each model slot
          result = send_message_with_fallback(
            system_prompt,
            user_message,
            model_key: model_key,
            max_tokens: max_tokens,
            temperature: temperature
          )
          Thread.current[:result] = result
        rescue => e
          Thread.current[:result] = {
            success: false,
            error: e.message,
            model: model_key,
            model_name: MODELS[model_key]&.dig(:name) || model_key.to_s,
            provider: MODELS[model_key]&.dig(:provider) || "Unknown",
            all_fallbacks_failed: true
          }
        end
      end
    end

    threads.each do |thread|
      thread.join
      model_key = thread[:model_key]
      results[model_key] = thread[:result]
    end

    results
  end

  # List available primary models (excludes fallbacks)
  PRIMARY_MODEL_KEYS = [:openai, :anthropic, :google, :meta, :xai, :deepseek].freeze

  def available_models
    PRIMARY_MODEL_KEYS.map do |key|
      config = MODELS[key]
      {
        key: key,
        id: config[:id],
        name: config[:name],
        provider: config[:provider]
      }
    end
  end

  # Fetch all available models from OpenRouter API (for dynamic discovery)
  def self.fetch_all_models
    cache_key = "openrouter:all_models"
    cached = Rails.cache.read(cache_key)
    return cached if cached

    response = HTTParty.get(
      "https://openrouter.ai/api/v1/models",
      headers: { "Content-Type" => "application/json" },
      timeout: 30
    )

    if response.success?
      models = response.parsed_response["data"] || []
      result = models.map do |m|
        {
          id: m["id"],
          name: m["name"],
          context_length: m["context_length"],
          pricing: {
            input: m.dig("pricing", "prompt")&.to_f,
            output: m.dig("pricing", "completion")&.to_f
          },
          top_provider: m.dig("top_provider", "is_moderated")
        }
      end
      Rails.cache.write(cache_key, result, expires_in: MODELS_CACHE_TTL)
      result
    else
      Rails.logger.error "Failed to fetch OpenRouter models: #{response.code}"
      []
    end
  rescue => e
    Rails.logger.error "Error fetching OpenRouter models: #{e.message}"
    []
  end

  # Get model info by ID from API (with caching)
  def self.get_model_info(model_id)
    all_models = fetch_all_models
    all_models.find { |m| m[:id] == model_id }
  end

  # Test connection to OpenRouter
  def test_connection
    result = send_message("You are helpful.", "Reply with just 'OK'.", model_key: :meta, max_tokens: 10)
    result[:success]
  rescue => e
    Rails.logger.error "OpenRouter connection test failed: #{e.message}"
    false
  end

  private

  def calculate_cost(usage, model_config)
    return nil unless usage["prompt_tokens"] && usage["completion_tokens"]

    input_cost = (usage["prompt_tokens"] / 1_000_000.0) * model_config[:cost_per_1m_input]
    output_cost = (usage["completion_tokens"] / 1_000_000.0) * model_config[:cost_per_1m_output]
    (input_cost + output_cost).round(6)
  end

  def parse_error(response)
    parsed = response.parsed_response rescue nil
    if parsed.is_a?(Hash)
      parsed.dig("error", "message") || parsed["error"] || "HTTP #{response.code}"
    else
      "HTTP #{response.code}: #{response.body&.truncate(200)}"
    end
  end
end
