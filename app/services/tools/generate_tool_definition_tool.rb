# frozen_string_literal: true

# GenerateToolDefinitionTool
#
# Platform Factory tool that generates tool definitions for modules.
# These tools can interact with module data models and perform actions.
#
class Tools::GenerateToolDefinitionTool < Tools::BaseTool
  def self.metadata
    {
      name: 'generate_tool_definition',
      description: 'Generates a tool definition for a module. The tool can perform CRUD operations, custom queries, or external integrations.',
      category: 'platform_factory',
      input_schema: {
        type: 'object',
        properties: {
          module_slug: {
            type: 'string',
            description: 'Slug of the module this tool belongs to'
          },
          tool_name: {
            type: 'string',
            description: 'Name of the tool (snake_case, e.g., "calculate_inventory_value")'
          },
          description: {
            type: 'string',
            description: 'Human-readable description of what the tool does'
          },
          tool_type: {
            type: 'string',
            enum: %w[crud query action integration],
            description: 'Type of tool: crud (auto-generate CRUD), query (custom data query), action (custom action), integration (external API)'
          },
          model_name: {
            type: 'string',
            description: 'For crud/query types - the model to operate on'
          },
          parameters: {
            type: 'object',
            description: 'Custom parameters schema for the tool'
          },
          custom_code: {
            type: 'string',
            description: 'For action type - custom Ruby code to execute'
          },
          api_config: {
            type: 'object',
            description: 'For integration type - HTTP API configuration'
          }
        },
        required: %w[module_slug tool_name description tool_type]
      }
    }
  end

  def execute(args)
    log_execution(args)

    module_slug = get_arg(args, :module_slug)
    tool_name = get_arg(args, :tool_name)
    description = get_arg(args, :description)
    tool_type = get_arg(args, :tool_type, 'action')
    model_name = get_arg(args, :model_name)
    parameters = get_arg(args, :parameters, {})
    custom_code = get_arg(args, :custom_code)
    api_config = get_arg(args, :api_config)

    return error_response('Module slug is required') if module_slug.blank?
    return error_response('Tool name is required') if tool_name.blank?
    return error_response('Description is required') if description.blank?

    # Validate tool name format
    unless tool_name.match?(/\A[a-z][a-z0-9_]*\z/)
      return error_response('Tool name must be snake_case (lowercase letters, numbers, underscores)')
    end

    # Find the module
    app_module = AppModule.find_by(entity: entity, slug: module_slug)
    return error_response("Module not found: #{module_slug}") unless app_module

    case tool_type
    when 'crud'
      create_crud_tools(app_module, model_name)
    when 'query'
      create_query_tool(app_module, tool_name, description, model_name, parameters)
    when 'action'
      create_action_tool(app_module, tool_name, description, parameters, custom_code)
    when 'integration'
      create_integration_tool(app_module, tool_name, description, parameters, api_config)
    else
      error_response("Unknown tool type: #{tool_type}")
    end
  end

  private

  def create_crud_tools(app_module, model_name)
    return error_response('Model name is required for CRUD tools') if model_name.blank?

    model_code = app_module.module_codes.models.find_by(name: model_name)
    return error_response("Model not found: #{model_name}") unless model_code

    # Use DynamicToolRegistrar to create CRUD tools
    registrar = Modules::DynamicToolRegistrar.instance
    tools = registrar.create_crud_tools_for_model(app_module, model_code)

    success_response(
      tools_created: tools.map(&:name),
      count: tools.count,
      message: "Created #{tools.count} CRUD tools for #{model_name}",
      next_step: 'Tools are now available for use'
    )
  end

  def create_query_tool(app_module, tool_name, description, model_name, parameters)
    return error_response('Model name is required for query tools') if model_name.blank?

    # Generate query code
    code = generate_query_code(model_name, app_module.slug, parameters)

    # Build parameters schema
    params_schema = {
      type: 'object',
      properties: parameters.present? ? parameters : default_query_params,
      required: []
    }

    tool_def = create_tool_definition(
      app_module: app_module,
      name: tool_name,
      description: description,
      parameters: params_schema,
      code: code
    )

    success_response(
      tool_id: tool_def.id,
      tool_name: tool_def.name,
      message: "Created query tool: #{tool_name}",
      next_step: 'Tool is now available for use'
    )
  end

  def create_action_tool(app_module, tool_name, description, parameters, custom_code)
    # Validate code if provided
    if custom_code.present?
      validation = validate_code(custom_code)
      return error_response("Code validation failed: #{validation[:error]}") unless validation[:valid]
    else
      custom_code = generate_placeholder_code(tool_name)
    end

    params_schema = {
      type: 'object',
      properties: parameters.present? ? parameters : {},
      required: []
    }

    tool_def = create_tool_definition(
      app_module: app_module,
      name: tool_name,
      description: description,
      parameters: params_schema,
      code: custom_code
    )

    success_response(
      tool_id: tool_def.id,
      tool_name: tool_def.name,
      message: "Created action tool: #{tool_name}",
      next_step: 'Tool is now available for use'
    )
  end

  def create_integration_tool(app_module, tool_name, description, parameters, api_config)
    return error_response('API config is required for integration tools') if api_config.blank?
    return error_response('API config must include url') unless api_config['url'].present?

    params_schema = {
      type: 'object',
      properties: parameters.present? ? parameters : {},
      required: []
    }

    tool_def = ToolDefinition.create!(
      name: tool_name,
      description: description,
      parameters: params_schema,
      execution_type: 'http_request',
      api_config: api_config,
      entity: entity,
      app_module: app_module,
      created_by: user,
      scout_accessible: true,
      is_public: false
    )

    # Register with catalog
    Modules::DynamicToolRegistrar.instance.register_tool(tool_def)

    # Update module components
    update_module_tools(app_module, tool_name)

    success_response(
      tool_id: tool_def.id,
      tool_name: tool_def.name,
      message: "Created integration tool: #{tool_name}",
      next_step: 'Tool is now available for use'
    )
  end

  def create_tool_definition(app_module:, name:, description:, parameters:, code:)
    tool_def = ToolDefinition.create!(
      name: name,
      description: description,
      parameters: parameters,
      execution_type: 'ruby_code',
      code: code,
      entity: entity,
      app_module: app_module,
      created_by: user,
      scout_accessible: true,
      is_public: false
    )

    # Register with catalog
    Modules::DynamicToolRegistrar.instance.register_tool(tool_def)

    # Update module components
    update_module_tools(app_module, name)

    tool_def
  end

  def update_module_tools(app_module, tool_name)
    tools = app_module.tools_list
    tools << tool_name unless tools.include?(tool_name)
    app_module.update!(components: app_module.components.merge('tools' => tools))
  end

  def default_query_params
    {
      'limit' => { type: 'integer', description: 'Maximum records to return', default: 100 },
      'offset' => { type: 'integer', description: 'Number of records to skip' },
      'order_by' => { type: 'string', description: 'Field to order by' },
      'filters' => { type: 'object', description: 'Filter conditions' }
    }
  end

  def generate_query_code(model_name, module_slug, parameters)
    <<~RUBY
      # Query #{model_name} records
      model_class = Modules::DynamicModelLoader.instance.get_model_by_path(
        _context[:entity], 
        "#{module_slug}/#{model_name}"
      )
      return { error: "Model not loaded" } unless model_class
      
      # Get allowed columns for security validation
      allowed_columns = model_class.column_names
      
      records = model_class.where(entity: _context[:entity])
      
      # Apply filters (only for valid columns to prevent SQL injection)
      if _args['filters'].present?
        _args['filters'].each do |field, value|
          field_str = field.to_s
          if allowed_columns.include?(field_str)
            records = records.where(field_str => value)
          end
        end
      end
      
      # Apply ordering (only for valid columns to prevent SQL injection)
      if _args['order_by'].present?
        order_field = _args['order_by'].to_s
        if allowed_columns.include?(order_field)
          dir = _args['order_dir'].to_s == 'desc' ? :desc : :asc
          records = records.order(order_field => dir)
        end
      end
      
      # Apply limit/offset
      limit = [(_args['limit'] || 100).to_i, 1000].min  # Cap at 1000
      records = records.limit(limit)
      records = records.offset(_args['offset'].to_i) if _args['offset'].present?
      
      { 
        success: true, 
        count: records.count, 
        records: records.map(&:attributes) 
      }
    RUBY
  end

  def generate_placeholder_code(tool_name)
    <<~RUBY
      # Custom action: #{tool_name}
      # TODO: Implement custom logic
      
      result = {
        success: true,
        message: "#{tool_name} executed successfully",
        args: _args
      }
      
      result
    RUBY
  end

  def validate_code(code)
    # Basic security checks
    dangerous_patterns = [
      /\bFile\./,
      /\bIO\./,
      /\bDir\./,
      /\bsystem\(/,
      /\bexec\(/,
      /\b`[^`]+`/,
      /\b%x\(/,
      /\bKernel\./,
      /\bProcess\./,
      /\brequire\s/,
      /\bload\s/,
      /\beval\(/
    ]

    dangerous_patterns.each do |pattern|
      if code.match?(pattern)
        return { valid: false, error: "Code contains dangerous pattern: #{pattern.source}" }
      end
    end

    # Syntax check
    begin
      RubyVM::InstructionSequence.compile(code)
      { valid: true }
    rescue SyntaxError => e
      { valid: false, error: "Syntax error: #{e.message}" }
    end
  end
end


