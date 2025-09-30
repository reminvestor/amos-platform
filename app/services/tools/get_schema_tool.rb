module Tools
  class GetSchemaTool < BaseTool
    def self.read_only?
      true  # This tool only provides schema information
    end
    
    def self.metadata
      {
        name: 'get_schema',
        description: 'Get database schema and field information for any object type',
        category: 'data',
        input_schema: {
          type: 'object',
          properties: {
            object_type: {
              type: 'string',
              description: "The type of object to get schema for (e.g., 'campaign', 'contact')"
            }
          },
          required: ['object_type']
        }
      }
    end
    
    def execute(args)
      log_execution(args)
      
      object_type = get_arg(args, :object_type)
      
      # Validate required args
      if error = validate_required_args(args, [:object_type])
        return error
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
        error_response(
          "Schema not found for object type: #{object_type}",
          available_types: available_types
        )
      end
    rescue => e
      Rails.logger.error "GetSchemaTool error: #{e.message}"
      error_response("Schema retrieval failed: #{e.message}")
    end
  end
end
