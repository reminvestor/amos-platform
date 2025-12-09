module Tools
  class ConfigureIntegrationAuthTool < BaseTool
    def self.metadata
      {
        name: "configure_integration_auth",
        description: <<~DESC.strip,
          **STAGE 2 of 4: Configure Integration Authentication**
          
          This configures HOW the API authenticates requests. This is CRITICAL - get it right!
          
          **Before calling this tool:**
          1. Research the EXACT authentication method from official docs
          2. Determine WHERE auth goes: header, query parameter, or URL path
          3. Identify the EXACT parameter names (e.g., 'key' vs 'api_key' vs 'X-API-Key')
          4. Find a test endpoint to verify credentials
          
          **Auth Type Guide:**
          - api_key: Key sent in header OR query param
          - bearer_token: Token sent as "Authorization: Bearer <token>"
          - basic_auth: Username:password encoded in Authorization header
          - oauth2: Full OAuth 2.0 flow
          - no_auth: No authentication required (public APIs like JSONPlaceholder)
          
          **Auth Placement Guide (CRITICAL!):**
          - header: Auth in HTTP header (most common)
          - query: Auth in URL query params (e.g., Trello uses ?key=X&token=Y)
          - url: Auth embedded in URL path (rare)
          
          **Examples:**
          - Stripe: basic_auth, header, API key as username
          - Trello: api_key, query, params named 'key' and 'token'
          - OpenAI: bearer_token, header, "Authorization: Bearer sk-..."
          
          **After this succeeds, you MUST:**
          1. Tell the user to go to Settings → Integrations to enter their credentials
          2. NEVER ask for credentials in chat (security risk!)
          3. Once user reports they've entered credentials, call test_integration_auth (Stage 3)
          4. If test fails, review the API response and help troubleshoot
        DESC
        category: "integration",
        input_schema: {
          type: "object",
          properties: {
            integration_id: {
              type: "integer",
              description: "Integration ID from create_integration_foundation"
            },
            auth_type: {
              type: "string",
              enum: %w[api_key bearer_token basic_auth oauth2 no_auth],
              description: "Authentication method - MUST match what the API actually uses. Use 'no_auth' for public APIs."
            },
            auth_placement: {
              type: "string",
              enum: %w[header query url],
              description: "WHERE auth credentials are sent. CRITICAL: Trello=query, Stripe=header, etc."
            },
            test_endpoint: {
              type: "string",
              description: "A simple GET endpoint to verify credentials (e.g., '/1/members/me', '/v1/account')"
            },
            
            # Auth configs - flexible key-value pairs
            auth_configs: {
              type: "array",
              description: "Authentication parameters. Each item defines one auth parameter.",
              items: {
                type: "object",
                properties: {
                  key: { 
                    type: "string", 
                    description: "Parameter name (e.g., 'Authorization', 'key', 'X-API-Key')" 
                  },
                  value: { 
                    type: "string", 
                    description: "Value template with placeholders (e.g., 'Bearer {token}', '{api_key}')" 
                  },
                  placement: { 
                    type: "string", 
                    enum: %w[header query url],
                    description: "Where this specific param goes (inherits from auth_placement if not set)"
                  }
                },
                required: %w[key value]
              }
            },

            # Legacy fields for simpler auth
            auth_header_name: {
              type: "string",
              description: "For simple header auth: Header name (e.g., 'X-API-Key')"
            },
            
            # Basic auth specific
            username_label: {
              type: "string",
              description: "For basic_auth: Label for username field (e.g., 'API Key')"
            },
            password_required: {
              type: "boolean",
              description: "For basic_auth: Whether password is required"
            },

            # OAuth2 specific
            authorize_url: {
              type: "string",
              description: "For oauth2: Authorization URL"
            },
            token_url: {
              type: "string",
              description: "For oauth2: Token exchange URL"
            },
            scopes: {
              type: "array",
              items: { type: "string" },
              description: "For oauth2: Required scopes"
            },
            callback_params: {
              type: "array",
              items: { type: "string" },
              description: "For oauth2: Extra params from callback to save"
            }
          },
          required: %w[integration_id auth_type]  # auth_placement and test_endpoint optional for no_auth
        }
      }
    end

    def execute(args)
      log_execution(args)

      factory = Factories::IntegrationFactory.new(user: @user, entity: @entity)

      result = factory.configure_auth(
        integration_id: args["integration_id"],
        auth_type: args["auth_type"],
        auth_placement: args["auth_placement"],
        test_endpoint: args["test_endpoint"],
        auth_configs: args["auth_configs"],
        auth_header_name: args["auth_header_name"],
        username_label: args["username_label"],
        password_required: args["password_required"],
        authorize_url: args["authorize_url"],
        token_url: args["token_url"],
        scopes: args["scopes"],
        callback_params: args["callback_params"]
      )

      if result[:success]
        integration = result[:integration]
        
        # Build user instructions based on auth type
        user_instructions = build_user_instructions(args["auth_type"], integration.name)
        
        success_response(
          message: "✅ Authentication configured! User needs to enter credentials via the Integrations screen.",
          integration_id: integration.id,
          integration_name: integration.name,
          auth_type: args["auth_type"],
          auth_placement: args["auth_placement"],
          test_endpoint: args["test_endpoint"],
          status: "pending_credentials",
          next_step: "Tell the user to go to Settings → Integrations → #{integration.name} to enter their credentials. Once they confirm, call test_integration_auth to verify.",
          user_instructions: user_instructions,
          auth_configs_created: result[:auth_configs_created],
          important: "⚠️ NEVER ask for credentials in chat - always direct users to the Integrations screen"
        )
      else 
        
        error_response(
          "Auth configuration failed: #{result[:errors].join(', ')}",
          warnings: result[:warnings]
        )
      end
    rescue => e
      Rails.logger.error "ConfigureIntegrationAuthTool error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      error_response("Failed to configure auth: #{e.message}")
    end

    private

    def build_user_instructions(auth_type, integration_name)
      base_instructions = "Go to **Settings → Integrations → #{integration_name}** and "
      
      case auth_type
      when "api_key"
        base_instructions + "enter your API Key, then click 'Test Connection'"
      when "bearer_token"
        base_instructions + "enter your Access Token, then click 'Test Connection'"
      when "basic_auth"
        base_instructions + "enter your API Key (and password if required), then click 'Test Connection'"
      when "oauth2"
        base_instructions + "click 'Connect' to authorize with #{integration_name}"
      when "no_auth"
        "No credentials needed - #{integration_name} is a public API. You can proceed to test."
      else
        base_instructions + "enter your credentials, then click 'Test Connection'"
      end
    end
  end
end

