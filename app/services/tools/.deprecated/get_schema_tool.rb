module Tools
  class GetSchemaTool < BaseTool
    def self.read_only?
      true  # This tool only provides schema information
    end

    def self.metadata
      {
        name: "get_schema",
        description: "Get database schema and field information for any object type",
        category: "data",
        input_schema: {
          type: "object",
          properties: {
            object_type: {
              type: "string",
              description: "The type of object to get schema for (e.g., 'campaign', 'contact')"
            }
          },
          required: [ "object_type" ]
        }
      }
    end

    def execute(args)
      log_execution(args)

      object_type = get_arg(args, :object_type)

      # Validate required args
      if error = validate_required_args(args, [ :object_type ])
        return error
      end

      # Check for dynamic module first
      config = ScoutDataRegistry.object_config(object_type, entity)
      if config && config[:dynamic]
        return get_module_schema(object_type, config)
      end

      # Use ScoutSchemaService for comprehensive schema
      schema_data = ScoutSchemaService.get_model_schema(object_type)

      if schema_data
        success_response(
          object_type: object_type,
          schema: schema_data,
          table_name: schema_data[:table_name],
          fields: schema_data[:fields],
          required_fields: schema_data[:required_fields],
          relationships: schema_data[:relationships],
          example_data: schema_data[:example_data],
          creation_notes: schema_data[:creation_notes]
        )
      else
        available_types = ScoutSchemaService.get_all_available_models.map { |m| m[:model_name] }
        # Add dynamic module types
        if entity
          entity.app_modules.active.each do |mod|
            available_types << mod.slug
            available_types << mod.slug.pluralize
          end
        end
        error_response(
          "Schema not found for object type: #{object_type}",
          available_types: available_types
        )
      end
    rescue => e
      Rails.logger.error "GetSchemaTool error: #{e.message}"
      error_response("Schema retrieval failed: #{e.message}")
    end
    
    private
    
    def get_module_schema(object_type, config)
      # Try exact match first, then singular
      app_module = entity.app_modules.active.find_by(slug: object_type.to_s)
      app_module ||= entity.app_modules.active.find_by(slug: object_type.to_s.singularize)
      
      unless app_module
        return error_response("Module not found: #{slug}")
      end
      
      schema = app_module.metadata&.dig('schema') || {}
      fields = schema['fields'] || []
      
      # Build field info
      field_info = fields.map do |f|
        {
          name: f['name'],
          type: f['field_type'] || f['type'] || 'string',
          required: f['required'] == true,
          description: f['description'],
          default: f['default_value']
        }
      end
      
      success_response(
        object_type: object_type,
        module_name: app_module.name,
        module_slug: app_module.slug,
        table_name: app_module.slug.pluralize,
        description: app_module.description,
        fields: field_info,
        required_fields: fields.select { |f| f['required'] }.map { |f| f['name'] },
        relationships: ['entity'],
        creation_notes: "Use create_object with object_type: '#{app_module.slug.pluralize}'"
      )
    end
  end
end
