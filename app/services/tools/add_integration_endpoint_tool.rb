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
        
        # Create IntegrationOperation record (secure DB-only approach!)
        operation = integration.integration_operations.create!(
          operation_id: endpoint_name.underscore,
          name: endpoint_name.titleize,
          description: description,
          http_method: http_method.upcase,
          path_template: endpoint_path,
          request_schema: generate_request_schema(parameters),
          response_schema: response_format || {},
          is_idempotent: http_method.upcase == 'GET',
          requires_confirmation: ['DELETE', 'POST', 'PUT', 'PATCH'].include?(http_method.upcase),
          is_enabled: true,
          metadata: {
            generated_by: 'ai_integration_builder',
            created_at: Time.current,
            parameters: parameters
          }
        )
        
        result = {
          success: true,
          operation_id: operation.id,
          method_name: endpoint_name.underscore
        }
        
        if result[:success]
          Rails.logger.info "✅ Created IntegrationOperation record (secure DB-only)"
          
          success_response(
            message: "Successfully added #{endpoint_name} endpoint to #{integration.name} (secure DB-only)",
            endpoint_name: endpoint_name,
            operation_id: endpoint_name.underscore,
            http_method: http_method,
            endpoint_path: endpoint_path,
            database_record_id: result[:operation_id],
            next_steps: [
              "Use execute_integration to call this endpoint",
              "Test with: execute_integration(integration: '#{integration.slug}', operation: '#{endpoint_name.underscore}', params: {...})",
              "Use list_operations to see all available operations",
              "Operation is securely stored in database (no code files)"
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

