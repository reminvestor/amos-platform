module Tools
  class AddIntegrationEndpointTool < BaseTool
    def self.metadata
      {
        name: 'add_integration_endpoint',
        description: 'Add a new endpoint/operation to an existing integration',
        category: 'integration',
        input_schema: {
          type: 'object',
          properties: {
            integration_slug: {
              type: 'string',
              description: 'Slug of the integration to add endpoint to (e.g., "stripe", "trello")'
            },
            endpoint_name: {
              type: 'string',
              description: 'Name of the endpoint/operation (e.g., "create_customer", "move_card", "send_message")'
            },
            http_method: {
              type: 'string',
              enum: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'],
              description: 'HTTP method for the endpoint (default: GET)'
            },
            endpoint_path: {
              type: 'string',
              description: 'API path for the endpoint (e.g., "/v1/customers", "/cards/{id}/move")'
            },
            parameters: {
              type: 'object',
              description: 'Parameters the endpoint accepts with their types (e.g., {"email": "string", "name": "string"})'
            },
            response_format: {
              type: 'object',
              description: 'Expected response structure (optional, for documentation)'
            },
            description: {
              type: 'string',
              description: 'Description of what this endpoint does'
            }
          },
          required: ['integration_slug', 'endpoint_name', 'endpoint_path']
        }
      }
    end
    
    def execute(args)
      log_execution(args)
      
      integration_slug = get_arg(args, :integration_slug)
      endpoint_name = get_arg(args, :endpoint_name)
      http_method = get_arg(args, :http_method, 'GET')
      endpoint_path = get_arg(args, :endpoint_path)
      parameters = get_arg(args, :parameters, {})
      response_format = get_arg(args, :response_format, {})
      description = get_arg(args, :description, "#{endpoint_name.titleize} endpoint")
      
      # Validate required args
      if error = validate_required_args(args, [:integration_slug, :endpoint_name, :endpoint_path])
        return error
      end
      
      begin
        # Find the integration
        integration = find_integration(integration_slug)
        
        if !integration
          return error_response("Integration not found: #{integration_slug}. Please create the integration scaffold first.")
        end
        
        # Use the code generator service
        code_gen_service = IntegrationCodeGeneratorService.new
        result = code_gen_service.generate_code(
          integration: integration,
          code_type: 'endpoint',
          endpoint_name: endpoint_name,
          http_method: http_method,
          endpoint_path: endpoint_path,
          parameters: parameters,
          response_format: response_format,
          documentation: description
        )
        
        if result[:success]
          # Automatically discover operations to sync to database
          Rails.logger.info "🔍 Running auto-discovery for #{integration.name}..."
          discovery_result = OperationDiscoveryService.discover_integration(integration.slug)
          
          success_response(
            message: "Successfully added #{endpoint_name} endpoint to #{integration.name}",
            endpoint_name: endpoint_name,
            method_name: result[:method_name],
            http_method: http_method,
            endpoint_path: endpoint_path,
            file_path: result[:file_path],
            code: result[:code],
            usage_example: result[:usage_example],
            operations_discovered: discovery_result&.length || 0,
            next_steps: [
              "Use execute_integration to call this endpoint",
              "Use list_operations to see all available operations",
              "Test with: execute_integration(integration: '#{integration.slug}', operation: '#{endpoint_name.underscore}', params: {...})",
              "Review the generated code in #{result[:file_path]}"
            ]
          )
        else
          error_response("Failed to add endpoint: #{result[:error]}")
        end
      rescue => e
        Rails.logger.error "Add endpoint failed: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        error_response("Failed to add endpoint: #{e.message}")
      end
    end
    
    private
    
    def find_integration(slug)
      Integration.find_by(slug: slug) ||
      Integration.find_by(name: slug.titleize)
    end
    
    def generate_request_schema(parameters)
      return {} if parameters.empty?
      
      {
        type: 'object',
        properties: parameters.transform_values { |type|
          { type: normalize_type(type) }
        },
        required: parameters.keys
      }
    end
    
    def normalize_type(type)
      case type.to_s.downcase
      when 'string', 'text'
        'string'
      when 'integer', 'int', 'number'
        'integer'
      when 'float', 'decimal'
        'number'
      when 'boolean', 'bool'
        'boolean'
      when 'array', 'list'
        'array'
      when 'object', 'hash'
        'object'
      else
        'string'
      end
    end
  end
end

