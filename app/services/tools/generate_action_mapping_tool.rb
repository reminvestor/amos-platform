# frozen_string_literal: true

module Tools
  # GenerateActionMappingTool - AI generates Ruby code for action parameter mapping
  #
  # Similar to GenerateTransformCodeTool but for API parameter mapping.
  # The AI generates mapping_code that converts normalized inputs to API-specific params.
  #
  # This code runs WITHOUT AI during execution - it's pure Ruby.
  #
  class GenerateActionMappingTool < BaseTool
    def self.metadata
      {
        name: "generate_action_mapping",
        description: <<~DESC.strip,
          Generate Ruby mapping code for an integration action.
          
          This creates a pre-defined action that Amos can call with normalized parameters.
          The AI generates Ruby code that maps normalized inputs → API-specific parameters.
          
          **Use this to create reusable, tested action templates.**
          
          **Required:**
          - integration_slug: The integration this action belongs to
          - action_name: Name for the action (e.g., "place_limit_order")
          - operation_id: The underlying API operation to call
          - input_schema: What inputs the action accepts
          - sample_input: Example input for testing
          
          **Optional:**
          - api_docs: Relevant API documentation (from RAG or provided)
          - sample_api_params: Example of what the API expects
        DESC
        category: "integration",
        input_schema: {
          type: "object",
          properties: {
            integration_slug: {
              type: "string",
              description: "Integration slug (e.g., 'coinbase', 'stripe')"
            },
            action_name: {
              type: "string",
              description: "Name for this action (e.g., 'place_limit_order')"
            },
            description: {
              type: "string",
              description: "What this action does"
            },
            operation_id: {
              type: "string",
              description: "The underlying IntegrationOperation operation_id"
            },
            input_schema: {
              type: "array",
              description: "Input fields: [{name, type, required, description}]"
            },
            sample_input: {
              type: "object",
              description: "Sample input for testing the mapping"
            },
            sample_api_params: {
              type: "object",
              description: "Example of what the API expects (for AI reference)"
            },
            api_docs: {
              type: "string",
              description: "Relevant API documentation"
            },
            rag_store_id: {
              type: "integer",
              description: "RAG store ID to query for API docs"
            },
            category: {
              type: "string",
              description: "Action category (trading, crm, messaging, etc.)"
            }
          },
          required: %w[integration_slug action_name operation_id input_schema sample_input]
        }
      }
    end

    def execute(args)
      log_execution(args)

      integration_slug = get_arg(args, :integration_slug)
      action_name = get_arg(args, :action_name)
      description = get_arg(args, :description, "#{action_name.titleize}")
      operation_id = get_arg(args, :operation_id)
      input_schema = get_arg(args, :input_schema, [])
      sample_input = get_arg(args, :sample_input, {})
      sample_api_params = get_arg(args, :sample_api_params)
      api_docs = get_arg(args, :api_docs)
      rag_store_id = get_arg(args, :rag_store_id)
      category = get_arg(args, :category)

      # Validate required args
      if error = validate_required_args(args, %i[integration_slug action_name operation_id input_schema sample_input])
        return error
      end

      begin
        # Find integration and operation
        integration = Integration.find_for_use(integration_slug, @entity)
        return error_response("Integration '#{integration_slug}' not found") unless integration

        operation = integration.integration_operations.find_by(operation_id: operation_id) ||
                    integration.integration_operations.find_by(id: operation_id)
        return error_response("Operation '#{operation_id}' not found") unless operation

        # Check if action already exists
        existing = IntegrationAction.find_by(integration: integration, action_name: action_name)
        if existing
          return error_response(
            "Action '#{action_name}' already exists for #{integration.name}",
            action_id: existing.id,
            hint: "To update, use update_action_mapping or delete and recreate"
          )
        end

        # Get API docs from RAG if needed
        if api_docs.blank? && rag_store_id.present?
          api_docs = query_rag_for_docs(rag_store_id, operation.name, operation.description)
        end

        # Generate mapping code using AI
        generated = generate_mapping_code(
          integration: integration,
          operation: operation,
          input_schema: input_schema,
          sample_input: sample_input,
          sample_api_params: sample_api_params,
          api_docs: api_docs
        )

        return error_response(generated[:error]) unless generated[:success]

        # Test the generated code
        test_result = test_mapping_code(generated[:code], sample_input)
        return error_response("Generated code failed test: #{test_result[:error]}") unless test_result[:success]

        # Create the action
        action = IntegrationAction.create!(
          integration: integration,
          integration_operation: operation,
          entity: @entity,
          created_by: @user,
          action_name: action_name,
          description: description,
          category: category,
          input_schema: input_schema,
          mapping_code: generated[:code],
          mapping_code_version: 1,
          mapping_code_generated_at: Time.current,
          mapping_code_generated_by: 'qwen3-next-80b',
          sample_input: sample_input,
          sample_output: test_result[:output],
          status: :testing
        )

        success_response(
          message: "Created action '#{action_name}' for #{integration.name}",
          action_id: action.id,
          action_name: action_name,
          slug: action.slug,
          status: action.status,
          mapping_code: generated[:code],
          test_input: sample_input,
          test_output: test_result[:output],
          next_steps: [
            "Test with: execute_integration_action(integration: '#{integration.slug}', action: '#{action_name}', inputs: #{sample_input.to_json})",
            "Activate when ready: The action is in 'testing' status",
            "Check execution history in the automation dashboard"
          ]
        )

      rescue => e
        Rails.logger.error "GenerateActionMappingTool error: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
        error_response("Failed to generate action: #{e.message}")
      end
    end

    private

    def query_rag_for_docs(rag_store_id, operation_name, operation_description)
      rag_service = RagStoreService.new
      
      results = rag_service.query_rag_store(
        rag_store_id,
        "#{operation_name} #{operation_description} parameters request body",
        top_k: 5
      )

      results[:matches]&.map { |m| m[:content] }&.join("\n\n")
    rescue => e
      Rails.logger.warn "[GenerateActionMapping] RAG query failed: #{e.message}"
      nil
    end

    def generate_mapping_code(integration:, operation:, input_schema:, sample_input:, sample_api_params:, api_docs:)
      prompt = build_prompt(integration, operation, input_schema, sample_input, sample_api_params, api_docs)

      response = BedrockService.new.chat(
        messages: [{ role: 'user', content: prompt }],
        system: code_generation_system_prompt,
        model: 'qwen3-next-80b',
        temperature: 0.2
      )

      code = extract_code(response[:content])

      if code.present?
        { success: true, code: code }
      else
        { success: false, error: "Failed to generate valid Ruby code" }
      end
    rescue => e
      { success: false, error: e.message }
    end

    def code_generation_system_prompt
      <<~PROMPT
        You are a Ruby code generator for API parameter mapping. Generate ONLY the map method body.

        RULES:
        1. The code must define a `map(inputs)` method
        2. `inputs` is a Hash with indifferent access (both string and symbol keys work)
        3. Return a Hash with the API-specific parameters
        4. Use ONLY the safe helpers available in the context (listed below)
        5. Do NOT use require, load, eval, send, or any metaprogramming
        6. Do NOT access files, network, or system resources
        7. Handle nil values gracefully
        8. Keep the code simple and readable

        AVAILABLE HELPERS:
        - get(path) - Get value using dot notation: get('address.city')
        - format(template) - String interpolation: format('{{first_name}} {{last_name}}')
        - titleize(str), downcase(str), upcase(str), strip(str), slugify(str), camelize(str)
        - to_cents(dollars), to_dollars(cents), round(num, decimals), to_string(num, precision)
        - parse_date(str), parse_datetime(str), from_unix(ts), to_unix(time), to_iso8601(time)
        - first(arr), last(arr), join(arr, sep), split(str, sep)
        - present?(val), blank?(val), default(val, fallback)
        - map_value(val, mapping_hash, default)
        - merge(hash1, hash2, ...)
        - normalize_trading_pair(pair, format) - "BTC/USD" → "BTC-USD" (:hyphen) or "BTCUSD" (:concat)
        - to_api_enum(value, mapping) - Map enum values
        - to_api_decimal(value, precision: 8) - Format decimal strings
        - to_api_bool(value, format: :string) - Convert booleans
        - format_phone(phone, format: :e164) - Format phone numbers
        - normalize_email(email) - Lowercase and strip

        OUTPUT FORMAT:
        Return ONLY the Ruby code wrapped in ```ruby ... ``` blocks.
        No explanations, just the code.
      PROMPT
    end

    def build_prompt(integration, operation, input_schema, sample_input, sample_api_params, api_docs)
      prompt = <<~PROMPT
        Generate a Ruby map method for the #{integration.name} API.

        OPERATION: #{operation.name}
        HTTP: #{operation.http_method} #{operation.path_template}
        DESCRIPTION: #{operation.description}

        NORMALIZED INPUTS (what Amos provides):
        ```json
        #{JSON.pretty_generate(sample_input)}
        ```

        INPUT SCHEMA:
        #{input_schema.map { |f| "- #{f['name'] || f[:name]}: #{f['type'] || f[:type]}#{' (required)' if f['required'] || f[:required]}" }.join("\n")}
      PROMPT

      if sample_api_params.present?
        prompt += <<~PARAMS

          EXPECTED API PARAMETERS:
          ```json
          #{JSON.pretty_generate(sample_api_params)}
          ```
        PARAMS
      end

      if api_docs.present?
        prompt += <<~DOCS

          API DOCUMENTATION:
          #{api_docs.truncate(2000)}
        DOCS
      end

      prompt += "\n\nGenerate the map(inputs) method:"
      prompt
    end

    def extract_code(response)
      # Extract code from markdown code blocks
      match = response.match(/```ruby\s*(.*?)\s*```/m)
      return match[1].strip if match

      # Try without language specifier
      match = response.match(/```\s*(def map.*?end)\s*```/m)
      return match[1].strip if match

      # Last resort: look for def map directly
      match = response.match(/(def map\(inputs\).*?^end)/m)
      match ? match[1].strip : nil
    end

    def test_mapping_code(code, sample_input)
      # Create a temporary action for testing
      temp_action = OpenStruct.new(
        mapping_code: code,
        integration: nil
      )

      executor = Integrations::ActionCodeExecutor.new(temp_action)
      result = executor.map_inputs(sample_input)

      if result[:success]
        { success: true, output: result[:params] }
      else
        { success: false, error: result[:error] }
      end
    rescue => e
      { success: false, error: e.message }
    end
  end
end

