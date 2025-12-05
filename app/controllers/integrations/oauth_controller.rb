class Integrations::OauthController < ApplicationController
  before_action :authenticate_user!
  before_action :set_integration, only: [ :authorize, :callback, :params_form, :submit_params ]

  # GET /integrations/oauth/:integration_slug/authorize
  def authorize
    oauth_config = OauthConfiguration.find_by(integration: @integration)
    
    # Check if there are required params that need to be collected first
    if oauth_config&.has_required_params? && session[:oauth_required_params].blank?
      # Redirect to params form
      redirect_to integrations_oauth_params_form_path(@integration.slug)
      return
    end
    
    # Build OAuth authorization URL
    credentials = build_oauth_credentials
    
    # Validate credentials exist
    return if credentials.nil?
    
    # Debug logging
    Rails.logger.info "🔍 OAuth authorize - Integration: #{@integration.slug}"
    Rails.logger.info "🔍 Credentials keys: #{credentials.keys}"
    Rails.logger.info "🔍 Client ID present: #{credentials['client_id'].present?}"
    Rails.logger.info "🔍 Client ID value: #{credentials['client_id']&.first(10)}..."

    # Store state for security
    session[:oauth_state] = SecureRandom.hex(16)
    session[:oauth_integration_id] = @integration.id

    # Build authorization URL with required params substitution
    required_params = session[:oauth_required_params] || {}
    auth_url = build_authorization_url(credentials, session[:oauth_state], required_params)
    
    Rails.logger.info "🔍 Authorization URL: #{auth_url}"

    redirect_to auth_url, allow_other_host: true
  end

  # GET /integrations/oauth/:integration_slug/params_form
  # Show form to collect required parameters before OAuth
  def params_form
    oauth_config = OauthConfiguration.find_by(integration: @integration)
    
    unless oauth_config&.has_required_params?
      redirect_to integrations_oauth_authorize_path(@integration.slug)
      return
    end
    
    @required_params = oauth_config.required_param_definitions
    @oauth_config = oauth_config
  end

  # POST /integrations/oauth/:integration_slug/submit_params
  # Process the required params form and redirect to OAuth
  def submit_params
    oauth_config = OauthConfiguration.find_by(integration: @integration)
    
    unless oauth_config&.has_required_params?
      redirect_to integrations_oauth_authorize_path(@integration.slug)
      return
    end
    
    # Collect submitted params
    required_params = {}
    oauth_config.required_param_definitions.each do |param_def|
      param_name = param_def[:name]
      value = params[:required_params]&.dig(param_name)
      
      if value.blank?
        flash[:alert] = "#{param_def[:label] || param_name.humanize} is required"
        redirect_to integrations_oauth_params_form_path(@integration.slug)
        return
      end
      
      required_params[param_name] = value.strip
    end
    
    # Store in session for use during OAuth flow
    session[:oauth_required_params] = required_params
    
    # Now redirect to the authorize action
    redirect_to integrations_oauth_authorize_path(@integration.slug)
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

      # Build credentials hash
      credentials_hash = {
        access_token: token_response["access_token"],
        refresh_token: token_response["refresh_token"],
        token_type: token_response["token_type"],
        expires_in: token_response["expires_in"],
        scope: token_response["scope"]
      }
      
      # Include required params that were collected before OAuth
      # (e.g., shop_domain for Shopify)
      required_params = session[:oauth_required_params] || {}
      required_params.each do |key, value|
        credentials_hash[key.to_sym] = value
      end
      
      # Dynamically capture OAuth callback parameters based on integration config
      oauth_config = OauthConfiguration.find_by(integration: @integration)
      if oauth_config && oauth_config.callback_param_names.any?
        oauth_config.callback_param_names.each do |param_name|
          if params[param_name].present?
            # Store with original name - the build_path method will handle case conversion
            credentials_hash[param_name.to_sym] = params[param_name]
          end
        end
      end

      credential.assign_attributes(
        credentials: credentials_hash,
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
    session.delete(:oauth_required_params)
  end

  private

  def set_integration
    @integration = Integration.find_by!(slug: params[:integration_slug] || params[:slug])

    unless @integration.oauth?
      redirect_to integrations_path, alert: "This integration does not support OAuth"
    end
  end

  def build_oauth_credentials
    # Get platform-wide OAuth configuration from database
    oauth_config = OauthConfiguration.find_by(integration: @integration)
    
    unless oauth_config
      redirect_to integrations_path, alert: "#{@integration.name} OAuth has not been configured yet. Please contact support."
      return nil
    end
    
    oauth_config.credentials
  end

  def build_authorization_url(credentials, state, required_params = {})
    oauth_config = OauthConfiguration.find_by(integration: @integration)
    
    # Get the authorize URL and substitute any placeholders with required params
    authorize_url = credentials["authorize_url"]
    if oauth_config && required_params.present?
      authorize_url = oauth_config.authorize_url_with_params(required_params)
    end
    
    url_params = {
      client_id: credentials["client_id"],
      redirect_uri: credentials["redirect_uri"],
      response_type: "code",
      state: state,
      scope: credentials["scopes"]&.join(" ") || credentials["scope"],
      access_type: credentials["access_type"] || "offline"
    }

    # Add any integration-specific params
    if @integration.slug == "hubspot"
      url_params[:optional_scope] = credentials["optional_scopes"]&.join(" ")
    end

    uri = URI(authorize_url)
    uri.query = url_params.to_query
    uri.to_s
  end

  def exchange_code_for_token(code)
    credentials = build_oauth_credentials
    oauth_config = OauthConfiguration.find_by(integration: @integration)
    required_params = session[:oauth_required_params] || {}

    # Get the token URL and substitute any placeholders with required params
    token_url = credentials["token_url"]
    if oauth_config && required_params.present?
      token_url = oauth_config.token_url_with_params(required_params)
    end

    Rails.logger.info "🔍 Token Exchange Request:"
    Rails.logger.info "  Token URL: #{token_url}"
    Rails.logger.info "  Client ID: #{credentials['client_id']&.first(10)}..."
    Rails.logger.info "  Client Secret present: #{credentials['client_secret'].present?}"
    Rails.logger.info "  Client Secret length: #{credentials['client_secret']&.length}"
    Rails.logger.info "  Redirect URI: #{credentials['redirect_uri']}"
    Rails.logger.info "  Code: #{code&.first(20)}..."

    # QuickBooks requires Basic Auth header (NOT credentials in body)
    auth_string = Base64.strict_encode64("#{credentials['client_id']}:#{credentials['client_secret']}")
    
    Rails.logger.info "  Auth Header: Basic #{auth_string[0..20]}..."

    # Build the request body
    body_params = {
      grant_type: "authorization_code",
      code: code,
      redirect_uri: credentials["redirect_uri"]
    }
    
    Rails.logger.info "  Body params: #{body_params.inspect}"

    response = HTTParty.post(
      token_url,
      body: body_params,
      headers: {
        "Content-Type" => "application/x-www-form-urlencoded",
        "Accept" => "application/json",
        "Authorization" => "Basic #{auth_string}"
      }
    )

    Rails.logger.info "🔍 Token Exchange Response:"
    Rails.logger.info "  Status: #{response.code}"
    Rails.logger.info "  Body: #{response.body}"
    Rails.logger.info "  Headers: #{response.headers.inspect}"

    unless response.success?
      raise "Token exchange failed: #{response.code} - #{response.body}"
    end

    response.parsed_response
  end
end
