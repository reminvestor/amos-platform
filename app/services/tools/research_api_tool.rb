module Tools
  class ResearchApiTool < BaseTool
    def self.metadata
      {
        name: "research_api",
        description: <<~DESC.strip,
          Helps structure API research before creating an integration.
          
          This tool guides you through researching an API systematically:
          1. Returns what information you need to find
          2. Suggests search queries to run
          3. Validates your findings before creation
          
          Use this BEFORE create_integration to ensure you have accurate information.
          
          **Workflow:**
          1. Call research_api with action: "start" and the service name
          2. Use web_search to find the information listed
          3. Call research_api with action: "record" to save each finding
          4. Call research_api with action: "validate" to check completeness
          5. Call research_api with action: "generate" to get create_integration params
        DESC
        category: "integration",
        input_schema: {
          type: "object",
          properties: {
            action: {
              type: "string",
              enum: %w[start record validate generate],
              description: "Action: start (begin research), record (save a finding), validate (check completeness), generate (create params)"
            },
            service_name: {
              type: "string",
              description: "Name of the service/API to research (for 'start' action)"
            },
            field: {
              type: "string",
              description: "Field being recorded (for 'record' action): base_url, auth_type, auth_details, test_endpoint, operation, etc."
            },
            value: {
              type: ["string", "object"],
              description: "Value found from research (for 'record' action)"
            },
            source_url: {
              type: "string",
              description: "URL where this information was found (for 'record' action)"
            },
            research_id: {
              type: "string",
              description: "Research session ID (returned from 'start', required for other actions)"
            }
          },
          required: ["action"]
        }
      }
    end

    def execute(args)
      log_execution(args)

      case args["action"]
      when "start"
        start_research(args["service_name"])
      when "record"
        record_finding(args["research_id"], args["field"], args["value"], args["source_url"])
      when "validate"
        validate_research(args["research_id"])
      when "generate"
        generate_params(args["research_id"])
      else
        error_response("Unknown action: #{args['action']}")
      end
    end

    private

    def start_research(service_name)
      return error_response("service_name is required") if service_name.blank?

      research_id = SecureRandom.uuid
      
      # Store research session in cache
      research_data = {
        service_name: service_name,
        started_at: Time.current,
        findings: {},
        sources: []
      }
      
      Rails.cache.write("api_research:#{research_id}", research_data, expires_in: 1.hour)

      success_response(
        research_id: research_id,
        service_name: service_name,
        message: "Research session started for #{service_name}",
        
        # What to research
        required_fields: [
          {
            field: "base_url",
            description: "The root URL for API requests",
            search_queries: [
              "#{service_name} API base URL",
              "#{service_name} API endpoint",
              "#{service_name} REST API documentation"
            ],
            tips: [
              "Look for 'Base URL', 'API Endpoint', or 'Server URL' in docs",
              "Usually looks like: https://api.#{service_name.downcase}.com",
              "Check if there are different URLs for sandbox vs production"
            ]
          },
          {
            field: "auth_type",
            description: "How the API authenticates requests",
            search_queries: [
              "#{service_name} API authentication",
              "#{service_name} API key",
              "#{service_name} API OAuth"
            ],
            tips: [
              "Look for 'Authentication', 'Authorization', or 'API Keys' section",
              "Common types: API Key (header), Bearer Token, Basic Auth, OAuth2",
              "Note the exact header name if it's an API key"
            ]
          },
          {
            field: "auth_details",
            description: "Specific auth configuration",
            search_queries: [
              "#{service_name} API authorization header",
              "#{service_name} API key header name"
            ],
            tips: [
              "For API Key: What header? (X-API-Key, Authorization, Api-Key, etc.)",
              "For OAuth: What are the authorize_url and token_url?",
              "For Basic Auth: Is it username:password or API key as username?"
            ]
          },
          {
            field: "test_endpoint",
            description: "A simple endpoint to verify credentials",
            search_queries: [
              "#{service_name} API get current user",
              "#{service_name} API account endpoint",
              "#{service_name} API health check"
            ],
            tips: [
              "Look for /me, /user, /account, /health, or similar",
              "Should be a simple GET that requires auth",
              "Used to verify credentials work before saving"
            ]
          },
          {
            field: "documentation_url",
            description: "Link to official API documentation",
            search_queries: [
              "#{service_name} API documentation",
              "#{service_name} developer docs"
            ],
            tips: [
              "Get the official docs URL for reference",
              "Usually developers.#{service_name}.com or #{service_name}.com/docs/api"
            ]
          }
        ],
        
        optional_fields: [
          {
            field: "api_version",
            description: "API version if applicable",
            tips: ["May be in URL path (/v1/) or header (API-Version: 2024-01)"]
          },
          {
            field: "rate_limits",
            description: "Request rate limits",
            tips: ["Look for 'Rate Limits' section in docs"]
          },
          {
            field: "operations",
            description: "Specific API endpoints to support",
            tips: [
              "List the endpoints the user needs",
              "For each: name, path, method, parameters"
            ]
          }
        ],

        next_steps: [
          "1. Use web_search with the suggested queries",
          "2. Read the documentation pages found",
          "3. Call research_api(action: 'record', research_id: '#{research_id}', field: 'base_url', value: '...', source_url: '...')",
          "4. Repeat for each required field",
          "5. Call research_api(action: 'validate', research_id: '#{research_id}') to check completeness"
        ]
      )
    end

    def record_finding(research_id, field, value, source_url)
      return error_response("research_id is required") if research_id.blank?
      return error_response("field is required") if field.blank?
      return error_response("value is required") if value.blank?

      research_data = Rails.cache.read("api_research:#{research_id}")
      return error_response("Research session not found or expired") unless research_data

      # Record the finding
      research_data[:findings][field] = {
        value: value,
        source_url: source_url,
        recorded_at: Time.current
      }

      # Track sources
      research_data[:sources] << source_url if source_url.present?
      research_data[:sources].uniq!

      Rails.cache.write("api_research:#{research_id}", research_data, expires_in: 1.hour)

      # Check what's still missing
      required = %w[base_url auth_type documentation_url]
      found = research_data[:findings].keys
      missing = required - found

      success_response(
        field: field,
        recorded: true,
        findings_count: research_data[:findings].size,
        missing_required: missing,
        message: missing.empty? ? 
          "All required fields recorded! Call validate to check." :
          "Recorded #{field}. Still need: #{missing.join(', ')}"
      )
    end

    def validate_research(research_id)
      return error_response("research_id is required") if research_id.blank?

      research_data = Rails.cache.read("api_research:#{research_id}")
      return error_response("Research session not found or expired") unless research_data

      findings = research_data[:findings]
      issues = []
      warnings = []

      # Check required fields
      required = %w[base_url auth_type documentation_url]
      required.each do |field|
        issues << "Missing required field: #{field}" unless findings[field].present?
      end

      # Validate base_url
      if findings["base_url"].present?
        url = findings["base_url"][:value]
        unless url.to_s.match?(/^https?:\/\//)
          issues << "base_url doesn't look like a valid URL: #{url}"
        end
      end

      # Validate auth_type
      if findings["auth_type"].present?
        auth = findings["auth_type"][:value].to_s.downcase
        valid_types = %w[api_key bearer_token basic_auth oauth2 oauth]
        unless valid_types.any? { |t| auth.include?(t) }
          warnings << "auth_type '#{auth}' may need to be mapped to: api_key, bearer_token, basic_auth, or oauth2"
        end
      end

      # Check for test endpoint
      unless findings["test_endpoint"].present?
        warnings << "No test_endpoint recorded - consider finding one to verify credentials"
      end

      # Check OAuth requirements
      if findings["auth_type"]&.dig(:value).to_s.downcase.include?("oauth")
        unless findings["auth_details"]&.dig(:value, "authorize_url") || findings["authorize_url"]
          issues << "OAuth requires authorize_url - search for OAuth authorization endpoint"
        end
        unless findings["auth_details"]&.dig(:value, "token_url") || findings["token_url"]
          issues << "OAuth requires token_url - search for OAuth token endpoint"
        end
      end

      ready = issues.empty?

      success_response(
        research_id: research_id,
        service_name: research_data[:service_name],
        ready_to_create: ready,
        issues: issues,
        warnings: warnings,
        findings_summary: findings.transform_values { |f| f[:value] },
        sources: research_data[:sources],
        next_step: ready ? 
          "Research complete! Call research_api(action: 'generate', research_id: '#{research_id}') to get create_integration params" :
          "Please resolve the issues above before creating the integration"
      )
    end

    def generate_params(research_id)
      return error_response("research_id is required") if research_id.blank?

      research_data = Rails.cache.read("api_research:#{research_id}")
      return error_response("Research session not found or expired") unless research_data

      # Validate first
      validation = validate_research_internal(research_data)
      unless validation[:ready]
        return error_response("Research not complete: #{validation[:issues].join(', ')}")
      end

      findings = research_data[:findings]

      # Build the params for create_integration
      params = {
        name: research_data[:service_name],
        base_url: findings.dig("base_url", :value),
        documentation_url: findings.dig("documentation_url", :value),
        auth_type: normalize_auth_type(findings.dig("auth_type", :value))
      }

      # Add auth details
      auth_details = findings.dig("auth_details", :value) || {}
      if auth_details.is_a?(Hash)
        params.merge!(auth_details.symbolize_keys)
      elsif auth_details.is_a?(String)
        # Try to parse common patterns
        if auth_details.include?("header")
          params[:auth_header_name] = extract_header_name(auth_details)
        end
      end

      # Add OAuth URLs if present
      params[:authorize_url] = findings.dig("authorize_url", :value) if findings["authorize_url"]
      params[:token_url] = findings.dig("token_url", :value) if findings["token_url"]
      params[:scopes] = findings.dig("scopes", :value) if findings["scopes"]

      # Add test endpoint
      params[:test_endpoint] = findings.dig("test_endpoint", :value) if findings["test_endpoint"]

      # Add operations
      if findings["operations"].present?
        ops = findings.dig("operations", :value)
        params[:operations] = ops.is_a?(Array) ? ops : [ops]
      end

      # Add optional fields
      params[:api_version] = findings.dig("api_version", :value) if findings["api_version"]
      params[:rate_limits] = findings.dig("rate_limits", :value) if findings["rate_limits"]
      params[:description] = findings.dig("description", :value) if findings["description"]
      params[:category] = findings.dig("category", :value) if findings["category"]

      success_response(
        message: "Research compiled into create_integration parameters",
        service_name: research_data[:service_name],
        sources_used: research_data[:sources],
        create_integration_params: params.compact,
        next_step: "Review the params above, then call create_integration with these values"
      )
    end

    def validate_research_internal(research_data)
      findings = research_data[:findings]
      issues = []

      %w[base_url auth_type documentation_url].each do |field|
        issues << "Missing: #{field}" unless findings[field].present?
      end

      { ready: issues.empty?, issues: issues }
    end

    def normalize_auth_type(value)
      return "api_key" if value.blank?
      
      v = value.to_s.downcase
      
      if v.include?("oauth") || v.include?("authorization code")
        "oauth2"
      elsif v.include?("bearer")
        "bearer_token"
      elsif v.include?("basic")
        "basic_auth"
      elsif v.include?("api key") || v.include?("api_key") || v.include?("apikey")
        "api_key"
      else
        "api_key" # Default
      end
    end

    def extract_header_name(text)
      # Try to find header name in text like "X-API-Key header" or "Authorization: Bearer"
      if match = text.match(/(X-[\w-]+|Authorization|Api-Key|API-Key)/i)
        match[1]
      else
        "X-API-Key"
      end
    end
  end
end

