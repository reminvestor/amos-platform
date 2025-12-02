module Factories
  class ToolFactory
    class ValidationError < StandardError; end
    class SchemaError < StandardError; end
    class SecurityError < StandardError; end
    class TestError < StandardError; end

    # Valid execution types
    VALID_EXECUTION_TYPES = %w[ruby_code http_request].freeze

    # Dangerous patterns in Ruby code
    DANGEROUS_PATTERNS = [
      /\beval\b/,
      /\bsystem\b/,
      /\bexec\b/,
      /\b`.*`/,
      /\bFile\.(delete|unlink|rm|write|open.*w)/i,
      /\bFileUtils\.(rm|remove|delete)/i,
      /\brequire\s+['"]net/,
      /\bKernel\./,
      /\bProcess\./,
      /\bIO\.popen/,
      /\bOpen3\./,
      /\b__send__\b/,
      /\bsend\(/,
      /\binstance_eval\b/,
      /\bclass_eval\b/,
      /\bmodule_eval\b/,
      /\bconst_get\b/,
      /\bconst_set\b/
    ].freeze

    # Required schema properties
    REQUIRED_SCHEMA_KEYS = %w[type].freeze

    attr_reader :user, :entity, :errors, :warnings

    def initialize(user:, entity:)
      @user = user
      @entity = entity
      @errors = []
      @warnings = []
    end

    # Main factory method to create a tool
    def create(params)
      @errors = []
      @warnings = []

      # Step 1: Validate the schema/structure
      validate_schema!(params)

      # Step 2: Validate parameters schema
      validate_parameters_schema!(params[:parameters] || params[:input_schema])

      # Step 3: Validate execution-specific config
      case params[:execution_type]
      when 'ruby_code'
        validate_ruby_code!(params[:code])
      when 'http_request'
        validate_api_config!(params[:api_config])
      end

      # Raise if we have errors
      raise ValidationError, @errors.join("; ") if @errors.any?

      # Step 4: Create the tool
      tool = build_tool(params)

      # Step 5: Run a test execution (optional)
      if params[:skip_test] != true && params[:test_args].present?
        test_result = test_tool(tool, params[:test_args])
        unless test_result[:success]
          tool.destroy if tool.persisted?
          raise TestError, "Tool test failed: #{test_result[:error]}"
        end
      end

      # Refresh the catalog so the tool is immediately available
      Tools::ToolCatalog.instance.refresh_dynamic_tools!

      {
        success: true,
        tool: tool,
        warnings: @warnings
      }
    rescue ValidationError, SchemaError, SecurityError, TestError => e
      { success: false, error: e.message, errors: @errors, warnings: @warnings }
    rescue => e
      Rails.logger.error "ToolFactory error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      { success: false, error: "Unexpected error: #{e.message}", errors: @errors }
    end

    # Update an existing tool with validation
    def update(tool, params)
      @errors = []
      @warnings = []

      # Verify ownership
      unless can_edit?(tool)
        return { success: false, error: "You don't have permission to edit this tool" }
      end

      # Validate updates
      validate_schema!(params, update: true) if params[:name]
      validate_parameters_schema!(params[:parameters] || params[:input_schema]) if params[:parameters] || params[:input_schema]
      
      if params[:code].present?
        validate_ruby_code!(params[:code])
      end
      
      if params[:api_config].present?
        validate_api_config!(params[:api_config])
      end

      raise ValidationError, @errors.join("; ") if @errors.any?

      # Apply updates
      update_tool_attributes(tool, params)
      tool.save!

      # Refresh catalog
      Tools::ToolCatalog.instance.refresh_dynamic_tools!

      {
        success: true,
        tool: tool.reload,
        warnings: @warnings
      }
    rescue ValidationError => e
      { success: false, error: e.message, errors: @errors, warnings: @warnings }
    rescue => e
      Rails.logger.error "ToolFactory update error: #{e.message}"
      { success: false, error: "Update failed: #{e.message}" }
    end

    # Validate tool schema without creating
    def validate_only(params)
      @errors = []
      @warnings = []

      validate_schema!(params)
      validate_parameters_schema!(params[:parameters] || params[:input_schema]) if params[:parameters] || params[:input_schema]
      
      case params[:execution_type]
      when 'ruby_code'
        validate_ruby_code!(params[:code])
      when 'http_request'
        validate_api_config!(params[:api_config])
      end

      {
        valid: @errors.empty?,
        errors: @errors,
        warnings: @warnings
      }
    end

    # Generate a tool template based on type
    def generate_template(type:, name:, description:)
      case type
      when 'http_request'
        generate_http_template(name, description)
      when 'ruby_code'
        generate_ruby_template(name, description)
      else
        { error: "Unknown template type: #{type}" }
      end
    end

    private

    def validate_schema!(params, update: false)
      # Required fields for creation
      unless update
        @errors << "name is required" if params[:name].blank?
        @errors << "description is required" if params[:description].blank?
        @errors << "execution_type is required" if params[:execution_type].blank?
      end

      # Name validation
      if params[:name].present?
        unless params[:name].match?(/\A[a-z0-9_]+\z/)
          @errors << "name must only contain lowercase letters, numbers, and underscores"
        end

        if params[:name].length > 64
          @errors << "name must be less than 64 characters"
        end

        # Check uniqueness
        existing = ToolDefinition.find_by(name: params[:name])
        if existing && (!update || existing.id != params[:id])
          @errors << "tool '#{params[:name]}' already exists"
        end

        # Check against built-in tools
        if Tools::ToolCatalog.instance.tool_exists?(params[:name])
          builtin = Tools::ToolCatalog.instance.all_tools[params[:name]]
          if builtin && builtin[:type] == :class
            @errors << "tool '#{params[:name]}' conflicts with a built-in tool"
          end
        end
      end

      # Execution type validation
      if params[:execution_type].present? && !VALID_EXECUTION_TYPES.include?(params[:execution_type])
        @errors << "execution_type must be one of: #{VALID_EXECUTION_TYPES.join(', ')}"
      end
    end

    def validate_parameters_schema!(schema)
      return if schema.blank?

      unless schema.is_a?(Hash)
        @errors << "parameters must be a JSON object"
        return
      end

      # Support both string and symbol keys
      schema = schema.with_indifferent_access if schema.respond_to?(:with_indifferent_access)
      
      unless schema['type'].present? || schema[:type].present?
        @errors << "parameters schema must have a 'type' field (usually 'object')"
      end

      schema_type = schema['type'] || schema[:type]
      schema_props = schema['properties'] || schema[:properties]
      
      if schema_type == 'object' && schema_props.blank?
        @warnings << "parameters schema has no properties defined"
      end

      # Validate property definitions
      if schema_props.is_a?(Hash)
        schema_props.each do |prop_name, prop_def|
          unless prop_def.is_a?(Hash)
            @errors << "property '#{prop_name}' must be an object"
            next
          end

          prop_def = prop_def.with_indifferent_access if prop_def.respond_to?(:with_indifferent_access)
          
          unless prop_def['type'].present? || prop_def[:type].present?
            @warnings << "property '#{prop_name}' has no type defined"
          end

          unless prop_def['description'].present? || prop_def[:description].present?
            @warnings << "property '#{prop_name}' has no description - this helps the AI use the tool correctly"
          end
        end
      end

      # Check required fields reference valid properties
      schema_required = schema['required'] || schema[:required]
      if schema_required.is_a?(Array) && schema_props.is_a?(Hash)
        schema_required.each do |req|
          unless schema_props.key?(req) || schema_props.key?(req.to_s) || schema_props.key?(req.to_sym)
            @errors << "required field '#{req}' is not defined in properties"
          end
        end
      end
    end

    def validate_ruby_code!(code)
      return @errors << "code is required for ruby_code execution type" if code.blank?

      # Check for dangerous patterns
      DANGEROUS_PATTERNS.each do |pattern|
        if code.match?(pattern)
          @errors << "code contains potentially dangerous pattern: #{pattern.source}"
        end
      end

      # Check syntax validity
      begin
        RubyVM::InstructionSequence.compile(code)
      rescue SyntaxError => e
        @errors << "Ruby syntax error: #{e.message}"
      end

      # Warn about common issues
      unless code.include?('_args')
        @warnings << "code should use '_args' to access input parameters"
      end

      if code.length > 10000
        @warnings << "code is very long (#{code.length} chars) - consider breaking into smaller tools"
      end
    end

    def validate_api_config!(config)
      return @errors << "api_config is required for http_request execution type" if config.blank?

      unless config.is_a?(Hash)
        @errors << "api_config must be an object"
        return
      end

      @errors << "api_config.url is required" if config['url'].blank?

      if config['url'].present?
        begin
          uri = URI.parse(config['url'].gsub(/\{\{.*?\}\}/, 'placeholder'))
          unless %w[http https].include?(uri.scheme)
            @errors << "api_config.url must use http or https"
          end
        rescue URI::InvalidURIError
          @errors << "api_config.url is not a valid URL"
        end
      end

      if config['method'].present?
        unless %w[GET POST PUT PATCH DELETE].include?(config['method'].upcase)
          @errors << "api_config.method must be GET, POST, PUT, PATCH, or DELETE"
        end
      end

      if config['headers'].present? && !config['headers'].is_a?(Hash)
        @errors << "api_config.headers must be an object"
      end
    end

    def build_tool(params)
      ToolDefinition.create!(
        name: params[:name],
        description: params[:description],
        execution_type: params[:execution_type],
        parameters: params[:parameters] || params[:input_schema] || { type: 'object', properties: {} },
        code: params[:code],
        api_config: params[:api_config],
        admin_only: params[:admin_only] || false,
        is_public: params[:is_public] || false,
        created_by: @user,
        entity_id: @entity&.id
      )
    end

    def update_tool_attributes(tool, params)
      updateable = %i[name description execution_type parameters code api_config admin_only is_public]
      
      updateable.each do |attr|
        if params[attr].present?
          tool.send("#{attr}=", params[attr])
        end
      end

      # Handle input_schema as alias for parameters
      if params[:input_schema].present?
        tool.parameters = params[:input_schema]
      end
    end

    def can_edit?(tool)
      return true if @user.admin?
      return false if tool.created_by_id.nil? # System tools can't be edited by non-admins
      tool.created_by_id == @user.id
    end

    def test_tool(tool, test_args)
      begin
        result = tool.execute(test_args, { user: @user, entity: @entity })
        
        if result.is_a?(Hash) && result[:error].present?
          { success: false, error: result[:error] }
        else
          { success: true, result: result }
        end
      rescue => e
        { success: false, error: e.message }
      end
    end

    def generate_http_template(name, description)
      {
        name: name,
        description: description,
        execution_type: 'http_request',
        parameters: {
          type: 'object',
          properties: {
            query: {
              type: 'string',
              description: 'The query parameter'
            }
          },
          required: ['query']
        },
        api_config: {
          url: 'https://api.example.com/endpoint?q={{query}}',
          method: 'GET',
          headers: {
            'Authorization' => 'Bearer YOUR_API_KEY',
            'Content-Type' => 'application/json'
          }
        }
      }
    end

    def generate_ruby_template(name, description)
      {
        name: name,
        description: description,
        execution_type: 'ruby_code',
        parameters: {
          type: 'object',
          properties: {
            input: {
              type: 'string',
              description: 'The input to process'
            }
          },
          required: ['input']
        },
        code: <<~RUBY
          # Access input parameters via _args hash
          input = _args['input']
          
          # Access context (user, entity) via _context hash
          # user = _context[:user]
          # entity = _context[:entity]
          
          # Your logic here
          result = input.upcase
          
          # Return a hash with your result
          { success: true, result: result }
        RUBY
      }
    end
  end
end

