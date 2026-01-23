# frozen_string_literal: true

module Tools
  class GenerateTransformCodeTool < BaseTool
    def self.metadata
      {
        name: "generate_transform_code",
        description: "Generate Ruby transformation code for an integration sync. This code runs WITHOUT AI during ETL execution - it's pure Ruby. Use this to create data mappings, transformations, and business logic for syncing data between systems.",
        category: "integration",
        input_schema: {
          type: "object",
          properties: {
            sync_config_id: {
              type: "integer",
              description: "ID of the sync config to generate transform code for"
            },
            source_schema: {
              type: "object",
              description: "Sample record from the source system showing field names and types"
            },
            target_schema: {
              type: "object",
              description: "Expected output format with field names and types"
            },
            transformation_rules: {
              type: "array",
              description: "List of transformation rules to apply",
              items: {
                type: "object",
                properties: {
                  source_field: { type: "string" },
                  target_field: { type: "string" },
                  transform: { type: "string", description: "Transformation to apply (e.g., 'downcase', 'cents_to_dollars', 'concat first_name last_name')" }
                }
              }
            },
            custom_logic: {
              type: "string",
              description: "Natural language description of any custom business logic needed"
            }
          },
          required: ["source_schema", "target_schema"]
        }
      }
    end

    def execute(args)
      log_execution(args)

      sync_config_id = get_arg(args, :sync_config_id)
      source_schema = get_arg(args, :source_schema, {})
      target_schema = get_arg(args, :target_schema, {})
      transformation_rules = get_arg(args, :transformation_rules, [])
      custom_logic = get_arg(args, :custom_logic, '')

      # Generate the transform code using AI
      generated_code = generate_code(source_schema, target_schema, transformation_rules, custom_logic)

      return error_response(generated_code[:error]) unless generated_code[:success]

      # Test the generated code
      test_result = test_code(generated_code[:code], source_schema)

      unless test_result[:success]
        return error_response("Generated code failed test: #{test_result[:error]}")
      end

      # Save to sync config if provided
      if sync_config_id.present?
        save_result = save_to_config(sync_config_id, generated_code[:code], source_schema, test_result[:output])
        return error_response(save_result[:error]) unless save_result[:success]
      end

      success_response(
        message: "Transform code generated successfully",
        code: generated_code[:code],
        test_input: source_schema,
        test_output: test_result[:output],
        sync_config_id: sync_config_id
      )
    end

    private

    def generate_code(source_schema, target_schema, rules, custom_logic)
      prompt = build_prompt(source_schema, target_schema, rules, custom_logic)

      response = BedrockService.new.chat(
        messages: [{ role: 'user', content: prompt }],
        system: code_generation_system_prompt,
        model: 'qwen3-next-80b',
        temperature: 0.2  # Low temperature for consistent code
      )

      # Extract code from response
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
        You are a Ruby code generator for data transformation. Generate ONLY the transform method body.

        RULES:
        1. The code must define a `transform(record)` method
        2. `record` is a Hash with indifferent access (both string and symbol keys work)
        3. Return a Hash with the transformed data
        4. Use ONLY the safe helpers available in the context (listed below)
        5. Do NOT use require, load, eval, send, or any metaprogramming
        6. Do NOT access files, network, or system resources
        7. Handle nil values gracefully
        8. Keep the code simple and readable

        AVAILABLE HELPERS:
        - get(path) - Get value using dot notation: get('address.city')
        - format(template) - String interpolation: format('{{first_name}} {{last_name}}')
        - titleize(str), downcase(str), upcase(str), strip(str), slugify(str)
        - to_cents(dollars), to_dollars(cents), round(num, decimals)
        - parse_date(str), parse_datetime(str), from_unix(ts), to_unix(time), today, now
        - first(arr), last(arr), join(arr, sep), split(str, sep)
        - present?(val), blank?(val), default(val, fallback)
        - lookup_contact_by_email(email), lookup_user_by_email(email)
        - map_value(val, mapping_hash, default)
        - merge(hash1, hash2, ...)

        OUTPUT FORMAT:
        Return ONLY the Ruby code wrapped in ```ruby ... ``` blocks.
        No explanations, just the code.
      PROMPT
    end

    def build_prompt(source_schema, target_schema, rules, custom_logic)
      prompt = <<~PROMPT
        Generate a Ruby transform method for data synchronization.

        SOURCE RECORD (sample):
        ```json
        #{JSON.pretty_generate(source_schema)}
        ```

        TARGET FORMAT:
        ```json
        #{JSON.pretty_generate(target_schema)}
        ```
      PROMPT

      if rules.any?
        prompt += "\nTRANSFORMATION RULES:\n"
        rules.each do |rule|
          prompt += "- #{rule['source_field']} → #{rule['target_field']}"
          prompt += " (#{rule['transform']})" if rule['transform'].present?
          prompt += "\n"
        end
      end

      if custom_logic.present?
        prompt += "\nCUSTOM BUSINESS LOGIC:\n#{custom_logic}\n"
      end

      prompt += "\nGenerate the transform(record) method:"
      prompt
    end

    def extract_code(response)
      # Extract code from markdown code blocks
      match = response.match(/```ruby\s*(.*?)\s*```/m)
      return match[1].strip if match

      # Try without language specifier
      match = response.match(/```\s*(def transform.*?end)\s*```/m)
      return match[1].strip if match

      # Last resort: look for def transform directly
      match = response.match(/(def transform\(record\).*?^end)/m)
      match ? match[1].strip : nil
    end

    def test_code(code, sample_input)
      # Create a temporary sync config for testing
      temp_config = OpenStruct.new(
        transform_code: code,
        field_mappings: {},
        entity: entity
      )

      executor = Integrations::TransformCodeExecutor.new(temp_config)
      result = executor.transform(sample_input)

      if result[:success]
        { success: true, output: result[:data] }
      else
        { success: false, error: result[:error] }
      end
    rescue => e
      { success: false, error: e.message }
    end

    def save_to_config(sync_config_id, code, sample_input, sample_output)
      config = IntegrationSyncConfig.find_by(id: sync_config_id)
      return { success: false, error: "Sync config not found" } unless config
      return { success: false, error: "Access denied" } unless config.entity_id == entity&.id

      config.update!(
        transform_code: code,
        transform_code_version: (config.transform_code_version || 0) + 1,
        transform_code_generated_at: Time.current,
        transform_code_generated_by: 'qwen3-next-80b',
        sample_input: sample_input,
        sample_output: sample_output
      )

      { success: true }
    rescue => e
      { success: false, error: e.message }
    end
  end
end

