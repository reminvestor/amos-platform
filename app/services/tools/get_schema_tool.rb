module Tools
  class GetSchemaTool < BaseTool
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
      schema_service = ScoutSchemaService.new
      result = schema_service.get_schema(object_type)
      
      if result[:success]
        success_response(
          object_type: object_type,
          schema: result[:schema],
          relationships: result[:relationships],
          available_types: result[:available_types]
        )
      else
        error_response(
          result[:error],
          available_types: result[:available_types]
        )
      end
    rescue => e
      Rails.logger.error "GetSchemaTool error: #{e.message}"
      error_response("Schema retrieval failed: #{e.message}")
    end
  end
end
