# frozen_string_literal: true

module Tools
  class RepairIntegrationTool < BaseTool
    def self.metadata
      {
        name: "repair_integration",
        description: <<~DESC.strip,
          Unified tool to repair integration configuration issues. Consolidates all repair actions:
          
          **Actions available:**
          - `diagnose`: Analyze the integration and identify issues
          - `repair_oauth`: Fix OAuth URLs, scopes, test endpoints
          - `repair_auth_headers`: Fix authentication headers/parameters
          - `repair_credentials`: Update connection credentials (user-specific)
          - `repair_endpoints`: Fix endpoint URLs or parameters
          - `test`: Test the integration after repairs
          
          **Common fixes:**
          - OAuth issues: authorize_url, token_url, required_params
          - Auth headers: Custom headers like X-Shopify-Access-Token
          - Endpoints: Base URL, endpoint paths, parameters
          
          Use `diagnose` first to understand what's broken, then apply specific repairs.
        DESC
        category: "integration",
        input_schema: {
          type: "object",
          properties: {
            integration_id: {
              type: "integer",
              description: "ID of the integration to repair"
            },
            integration_slug: {
              type: "string",
              description: "Slug of the integration (alternative to integration_id)"
            },
            connection_id: {
              type: "integer",
              description: "ID of specific connection to repair (for credential repairs)"
            },
            action: {
              type: "string",
              enum: %w[diagnose repair_oauth repair_auth_headers repair_credentials repair_endpoints test],
              description: "What action to perform"
            },
            # OAuth repair fields
            authorize_url: {
              type: "string",
              description: "OAuth authorization URL (supports placeholders like {shop_domain})"
            },
            token_url: {
              type: "string",
              description: "OAuth token exchange URL"
            },
            scopes: {
              type: "string",
              description: "OAuth scopes (space-separated)"
            },
            test_endpoint: {
              type: "string",
              description: "Endpoint to test connection"
            },
            required_params: {
              type: "array",
              description: "Parameters to collect before OAuth",
              items: {
                type: "object",
                properties: {
                  name: { type: "string" },
                  label: { type: "string" },
                  placeholder: { type: "string" }
                }
              }
            },
            # Auth header repair fields
            auth_configs: {
              type: "array",
              description: "Auth header/parameter configurations",
              items: {
                type: "object",
                properties: {
                  auth_key: { type: "string", description: "Header/param name" },
                  auth_value: { type: "string", description: "Value template (e.g., '{access_token}')" },
                  auth_placement: { type: "string", enum: %w[header query url] }
                }
              }
            },
            replace_auth_configs: {
              type: "boolean",
              description: "If true, replaces all existing auth configs. If false, merges."
            },
            # Credentials repair fields
            credentials: {
              type: "object",
              description: "New credentials to set",
              additionalProperties: { type: "string" }
            },
            # Endpoint repair fields
            base_url: {
              type: "string",
              description: "New base URL for the integration"
            },
            endpoints: {
              type: "array",
              description: "Endpoints to update",
              items: {
                type: "object",
                properties: {
                  operation_name: { type: "string" },
                  endpoint_path: { type: "string" },
                  http_method: { type: "string", enum: %w[GET POST PUT PATCH DELETE] },
                  parameters: { type: "object" }
                }
              }
            }
          },
          required: ["action"]
        }
      }
    end

    def execute(args)
      log_execution(args)
      
      action = args["action"]
      integration_id = args["integration_id"]
      integration_slug = args["integration_slug"]
      connection_id = args["connection_id"]
      
      # Find integration
      integration = find_integration(integration_id, integration_slug)
      return error_response("Integration not found") unless integration
      
      case action
      when "diagnose"
        diagnose_integration(integration)
      when "repair_oauth"
        repair_oauth(integration, args)
      when "repair_auth_headers"
        repair_auth_headers(integration, args)
      when "repair_credentials"
        repair_credentials(integration, connection_id, args)
      when "repair_endpoints"
        repair_endpoints(integration, args)
      when "test"
        test_integration(integration, connection_id)
      else
        error_response("Unknown action: #{action}")
      end
    rescue => e
      Rails.logger.error "RepairIntegrationTool error: #{e.message}"
      error_response("Repair failed: #{e.message}")
    end

    private

    def find_integration(id, slug)
      if id.present?
        Integration.find_by(id: id)
      elsif slug.present?
        Integration.find_by(slug: slug)
      end
    end

    def diagnose_integration(integration)
      issues = []
      recommendations = []
      
      # Check OAuth config
      if integration.auth_type == "oauth"
        if integration.authorize_url.blank?
          issues << "Missing OAuth authorize_url"
          recommendations << "Set authorize_url for OAuth flow"
        end
        if integration.token_url.blank?
          issues << "Missing OAuth token_url"
          recommendations << "Set token_url for token exchange"
        end
        if integration.client_id.blank? || integration.client_secret.blank?
          issues << "Missing client credentials"
          recommendations << "Configure client_id and client_secret"
        end
      end
      
      # Check base URL
      if integration.base_url.blank?
        issues << "Missing base_url"
        recommendations << "Set base_url for API calls"
      end
      
      # Check auth configs
      auth_configs = AuthConfig.where(integration_id: integration.id)
      if integration.auth_type != "oauth" && auth_configs.empty?
        issues << "No auth configs defined"
        recommendations << "Add auth headers or parameters"
      end
      
      # Check operations
      operations = IntegrationOperation.where(integration_id: integration.id)
      if operations.empty?
        issues << "No operations defined"
        recommendations << "Add at least one operation"
      end
      
      # Check for active connections
      connections = IntegrationConnection.where(integration_id: integration.id)
      connection_stats = {
        total: connections.count,
        active: connections.where(status: "active").count,
        failed: connections.where(status: "failed").count
      }
      
      success_response(
        integration: {
          id: integration.id,
          name: integration.name,
          slug: integration.slug,
          auth_type: integration.auth_type,
          base_url: integration.base_url
        },
        issues: issues,
        recommendations: recommendations,
        auth_configs: auth_configs.map { |c| { key: c.auth_key, placement: c.auth_placement } },
        operations_count: operations.count,
        connection_stats: connection_stats,
        healthy: issues.empty?
      )
    end

    def repair_oauth(integration, args)
      updates = {}
      updates[:authorize_url] = args["authorize_url"] if args["authorize_url"].present?
      updates[:token_url] = args["token_url"] if args["token_url"].present?
      updates[:scopes] = args["scopes"] if args["scopes"].present?
      updates[:test_endpoint] = args["test_endpoint"] if args["test_endpoint"].present?
      
      if args["required_params"].present?
        updates[:required_params] = args["required_params"]
      end
      
      return error_response("No OAuth updates provided") if updates.empty?
      
      integration.update!(updates)
      
      success_response(
        message: "OAuth configuration updated",
        updated_fields: updates.keys,
        integration_id: integration.id
      )
    end

    def repair_auth_headers(integration, args)
      auth_configs = args["auth_configs"]
      return error_response("No auth_configs provided") if auth_configs.blank?
      
      replace_all = args["replace_auth_configs"] == true
      
      if replace_all
        AuthConfig.where(integration_id: integration.id).destroy_all
      end
      
      created = []
      args["auth_configs"].each do |config|
        auth_config = AuthConfig.create!(
          integration_id: integration.id,
          auth_key: config["auth_key"],
          auth_value: config["auth_value"] || "{access_token}",
          auth_placement: config["auth_placement"] || "header"
        )
        created << { id: auth_config.id, key: auth_config.auth_key }
      end
      
      success_response(
        message: "Auth headers configured",
        created: created,
        replaced_existing: replace_all
      )
    end

    def repair_credentials(integration, connection_id, args)
      return error_response("connection_id required for credential repair") unless connection_id
      return error_response("credentials required") if args["credentials"].blank?
      
      connection = IntegrationConnection.find_by(id: connection_id, integration_id: integration.id)
      return error_response("Connection not found") unless connection
      
      # Merge new credentials with existing
      existing = connection.credentials || {}
      new_creds = existing.merge(args["credentials"])
      
      connection.update!(
        credentials: new_creds,
        status: "pending" # Reset status for re-test
      )
      
      success_response(
        message: "Credentials updated",
        connection_id: connection.id,
        status: connection.status
      )
    end

    def repair_endpoints(integration, args)
      updates = {}
      updates[:base_url] = args["base_url"] if args["base_url"].present?
      
      if updates.present?
        integration.update!(updates)
      end
      
      updated_ops = []
      if args["endpoints"].present?
        args["endpoints"].each do |ep|
          op = IntegrationOperation.find_by(
            integration_id: integration.id,
            operation_name: ep["operation_name"]
          )
          if op
            op.update!(
              endpoint_path: ep["endpoint_path"] || op.endpoint_path,
              http_method: ep["http_method"] || op.http_method
            )
            updated_ops << op.operation_name
          end
        end
      end
      
      success_response(
        message: "Endpoints updated",
        base_url_updated: args["base_url"].present?,
        operations_updated: updated_ops
      )
    end

    def test_integration(integration, connection_id)
      # Find a connection to test with
      connection = if connection_id
        IntegrationConnection.find_by(id: connection_id, integration_id: integration.id)
      else
        IntegrationConnection.where(integration_id: integration.id, entity_id: @entity.id).first
      end
      
      return error_response("No connection available to test") unless connection
      
      # Try to execute a test operation
      service = IntegrationApiService.new(@entity, @user)
      
      test_endpoint = integration.test_endpoint.presence || 
                     IntegrationOperation.where(integration_id: integration.id, http_method: "GET").first&.endpoint_path
      
      return error_response("No test endpoint configured") unless test_endpoint
      
      begin
        result = service.make_request(
          connection: connection,
          endpoint: test_endpoint,
          method: :get
        )
        
        connection.update!(status: "active", last_used_at: Time.current)
        
        success_response(
          message: "Integration test successful",
          connection_id: connection.id,
          status: "active",
          response_sample: result.to_s.truncate(500)
        )
      rescue => e
        connection.update!(status: "failed", error_message: e.message)
        
        error_response(
          "Test failed: #{e.message}",
          connection_id: connection.id,
          status: "failed"
        )
      end
    end
  end
end
