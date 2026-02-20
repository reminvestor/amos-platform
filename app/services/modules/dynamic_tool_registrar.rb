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

      # Use find_or_initialize matching name + entity (the unique constraint)
      # This handles reinstalls AND orphaned tools from failed builds
      tool_def = ToolDefinition.find_or_initialize_by(
        name: tool_spec[:name],
        entity: app_module.entity
      )
      
      # Update attributes (whether new or existing)
      tool_def.assign_attributes(
        description: tool_spec[:description],
        parameters: tool_spec[:parameters] || {},
        execution_type: tool_spec[:execution_type] || 'ruby_code',
        code: tool_spec[:code],
        api_config: tool_spec[:api_config],
        app_module: app_module,
        created_by: app_module.created_by,
        scout_accessible: tool_spec[:scout_accessible] != false,
        is_public: false
      )
      
      tool_def.save!

      # Register immediately
      register_tool(tool_def)

      # Update module components
      tools = app_module.tools_list
      tools << tool_def.name unless tools.include?(tool_def.name)
      app_module.update!(components: app_module.components.merge('tools' => tools))

      tool_def
    end

    # DEPRECATED: CRUD tools are no longer generated per-module.
    # The V3 platform tools (platform_create, platform_query, platform_update,
    # platform_execute) handle all custom module CRUD natively via
    # ScoutDataRegistry and resolve_dynamic_model.
    def create_crud_tools_for_model(app_module, model_code)
      Rails.logger.info "[DynamicToolRegistrar] Skipping CRUD tool generation for #{app_module.slug}/#{model_code.name} - handled by platform tools"
      []
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
        
        # Get allowed columns for security - whitelist approach
        allowed_columns = model_class.column_names - ['id', 'entity_id', 'created_at', 'updated_at']
        safe_params = _args.slice(*allowed_columns)
        
        record = model_class.new(safe_params)
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
        
        # Get allowed columns for security - whitelist approach
        allowed_columns = model_class.column_names - ['id', 'entity_id', 'created_at', 'updated_at']
        safe_params = _args.slice(*allowed_columns)
        
        if record.update(safe_params)
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


