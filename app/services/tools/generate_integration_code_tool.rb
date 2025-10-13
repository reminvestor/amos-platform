module Tools
  class GenerateIntegrationCodeTool < BaseTool
    def self.metadata
      {
        name: 'generate_integration_code',
        description: 'Generate specific integration code for API endpoints, authentication, or operations',
        category: 'integration',
        input_schema: {
          type: 'object',
          properties: {
            integration_slug: {
              type: 'string',
              description: 'Slug of the integration to generate code for'
            },
            code_type: {
              type: 'string',
              enum: ['endpoint', 'auth', 'operation', 'error_handler'],
              description: 'Type of code to generate'
            },
            endpoint_name: {
              type: 'string',
              description: 'Name of the endpoint/operation (e.g., "get_customer", "create_charge")'
            },
            http_method: {
              type: 'string',
              enum: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'],
              description: 'HTTP method for the endpoint'
            },
            endpoint_path: {
              type: 'string',
              description: 'API path for the endpoint (e.g., "/v1/customers")'
            },
            parameters: {
              type: 'object',
              description: 'Parameters the endpoint accepts'
            },
            response_format: {
              type: 'object',
              description: 'Expected response structure'
            },
            documentation: {
              type: 'string',
              description: 'Additional documentation or context for code generation'
            }
          },
          required: ['integration_slug', 'code_type']
        }
      }
    end
    
    def execute(args)
      log_execution(args)
      
      integration_slug = get_arg(args, :integration_slug)
      code_type = get_arg(args, :code_type)
      endpoint_name = get_arg(args, :endpoint_name)
      http_method = get_arg(args, :http_method, 'GET')
      endpoint_path = get_arg(args, :endpoint_path)
      parameters = get_arg(args, :parameters, {})
      response_format = get_arg(args, :response_format, {})
      documentation = get_arg(args, :documentation)
      
      # Validate required args
      if error = validate_required_args(args, [:integration_slug, :code_type])
        return error
      end
      
      begin
        # Find the integration
        integration = find_integration(integration_slug)
        
        if !integration
          return error_response("Integration not found: #{integration_slug}")
        end
        
        # Generate code using service
        code_gen_service = IntegrationCodeGeneratorService.new
        result = code_gen_service.generate_code(
          integration: integration,
          code_type: code_type,
          endpoint_name: endpoint_name,
          http_method: http_method,
          endpoint_path: endpoint_path,
          parameters: parameters,
          response_format: response_format,
          documentation: documentation
        )
        
        if result[:success]
          success_response(
            message: "Successfully generated #{code_type} code",
            code: result[:code],
            file_path: result[:file_path],
            method_name: result[:method_name],
            usage_example: result[:usage_example]
          )
        else
          error_response("Code generation failed: #{result[:error]}")
        end
      rescue => e
        Rails.logger.error "Integration code generation failed: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        error_response("Code generation failed: #{e.message}")
      end
    end
    
    private
    
    def find_integration(slug)
      Integration.find_by(slug: slug) ||
      Integration.find_by(name: slug.titleize)
    end
  end
end

