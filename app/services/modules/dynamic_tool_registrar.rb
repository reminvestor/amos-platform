# frozen_string_literal: true

# DynamicToolRegistrar
#
# Registers AI-generated tools at runtime from ToolDefinition records
# that are linked to AppModules.
#
module Modules
  class DynamicToolRegistrar
    include Singleton

    attr_reader :registered_tools

    def initialize
      @registered_tools = {}
      @mutex = Mutex.new
    end

    # Register all tools for a module
    def register_module_tools(app_module)
      app_module.tool_definitions.each do |tool_def|
        register_tool(tool_def)
      end
    end

    # Register a single tool
    def register_tool(tool_definition)
      @mutex.synchronize do
        return @registered_tools[tool_definition.id] if @registered_tools[tool_definition.id]

        begin
          # Register with the ToolCatalog
          catalog = Tools::ToolCatalog.instance
          catalog.register_definition(tool_definition)

          @registered_tools[tool_definition.id] = tool_definition.name
          Rails.logger.info "[DynamicToolRegistrar] Registered tool: #{tool_definition.name}"

          tool_definition.name
        rescue => e
          Rails.logger.error "[DynamicToolRegistrar] Failed to register #{tool_definition.name}: #{e.message}"
          nil
        end
      end
    end

    # Unregister a tool
    def unregister_tool(tool_definition)
      @mutex.synchronize do
        if @registered_tools.delete(tool_definition.id)
          # Remove from catalog
          catalog = Tools::ToolCatalog.instance
          catalog.unregister(tool_definition.name) if catalog.respond_to?(:unregister)
          
          Rails.logger.info "[DynamicToolRegistrar] Unregistered tool: #{tool_definition.name}"
        end
      end
    end

    # Create and register a new module tool
    def create_tool_for_module(app_module, tool_spec)
      tool_spec = tool_spec.deep_symbolize_keys

      tool_def = ToolDefinition.create!(
        name: tool_spec[:name],
        description: tool_spec[:description],
        parameters: tool_spec[:parameters] || {},
        execution_type: tool_spec[:execution_type] || 'ruby_code',
        code: tool_spec[:code],
        api_config: tool_spec[:api_config],
        entity: app_module.entity,
        app_module: app_module,
        created_by: app_module.created_by,
        scout_accessible: tool_spec[:scout_accessible] != false,
        is_public: false
      )

      # Register immediately
      register_tool(tool_def)

      # Update module components
      tools = app_module.tools_list
      tools << tool_def.name unless tools.include?(tool_def.name)
      app_module.update!(components: app_module.components.merge('tools' => tools))

      tool_def
    end

    # Generate a basic CRUD tool for a module model
    def create_crud_tools_for_model(app_module, model_code)
      model_name = model_code.name
      table_name = model_code.table_name
      
      tools = []

      # Create tool
      tools << create_tool_for_module(app_module, {
        name: "create_#{model_name.underscore}",
        description: "Create a new #{model_name.titleize}",
        parameters: {
          type: 'object',
          properties: build_properties_from_schema(model_code),
          required: required_fields_from_schema(model_code)
        },
        execution_type: 'ruby_code',
        code: generate_create_code(model_name, app_module.slug)
      })

      # Read/List tool
      tools << create_tool_for_module(app_module, {
        name: "list_#{model_name.underscore.pluralize}",
        description: "List all #{model_name.titleize.pluralize} with optional filters",
        parameters: {
          type: 'object',
          properties: {
            limit: { type: 'integer', description: 'Maximum number of records to return' },
            offset: { type: 'integer', description: 'Number of records to skip' },
            order_by: { type: 'string', description: 'Field to order by' },
            order_dir: { type: 'string', enum: %w[asc desc], description: 'Order direction' },
            filters: { type: 'object', description: 'Filter conditions' }
          }
        },
        execution_type: 'ruby_code',
        code: generate_list_code(model_name, app_module.slug)
      })

      # Update tool
      tools << create_tool_for_module(app_module, {
        name: "update_#{model_name.underscore}",
        description: "Update an existing #{model_name.titleize}",
        parameters: {
          type: 'object',
          properties: {
            id: { type: 'integer', description: 'ID of the record to update' },
            **build_properties_from_schema(model_code)
          },
          required: ['id']
        },
        execution_type: 'ruby_code',
        code: generate_update_code(model_name, app_module.slug)
      })

      # Delete tool
      tools << create_tool_for_module(app_module, {
        name: "delete_#{model_name.underscore}",
        description: "Delete a #{model_name.titleize}",
        parameters: {
          type: 'object',
          properties: {
            id: { type: 'integer', description: 'ID of the record to delete' }
          },
          required: ['id']
        },
        execution_type: 'ruby_code',
        code: generate_delete_code(model_name, app_module.slug)
      })

      tools
    end

    private

    def build_properties_from_schema(model_code)
      schema = model_code.schema_definition.deep_symbolize_keys
      properties = {}

      (schema[:fields] || []).each do |field|
        name = field[:name].to_s
        type = field_type_to_json_type(field[:type])
        
        properties[name] = {
          type: type,
          description: "#{name.titleize} field"
        }
      end

      properties
    end

    def required_fields_from_schema(model_code)
      schema = model_code.schema_definition.deep_symbolize_keys
      required = []

      (schema[:fields] || []).each do |field|
        required << field[:name].to_s if field[:null] == false
      end

      (schema[:validations] || []).each do |val|
        if val[:type].to_s == 'presence'
          required.concat(Array(val[:fields] || val[:field]).map(&:to_s))
        end
      end

      required.uniq
    end

    def field_type_to_json_type(type)
      case type.to_s
      when 'integer', 'bigint' then 'integer'
      when 'decimal', 'float' then 'number'
      when 'boolean' then 'boolean'
      when 'json', 'jsonb' then 'object'
      when 'array' then 'array'
      else 'string'
      end
    end

    def generate_create_code(model_name, module_slug)
      <<~RUBY
        # Create a new #{model_name}
        model_class = Modules::DynamicModelLoader.instance.get_model_by_path(_context[:entity], "#{module_slug}/#{model_name}")
        return { error: "Model not loaded" } unless model_class
        
        record = model_class.new(_args.except('entity_id'))
        record.entity = _context[:entity]
        
        if record.save
          { success: true, id: record.id, record: record.attributes }
        else
          { success: false, errors: record.errors.full_messages }
        end
      RUBY
    end

    def generate_list_code(model_name, module_slug)
      <<~RUBY
        # List #{model_name.pluralize}
        model_class = Modules::DynamicModelLoader.instance.get_model_by_path(_context[:entity], "#{module_slug}/#{model_name}")
        return { error: "Model not loaded" } unless model_class
        
        records = model_class.where(entity: _context[:entity])
        
        # Apply filters
        if _args['filters'].present?
          _args['filters'].each do |field, value|
            records = records.where(field => value)
          end
        end
        
        # Apply ordering
        if _args['order_by'].present?
          dir = _args['order_dir'] || 'asc'
          records = records.order(_args['order_by'] => dir)
        end
        
        # Apply limit/offset
        records = records.limit(_args['limit'] || 100)
        records = records.offset(_args['offset']) if _args['offset'].present?
        
        { success: true, count: records.count, records: records.map(&:attributes) }
      RUBY
    end

    def generate_update_code(model_name, module_slug)
      <<~RUBY
        # Update a #{model_name}
        model_class = Modules::DynamicModelLoader.instance.get_model_by_path(_context[:entity], "#{module_slug}/#{model_name}")
        return { error: "Model not loaded" } unless model_class
        
        record = model_class.find_by(id: _args['id'], entity: _context[:entity])
        return { success: false, error: "Record not found" } unless record
        
        if record.update(_args.except('id', 'entity_id'))
          { success: true, record: record.attributes }
        else
          { success: false, errors: record.errors.full_messages }
        end
      RUBY
    end

    def generate_delete_code(model_name, module_slug)
      <<~RUBY
        # Delete a #{model_name}
        model_class = Modules::DynamicModelLoader.instance.get_model_by_path(_context[:entity], "#{module_slug}/#{model_name}")
        return { error: "Model not loaded" } unless model_class
        
        record = model_class.find_by(id: _args['id'], entity: _context[:entity])
        return { success: false, error: "Record not found" } unless record
        
        record.destroy
        { success: true, message: "#{model_name} deleted successfully" }
      RUBY
    end
  end
end


