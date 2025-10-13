module Tools
  class TestIntegrationEndpointTool < BaseTool
    def self.read_only?
      true  # Testing doesn't modify data, just validates
    end
    
    def self.metadata
      {
        name: 'test_integration_endpoint',
        description: 'Test an integration endpoint to verify it works correctly',
        category: 'integration',
        input_schema: {
          type: 'object',
          properties: {
            integration_slug: {
              type: 'string',
              description: 'Slug of the integration to test'
            },
            endpoint_name: {
              type: 'string',
              description: 'Name of the endpoint/operation to test'
            },
            test_params: {
              type: 'object',
              description: 'Test parameters to pass to the endpoint'
            },
            connection_id: {
              type: 'integer',
              description: 'ID of the connection to use for testing (optional, will use first available)'
            }
          },
          required: ['integration_slug', 'endpoint_name']
        }
      }
    end
    
    def execute(args)
      log_execution(args)
      
      integration_slug = get_arg(args, :integration_slug)
      endpoint_name = get_arg(args, :endpoint_name)
      test_params = get_arg(args, :test_params, {})
      connection_id = get_arg(args, :connection_id)
      
      # Validate required args
      if error = validate_required_args(args, [:integration_slug, :endpoint_name])
        return error
      end
      
      begin
        # Find integration
        integration = find_integration(integration_slug)
        if !integration
          return error_response("Integration not found: #{integration_slug}")
        end
        
        # Find connection
        connection = find_connection(integration, connection_id)
        if !connection
          return error_response("No connection found for #{integration_slug}. Please create a connection first.")
        end
        
        # Test the endpoint
        tester = IntegrationEndpointTester.new(integration, connection)
        result = tester.test_endpoint(endpoint_name, test_params)
        
        if result[:success]
          success_response(
            message: "Endpoint test successful",
            endpoint: endpoint_name,
            response: result[:response],
            status_code: result[:status_code],
            response_time_ms: result[:response_time_ms],
            test_passed: true
          )
        else
          # Still return success but indicate test failed
          success_response(
            message: "Endpoint test completed with errors",
            endpoint: endpoint_name,
            error: result[:error],
            status_code: result[:status_code],
            response: result[:response],
            test_passed: false,
            troubleshooting: result[:troubleshooting]
          )
        end
      rescue => e
        Rails.logger.error "Integration endpoint test failed: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        error_response("Test failed: #{e.message}")
      end
    end
    
    private
    
    def find_integration(slug)
      Integration.find_by(slug: slug) ||
      Integration.find_by(name: slug.titleize)
    end
    
    def find_connection(integration, connection_id)
      if connection_id
        Connection.find_by(id: connection_id, integration: integration, entity: @entity)
      else
        # Find first active connection for this integration
        Connection.where(integration: integration, entity: @entity)
                 .where(status: 'active')
                 .order(created_at: :desc)
                 .first
      end
    end
  end
end

