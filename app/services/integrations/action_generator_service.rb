# frozen_string_literal: true

module Integrations
  # ActionGeneratorService - Automatically generates IntegrationAction records from IntegrationOperations
  #
  # Use cases:
  # 1. Backfill: Generate actions for all existing operations that don't have one
  # 2. On-create: Automatically create action when operation is added
  # 3. AI-enhanced: Use AI to generate smart mapping code from API docs
  #
  # Example:
  #   # Generate actions for all Stripe operations
  #   ActionGeneratorService.backfill_for_integration('stripe')
  #
  #   # Generate action for a single operation
  #   ActionGeneratorService.generate_for_operation(operation)
  #
  #   # With AI-generated mapping code
  #   ActionGeneratorService.generate_for_operation(operation, use_ai: true)
  #
  class ActionGeneratorService
    attr_reader :operation, :integration, :options

    def initialize(operation, options = {})
      @operation = operation
      @integration = operation.integration
      @options = options.with_indifferent_access
    end

    # ============================================
    # CLASS METHODS
    # ============================================

    # Generate actions for all operations in an integration
    def self.backfill_for_integration(integration_slug, options = {})
      integration = Integration.find_by!(slug: integration_slug)
      results = { created: [], skipped: [], errors: [] }

      integration.integration_operations.find_each do |operation|
        # Skip if action already exists
        if IntegrationAction.exists?(integration: integration, integration_operation: operation)
          results[:skipped] << operation.operation_id
          next
        end

        begin
          result = new(operation, options).generate!
          if result[:success]
            results[:created] << result[:action].action_name
          else
            results[:errors] << { operation: operation.operation_id, error: result[:error] }
          end
        rescue => e
          results[:errors] << { operation: operation.operation_id, error: e.message }
        end
      end

      Rails.logger.info "[ActionGenerator] Backfill for #{integration.name}: " \
                        "#{results[:created].length} created, " \
                        "#{results[:skipped].length} skipped, " \
                        "#{results[:errors].length} errors"
      results
    end

    # Generate actions for all operations across all integrations
    def self.backfill_all(options = {})
      results = {}
      
      Integration.find_each do |integration|
        results[integration.slug] = backfill_for_integration(integration.slug, options)
      end

      results
    end

    # Generate action for a single operation
    def self.generate_for_operation(operation, options = {})
      new(operation, options).generate!
    end

    # Check which operations are missing actions
    def self.audit(integration_slug = nil)
      scope = IntegrationOperation.includes(:integration)
      scope = scope.joins(:integration).where(integrations: { slug: integration_slug }) if integration_slug

      missing = []
      has_action = []

      scope.find_each do |operation|
        if IntegrationAction.exists?(integration: operation.integration, integration_operation: operation)
          has_action << operation.operation_id
        else
          missing << {
            integration: operation.integration.slug,
            operation_id: operation.operation_id,
            name: operation.name,
            method: operation.http_method
          }
        end
      end

      {
        total_operations: scope.count,
        with_actions: has_action.length,
        missing_actions: missing.length,
        missing: missing
      }
    end

    # ============================================
    # INSTANCE METHODS
    # ============================================

    def generate!
      # Check if action already exists
      existing = IntegrationAction.find_by(
        integration: integration,
        integration_operation: operation
      )
      
      if existing
        return { success: false, error: 'Action already exists', action: existing }
      end

      # Generate action name from operation
      action_name = generate_action_name
      
      # Generate input schema from operation's request_schema
      input_schema = generate_input_schema

      # Generate mapping code
      mapping_code = if options[:use_ai]
        generate_ai_mapping_code
      else
        generate_default_mapping_code
      end

      # Create the action
      action = IntegrationAction.new(
        integration: integration,
        integration_operation: operation,
        entity_id: options[:entity_id],  # nil for global
        created_by_id: options[:user_id],
        action_name: action_name,
        description: operation.description || "#{operation.name} via #{integration.name}",
        category: determine_category,
        input_schema: input_schema,
        mapping_code: mapping_code,
        mapping_code_version: 1,
        mapping_code_generated_at: Time.current,
        mapping_code_generated_by: options[:use_ai] ? 'ai' : 'auto',
        sample_input: generate_sample_input(input_schema),
        status: options[:auto_activate] ? :active : :draft
      )

      if action.save
        Rails.logger.info "[ActionGenerator] Created action: #{action.slug}"
        { success: true, action: action }
      else
        { success: false, error: action.errors.full_messages.join(', ') }
      end
    end

    private

    # ============================================
    # NAME GENERATION
    # ============================================

    def generate_action_name
      # Remove integration prefix and version suffix
      name = operation.operation_id
        .gsub(/^#{Regexp.escape(integration.slug)}\./, '')  # Remove "stripe."
        .gsub(/\.v\d+.*$/, '')  # Remove ".v1", ".v2024-01"
        .gsub(/[-.]/, '_')  # Normalize separators

      # Handle common patterns
      name = name
        .gsub(/^get_/, '')  # get_customer → customer (will be prefixed)
        .gsub(/_by_id$/, '')

      name.underscore
    end

    # ============================================
    # INPUT SCHEMA GENERATION
    # ============================================

    def generate_input_schema
      request_schema = operation.request_schema || {}
      properties = request_schema['properties'] || {}
      required = request_schema['required'] || []

      schema = []

      properties.each do |field_name, field_def|
        schema << {
          name: normalize_field_name(field_name),
          type: map_json_type(field_def['type']),
          required: required.include?(field_name),
          description: field_def['description'],
          # Preserve validation rules
          min: field_def['minimum'],
          max: field_def['maximum'],
          values: field_def['enum'],
          pattern: field_def['pattern']
        }.compact
      end

      # Add path parameters
      path_params = extract_path_params
      path_params.each do |param|
        next if schema.any? { |s| s[:name] == param }
        schema << {
          name: param,
          type: 'string',
          required: true,
          description: "Path parameter: #{param}"
        }
      end

      schema
    end

    def normalize_field_name(name)
      # Convert API naming to normalized naming
      {
        'maxResults' => 'limit',
        'pageSize' => 'limit',
        'pageToken' => 'cursor',
        'starting_after' => 'cursor',
        'after' => 'cursor'
      }[name] || name.underscore
    end

    def map_json_type(json_type)
      case json_type
      when 'string' then 'string'
      when 'integer' then 'integer'
      when 'number' then 'number'
      when 'boolean' then 'boolean'
      when 'array' then 'array'
      when 'object' then 'object'
      else 'string'
      end
    end

    def extract_path_params
      operation.path_template.scan(/\{(\w+)\}/).flatten
    end

    # ============================================
    # MAPPING CODE GENERATION
    # ============================================

    def generate_default_mapping_code
      request_schema = operation.request_schema || {}
      properties = request_schema['properties'] || {}

      # Build simple pass-through mapping with known transformations
      mappings = []

      properties.each do |api_field, field_def|
        normalized = normalize_field_name(api_field)
        
        # Determine if transformation needed
        transformation = determine_transformation(normalized, api_field, field_def)
        
        if normalized == api_field && transformation.nil?
          mappings << "result[:#{api_field}] = inputs[:#{normalized}] if present?(inputs[:#{normalized}])"
        else
          value_expr = transformation || "inputs[:#{normalized}]"
          mappings << "result[:#{api_field}] = #{value_expr} if present?(inputs[:#{normalized}])"
        end
      end

      <<~RUBY
        def map(inputs)
          result = {}
          
          #{mappings.join("\n      ")}
          
          result.compact
        end
      RUBY
    end

    def determine_transformation(normalized, api_field, field_def)
      # Common transformations
      case normalized
      when 'email'
        'normalize_email(inputs[:email])'
      when 'phone'
        'format_phone(inputs[:phone])'
      when 'limit'
        return "default(inputs[:limit], #{field_def['default'] || 10})" if api_field == 'limit'
        "default(inputs[:limit], #{field_def['default'] || 10})"
      when 'cursor'
        "inputs[:cursor]"
      else
        # Check for amount fields that might need cents conversion
        if api_field.include?('amount') && field_def['type'] == 'integer'
          'to_cents(inputs[:amount])'
        else
          nil
        end
      end
    end

    def generate_ai_mapping_code
      # Use BedrockService to generate smarter mapping code
      prompt = build_ai_prompt

      response = BedrockService.new.chat(
        messages: [{ role: 'user', content: prompt }],
        system: ai_system_prompt,
        model: 'qwen3-next-80b',
        temperature: 0.2
      )

      extract_code(response[:content]) || generate_default_mapping_code
    rescue => e
      Rails.logger.warn "[ActionGenerator] AI generation failed: #{e.message}, falling back to default"
      generate_default_mapping_code
    end

    def ai_system_prompt
      <<~PROMPT
        You are a Ruby code generator for API parameter mapping.
        Generate a `map(inputs)` method that transforms normalized inputs to API parameters.
        
        RULES:
        1. Return ONLY Ruby code wrapped in ```ruby ... ```
        2. Use available helpers: normalize_email, format_phone, to_cents, to_dollars, 
           default, present?, titleize, downcase, upcase, to_unix, parse_datetime
        3. Handle nil values gracefully with `if present?()`
        4. Return a Hash
      PROMPT
    end

    def build_ai_prompt
      <<~PROMPT
        Generate mapping code for: #{integration.name} - #{operation.name}
        
        HTTP: #{operation.http_method} #{operation.path_template}
        
        API Request Schema:
        #{JSON.pretty_generate(operation.request_schema || {})}
        
        API Documentation: #{operation.documentation}
        
        Generate the map(inputs) method:
      PROMPT
    end

    def extract_code(response)
      match = response.match(/```ruby\s*(.*?)\s*```/m)
      match ? match[1].strip : nil
    end

    # ============================================
    # HELPERS
    # ============================================

    def determine_category
      case integration.category
      when 'payment' then 'payment'
      when 'crm' then 'crm'
      when 'ecommerce' then 'ecommerce'
      when 'communication' then 'messaging'
      when 'productivity' then 'productivity'
      when 'accounting' then 'accounting'
      else 'general'
      end
    end

    def generate_sample_input(schema)
      sample = {}
      
      schema.each do |field|
        next unless field[:required]
        
        sample[field[:name].to_sym] = case field[:type]
        when 'string' then 'example'
        when 'integer' then 1
        when 'number' then 1.0
        when 'boolean' then true
        when 'array' then []
        when 'object' then {}
        else 'example'
        end
      end

      sample
    end
  end
end

