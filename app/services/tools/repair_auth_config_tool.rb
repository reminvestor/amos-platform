# frozen_string_literal: true

module Tools
  class RepairAuthConfigTool < BaseTool
    # DEPRECATED: Use repair_integration with action: 'repair_auth_headers' instead
    
    def self.metadata
      {
        name: "repair_auth_config",
        description: <<~DESC.strip,
          DEPRECATED - Use repair_integration with action: 'repair_auth_headers' instead.
          This tool has been consolidated into repair_integration.
          
          **Common uses:**
          - Shopify: Add X-Shopify-Access-Token header with {access_token}
          - Trello: Add 'key' and 'token' query params
          - Custom APIs: Configure specific auth headers
          
          **ADMIN ONLY:** This modifies platform-wide settings that affect all connections.
          Only system administrators can use this tool.
        DESC
        category: "integration_repair",
        admin_only: true,
        input_schema: {
          type: "object",
          properties: {
            integration_slug: {
              type: "string",
              description: "The slug of the integration"
            },
            action: {
              type: "string",
              enum: ["add", "update", "remove", "replace_all"],
              description: "Action to perform on auth configs"
            },
            auth_configs: {
              type: "array",
              description: "Auth configurations to add/update",
              items: {
                type: "object",
                properties: {
                  id: { type: "integer", description: "ID of existing config to update (for 'update' action)" },
                  auth_key: { type: "string", description: "Header/param name (e.g., 'X-Shopify-Access-Token')" },
                  auth_value: { type: "string", description: "Value template (e.g., '{access_token}')" },
                  auth_placement: { 
                    type: "string", 
                    enum: ["header", "query", "url"],
                    description: "Where to send this auth param" 
                  },
                  position: { type: "integer", description: "Order position" }
                },
                required: ["auth_key", "auth_value", "auth_placement"]
              }
            },
            remove_ids: {
              type: "array",
              items: { type: "integer" },
              description: "IDs of auth configs to remove (for 'remove' action)"
            }
          },
          required: ["integration_slug", "action"]
        }
      }
    end

    def execute(args)
      log_execution(args)

      # PERMISSION CHECK: Only admins can modify system auth configs
      unless user_is_admin?
        return error_response(
          "Permission denied: Only system administrators can modify authentication configurations",
          suggestion: "If you need to fix a connection issue, use repair_connection_credentials instead"
        )
      end

      integration_slug = get_arg(args, :integration_slug)
      action = get_arg(args, :action)
      
      # Find the integration (scoped to entity for multi-tenancy)
      integration = Integration.for_entity(@entity).find_by(slug: integration_slug)
      unless integration
        return error_response("Integration '#{integration_slug}' not found for this entity")
      end

      # Get OAuth configuration
      oauth_config = integration.oauth_configurations.first
      unless oauth_config
        oauth_config = integration.oauth_configurations.create!(status: :active)
      end

      case action
      when "add"
        add_auth_configs(oauth_config, args["auth_configs"])
      when "update"
        update_auth_configs(oauth_config, args["auth_configs"])
      when "remove"
        remove_auth_configs(oauth_config, args["remove_ids"])
      when "replace_all"
        replace_all_auth_configs(oauth_config, args["auth_configs"])
      else
        error_response("Unknown action: #{action}")
      end
    rescue => e
      Rails.logger.error "RepairAuthConfigTool error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      error_response("Failed to repair auth config: #{e.message}")
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

    def add_auth_configs(oauth_config, configs)
      return error_response("No auth_configs provided") if configs.blank?

      created = []
      errors = []

      configs.each_with_index do |config, idx|
        auth_config = oauth_config.auth_configs.build(
          auth_key: config["auth_key"],
          auth_value: config["auth_value"],
          auth_placement: config["auth_placement"],
          position: config["position"] || (oauth_config.auth_configs.maximum(:position).to_i + idx + 1)
        )

        if auth_config.save
          created << { id: auth_config.id, key: auth_config.auth_key }
        else
          errors << { key: config["auth_key"], errors: auth_config.errors.full_messages }
        end
      end

      if errors.any?
        error_response(
          "Some auth configs failed to create",
          created: created,
          errors: errors
        )
      else
        success_response(
          message: "Auth configs added successfully",
          created: created,
          current_configs: list_auth_configs(oauth_config)
        )
      end
    end

    def update_auth_configs(oauth_config, configs)
      return error_response("No auth_configs provided") if configs.blank?

      updated = []
      errors = []

      configs.each do |config|
        auth_config = if config["id"]
                        oauth_config.auth_configs.find_by(id: config["id"])
                      else
                        oauth_config.auth_configs.find_by(auth_key: config["auth_key"])
                      end

        unless auth_config
          errors << { key: config["auth_key"], error: "Not found" }
          next
        end

        updates = {}
        updates[:auth_key] = config["auth_key"] if config["auth_key"].present?
        updates[:auth_value] = config["auth_value"] if config["auth_value"].present?
        updates[:auth_placement] = config["auth_placement"] if config["auth_placement"].present?
        updates[:position] = config["position"] if config["position"].present?

        if auth_config.update(updates)
          updated << { id: auth_config.id, key: auth_config.auth_key }
        else
          errors << { key: config["auth_key"], errors: auth_config.errors.full_messages }
        end
      end

      if errors.any? && updated.empty?
        error_response(
          "Failed to update auth configs",
          errors: errors
        )
      else
        success_response(
          message: "Auth configs updated",
          updated: updated,
          errors: errors.presence,
          current_configs: list_auth_configs(oauth_config)
        )
      end
    end

    def remove_auth_configs(oauth_config, ids)
      return error_response("No remove_ids provided") if ids.blank?

      removed = []
      not_found = []

      ids.each do |id|
        auth_config = oauth_config.auth_configs.find_by(id: id)
        if auth_config
          auth_config.destroy
          removed << { id: id, key: auth_config.auth_key }
        else
          not_found << id
        end
      end

      success_response(
        message: "Auth configs removed",
        removed: removed,
        not_found: not_found.presence,
        current_configs: list_auth_configs(oauth_config)
      )
    end

    def replace_all_auth_configs(oauth_config, configs)
      return error_response("No auth_configs provided") if configs.blank?

      # Remove all existing
      old_count = oauth_config.auth_configs.count
      oauth_config.auth_configs.destroy_all

      # Add new ones
      created = []
      errors = []

      configs.each_with_index do |config, idx|
        auth_config = oauth_config.auth_configs.create(
          auth_key: config["auth_key"],
          auth_value: config["auth_value"],
          auth_placement: config["auth_placement"],
          position: config["position"] || idx
        )

        if auth_config.persisted?
          created << { id: auth_config.id, key: auth_config.auth_key }
        else
          errors << { key: config["auth_key"], errors: auth_config.errors.full_messages }
        end
      end

      success_response(
        message: "Auth configs replaced",
        removed_count: old_count,
        created: created,
        errors: errors.presence,
        current_configs: list_auth_configs(oauth_config)
      )
    end

    def list_auth_configs(oauth_config)
      oauth_config.auth_configs.reload.order(:position).map do |ac|
        {
          id: ac.id,
          auth_key: ac.auth_key,
          auth_value: ac.auth_value,
          auth_placement: ac.auth_placement,
          position: ac.position
        }
      end
    end
  end
end

