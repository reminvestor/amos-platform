module Tools
  class TestIntegrationAuthTool < BaseTool
    def self.metadata
      {
        name: "test_integration_auth",
        description: <<~DESC.strip,
          **STAGE 3 of 4: Test Integration Authentication**
          
          Tests that the user's credentials work with the configured authentication.
          This MUST pass before adding operations.
          
          **Before calling this tool:**
          1. configure_integration_auth must have been called (Stage 2)
          2. User must have entered credentials via Settings → Integrations screen
          3. NEVER ask for credentials in chat!
          
          **What this does:**
          1. Uses credentials already stored in the system (entered via UI)
          2. Makes a test API call to the test_endpoint
          3. Returns the ACTUAL API response (for troubleshooting)
          4. Marks the connection as 'connected' if successful
          
          **If the test fails:**
          - Review the actual API response to understand the error
          - Check auth_placement is correct (header vs query)
          - Check auth_configs have correct parameter names
          - Help user troubleshoot based on the response
          - Have user update credentials via Integrations screen and test again
          
          **After this succeeds, call:**
          → add_integration_operations (Stage 4)
        DESC
        category: "integration",
        input_schema: {
          type: "object",
          properties: {
            integration_id: {
              type: "integer",
              description: "Integration ID from previous stages"
            }
          },
          required: %w[integration_id]
        }
      }
    end

    def execute(args)
      log_execution(args)

      factory = Factories::IntegrationFactory.new(user: @user, entity: @entity)

      # Test using credentials already stored in the system
      result = factory.test_auth(
        integration_id: args["integration_id"]
      )

      if result[:success]
        success_response(
          message: "✅ Authentication test passed! The integration is now connected.",
          integration_id: result[:integration].id,
          integration_name: result[:integration].name,
          connection_status: "connected",
          api_response: result[:test_response],
          next_step: "STAGE 4: Research API endpoints, then call add_integration_operations",
          research_prompts: [
            "#{result[:integration].name} API endpoints list",
            "#{result[:integration].name} API common operations",
            "#{result[:integration].name} API reference documentation"
          ]
        )
      else
        # Return detailed info so agent can help troubleshoot
        error_response(
          "Authentication test failed",
          api_response: result[:api_response],
          status_code: result[:status_code],
          error_message: result[:error],
          suggestion: result[:suggestion],
          debug_info: result[:debug_info],
          troubleshooting_tips: [
            "Review the api_response above to understand what the API returned",
            "If status_code is 401/403: credentials may be wrong or expired",
            "If status_code is 404: test_endpoint path may be incorrect",
            "Have the user verify/update credentials at Settings → Integrations",
            "Once updated, call test_integration_auth again"
          ]
        )
      end
    rescue => e
      Rails.logger.error "TestIntegrationAuthTool error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      error_response("Failed to test auth: #{e.message}")
    end
  end
end

