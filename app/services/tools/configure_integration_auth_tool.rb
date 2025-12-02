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
          1. Ask the user for their credentials
          2. Call test_integration_auth (Stage 3)
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
        
        # Build credential prompt based on auth type
        credential_prompt = build_credential_prompt(args["auth_type"], args["auth_configs"], integration.name)
        
        success_response(
          message: "✅ Authentication configured! Now get credentials from the user and test.",
          integration_id: integration.id,
          integration_name: integration.name,
          auth_type: args["auth_type"],
          auth_placement: args["auth_placement"],
          test_endpoint: args["test_endpoint"],
          status: "pending_credentials",
          next_step: "STAGE 3: Ask the user for credentials, then call test_integration_auth",
          credential_prompt: credential_prompt,
          auth_configs_created: result[:auth_configs_created]
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

    def build_credential_prompt(auth_type, auth_configs, integration_name)
      case auth_type
      when "api_key"
        if auth_configs&.any? { |c| c["key"]&.downcase&.include?("token") }
          "Please provide your #{integration_name} API Key and Token"
        else
          "Please provide your #{integration_name} API Key"
        end
      when "bearer_token"
        "Please provide your #{integration_name} Access Token"
      when "basic_auth"
        "Please provide your #{integration_name} API Key (and password if required)"
      when "oauth2"
        "Click 'Connect' to authorize with #{integration_name}"
      when "no_auth"
        "No credentials needed - #{integration_name} is a public API. You can proceed to test."
      else
        "Please provide your #{integration_name} credentials"
      end
    end
  end
end

