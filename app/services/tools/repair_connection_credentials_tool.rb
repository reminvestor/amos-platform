# frozen_string_literal: true

module Tools
  class RepairConnectionCredentialsTool < BaseTool
    # DEPRECATED: Use repair_integration with action: 'repair_credentials' instead
    
    def self.metadata
      {
        name: "repair_connection_credentials",
        description: <<~DESC.strip,
          DEPRECATED - Use repair_integration with action: 'repair_credentials' instead.
          This tool has been consolidated into repair_integration.
          
          **Use cases:**
          - Connection failing because it's missing shop_domain
          - Need to manually add a parameter to existing credentials
          - Token refresh failed and needs manual intervention
          
          **Permissions:**
          - Regular users can only repair their own entity's connections
          - Admins can repair any connection
          
          This modifies a specific user's connection, not the global configuration.
        DESC
        category: "integration_repair",
        input_schema: {
          type: "object",
          properties: {
            connection_id: {
              type: "integer",
              description: "The ID of the connection to repair"
            },
            integration_slug: {
              type: "string",
              description: "Integration slug (alternative to connection_id - will find connection for current entity)"
            },
            action: {
              type: "string",
              enum: ["add_param", "update_param", "remove_param", "update_status", "test_and_fix"],
              description: "Action to perform"
            },
            param_name: {
              type: "string",
              description: "Name of the credential parameter to add/update/remove"
            },
            param_value: {
              type: "string",
              description: "Value for the parameter"
            },
            new_status: {
              type: "string",
              enum: ["pending", "connected", "disconnected", "failing", "expired"],
              description: "New status for the connection (for 'update_status' action)"
            },
            reset_failures: {
              type: "boolean",
              description: "Whether to reset consecutive_failures counter"
            }
          },
          required: ["action"]
        }
      }
    end

    def execute(args)
      log_execution(args)

      action = get_arg(args, :action)
      
      # Find the connection
      connection = find_connection(args)
      return connection if connection.is_a?(Hash) # Error response

      credential = connection.active_credential
      unless credential
        return error_response("No active credentials found for this connection")
      end

      case action
      when "add_param"
        add_credential_param(connection, credential, args)
      when "update_param"
        update_credential_param(connection, credential, args)
      when "remove_param"
        remove_credential_param(connection, credential, args)
      when "update_status"
        update_connection_status(connection, args)
      when "test_and_fix"
        test_and_fix_connection(connection, credential)
      else
        error_response("Unknown action: #{action}")
      end
    rescue => e
      Rails.logger.error "RepairConnectionCredentialsTool error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      error_response("Failed to repair connection: #{e.message}")
    end

    private

    def find_connection(args)
      if args["connection_id"].present?
        # For admins, allow access to any connection by ID
        # For regular users, scope to their user+entity
        connection = if user_is_admin?
          Connection.find_by(id: args["connection_id"])
        else
          Connection.find_by(id: args["connection_id"], user: @user, entity: @entity)
        end
        return error_response("Connection not found or access denied") unless connection
        
        connection
      elsif args["integration_slug"].present?
        # Find integration - prefer entity-owned over globals
        integration = Integration.find_for_use(args["integration_slug"], @entity)
        return error_response("Integration '#{args["integration_slug"]}' not found for this entity") unless integration
        
        # For regular users, only find their own connection
        # For admins, they can specify which entity via context
        if user_is_admin? && @context[:target_entity_id]
          target_entity = Entity.find_by(id: @context[:target_entity_id])
          connection = Connection.find_by(integration: integration, entity: target_entity)
        else
          connection = Connection.find_by(integration: integration, user: @user, entity: @entity)
        end
        
        return error_response("No connection found for #{integration.name}") unless connection
        connection
      else
        error_response("Either connection_id or integration_slug is required")
      end
    end

    def can_access_connection?(connection)
      # Admins can access any connection
      return true if user_is_admin?
      
      # Regular users can only access their own entity's connections
      connection.entity_id == @entity&.id
    end

    def user_is_admin?
      # Check if user is a system admin (internal admin user)
      return true if @user.respond_to?(:admin?) && @user.admin?
      return true if @user.respond_to?(:role) && @user.role.to_s.in?(%w[admin super_admin])
      return true if @user.respond_to?(:is_admin) && @user.is_admin
      
      # Check context for admin flag (passed from agent execution)
      return true if @context[:is_admin] || @context["is_admin"]
      
      false
    end

    def add_credential_param(connection, credential, args)
      param_name = args["param_name"]
      param_value = args["param_value"]

      return error_response("param_name is required") if param_name.blank?
      return error_response("param_value is required") if param_value.blank?

      creds = credential.credentials.dup || {}
      
      if creds.key?(param_name)
        return error_response("Parameter '#{param_name}' already exists. Use 'update_param' action to modify it.")
      end

      creds[param_name] = param_value

      if credential.update(credentials: creds)
        Rails.logger.info "🔧 Added credential param '#{param_name}' to connection #{connection.id}"
        
        success_response(
          message: "Parameter '#{param_name}' added to credentials",
          connection_id: connection.id,
          integration: connection.integration.name,
          credential_keys: credential.reload.credentials.keys
        )
      else
        error_response("Failed to update credentials", errors: credential.errors.full_messages)
      end
    end

    def update_credential_param(connection, credential, args)
      param_name = args["param_name"]
      param_value = args["param_value"]

      return error_response("param_name is required") if param_name.blank?
      return error_response("param_value is required") if param_value.blank?

      creds = credential.credentials.dup || {}
      old_value = creds[param_name]
      creds[param_name] = param_value

      if credential.update(credentials: creds)
        Rails.logger.info "🔧 Updated credential param '#{param_name}' for connection #{connection.id}"
        
        success_response(
          message: "Parameter '#{param_name}' updated",
          connection_id: connection.id,
          integration: connection.integration.name,
          was_new: old_value.nil?,
          credential_keys: credential.reload.credentials.keys
        )
      else
        error_response("Failed to update credentials", errors: credential.errors.full_messages)
      end
    end

    def remove_credential_param(connection, credential, args)
      param_name = args["param_name"]
      return error_response("param_name is required") if param_name.blank?

      creds = credential.credentials.dup || {}
      
      unless creds.key?(param_name)
        return error_response("Parameter '#{param_name}' not found in credentials")
      end

      creds.delete(param_name)

      if credential.update(credentials: creds)
        Rails.logger.info "🔧 Removed credential param '#{param_name}' from connection #{connection.id}"
        
        success_response(
          message: "Parameter '#{param_name}' removed from credentials",
          connection_id: connection.id,
          integration: connection.integration.name,
          credential_keys: credential.reload.credentials.keys
        )
      else
        error_response("Failed to update credentials", errors: credential.errors.full_messages)
      end
    end

    def update_connection_status(connection, args)
      new_status = args["new_status"]
      reset_failures = args["reset_failures"]

      return error_response("new_status is required") if new_status.blank?

      updates = { status: new_status }
      updates[:consecutive_failures] = 0 if reset_failures

      old_status = connection.status

      if connection.update(updates)
        Rails.logger.info "🔧 Updated connection #{connection.id} status: #{old_status} -> #{new_status}"
        
        success_response(
          message: "Connection status updated",
          connection_id: connection.id,
          integration: connection.integration.name,
          old_status: old_status,
          new_status: new_status,
          failures_reset: reset_failures
        )
      else
        error_response("Failed to update connection", errors: connection.errors.full_messages)
      end
    end

    def test_and_fix_connection(connection, credential)
      # First, run a test
      test_result = connection.test_connection!
      
      if test_result[:success]
        # Connection works - update status if needed
        if connection.status != "connected"
          connection.update(status: :connected, last_health_check: Time.current)
        end
        
        success_response(
          message: "Connection test passed - no repair needed",
          connection_id: connection.id,
          integration: connection.integration.name,
          test_result: test_result,
          status: connection.status
        )
      else
        # Analyze the error and provide recommendations
        error_message = test_result[:error] || "Unknown error"
        
        recommendations = analyze_error_for_fixes(error_message, connection)
        
        # Try auto-fixes if any are available
        auto_fixed = []
        recommendations.each do |rec|
          if rec[:auto_fix]
            result = rec[:auto_fix].call
            auto_fixed << rec[:fix] if result
          end
        end

        # Re-test if we made fixes
        if auto_fixed.any?
          retry_result = connection.test_connection!
          
          if retry_result[:success]
            connection.update(status: :connected, last_health_check: Time.current)
            
            return success_response(
              message: "Connection repaired and test passed",
              connection_id: connection.id,
              integration: connection.integration.name,
              fixes_applied: auto_fixed,
              test_result: retry_result,
              status: "connected"
            )
          end
        end

        # Return what we found with manual fix suggestions
        error_response(
          "Connection test failed",
          test_result: test_result,
          auto_fixes_attempted: auto_fixed,
          manual_fixes_needed: recommendations.select { |r| !r[:auto_fix] }.map { |r| r[:fix] }
        )
      end
    rescue => e
      error_response("Test and fix failed: #{e.message}")
    end

    def analyze_error_for_fixes(error_message, connection)
      recommendations = []

      if error_message.include?("redirect") || error_message.include?("302")
        recommendations << {
          fix: "Authentication not being accepted - check auth headers",
          auto_fix: nil
        }
      end

      if error_message.include?("401") || error_message.include?("Unauthorized")
        recommendations << {
          fix: "Invalid or expired credentials - user may need to re-authorize",
          auto_fix: nil
        }
      end

      if error_message.include?("404") || error_message.include?("Not Found")
        recommendations << {
          fix: "Endpoint not found - check API base URL and test endpoint",
          auto_fix: nil
        }
      end

      if error_message.include?("Missing required")
        param_match = error_message.match(/Missing required.*?:?\s*(\w+)/)
        if param_match
          recommendations << {
            fix: "Add missing parameter: #{param_match[1]}",
            auto_fix: nil
          }
        end
      end

      recommendations
    end
  end
end

