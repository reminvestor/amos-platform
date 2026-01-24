# frozen_string_literal: true

module Tools
  class RepairIntegrationEndpointTool < BaseTool
    # DEPRECATED: Use repair_integration with action: 'repair_endpoints' instead
    
    def self.metadata
      {
        name: "repair_integration_endpoint",
        description: <<~DESC.strip,
          DEPRECATED - Use repair_integration with action: 'repair_endpoints' instead.
          This tool has been consolidated into repair_integration.
          - Update operation parameters and request schemas
          
          **Use cases:**
          - API version changed (e.g., v1 to v2)
          - Endpoint path changed
          - Need to add/remove trailing slashes
          - Fix HTTP method (GET vs POST)
          - Update request parameters
          
          **ADMIN ONLY:** This modifies platform-wide configuration.
          Only system administrators can use this tool.
        DESC
        category: "integration_repair",
        admin_only: true,
        input_schema: {
          type: "object",
          properties: {
            integration_slug: {
              type: "string",
              description: "The slug of the integration to repair"
            },
            action: {
              type: "string",
              enum: ["update_base_url", "update_test_endpoint", "update_operation", "enable_operation", "disable_operation", "list_operations"],
              description: "Action to perform"
            },
            # For update_base_url
            api_base_url: {
              type: "string",
              description: "New API base URL (supports placeholders like {shop_domain})"
            },
            # For update_test_endpoint
            test_endpoint: {
              type: "string",
              description: "New test endpoint path"
            },
            # For operation updates
            operation_id: {
              type: "integer",
              description: "ID of the operation to update"
            },
            operation_name: {
              type: "string",
              description: "Name of the operation to find (alternative to operation_id)"
            },
            operation_updates: {
              type: "object",
              description: "Fields to update on the operation",
              properties: {
                name: { type: "string", description: "Operation name" },
                description: { type: "string", description: "Operation description" },
                http_method: { 
                  type: "string", 
                  enum: ["get", "post", "put", "patch", "delete"],
                  description: "HTTP method" 
                },
                path: { type: "string", description: "Endpoint path (e.g., /customers/{id})" },
                is_enabled: { type: "boolean", description: "Whether operation is enabled" },
                request_schema: { 
                  type: "object", 
                  description: "JSON schema for request body" 
                },
                response_schema: { 
                  type: "object", 
                  description: "JSON schema for response" 
                },
                parameters: {
                  type: "array",
                  description: "Path/query parameters",
                  items: {
                    type: "object",
                    properties: {
                      name: { type: "string" },
                      location: { type: "string", enum: ["path", "query", "header"] },
                      required: { type: "boolean" },
                      type: { type: "string" },
                      description: { type: "string" }
                    }
                  }
                }
              }
            }
          },
          required: ["integration_slug", "action"]
        }
      }
    end

    def execute(args)
      log_execution(args)

      # PERMISSION CHECK: Only admins can modify endpoints
      unless user_is_admin?
        return error_response(
          "Permission denied: Only system administrators can modify integration endpoints",
          suggestion: "Contact a system administrator to make these changes"
        )
      end

      integration_slug = get_arg(args, :integration_slug)
      action = get_arg(args, :action)
      
      # Find the integration (scoped to entity for multi-tenancy)
      integration = Integration.for_entity(@entity).find_by(slug: integration_slug)
      unless integration
        return error_response("Integration '#{integration_slug}' not found for this entity")
      end

      case action
      when "update_base_url"
        update_base_url(integration, args)
      when "update_test_endpoint"
        update_test_endpoint(integration, args)
      when "update_operation"
        update_operation(integration, args)
      when "enable_operation"
        toggle_operation(integration, args, enabled: true)
      when "disable_operation"
        toggle_operation(integration, args, enabled: false)
      when "list_operations"
        list_operations(integration)
      else
        error_response("Unknown action: #{action}")
      end
    rescue => e
      Rails.logger.error "RepairIntegrationEndpointTool error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      error_response("Failed to repair endpoint: #{e.message}")
    end

    private

    def user_is_admin?
      return true if @user.respond_to?(:admin?) && @user.admin?
      return true if @user.respond_to?(:role) && @user.role.to_s.in?(%w[admin super_admin])
      return true if @user.respond_to?(:is_admin) && @user.is_admin
      return true if @context[:is_admin] || @context["is_admin"]
      false
    end

    def update_base_url(integration, args)
      new_url = args["api_base_url"]
      return error_response("api_base_url is required") if new_url.blank?

      old_url = integration.api_base_url

      # Validate URL format (allow placeholders)
      unless valid_url_with_placeholders?(new_url)
        return error_response(
          "Invalid URL format: #{new_url}",
          suggestion: "URL should be like https://api.example.com/v1 or https://{shop_domain}/admin/api/2025-01/"
        )
      end

      if integration.update(api_base_url: new_url)
        Rails.logger.info "🔧 Updated API base URL for #{integration.name}: #{old_url} -> #{new_url}"
        
        success_response(
          message: "API base URL updated successfully",
          integration: integration.name,
          old_url: old_url,
          new_url: new_url,
          placeholders_found: new_url.scan(/\{(\w+)\}/).flatten
        )
      else
        error_response("Failed to update base URL", errors: integration.errors.full_messages)
      end
    end

    def update_test_endpoint(integration, args)
      new_endpoint = args["test_endpoint"]
      return error_response("test_endpoint is required") if new_endpoint.blank?

      oauth_config = integration.oauth_configurations.first
      unless oauth_config
        oauth_config = integration.oauth_configurations.create!(status: :active)
      end

      old_endpoint = oauth_config.test_endpoint

      if oauth_config.update(test_endpoint: new_endpoint)
        Rails.logger.info "🔧 Updated test endpoint for #{integration.name}: #{old_endpoint} -> #{new_endpoint}"
        
        success_response(
          message: "Test endpoint updated successfully",
          integration: integration.name,
          old_endpoint: old_endpoint,
          new_endpoint: new_endpoint
        )
      else
        error_response("Failed to update test endpoint", errors: oauth_config.errors.full_messages)
      end
    end

    def update_operation(integration, args)
      operation = find_operation(integration, args)
      return operation if operation.is_a?(Hash) # Error response

      updates = args["operation_updates"]
      return error_response("operation_updates is required") if updates.blank?

      # Filter to allowed updates
      allowed_keys = %w[name description http_method path is_enabled request_schema response_schema parameters documentation]
      filtered_updates = updates.slice(*allowed_keys)

      # Handle parameters specially - store as JSON
      if filtered_updates["parameters"]
        filtered_updates["parameters"] = filtered_updates["parameters"].to_json
      end

      old_values = operation.attributes.slice(*filtered_updates.keys)

      if operation.update(filtered_updates)
        Rails.logger.info "🔧 Updated operation #{operation.name} for #{integration.name}: #{filtered_updates.keys.join(', ')}"
        
        success_response(
          message: "Operation updated successfully",
          integration: integration.name,
          operation: {
            id: operation.id,
            name: operation.name,
            http_method: operation.http_method,
            path: operation.path
          },
          updates_applied: filtered_updates.keys,
          old_values: old_values
        )
      else
        error_response("Failed to update operation", errors: operation.errors.full_messages)
      end
    end

    def toggle_operation(integration, args, enabled:)
      operation = find_operation(integration, args)
      return operation if operation.is_a?(Hash) # Error response

      old_status = operation.is_enabled

      if operation.update(is_enabled: enabled)
        action = enabled ? "enabled" : "disabled"
        Rails.logger.info "🔧 #{action.capitalize} operation #{operation.name} for #{integration.name}"
        
        success_response(
          message: "Operation #{action} successfully",
          integration: integration.name,
          operation: {
            id: operation.id,
            name: operation.name,
            was_enabled: old_status,
            is_enabled: enabled
          }
        )
      else
        error_response("Failed to toggle operation", errors: operation.errors.full_messages)
      end
    end

    def list_operations(integration)
      operations = integration.integration_operations.order(:name)
      
      success_response(
        integration: integration.name,
        api_base_url: integration.api_base_url,
        operation_count: operations.count,
        operations: operations.map do |op|
          {
            id: op.id,
            name: op.name,
            operation_id: op.operation_id,
            http_method: op.http_method,
            path: op.path,
            is_enabled: op.is_enabled,
            description: op.description&.truncate(100)
          }
        end
      )
    end

    def find_operation(integration, args)
      if args["operation_id"].present?
        operation = integration.integration_operations.find_by(id: args["operation_id"])
        return error_response("Operation ID #{args["operation_id"]} not found") unless operation
        operation
      elsif args["operation_name"].present?
        operation = integration.integration_operations.find_by(name: args["operation_name"])
        operation ||= integration.integration_operations.where("name ILIKE ?", "%#{args["operation_name"]}%").first
        return error_response("Operation '#{args["operation_name"]}' not found") unless operation
        operation
      else
        error_response("Either operation_id or operation_name is required")
      end
    end

    def valid_url_with_placeholders?(url)
      # Replace placeholders with dummy values for URL validation
      test_url = url.gsub(/\{(\w+)\}/, 'placeholder')
      
      begin
        uri = URI.parse(test_url)
        uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
      rescue URI::InvalidURIError
        false
      end
    end
  end
end

