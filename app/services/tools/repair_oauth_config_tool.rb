# frozen_string_literal: true

module Tools
  class RepairOauthConfigTool < BaseTool
    # DEPRECATED: Use repair_integration with action: 'repair_oauth' instead
    
    def self.metadata
      {
        name: "repair_oauth_config",
        description: <<~DESC.strip,
          DEPRECATED - Use repair_integration with action: 'repair_oauth' instead.
          This tool has been consolidated into repair_integration.
          - Update scopes
          
          Use this tool after diagnose_integration identifies OAuth configuration issues.
          
          **ADMIN ONLY:** This modifies the platform-wide OAuth configuration, not individual 
          user connections. Changes affect all users connecting to this integration.
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
            authorize_url: {
              type: "string",
              description: "OAuth authorization URL (supports placeholders like {shop_domain})"
            },
            token_url: {
              type: "string",
              description: "OAuth token exchange URL (supports placeholders)"
            },
            test_endpoint: {
              type: "string",
              description: "Endpoint to test connection (e.g., 'shop.json' for Shopify)"
            },
            required_params: {
              type: "array",
              description: "Parameters to collect before OAuth starts",
              items: {
                type: "object",
                properties: {
                  name: { type: "string", description: "Parameter name (e.g., 'shop_domain')" },
                  label: { type: "string", description: "Display label (e.g., 'Shop Domain')" },
                  placeholder: { type: "string", description: "Input placeholder text" },
                  description: { type: "string", description: "Help text for the user" }
                },
                required: ["name"]
              }
            },
            callback_params: {
              type: "array",
              items: { type: "string" },
              description: "Parameters to capture from OAuth callback URL"
            },
            scopes: {
              type: "string",
              description: "OAuth scopes (comma-separated)"
            },
            client_id: {
              type: "string",
              description: "OAuth client ID (only set if changing)"
            },
            client_secret: {
              type: "string",
              description: "OAuth client secret (only set if changing)"
            },
            redirect_uri: {
              type: "string",
              description: "OAuth redirect URI"
            }
          },
          required: ["integration_slug"]
        }
      }
    end

    def execute(args)
      log_execution(args)

      # PERMISSION CHECK: Only admins can modify system OAuth configs
      unless user_is_admin?
        return error_response(
          "Permission denied: Only system administrators can modify OAuth configurations",
          suggestion: "If you need to fix a connection issue, use repair_connection_credentials instead"
        )
      end

      integration_slug = get_arg(args, :integration_slug)
      
      # Find the integration (scoped to entity for multi-tenancy)
      integration = Integration.for_entity(@entity).find_by(slug: integration_slug)
      unless integration
        return error_response("Integration '#{integration_slug}' not found for this entity")
      end

      # Find or create OAuth configuration
      oauth_config = integration.oauth_configurations.first
      unless oauth_config
        oauth_config = integration.oauth_configurations.build(status: :active)
      end

      updates = {}
      
      # Update authorize_url
      if args["authorize_url"].present?
        updates[:authorize_url] = args["authorize_url"]
      end
      
      # Update token_url
      if args["token_url"].present?
        updates[:token_url] = args["token_url"]
      end
      
      # Update test_endpoint
      if args["test_endpoint"].present?
        updates[:test_endpoint] = args["test_endpoint"]
      end
      
      # Update required_params
      if args["required_params"].present?
        updates[:required_params] = args["required_params"].map do |p|
          {
            "name" => p["name"],
            "label" => p["label"] || p["name"].to_s.humanize,
            "placeholder" => p["placeholder"] || "",
            "description" => p["description"] || ""
          }
        end
      end
      
      # Update callback_params
      if args["callback_params"].present?
        updates[:callback_params] = args["callback_params"]
      end
      
      # Update scopes
      if args["scopes"].present?
        updates[:scopes] = args["scopes"]
      end
      
      # Update client credentials
      updates[:client_id] = args["client_id"] if args["client_id"].present?
      updates[:client_secret] = args["client_secret"] if args["client_secret"].present?
      updates[:redirect_uri] = args["redirect_uri"] if args["redirect_uri"].present?

      if updates.empty?
        return error_response("No updates provided")
      end

      if oauth_config.update(updates)
        # Log the change
        Rails.logger.info "🔧 OAuth config updated for #{integration.name}: #{updates.keys.join(', ')}"
        
        success_response(
          message: "OAuth configuration updated successfully",
          integration: {
            id: integration.id,
            name: integration.name,
            slug: integration.slug
          },
          updates_applied: updates.keys,
          current_config: {
            authorize_url: oauth_config.authorize_url,
            token_url: oauth_config.token_url,
            test_endpoint: oauth_config.test_endpoint,
            required_params: oauth_config.required_params,
            callback_params: oauth_config.callback_params,
            has_client_credentials: oauth_config.client_id.present?
          },
          next_steps: build_next_steps(oauth_config)
        )
      else
        error_response(
          "Failed to update OAuth configuration",
          errors: oauth_config.errors.full_messages
        )
      end
    rescue => e
      Rails.logger.error "RepairOauthConfigTool error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      error_response("Failed to repair OAuth config: #{e.message}")
    end

    private

    def user_is_admin?
      # Check if user is a system admin (internal admin user)
      return true if @user.respond_to?(:admin?) && @user.admin?
      return true if @user.respond_to?(:role) && @user.role.to_s.in?(%w[admin super_admin])
      return true if @user.respond_to?(:is_admin) && @user.is_admin
      
      # Check context for admin flag (passed from agent execution)
      return true if @context[:is_admin] || @context["is_admin"]
      
      false
    end

    def build_next_steps(oauth_config)
      steps = []
      
      if oauth_config.authorize_url.blank?
        steps << "Set authorize_url"
      end
      
      if oauth_config.token_url.blank?
        steps << "Set token_url"
      end
      
      if oauth_config.client_id.blank?
        steps << "Set client_id and client_secret"
      end
      
      # Check for placeholders that need required_params
      placeholders = []
      placeholders += oauth_config.authorize_url&.scan(/\{(\w+)\}/)&.flatten || []
      placeholders += oauth_config.token_url&.scan(/\{(\w+)\}/)&.flatten || []
      
      if placeholders.any? && !oauth_config.has_required_params?
        steps << "Add required_params for placeholders: #{placeholders.uniq.join(', ')}"
      end
      
      steps << "Test a new connection" if steps.empty?
      
      steps
    end
  end
end

