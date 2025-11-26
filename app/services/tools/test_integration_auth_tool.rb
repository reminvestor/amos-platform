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
          2. You must have obtained credentials from the user
          
          **What this does:**
          1. Stores the credentials securely
          2. Makes a test API call to the test_endpoint
          3. Verifies the response is successful
          4. Marks the connection as 'connected' if successful
          
          **If the test fails:**
          - Check the error message for hints
          - Verify auth_placement is correct (header vs query)
          - Verify auth_configs have correct parameter names
          - Ask user to verify their credentials
          
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
            },
            credentials: {
              type: "object",
              description: "User's credentials. Keys should match placeholders in auth_configs.",
              properties: {
                api_key: { type: "string", description: "API key (for api_key auth)" },
                token: { type: "string", description: "Token (for bearer_token or Trello-style)" },
                username: { type: "string", description: "Username (for basic_auth)" },
                password: { type: "string", description: "Password (for basic_auth)" },
                access_token: { type: "string", description: "OAuth access token" },
                refresh_token: { type: "string", description: "OAuth refresh token" }
              },
              additionalProperties: true
            }
          },
          required: %w[integration_id credentials]
        }
      }
    end

    def execute(args)
      log_execution(args.except("credentials")) # Don't log credentials!

      factory = Factories::IntegrationFactory.new(user: @user, entity: @entity)

      result = factory.test_auth(
        integration_id: args["integration_id"],
        credentials: args["credentials"]
      )

      if result[:success]
        success_response(
          message: "✅ Authentication test passed! The integration is now connected.",
          integration_id: result[:integration].id,
          integration_name: result[:integration].name,
          connection_status: "connected",
          test_response: result[:test_response],
          next_step: "STAGE 4: Research API endpoints, then call add_integration_operations",
          research_prompts: [
            "#{result[:integration].name} API endpoints list",
            "#{result[:integration].name} API common operations",
            "#{result[:integration].name} API reference documentation"
          ]
        )
      else
        error_response(
          "Authentication test failed: #{result[:error]}",
          status_code: result[:status_code],
          suggestion: result[:suggestion],
          debug_info: result[:debug_info]
        )
      end
    rescue => e
      Rails.logger.error "TestIntegrationAuthTool error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      error_response("Failed to test auth: #{e.message}")
    end
  end
end

