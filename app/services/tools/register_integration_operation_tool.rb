module Tools
  class RegisterIntegrationOperationTool < BaseTool
    def self.metadata
      {
        name: 'register_integration_operation',
        description: 'Register a generated integration endpoint as an IntegrationOperation so it can be used with invoke_operation and list_operations tools',
        category: 'integration',
        input_schema: {
          type: 'object',
          properties: {
            integration_slug: {
              type: 'string',
              description: 'Slug of the integration (e.g., "stripe", "trello")'
            },
            operation_id: {
              type: 'string',
              description: 'Unique identifier for the operation (e.g., "create_customer", "move_card")'
            },
            name: {
              type: 'string',
              description: 'Human-readable name for the operation'
            },
            description: {
              type: 'string',
              description: 'Description of what this operation does'
            },
            http_method: {
              type: 'string',
              enum: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'],
              description: 'HTTP method used by this endpoint'
            },
            path_template: {
              type: 'string',
              description: 'API path template (e.g., "/v1/customers", "/cards/{id}")'
            },
            request_schema: {
              type: 'object',
              description: 'JSON schema for request parameters'
            },
            response_schema: {
              type: 'object',
              description: 'JSON schema for response format'
            },
            requires_confirmation: {
              type: 'boolean',
              description: 'Whether this operation requires user confirmation (default: false for GET, true for DELETE)'
            }
          },
          required: ['integration_slug', 'operation_id', 'name', 'http_method', 'path_template']
        }
      }
    end
    
    def execute(args)
      log_execution(args)
      
      integration_slug = get_arg(args, :integration_slug)
      operation_id = get_arg(args, :operation_id)
      name = get_arg(args, :name)
      description = get_arg(args, :description, "")
      http_method = get_arg(args, :http_method)
      path_template = get_arg(args, :path_template)
      request_schema = get_arg(args, :request_schema, {})
      response_schema = get_arg(args, :response_schema, {})
      requires_confirmation = get_arg(args, :requires_confirmation)
      
      # Auto-set requires_confirmation based on method if not provided
      if requires_confirmation.nil?
        requires_confirmation = ['DELETE', 'POST', 'PUT', 'PATCH'].include?(http_method.upcase)
      end
      
      # Validate required args
      if error = validate_required_args(args, [:integration_slug, :operation_id, :name, :http_method, :path_template])
        return error
      end
      
      begin
        # Find the integration
        integration = Integration.find_by(slug: integration_slug)
        
        if !integration
          return error_response("Integration not found: #{integration_slug}")
        end
        
        # Check if operation already exists
        existing_operation = integration.integration_operations.find_by(operation_id: operation_id)
        
        if existing_operation
          # Update existing operation
          existing_operation.update!(
            name: name,
            description: description,
            http_method: http_method.upcase,
            path_template: path_template,
            request_schema: request_schema,
            response_schema: response_schema,
            requires_confirmation: requires_confirmation,
            is_idempotent: http_method.upcase == 'GET',
            metadata: {
              generated_by: 'integration_builder',
              updated_at: Time.current
            }
          )
          
          success_response(
            message: "Updated operation: #{name}",
            operation_id: existing_operation.id,
            operation: format_operation(existing_operation),
            status: 'updated'
          )
        else
          # Create new operation
          operation = integration.integration_operations.create!(
            operation_id: operation_id,
            name: name,
            description: description,
            http_method: http_method.upcase,
            path_template: path_template,
            request_schema: request_schema,
            response_schema: response_schema,
            requires_confirmation: requires_confirmation,
            is_idempotent: http_method.upcase == 'GET',
            is_enabled: true,
            metadata: {
              generated_by: 'integration_builder',
              created_at: Time.current
            }
          )
          
          success_response(
            message: "Registered operation: #{name}",
            operation_id: operation.id,
            operation: format_operation(operation),
            status: 'created',
            next_steps: [
              "Use 'list_operations' to see all operations for #{integration.name}",
              "Use 'invoke_operation' with connection_id and operation_id to call this endpoint",
              "The operation is now available to all users with #{integration.name} connections"
            ]
          )
        end
      rescue => e
        Rails.logger.error "Register operation failed: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        error_response("Failed to register operation: #{e.message}")
      end
    end
    
    private
    
    def format_operation(operation)
      {
        id: operation.id,
        operation_id: operation.operation_id,
        name: operation.name,
        description: operation.description,
        http_method: operation.http_method,
        path_template: operation.path_template,
        request_schema: operation.request_schema || {},
        response_schema: operation.response_schema || {},
        requires_confirmation: operation.requires_confirmation,
        is_idempotent: operation.is_idempotent,
        is_enabled: operation.is_enabled
      }
    end
  end
end

