class Integrations::OauthController < ApplicationController
  before_action :authenticate_user!
  before_action :set_integration, only: [ :authorize, :callback ]

  def authorize
    # Build OAuth authorization URL
    credentials = build_oauth_credentials

    # Store state for security
    session[:oauth_state] = SecureRandom.hex(16)
    session[:oauth_integration_id] = @integration.id

    # Build authorization URL
    auth_url = build_authorization_url(credentials, session[:oauth_state])

    redirect_to auth_url
  end

  def callback
    # Verify state to prevent CSRF
    if params[:state] != session[:oauth_state]
      return redirect_to integrations_path, alert: "Invalid OAuth state"
    end

    # Handle denial
    if params[:error]
      return redirect_to integrations_path, alert: "Authorization denied: #{params[:error_description]}"
    end

    # Exchange code for token
    begin
      token_response = exchange_code_for_token(params[:code])

      # Create or update connection
      connection = current_entity.connections.find_or_initialize_by(
        integration: @integration
      )

      connection.name ||= "#{@integration.name} - #{current_user.email}"
      connection.status = :connected
      connection.save!

      # Store credentials
      credential = connection.integration_credentials.find_or_initialize_by(
        name: "OAuth Token"
      )

      credential.assign_attributes(
        credentials: {
          access_token: token_response["access_token"],
          refresh_token: token_response["refresh_token"],
          token_type: token_response["token_type"],
          expires_in: token_response["expires_in"],
          scope: token_response["scope"]
        },
        auth_method: "bearer",
        expires_at: token_response["expires_in"] ? Time.current + token_response["expires_in"].seconds : nil,
        status: :active
      )

      credential.save!

      # Test the connection
      test_result = connection.test_connection!

      if test_result[:success]
        redirect_to integrations_path, notice: "Successfully connected to #{@integration.name}!"
      else
        redirect_to integrations_path, alert: "Connected but test failed: #{test_result[:error]}"
      end

    rescue => e
      Rails.logger.error "OAuth callback error: #{e.message}"
      redirect_to integrations_path, alert: "Failed to complete authorization: #{e.message}"
    end
  ensure
    # Clean up session
    session.delete(:oauth_state)
    session.delete(:oauth_integration_id)
  end

  private

  def set_integration
    @integration = Integration.find_by!(slug: params[:integration_slug] || params[:slug])

    unless @integration.oauth?
      redirect_to integrations_path, alert: "This integration does not support OAuth"
    end
  end

  def build_oauth_credentials
    if @integration.oauth2_custom?
      # User must have configured OAuth app
      oauth_config = current_entity.oauth_configurations.find_by(integration: @integration)
      unless oauth_config
        redirect_to integrations_path, alert: "Please configure OAuth credentials first"
        return
      end
      oauth_config.credentials
    else
      # Use pre-configured credentials
      @integration.auth_config
    end
  end

  def build_authorization_url(credentials, state)
    params = {
      client_id: credentials["client_id"],
      redirect_uri: credentials["redirect_uri"],
      response_type: "code",
      state: state,
      scope: credentials["scopes"]&.join(" ") || credentials["scope"],
      access_type: credentials["access_type"] || "offline"
    }

    # Add any integration-specific params
    if @integration.slug == "hubspot"
      params[:optional_scope] = credentials["optional_scopes"]&.join(" ")
    end

    uri = URI(credentials["authorize_url"])
    uri.query = params.to_query
    uri.to_s
  end

  def exchange_code_for_token(code)
    credentials = build_oauth_credentials

    response = HTTParty.post(
      credentials["token_url"],
      body: {
        client_id: credentials["client_id"],
        client_secret: credentials["client_secret"],
        code: code,
        grant_type: "authorization_code",
        redirect_uri: credentials["redirect_uri"]
      },
      headers: {
        "Content-Type" => "application/x-www-form-urlencoded"
      }
    )

    unless response.success?
      raise "Token exchange failed: #{response.code} - #{response.body}"
    end

    response.parsed_response
  end
end
