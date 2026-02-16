class IntegrationsController < ApplicationController
  before_action :authenticate_user!

  def index
    # Redirect to Scout with integrations canvas
    redirect_to scout_path(canvas: "integrations_manager")
  end

  def connect
    @integration = Integration.find_by!(slug: params[:slug])
    @oauth_config = OauthConfiguration.includes(:auth_configs).find_by(integration: @integration)

    case @integration.auth_type
    when "oauth2", "oauth2_custom"
      # Redirect to OAuth authorization - the route is namespaced as integrations/oauth
      redirect_to "/integrations/#{@integration.slug}/auth"
    else
      # Show credentials form
      render :connect
    end
  end

  def create_connection
    @integration = Integration.find_by!(slug: params[:slug])

    begin
      # Create connection (scoped to both entity AND user for proper visibility)
      connection = Connection.find_or_initialize_by(
        entity: current_entity,
        user: current_user,
        integration: @integration
      )

      connection.name = params[:connection_name] || "#{@integration.name} - #{current_user.email}"
      connection.status = :connected

      if connection.save
        # Revoke any existing credentials before creating new ones
        # This prevents stale credentials from being used on reconnect
        connection.integration_credentials.active.update_all(
          status: :revoked,
          updated_at: Time.current
        )

        # Create credentials (store as JSON)
        credential = connection.integration_credentials.build(
          name: params[:credential_name] || "API Credentials",
          credentials: build_credentials_from_params.to_json,
          auth_method: determine_auth_method,
          status: :active
        )

        if credential.save
          # Test connection
          begin
            test_result = connection.test_connection!

            if test_result[:success]
              respond_to do |format|
                format.html { redirect_to integrations_path, notice: "Successfully connected to #{@integration.name}!" }
                format.json { render json: { success: true, message: "Successfully connected to #{@integration.name}!" } }
              end
            else
              respond_to do |format|
                format.html { redirect_to integrations_path, alert: "Connected but test failed: #{test_result[:error]}" }
                format.json { render json: { success: false, error: "Connected but test failed: #{test_result[:error]}" } }
              end
            end
          rescue => e
            Rails.logger.error "Connection test failed: #{e.message}"
            respond_to do |format|
              format.html { redirect_to integrations_path, notice: "Connected successfully (test skipped)" }
              format.json { render json: { success: true, message: "Connected successfully (test skipped)" } }
            end
          end
        else
          error_msg = credential.errors.full_messages.join(", ")
          respond_to do |format|
            format.html { redirect_to connect_integration_path(@integration.slug), alert: "Failed to save credentials: #{error_msg}" }
            format.json { render json: { success: false, error: "Failed to save credentials: #{error_msg}" } }
          end
        end
      else
        error_msg = connection.errors.full_messages.join(", ")
        respond_to do |format|
          format.html { redirect_to connect_integration_path(@integration.slug), alert: "Failed to create connection: #{error_msg}" }
          format.json { render json: { success: false, error: "Failed to create connection: #{error_msg}" } }
        end
      end
    rescue => e
      Rails.logger.error "Connection creation failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      respond_to do |format|
        format.html { redirect_to connect_integration_path(@integration.slug), alert: "An error occurred: #{e.message}" }
        format.json { render json: { success: false, error: "An error occurred: #{e.message}" } }
      end
    end
  end

  private

  def build_credentials_from_params
    # Check if integration has database-configured auth_configs
    oauth_config = OauthConfiguration.includes(:auth_configs).find_by(integration: @integration)
    
    if oauth_config && oauth_config.auth_configs.any?
      # Build credentials from dynamic auth_configs
      credentials = {}
      oauth_config.auth_configs.each do |auth_config|
        # Extract placeholder names from auth_value like {api_key}, {token}, etc.
        placeholders = auth_config.auth_value.scan(/\{(\w+)\}/).flatten
        
        # Look for each placeholder in params
        placeholders.each do |placeholder|
          param_value = params[placeholder] || params[placeholder.to_sym]
          if param_value.present?
            credentials[placeholder] = param_value
          end
        end
      end
      return credentials
    end
    
    # Fallback to static auth type mapping
    case @integration.auth_type
    when "api_key"
      { "api_key" => params[:api_key] }
    when "bearer_token"
      { "token" => params[:bearer_token] }
    when "basic_auth"
      {
        "username" => params[:username],
        "password" => params[:password]
      }
    when "custom"
      # Handle custom auth based on integration
      case @integration.slug
      when "slack"
        { "webhook_url" => params[:webhook_url] }
      else
        params.permit(:api_key, :token, :username, :password).to_h.stringify_keys
      end
    else
      {}
    end
  end

  def determine_auth_method
    case @integration.auth_type
    when "api_key"
      "header" # Usually goes in header
    when "bearer_token"
      "bearer"
    when "basic_auth"
      "basic"
    else
      "header"
    end
  end
end
