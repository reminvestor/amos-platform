# frozen_string_literal: true

module Tools
  class DiagnoseIntegrationTool < BaseTool
    def self.metadata
      {
        name: "diagnose_integration",
        description: <<~DESC.strip,
          Diagnose issues with an integration connection. This tool performs a comprehensive
          analysis of the integration configuration, credentials, and connectivity.
          
          Returns detailed diagnostics including:
          - Connection status and health
          - OAuth/Auth configuration issues
          - Credential problems (missing, expired, invalid)
          - Endpoint configuration issues
          - Recent error logs
          - Recommended fixes
          
          Use this as the first step when debugging integration problems.
        DESC
        category: "integration_repair",
        input_schema: {
          type: "object",
          properties: {
            integration_slug: {
              type: "string",
              description: "The slug of the integration to diagnose (e.g., 'shopify', 'stripe')"
            },
            connection_id: {
              type: "integer",
              description: "Specific connection ID to diagnose (optional - if not provided, checks all connections for this entity)"
            },
            include_logs: {
              type: "boolean",
              description: "Whether to include recent error logs in the diagnosis (default: true)"
            }
          },
          required: ["integration_slug"]
        }
      }
    end

    def execute(args)
      log_execution(args)

      integration_slug = get_arg(args, :integration_slug)
      connection_id = get_arg(args, :connection_id)
      include_logs = get_arg(args, :include_logs, true)

      # Find the integration
      integration = Integration.find_by(slug: integration_slug)
      unless integration
        return error_response("Integration '#{integration_slug}' not found")
      end

      # Find connections - user-scoped for data privacy
      connections = if connection_id
                      conn = Connection.find_by(id: connection_id, integration: integration, user: @user, entity: @entity)
                      conn ? [conn] : []
                    elsif user_is_admin? && @context[:all_connections]
                      # Admins can see all connections if explicitly requested
                      Connection.where(integration: integration)
                    else
                      # Regular users only see their own connections
                      Connection.where(integration: integration, user: @user, entity: @entity)
                    end

      if connections.empty?
        return error_response(
          "No connections found for #{integration.name}",
          suggestion: "The user may need to connect to #{integration.name} first"
        )
      end

      # Diagnose each connection
      diagnostics = connections.map { |conn| diagnose_connection(conn, include_logs) }

      # Get OAuth/Auth configuration issues (full details for admins only)
      oauth_issues = diagnose_oauth_config(integration)
      auth_issues = diagnose_auth_configs(integration)

      # Build recommendations - filter based on permissions
      recommendations = build_recommendations(diagnostics, oauth_issues, auth_issues)
      
      # Non-admins only see user-level fix recommendations
      unless user_is_admin?
        recommendations = recommendations.reject { |r| r[:admin_only] }
        # Hide sensitive config details from non-admins
        oauth_issues = sanitize_for_user(oauth_issues)
        auth_issues = { configured: auth_issues[:configured], count: auth_issues[:count] }
      end

      success_response(
        integration: {
          id: integration.id,
          name: integration.name,
          slug: integration.slug,
          auth_type: integration.auth_type,
          api_base_url: user_is_admin? ? integration.api_base_url : "[hidden]"
        },
        oauth_configuration: oauth_issues,
        auth_configuration: auth_issues,
        connections: diagnostics,
        overall_health: calculate_health(diagnostics),
        recommendations: recommendations,
        fixable_issues: recommendations.select { |r| r[:auto_fixable] },
        is_admin: user_is_admin?
      )
    rescue => e
      Rails.logger.error "DiagnoseIntegrationTool error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      error_response("Failed to diagnose integration: #{e.message}")
    end

    private

    def user_is_admin?
      return true if @user.respond_to?(:admin?) && @user.admin?
      return true if @user.respond_to?(:role) && @user.role.to_s.in?(%w[admin super_admin])
      return true if @user.respond_to?(:is_admin) && @user.is_admin
      return true if @context[:is_admin] || @context["is_admin"]
      false
    end

    def can_access_connection?(connection)
      return true if user_is_admin?
      connection.entity_id == @entity&.id
    end

    def sanitize_for_user(oauth_issues)
      # Remove sensitive details for non-admin users
      {
        configured: oauth_issues[:configured],
        status: oauth_issues[:status],
        has_client_credentials: oauth_issues[:has_client_credentials],
        issues: oauth_issues[:issues]&.select { |i| i[:type] != :oauth_url }
      }
    end

    def diagnose_connection(connection, include_logs)
      credential = connection.active_credential
      
      issues = []
      
      # Check connection status
      issues << { type: :status, severity: :error, message: "Connection is in #{connection.status} status" } unless connection.connected?
      
      # Check credentials
      if credential.nil?
        issues << { type: :credentials, severity: :error, message: "No active credentials found" }
      else
        # Check for required credential keys
        creds = credential.credentials || {}
        
        if connection.integration.oauth?
          issues << { type: :credentials, severity: :error, message: "Missing access_token" } if creds["access_token"].blank?
          issues << { type: :credentials, severity: :warning, message: "Missing refresh_token (cannot auto-refresh)" } if creds["refresh_token"].blank?
          
          # Check expiration
          if credential.expires_at && credential.expires_at < Time.current
            issues << { type: :credentials, severity: :error, message: "Token expired at #{credential.expires_at}" }
          end
        else
          issues << { type: :credentials, severity: :error, message: "Missing api_key/token" } if creds["api_key"].blank? && creds["token"].blank? && creds["access_token"].blank?
        end
        
        # Check for required params (like shop_domain for Shopify)
        oauth_config = connection.integration.oauth_configurations.first
        if oauth_config&.has_required_params?
          oauth_config.required_param_definitions.each do |param|
            param_name = param[:name]
            if creds[param_name].blank? && creds[param_name.to_sym].blank?
              issues << { type: :credentials, severity: :error, message: "Missing required parameter: #{param_name}" }
            end
          end
        end
      end

      # Check last health check
      if connection.last_health_check
        age = Time.current - connection.last_health_check
        if age > 24.hours
          issues << { type: :health_check, severity: :warning, message: "Health check is #{(age / 3600).round} hours old" }
        end
      else
        issues << { type: :health_check, severity: :info, message: "No health check recorded" }
      end

      # Get recent errors if requested
      recent_errors = []
      if include_logs
        recent_errors = IntegrationLog.where(connection: connection)
                                       .where("response_status >= 400 OR error_message IS NOT NULL")
                                       .order(created_at: :desc)
                                       .limit(5)
                                       .map do |log|
          {
            timestamp: log.created_at,
            endpoint: log.endpoint,
            status: log.response_status,
            error: log.error_message
          }
        end
      end

      # Test connection if it appears healthy
      test_result = nil
      if issues.none? { |i| i[:severity] == :error }
        begin
          test_result = connection.test_connection!
        rescue => e
          test_result = { success: false, error: e.message }
        end
      end

      {
        id: connection.id,
        name: connection.name,
        status: connection.status,
        has_credentials: credential.present?,
        credential_status: credential&.status,
        credential_keys: credential&.credentials&.keys || [],
        issues: issues,
        recent_errors: recent_errors,
        test_result: test_result,
        created_at: connection.created_at,
        last_health_check: connection.last_health_check
      }
    end

    def diagnose_oauth_config(integration)
      oauth_config = integration.oauth_configurations.first
      return { configured: false, message: "No OAuth configuration found" } unless oauth_config

      issues = []

      # Check OAuth URLs for placeholders
      if oauth_config.authorize_url.present?
        placeholders = oauth_config.authorize_url.scan(/\{(\w+)\}/).flatten
        if placeholders.any?
          if oauth_config.has_required_params?
            required_names = oauth_config.required_param_definitions.map { |p| p[:name] }
            missing = placeholders - required_names
            issues << { type: :oauth_url, severity: :error, message: "Authorize URL has placeholders #{missing} not defined in required_params" } if missing.any?
          else
            issues << { type: :oauth_url, severity: :error, message: "Authorize URL has placeholders but no required_params defined" }
          end
        end
      end

      if oauth_config.token_url.present?
        placeholders = oauth_config.token_url.scan(/\{(\w+)\}/).flatten
        if placeholders.any? && !oauth_config.has_required_params?
          issues << { type: :oauth_url, severity: :error, message: "Token URL has placeholders but no required_params defined" }
        end
      end

      # Check for custom auth headers
      auth_configs = oauth_config.auth_configs.to_a
      if integration.oauth? && auth_configs.empty?
        issues << { type: :auth_header, severity: :info, message: "Using default Bearer token (no custom auth header configured)" }
      end

      {
        configured: true,
        status: oauth_config.status,
        has_client_credentials: oauth_config.client_id.present? && oauth_config.client_secret.present?,
        authorize_url: oauth_config.authorize_url,
        token_url: oauth_config.token_url,
        test_endpoint: oauth_config.test_endpoint,
        required_params: oauth_config.required_param_definitions,
        callback_params: oauth_config.callback_param_names,
        auth_configs: auth_configs.map { |ac| { key: ac.auth_key, value: ac.auth_value, placement: ac.auth_placement } },
        issues: issues
      }
    end

    def diagnose_auth_configs(integration)
      oauth_config = integration.oauth_configurations.first
      return { configured: false } unless oauth_config

      auth_configs = oauth_config.auth_configs.to_a
      issues = []

      auth_configs.each do |ac|
        # Check for common issues
        if ac.auth_value.blank?
          issues << { type: :auth_config, severity: :error, message: "Auth config '#{ac.auth_key}' has empty value" }
        end

        # Check placeholder format
        placeholders = ac.auth_value&.scan(/\{(\w+)\}/)&.flatten || []
        if placeholders.empty? && !ac.auth_value&.include?('{')
          issues << { type: :auth_config, severity: :warning, message: "Auth config '#{ac.auth_key}' has no placeholder - will use literal value" }
        end
      end

      {
        configured: auth_configs.any?,
        count: auth_configs.count,
        configs: auth_configs.map { |ac| { id: ac.id, key: ac.auth_key, value: ac.auth_value, placement: ac.auth_placement } },
        issues: issues
      }
    end

    def calculate_health(diagnostics)
      return "unknown" if diagnostics.empty?

      error_count = diagnostics.sum { |d| d[:issues].count { |i| i[:severity] == :error } }
      warning_count = diagnostics.sum { |d| d[:issues].count { |i| i[:severity] == :warning } }

      if error_count > 0
        "critical"
      elsif warning_count > 0
        "warning"
      elsif diagnostics.all? { |d| d[:test_result]&.dig(:success) }
        "healthy"
      else
        "degraded"
      end
    end

    def build_recommendations(diagnostics, oauth_issues, auth_issues)
      recommendations = []

      # Check for missing credentials
      diagnostics.each do |diag|
        diag[:issues].each do |issue|
          case issue[:type]
          when :credentials
            if issue[:message].include?("Missing required parameter")
              param = issue[:message].match(/Missing required parameter: (\w+)/)[1]
              recommendations << {
                priority: :high,
                issue: issue[:message],
                fix: "Add '#{param}' to connection credentials",
                action: "repair_connection_credentials",
                auto_fixable: false,
                admin_only: false,  # Users can fix their own credentials
                params: { connection_id: diag[:id], param_name: param }
              }
            elsif issue[:message].include?("Token expired")
              recommendations << {
                priority: :high,
                issue: issue[:message],
                fix: "Refresh the OAuth token or re-authorize",
                action: "refresh_oauth_token",
                auto_fixable: true,
                admin_only: false,
                params: { connection_id: diag[:id] }
              }
            end
          when :status
            recommendations << {
              priority: :high,
              issue: issue[:message],
              fix: "Test and update connection status",
              action: "repair_connection_credentials",
              auto_fixable: true,
              admin_only: false,
              params: { connection_id: diag[:id], action: "test_and_fix" }
            }
          end
        end
      end

      # OAuth config issues - ADMIN ONLY
      oauth_issues[:issues]&.each do |issue|
        if issue[:type] == :oauth_url
          recommendations << {
            priority: :high,
            issue: issue[:message],
            fix: "Update OAuth URLs or add required_params (requires admin)",
            action: "repair_oauth_config",
            auto_fixable: false,
            admin_only: true  # Only admins can modify OAuth config
          }
        elsif issue[:type] == :auth_header
          recommendations << {
            priority: :medium,
            issue: issue[:message],
            fix: "Configure custom auth header (requires admin)",
            action: "repair_auth_config",
            auto_fixable: false,
            admin_only: true
          }
        end
      end

      # Auth config issues - ADMIN ONLY
      auth_issues[:issues]&.each do |issue|
        recommendations << {
          priority: :medium,
          issue: issue[:message],
          fix: "Update auth configuration (requires admin)",
          action: "repair_auth_config",
          auto_fixable: false,
          admin_only: true
        }
      end

      recommendations.sort_by { |r| r[:priority] == :high ? 0 : 1 }
    end
  end
end

