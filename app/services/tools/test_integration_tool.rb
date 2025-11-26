module Tools
  class TestIntegrationTool < BaseTool
    def self.metadata
      {
        name: "test_integration",
        description: <<~DESC.strip,
          Test an integration's API connection before or after creation.
          
          **Use Cases:**
          1. **Pre-creation test**: Test API credentials before creating the integration
             - Provide: base_url, auth_type, auth_config, test_endpoint, test_credentials
          2. **Post-creation test**: Test an existing integration's connection
             - Provide: integration_identifier (slug, name, or ID)
          
          This tool makes a real API call to verify:
          - The base URL is correct and reachable
          - The authentication is configured properly
          - The test endpoint returns a successful response
          
          **IMPORTANT**: For pre-creation tests, you need actual credentials from the user.
          Ask them for their API key/token before testing.
        DESC
        category: "integration",
        input_schema: {
          type: "object",
          properties: {
            # For testing existing integration
            integration_identifier: {
              type: "string",
              description: "Integration slug, name, or ID to test (for existing integrations)"
            },

            # For pre-creation testing
            base_url: {
              type: "string",
              description: "API base URL to test (for pre-creation testing)"
            },
            auth_type: {
              type: "string",
              enum: %w[api_key bearer_token basic_auth],
              description: "Authentication type (for pre-creation testing)"
            },
            test_endpoint: {
              type: "string",
              description: "Endpoint path to test (e.g., '/v1/account', '/me')"
            },
            test_credentials: {
              type: "object",
              description: "Credentials to test with",
              properties: {
                api_key: { type: "string", description: "API key (for api_key or basic_auth)" },
                token: { type: "string", description: "Bearer token (for bearer_token)" },
                username: { type: "string", description: "Username (for basic_auth)" },
                password: { type: "string", description: "Password (for basic_auth)" }
              }
            },
            auth_header_name: {
              type: "string",
              description: "Header name for API key (default: X-API-Key)"
            },

            # Options
            verbose: {
              type: "boolean",
              description: "Include full response details in output"
            }
          }
        }
      }
    end

    def execute(args)
      log_execution(args.except("test_credentials")) # Don't log credentials

      if args["integration_identifier"].present?
        test_existing_integration(args)
      elsif args["base_url"].present?
        test_new_integration(args)
      else
        error_response("Provide either integration_identifier (for existing) or base_url (for new integration)")
      end
    end

    private

    def test_existing_integration(args)
      integration = find_integration(args["integration_identifier"])
      
      unless integration
        return error_response("Integration not found: #{args['integration_identifier']}")
      end

      # Find a connection for this entity
      connection = integration.connections.find_by(entity: @entity)
      
      unless connection
        return error_response("No connection found for #{integration.name}. Create a connection first.")
      end

      credential = connection.active_credential
      
      unless credential
        return error_response(
          "No active credentials for #{integration.name}. " \
          "Add credentials via Settings > Integrations > #{integration.name}"
        )
      end

      # Use the IntegrationApiService to test
      begin
        api_service = IntegrationApiService.new(connection)
        result = api_service.test_connection

        if result[:success]
          success_response(
            integration: integration.name,
            status: "connected",
            message: result[:message] || "Connection successful!",
            status_code: result[:status_code],
            response_preview: args["verbose"] ? result[:data]&.to_json&.truncate(500) : nil
          )
        else
          error_response(
            "Connection test failed for #{integration.name}: #{result[:error]}",
            status_code: result[:status_code],
            suggestion: suggest_fix(integration.auth_type, result[:status_code], result[:error])
          )
        end
      rescue => e
        error_response("Test failed: #{e.message}")
      end
    end

    def test_new_integration(args)
      base_url = args["base_url"]
      auth_type = args["auth_type"] || "api_key"
      test_endpoint = args["test_endpoint"] || "/"
      credentials = args["test_credentials"] || {}

      # Validate we have credentials
      if credentials.empty?
        return error_response(
          "test_credentials required for pre-creation testing. " \
          "Ask the user for their API key or token, then call again with: " \
          "test_credentials: { api_key: 'their_key' }"
        )
      end

      # Build the full URL
      url = build_url(base_url, test_endpoint)

      # Build headers based on auth type
      headers = build_headers(auth_type, credentials, args["auth_header_name"])

      # Make the test request
      begin
        Rails.logger.info "🧪 Testing API: #{url}"
        
        response = HTTParty.get(
          url,
          headers: headers,
          timeout: 10,
          format: :plain # Don't auto-parse, handle it ourselves
        )

        status_code = response.code
        
        if response.success?
          # Try to parse response
          body = begin
            JSON.parse(response.body)
          rescue
            response.body&.truncate(200)
          end

          success_response(
            status: "success",
            message: "API connection verified!",
            status_code: status_code,
            base_url: base_url,
            test_endpoint: test_endpoint,
            auth_type: auth_type,
            response_preview: args["verbose"] ? body : nil,
            ready_to_create: true,
            next_step: "The API is responding correctly. You can now call create_integration."
          )
        else
          # Parse error response
          error_body = begin
            JSON.parse(response.body)
          rescue
            response.body&.truncate(200)
          end

          error_response(
            "API returned error status #{status_code}",
            status_code: status_code,
            error_details: error_body,
            suggestion: suggest_fix(auth_type, status_code, error_body.to_s),
            tested_url: url
          )
        end

      rescue Net::OpenTimeout, Net::ReadTimeout
        error_response(
          "Connection timed out",
          suggestion: "Check if the base_url is correct: #{base_url}",
          tested_url: url
        )
      rescue SocketError, Errno::ECONNREFUSED => e
        error_response(
          "Could not connect to server: #{e.message}",
          suggestion: "Verify the base_url is correct and the API is available",
          tested_url: url
        )
      rescue => e
        error_response("Test failed: #{e.message}", tested_url: url)
      end
    end

    def build_url(base_url, endpoint)
      base = base_url.chomp('/')
      path = endpoint.start_with?('/') ? endpoint : "/#{endpoint}"
      "#{base}#{path}"
    end

    def build_headers(auth_type, credentials, custom_header_name = nil)
      headers = {
        "Content-Type" => "application/json",
        "Accept" => "application/json",
        "User-Agent" => "AmosLabs/IntegrationTest"
      }

      case auth_type.to_s
      when "api_key"
        key = credentials["api_key"] || credentials["token"] || credentials[:api_key] || credentials[:token]
        header_name = custom_header_name || "X-API-Key"
        headers[header_name] = key if key.present?

      when "bearer_token"
        token = credentials["token"] || credentials["access_token"] || credentials[:token] || credentials[:access_token]
        headers["Authorization"] = "Bearer #{token}" if token.present?

      when "basic_auth"
        username = credentials["username"] || credentials["api_key"] || credentials[:username] || credentials[:api_key]
        password = credentials["password"] || credentials[:password] || ""
        if username.present?
          encoded = Base64.strict_encode64("#{username}:#{password}")
          headers["Authorization"] = "Basic #{encoded}"
        end
      end

      headers
    end

    def suggest_fix(auth_type, status_code, error_message)
      case status_code
      when 401, 403
        case auth_type.to_s
        when "api_key"
          "Authentication failed. Check that:\n" \
          "1. The API key is correct and active\n" \
          "2. The header name is correct (try Authorization, X-API-Key, or Api-Key)\n" \
          "3. The API key has the required permissions"
        when "bearer_token"
          "Authentication failed. Check that:\n" \
          "1. The token is correct and not expired\n" \
          "2. The token has the required scopes"
        when "basic_auth"
          "Authentication failed. Check that:\n" \
          "1. The username/API key is correct\n" \
          "2. The password is correct (or empty if using API key as username)"
        else
          "Authentication failed. Verify your credentials."
        end
      when 404
        "Endpoint not found. Check that:\n" \
        "1. The base_url is correct\n" \
        "2. The test_endpoint path exists\n" \
        "3. The API version is correct (may need /v1/ or /v2/ in path)"
      when 429
        "Rate limited. Wait a moment and try again."
      when 500..599
        "Server error. The API may be temporarily unavailable."
      else
        "Request failed. Review the error details and check the API documentation."
      end
    end

    def find_integration(identifier)
      Integration.find_by(id: identifier) ||
        Integration.find_by(slug: identifier) ||
        Integration.find_by(name: identifier)
    end
  end
end

