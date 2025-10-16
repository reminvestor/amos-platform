module Agents
  module Platform
    class ModelRegistry
      include Singleton

      def initialize
        @models = {}
        @custom_models = {}
        @mutex = Mutex.new

        # Register all Bedrock models
        register_bedrock_models
      end

      # Get available models for a user
      def available_models(user:, entity:)
        models = {}

        # Bedrock models (check permissions)
        models[:bedrock] = get_bedrock_models_for_user(user, entity)

        # Custom models via Bedrock's custom model import
        models[:custom] = get_custom_models(user, entity)

        # Bedrock marketplace models
        models[:marketplace] = get_marketplace_models(user, entity)

        models
      end

      # Register a custom model through Bedrock
      def register_custom_model(user:, entity:, model_config:)
        validate_custom_model!(model_config)

        model_id = "custom-#{entity.id}-#{SecureRandom.hex(8)}"

        case model_config[:type]
        when "bedrock_custom"
          # Use Bedrock's custom model import feature
          result = import_to_bedrock(model_config, model_id)
        when "bedrock_fine_tuned"
          # Use Bedrock's fine-tuning feature
          result = create_fine_tuned_model(model_config, model_id)
        when "external_endpoint"
          # Register external model that Bedrock can proxy to
          result = register_external_endpoint(model_config, model_id)
        else
          raise "Unsupported model type: #{model_config[:type]}"
        end

        if result[:success]
          # Save to database
          CustomModel.create!(
            user: user,
            entity: entity,
            model_id: model_id,
            bedrock_model_id: result[:bedrock_model_id],
            config: model_config,
            status: "active"
          )

          # Register locally
          @mutex.synchronize do
            @custom_models[model_id] = {
              bedrock_id: result[:bedrock_model_id],
              owner: entity,
              config: model_config,
              created_at: Time.current
            }
          end
        end

        result
      end

      # Execute inference using Bedrock
      def invoke_model(model_id, prompt_config, user:, entity:)
        model = find_model(model_id, user, entity)
        raise "Model not found or access denied" unless model

        # Track usage for billing
        usage_tracker = UsageTracker.new(user: user, entity: entity)

        begin
          # All models go through Bedrock's unified API
          response = bedrock_client.invoke_model(
            model_id: model[:bedrock_id],
            body: build_model_request(model, prompt_config).to_json,
            content_type: "application/json",
            accept: "application/json"
          )

          result = parse_model_response(model, response)

          # Track usage
          usage_tracker.track_inference(
            model_id: model_id,
            input_tokens: result[:usage][:input_tokens],
            output_tokens: result[:usage][:output_tokens],
            cost: calculate_cost(model, result[:usage])
          )

          result
        rescue Aws::BedrockRuntime::Errors::AccessDeniedException => e
          raise "Access denied to model #{model_id}. Please check your permissions."
        rescue Aws::BedrockRuntime::Errors::ThrottlingException => e
          raise "Rate limit exceeded. Please try again later."
        rescue => e
          Rails.logger.error "Model invocation failed: #{e.message}"
          raise "Model invocation failed: #{e.message}"
        end
      end

      # Stream inference using Bedrock
      def invoke_model_stream(model_id, prompt_config, user:, entity:, &block)
        model = find_model(model_id, user, entity)
        raise "Model not found or access denied" unless model

        usage_tracker = UsageTracker.new(user: user, entity: entity)
        total_tokens = 0

        begin
          response = bedrock_client.invoke_model_with_response_stream(
            model_id: model[:bedrock_id],
            body: build_model_request(model, prompt_config).to_json,
            content_type: "application/json",
            accept: "application/json"
          )

          response.body.each do |event|
            chunk = parse_stream_chunk(model, event)
            total_tokens += chunk[:token_count] if chunk[:token_count]
            yield chunk
          end

          # Track usage after streaming completes
          usage_tracker.track_inference(
            model_id: model_id,
            output_tokens: total_tokens,
            cost: calculate_token_cost(model, total_tokens)
          )

        rescue => e
          Rails.logger.error "Model streaming failed: #{e.message}"
          raise "Model streaming failed: #{e.message}"
        end
      end

      private

      def register_bedrock_models
        # Register all available Bedrock models
        bedrock_models = {
          # Anthropic Claude
          "anthropic.claude-3-opus-20240229" => {
            name: "Claude 3 Opus",
            provider: "anthropic",
            capabilities: [ "chat", "analysis", "coding", "vision" ],
            context_window: 200000,
            max_tokens: 4096,
            cost_per_1k_input: 0.015,
            cost_per_1k_output: 0.075
          },
          "anthropic.claude-3-sonnet-20240229" => {
            name: "Claude 3 Sonnet",
            provider: "anthropic",
            capabilities: [ "chat", "analysis", "coding", "vision" ],
            context_window: 200000,
            max_tokens: 4096,
            cost_per_1k_input: 0.003,
            cost_per_1k_output: 0.015
          },
          "anthropic.claude-3-haiku-20240307" => {
            name: "Claude 3 Haiku",
            provider: "anthropic",
            capabilities: [ "chat", "analysis", "coding" ],
            context_window: 200000,
            max_tokens: 4096,
            cost_per_1k_input: 0.00025,
            cost_per_1k_output: 0.00125
          },

          # Meta Llama
          "meta.llama3-70b-instruct-v1" => {
            name: "Llama 3 70B",
            provider: "meta",
            capabilities: [ "chat", "analysis", "coding" ],
            context_window: 8192,
            max_tokens: 2048,
            cost_per_1k_input: 0.00265,
            cost_per_1k_output: 0.0035
          },

          # Mistral
          "mistral.mistral-large-2402-v1:0" => {
            name: "Mistral Large",
            provider: "mistral",
            capabilities: [ "chat", "analysis", "coding" ],
            context_window: 32000,
            max_tokens: 8192,
            cost_per_1k_input: 0.008,
            cost_per_1k_output: 0.024
          },

          # Amazon Titan
          "amazon.titan-text-express-v1" => {
            name: "Amazon Titan Express",
            provider: "amazon",
            capabilities: [ "chat", "summarization" ],
            context_window: 8192,
            max_tokens: 4096,
            cost_per_1k_input: 0.0008,
            cost_per_1k_output: 0.0016
          },

          # Cohere
          "cohere.command-r-plus-v1:0" => {
            name: "Cohere Command R+",
            provider: "cohere",
            capabilities: [ "chat", "rag", "analysis" ],
            context_window: 128000,
            max_tokens: 4096,
            cost_per_1k_input: 0.003,
            cost_per_1k_output: 0.015
          }
        }

        @mutex.synchronize do
          bedrock_models.each do |bedrock_id, config|
            @models[bedrock_id] = config.merge(
              bedrock_id: bedrock_id,
              type: "bedrock_native"
            )
          end
        end
      end

      def bedrock_client
        @bedrock_client ||= Aws::BedrockRuntime::Client.new(
          region: ENV["AWS_REGION"] || "us-east-1",
          credentials: Aws::Credentials.new(
            ENV["AWS_ACCESS_KEY_ID"],
            ENV["AWS_SECRET_ACCESS_KEY"]
          )
        )
      end

      def find_model(model_id, user, entity)
        # Check native Bedrock models
        if model = @models[model_id]
          return model if can_access_model?(model, user, entity)
        end

        # Check custom models
        if custom = @custom_models[model_id]
          return custom if custom[:owner] == entity
        end

        # Check database for shared models
        if custom_model = CustomModel.find_by(model_id: model_id)
          if can_access_custom_model?(custom_model, user, entity)
            return {
              bedrock_id: custom_model.bedrock_model_id,
              type: "custom",
              config: custom_model.config
            }
          end
        end

        nil
      end

      def can_access_model?(model, user, entity)
        # Check if entity has access to this Bedrock model
        subscription = entity.subscription_level || "free"

        case subscription
        when "enterprise"
          true # Access to all models
        when "pro"
          # Access to most models except premium ones
          ![ "anthropic.claude-3-opus-20240229" ].include?(model[:bedrock_id])
        else # free
          # Only access to basic models
          [ "amazon.titan-text-express-v1", "meta.llama3-70b-instruct-v1" ].include?(model[:bedrock_id])
        end
      end

      def can_access_custom_model?(custom_model, user, entity)
        return true if custom_model.entity == entity
        return true if custom_model.shared_with_entities.include?(entity)
        return true if custom_model.public?

        # Check explicit permissions
        ModelPermission.exists?(
          custom_model: custom_model,
          entity: entity,
          permission_type: "use"
        )
      end

      def build_model_request(model, prompt_config)
        case model[:provider] || detect_provider(model[:bedrock_id])
        when "anthropic"
          build_anthropic_request(prompt_config)
        when "meta"
          build_llama_request(prompt_config)
        when "mistral"
          build_mistral_request(prompt_config)
        when "amazon"
          build_titan_request(prompt_config)
        when "cohere"
          build_cohere_request(prompt_config)
        else
          raise "Unknown model provider"
        end
      end

      def build_anthropic_request(config)
        {
          anthropic_version: "bedrock-2023-05-31",
          max_tokens: config[:max_tokens] || 1000,
          temperature: config[:temperature] || 0.7,
          top_p: config[:top_p] || 1.0,
          messages: config[:messages],
          system: config[:system_prompt]
        }.compact
      end

      def build_llama_request(config)
        {
          prompt: format_llama_prompt(config),
          max_gen_len: config[:max_tokens] || 512,
          temperature: config[:temperature] || 0.7,
          top_p: config[:top_p] || 0.9
        }
      end

      def build_mistral_request(config)
        {
          prompt: format_mistral_prompt(config),
          max_tokens: config[:max_tokens] || 1000,
          temperature: config[:temperature] || 0.7,
          top_p: config[:top_p] || 1.0,
          top_k: config[:top_k] || 50
        }
      end

      def build_titan_request(config)
        {
          inputText: format_titan_prompt(config),
          textGenerationConfig: {
            maxTokenCount: config[:max_tokens] || 512,
            temperature: config[:temperature] || 0.7,
            topP: config[:top_p] || 1.0,
            stopSequences: config[:stop_sequences] || []
          }
        }
      end

      def build_cohere_request(config)
        {
          prompt: format_cohere_prompt(config),
          max_tokens: config[:max_tokens] || 1000,
          temperature: config[:temperature] || 0.7,
          p: config[:top_p] || 0.75,
          k: config[:top_k] || 0,
          stop_sequences: config[:stop_sequences] || []
        }
      end

      def parse_model_response(model, response)
        response_body = JSON.parse(response.body.read)

        case model[:provider] || detect_provider(model[:bedrock_id])
        when "anthropic"
          parse_anthropic_response(response_body)
        when "meta"
          parse_llama_response(response_body)
        when "mistral"
          parse_mistral_response(response_body)
        when "amazon"
          parse_titan_response(response_body)
        when "cohere"
          parse_cohere_response(response_body)
        end
      end

      def parse_anthropic_response(response)
        {
          content: response["content"][0]["text"],
          usage: {
            input_tokens: response["usage"]["input_tokens"],
            output_tokens: response["usage"]["output_tokens"]
          },
          stop_reason: response["stop_reason"]
        }
      end

      def parse_llama_response(response)
        {
          content: response["generation"],
          usage: {
            input_tokens: response["prompt_token_count"],
            output_tokens: response["generation_token_count"]
          },
          stop_reason: response["stop_reason"]
        }
      end

      def parse_mistral_response(response)
        {
          content: response["outputs"][0]["text"],
          usage: {
            input_tokens: nil, # Mistral doesn't provide token counts
            output_tokens: nil
          },
          stop_reason: response["outputs"][0]["stop_reason"]
        }
      end

      def parse_titan_response(response)
        {
          content: response["results"][0]["outputText"],
          usage: {
            input_tokens: response["inputTextTokenCount"],
            output_tokens: response["results"][0]["tokenCount"]
          },
          stop_reason: response["results"][0]["completionReason"]
        }
      end

      def parse_cohere_response(response)
        {
          content: response["generations"][0]["text"],
          usage: {
            input_tokens: nil, # Cohere doesn't provide in this format
            output_tokens: nil
          },
          stop_reason: response["generations"][0]["finish_reason"]
        }
      end

      def detect_provider(bedrock_id)
        case bedrock_id
        when /^anthropic\./
          "anthropic"
        when /^meta\./
          "meta"
        when /^mistral\./
          "mistral"
        when /^amazon\./
          "amazon"
        when /^cohere\./
          "cohere"
        else
          nil
        end
      end

      def format_llama_prompt(config)
        # Llama expects a specific prompt format
        prompt = ""

        if config[:system_prompt]
          prompt += "<<SYS>>\n#{config[:system_prompt]}\n<</SYS>>\n\n"
        end

        if config[:messages]
          config[:messages].each do |msg|
            case msg[:role]
            when "user"
              prompt += "[INST] #{msg[:content]} [/INST]\n"
            when "assistant"
              prompt += "#{msg[:content]}\n"
            end
          end
        else
          prompt += config[:prompt] || ""
        end

        prompt
      end

      def format_mistral_prompt(config)
        # Similar to Llama format
        prompt = ""

        if config[:messages]
          config[:messages].each do |msg|
            case msg[:role]
            when "system"
              prompt += "<s>[INST] #{msg[:content]} [/INST]</s>\n"
            when "user"
              prompt += "[INST] #{msg[:content]} [/INST]\n"
            when "assistant"
              prompt += "#{msg[:content]}</s>\n"
            end
          end
        else
          prompt = config[:prompt] || ""
        end

        prompt
      end

      def format_titan_prompt(config)
        # Titan uses simple text format
        if config[:messages]
          config[:messages].map { |m| m[:content] }.join("\n\n")
        else
          config[:prompt] || ""
        end
      end

      def format_cohere_prompt(config)
        # Cohere uses simple prompt
        if config[:messages]
          config[:messages].map { |m| "#{m[:role]}: #{m[:content]}" }.join("\n")
        else
          config[:prompt] || ""
        end
      end

      def calculate_cost(model, usage)
        input_cost = (usage[:input_tokens] || 0) / 1000.0 * (model[:cost_per_1k_input] || 0)
        output_cost = (usage[:output_tokens] || 0) / 1000.0 * (model[:cost_per_1k_output] || 0)

        input_cost + output_cost
      end

      def calculate_token_cost(model, tokens)
        (tokens / 1000.0) * (model[:cost_per_1k_output] || 0)
      end

      def import_to_bedrock(model_config, model_id)
        # Use Bedrock's model import API (when available)
        # For now, we'll store the config and use a proxy approach

        {
          success: true,
          bedrock_model_id: "custom/#{model_id}"
        }
      end

      def create_fine_tuned_model(model_config, model_id)
        # Use Bedrock's fine-tuning API
        # This would create a fine-tuning job in Bedrock

        base_model = model_config[:base_model] || "anthropic.claude-3-haiku-20240307"

        # In production, this would call Bedrock's fine-tuning API
        {
          success: true,
          bedrock_model_id: "ft/#{base_model}/#{model_id}"
        }
      end

      def register_external_endpoint(model_config, model_id)
        # Register an external model endpoint that Bedrock can proxy to
        # This allows using custom deployed models

        {
          success: true,
          bedrock_model_id: "external/#{model_id}"
        }
      end

      def validate_custom_model!(model_config)
        raise "Model name required" unless model_config[:name]
        raise "Model type required" unless model_config[:type]

        case model_config[:type]
        when "bedrock_fine_tuned"
          raise "Base model required for fine-tuning" unless model_config[:base_model]
          raise "Training data required for fine-tuning" unless model_config[:training_data]
        when "external_endpoint"
          raise "Endpoint URL required" unless model_config[:endpoint_url]
          raise "Invalid endpoint URL" unless valid_url?(model_config[:endpoint_url])
        end
      end

      def valid_url?(url)
        uri = URI.parse(url)
        uri.scheme && uri.host
      rescue
        false
      end

      def get_bedrock_models_for_user(user, entity)
        @models.select do |id, model|
          can_access_model?(model, user, entity)
        end.map do |id, model|
          {
            id: id,
            name: model[:name],
            provider: model[:provider],
            capabilities: model[:capabilities],
            context_window: model[:context_window],
            cost_per_1k: {
              input: model[:cost_per_1k_input],
              output: model[:cost_per_1k_output]
            }
          }
        end
      end

      def get_custom_models(user, entity)
        CustomModel.where(entity: entity, status: "active").map do |model|
          {
            id: model.model_id,
            name: model.config["name"],
            type: model.config["type"],
            base_model: model.config["base_model"],
            created_at: model.created_at
          }
        end
      end

      def get_marketplace_models(user, entity)
        # Get models shared in Bedrock marketplace or by other entities
        SharedModel.active.visible_to(entity).map do |model|
          {
            id: model.model_id,
            name: model.name,
            provider: model.provider_entity.name,
            description: model.description,
            rating: model.average_rating,
            usage_count: model.usage_count
          }
        end
      end

      def parse_stream_chunk(model, event)
        # Parse streaming response based on model type
        if event.event_type == "chunk"
          payload = JSON.parse(event.event_payload)

          case model[:provider] || detect_provider(model[:bedrock_id])
          when "anthropic"
            {
              content: payload.dig("delta", "text") || "",
              token_count: 1 # Approximate
            }
          when "meta", "mistral"
            {
              content: payload["generation"] || "",
              token_count: 1
            }
          when "amazon"
            {
              content: payload["outputText"] || "",
              token_count: 1
            }
          else
            {
              content: payload["text"] || payload["generation"] || "",
              token_count: 1
            }
          end
        else
          { content: "", token_count: 0 }
        end
      end
    end
  end
end
