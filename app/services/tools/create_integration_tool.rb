module Tools
  class CreateIntegrationTool < BaseTool
    def self.metadata
      {
        name: "create_integration",
        description: <<~DESC.strip,
          Creates a new Integration using the Integration Factory. This is a COMPLEX operation
          that requires thorough research and accurate information.
          
          **CRITICAL: Do NOT hallucinate API details!**
          
          Before calling this tool, you MUST:
          1. Use web_search to find the official API documentation
          2. Verify the exact base URL from the documentation
          3. Confirm the authentication method (api_key, bearer_token, basic_auth, oauth2)
          4. Identify a test endpoint to verify credentials work
          5. Research the exact paths and parameters for each operation
          
          **Auth Type Guide:**
          - api_key: API key sent in a header (e.g., X-API-Key: your_key)
          - bearer_token: Token sent as Authorization: Bearer your_token
          - basic_auth: Username/password encoded in Authorization header (Stripe uses this with API key as username)
          - oauth2: Full OAuth 2.0 flow with authorize_url and token_url
          
          **Example - Creating a Stripe-like Integration:**
          {
            name: "Stripe",
            auth_type: "basic_auth",
            base_url: "https://api.stripe.com",
            documentation_url: "https://stripe.com/docs/api",
            test_endpoint: "/v1/balance",
            username_label: "API Key",
            password_required: false,
            operations: [
              { name: "List Customers", path: "/v1/customers", method: "GET" },
              { name: "Create Customer", path: "/v1/customers", method: "POST", parameters: { email: "string", name: "string" } }
            ]
          }
        DESC
        category: "integration",
        input_schema: {
          type: "object",
          properties: {
            # Required fields
            name: {
              type: "string",
              description: "Display name for the integration (e.g., 'Stripe', 'Trello')"
            },
            auth_type: {
              type: "string",
              enum: %w[api_key bearer_token basic_auth oauth2],
              description: "Authentication method - MUST match what the API actually uses"
            },
            base_url: {
              type: "string",
              description: "Base URL for API requests (e.g., 'https://api.stripe.com'). Get this from official docs!"
            },
            documentation_url: {
              type: "string",
              description: "Link to official API documentation - REQUIRED for verification"
            },
            test_endpoint: {
              type: "string",
              description: "A simple GET endpoint to verify credentials (e.g., '/v1/account', '/me')"
            },

            # Optional fields
            slug: {
              type: "string",
              description: "URL-safe identifier. Auto-generated from name if not provided."
            },
            description: {
              type: "string",
              description: "Brief description of what the integration does"
            },
            category: {
              type: "string",
              enum: %w[payment ecommerce crm communication productivity marketing analytics custom],
              description: "Category for organization"
            },
            api_version: {
              type: "string",
              description: "API version if applicable (e.g., '2024-01', 'v3')"
            },

            # Auth-specific fields
            auth_header_name: {
              type: "string",
              description: "For api_key: Header name (e.g., 'X-API-Key', 'Api-Key')"
            },
            username_label: {
              type: "string",
              description: "For basic_auth: Label for username field (e.g., 'API Key', 'Username')"
            },
            password_required: {
              type: "boolean",
              description: "For basic_auth: Whether password is required (false for Stripe-style)"
            },

            # OAuth2 fields
            authorize_url: {
              type: "string",
              description: "For oauth2: Authorization URL (e.g., 'https://example.com/oauth/authorize')"
            },
            token_url: {
              type: "string",
              description: "For oauth2: Token exchange URL (e.g., 'https://example.com/oauth/token')"
            },
            scopes: {
              type: "array",
              items: { type: "string" },
              description: "For oauth2: Required scopes (e.g., ['read', 'write'])"
            },
            callback_params: {
              type: "array",
              items: { type: "string" },
              description: "For oauth2: Extra params from callback to save (e.g., ['realmId'] for QuickBooks)"
            },

            # Operations
            operations: {
              type: "array",
              description: "API operations (endpoints) to create. Each needs: name, path, method.",
              items: {
                type: "object",
                properties: {
                  name: { type: "string", description: "Operation name (e.g., 'List Customers')" },
                  operation_id: { type: "string", description: "Unique ID (e.g., 'list_customers'). Auto-generated from name if not provided." },
                  path: { type: "string", description: "API path (e.g., '/v1/customers', '/company/{companyId}/invoice')" },
                  method: { type: "string", enum: %w[GET POST PUT PATCH DELETE], description: "HTTP method" },
                  description: { type: "string", description: "What this operation does" },
                  parameters: { 
                    type: "object", 
                    description: "Request parameters. Can be simple (name: 'string') or detailed JSON Schema" 
                  },
                  pagination_strategy: { 
                    type: "string", 
                    enum: %w[no_pagination cursor page offset],
                    description: "How pagination works for list endpoints"
                  }
                },
                required: %w[name path]
              }
            }
          },
          required: %w[name auth_type base_url documentation_url]
        }
      }
    end

    def execute(args)
      log_execution(args)

      # Validate documentation_url is provided
      unless args["documentation_url"].present?
        return error_response(
          "documentation_url is required. You MUST research the API documentation before creating an integration. " \
          "Use web_search to find the official API docs first."
        )
      end

      factory = Factories::IntegrationFactory.new(user: @user, entity: @entity)

      # First validate
      validation = factory.validate(args.symbolize_keys)
      
      unless validation[:ready_to_create]
        return error_response(
          "Validation failed:\n" \
          "Errors: #{validation[:errors].join(', ')}\n" \
          "Warnings: #{validation[:warnings].join(', ')}\n\n" \
          "Please fix these issues and try again. Make sure all information comes from official documentation."
        )
      end

      # Create the integration
      result = factory.create(args.symbolize_keys)

      if result[:success]
        integration = result[:integration]
        connection = result[:connection]
        operations = result[:operations_created] || []

        response = {
          success: true,
          integration_id: integration.id,
          integration_slug: integration.slug,
          integration_name: integration.name,
          connection_id: connection.id,
          auth_type: integration.auth_type,
          base_url: integration.api_base_url,
          operations_created: operations.compact.map { |op| 
            { 
              name: op.name, 
              operation_id: op.operation_id,
              method: op.http_method,
              path: op.path_template
            } 
          },
          next_steps: result[:next_steps]
        }

        if result[:warnings].present?
          response[:warnings] = result[:warnings]
        end

        success_response(**response)
      else
        error_response(
          "Integration creation failed:\n" \
          "#{result[:errors].join("\n")}\n\n" \
          "#{result[:warnings].present? ? "Warnings: #{result[:warnings].join(', ')}" : ''}"
        )
      end
    rescue => e
      Rails.logger.error "CreateIntegrationTool error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      error_response("Failed to create integration: #{e.message}")
    end
  end
end
