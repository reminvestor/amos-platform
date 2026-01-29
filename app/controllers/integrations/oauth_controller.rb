class Integrations::OauthController < ApplicationController
  before_action :authenticate_user!
  before_action :set_integration, only: [ :authorize, :callback, :params_form, :submit_params ]
  before_action :require_two_factor!, only: [ :authorize, :params_form, :submit_params ]

  # GET /integrations/oauth/:integration_slug/authorize
  def authorize
    oauth_config = OauthConfiguration.find_by(integration: @integration)
    
    # Check if there are required params that need to be collected first
    # Use a temporary cache key to pass params from the form
    params_cache_key = "oauth_params:#{current_user.id}:#{@integration.id}"
    cached_params = Rails.cache.read(params_cache_key)
    
    if oauth_config&.has_required_params? && cached_params.blank?
      # Redirect to params form
      redirect_to integrations_oauth_params_form_path(@integration.slug)
      return
    end
    
    # Clean up the temporary params cache
    Rails.cache.delete(params_cache_key) if cached_params.present?
    session[:oauth_required_params] = cached_params
    
    # Build OAuth authorization URL
    credentials = build_oauth_credentials
    
    # Validate credentials exist
    return if credentials.nil?
    
    # Debug logging
    Rails.logger.info "🔍 OAuth authorize - Integration: #{@integration.slug}"
    Rails.logger.info "🔍 Credentials keys: #{credentials.keys}"
    Rails.logger.info "🔍 Client ID present: #{credentials['client_id'].present?}"
    Rails.logger.info "🔍 Client ID value: #{credentials['client_id']&.first(10)}..."

    # Store state for security - use cache instead of session to avoid cookie overflow
    oauth_state = SecureRandom.hex(16)
    oauth_data = {
      integration_id: @integration.id,
      required_params: session.delete(:oauth_required_params) || {},
      user_id: current_user.id,
      entity_id: current_entity.id
    }
    
    # Store in cache with 10 minute expiry
    Rails.cache.write("oauth_state:#{oauth_state}", oauth_data, expires_in: 10.minutes)

    # Build authorization URL with required params substitution
    auth_url = build_authorization_url(credentials, oauth_state, oauth_data[:required_params])
    
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
    
    # Store in cache for use during OAuth flow (avoid session cookie overflow)
    params_cache_key = "oauth_params:#{current_user.id}:#{@integration.id}"
    Rails.cache.write(params_cache_key, required_params, expires_in: 10.minutes)
    
    # Now redirect to the authorize action
    redirect_to integrations_oauth_authorize_path(@integration.slug)
  end

  def callback
    # Retrieve OAuth state from cache
    oauth_state = params[:state]
    oauth_data = Rails.cache.read("oauth_state:#{oauth_state}")
    
    # Verify state to prevent CSRF
    if oauth_data.nil?
      return redirect_to "#{chat_mode_path}?canvas=integrations_manager&alert=#{CGI.escape("Invalid or expired OAuth state. Please try again.")}"
    end
    
    # Delete the state from cache (one-time use)
    Rails.cache.delete("oauth_state:#{oauth_state}")

    # Handle denial
    if params[:error]
      return redirect_to "#{chat_mode_path}?canvas=integrations_manager&alert=#{CGI.escape("Authorization denied: #{params[:error_description]}")}"
    end

    # Exchange code for token
    begin
      token_response = exchange_code_for_token(params[:code], oauth_data)

      # Use the entity from when OAuth was initiated (not current_entity which may have changed)
      # This ensures the connection is created for the correct entity
      oauth_entity = Entity.find_by(id: oauth_data[:entity_id])
      oauth_user = User.find_by(id: oauth_data[:user_id])
      
      unless oauth_entity && oauth_user
        return redirect_to "#{chat_mode_path}?canvas=integrations_manager&alert=#{CGI.escape("OAuth session expired. Please try again.")}"
      end
      
      # Verify the current user matches the user who started the OAuth flow
      unless current_user.id == oauth_user.id
        return redirect_to "#{chat_mode_path}?canvas=integrations_manager&alert=#{CGI.escape("User mismatch. Please log in as the user who started the connection.")}"
      end

      # Create or update connection (scoped to both user AND entity from OAuth start)
      # This ensures that the same user can have separate connections per entity
      connection = Connection.find_or_initialize_by(
        user: oauth_user,
        entity: oauth_entity,
        integration: @integration
      )
      connection.name ||= "#{@integration.name} - #{oauth_user.email}"
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
      required_params = oauth_data[:required_params] || {}
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

      # Clean up session to avoid CookieOverflow on redirect
      cleanup_session_for_redirect!

      # Check if this OAuth was initiated from mobile
      if oauth_data[:from_mobile]
        # For mobile, show a success page that instructs user to return to app
        # or redirect to custom URL scheme
        if test_result[:success]
          render_mobile_oauth_success(@integration.name)
        else
          render_mobile_oauth_error("Connected but test failed: #{test_result[:error]}")
        end
      else
        # Redirect back to chat with canvas load parameter (web flow)
        if test_result[:success]
          redirect_to "#{chat_mode_path}?canvas=integrations_manager&notice=#{CGI.escape("Successfully connected to #{@integration.name}!")}"
        else
          redirect_to "#{chat_mode_path}?canvas=integrations_manager&alert=#{CGI.escape("Connected but test failed: #{test_result[:error]}")}"
        end
      end

    rescue => e
      Rails.logger.error "OAuth callback error: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
      cleanup_session_for_redirect!

      # Check if from mobile
      if oauth_data&.dig(:from_mobile)
        render_mobile_oauth_error("Failed to complete authorization: #{e.message}")
      else
        redirect_to "#{chat_mode_path}?canvas=integrations_manager&alert=#{CGI.escape("Failed to complete authorization: #{e.message}")}"
      end
    end
  end

  private

  def set_integration
    @integration = Integration.find_by!(slug: params[:integration_slug] || params[:slug])

    unless @integration.oauth?
      redirect_to "#{chat_mode_path}?canvas=integrations_manager&alert=#{CGI.escape("This integration does not support OAuth")}"
    end
  end

  def build_oauth_credentials
    # Get platform-wide OAuth configuration from database
    oauth_config = OauthConfiguration.find_by(integration: @integration)
    
    unless oauth_config
      redirect_to "#{chat_mode_path}?canvas=integrations_manager&alert=#{CGI.escape("#{@integration.name} OAuth has not been configured yet. Please contact support.")}"
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

  # Clean up OAuth-specific session keys after flow completes
  def cleanup_session_for_redirect!
    # Remove OAuth-specific keys that are no longer needed
    oauth_keys = %w[
      oauth_state oauth_integration_id oauth_required_params
      user_return_to
    ]
    oauth_keys.each { |key| session.delete(key) }
  end

  # Render success page for mobile OAuth
  def render_mobile_oauth_success(integration_name)
    render html: <<~HTML.html_safe, layout: false
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Connected Successfully</title>
        <style>
          body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            min-height: 100vh;
            margin: 0;
            padding: 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            text-align: center;
          }
          .icon { font-size: 64px; margin-bottom: 20px; }
          h1 { margin: 0 0 10px 0; font-size: 24px; }
          p { margin: 0; opacity: 0.9; font-size: 16px; }
          .return-btn {
            margin-top: 30px;
            padding: 15px 30px;
            background: white;
            color: #667eea;
            border: none;
            border-radius: 8px;
            font-size: 16px;
            font-weight: 600;
            cursor: pointer;
          }
        </style>
      </head>
      <body>
        <div class="icon">✓</div>
        <h1>#{integration_name} Connected!</h1>
        <p>You can now close this window and return to the AMOS app.</p>
        <button class="return-btn" onclick="window.close()">Close Window</button>
      </body>
      </html>
    HTML
  end

  # Render error page for mobile OAuth
  def render_mobile_oauth_error(error_message)
    render html: <<~HTML.html_safe, layout: false
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Connection Failed</title>
        <style>
          body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            min-height: 100vh;
            margin: 0;
            padding: 20px;
            background: linear-gradient(135deg, #e74c3c 0%, #c0392b 100%);
            color: white;
            text-align: center;
          }
          .icon { font-size: 64px; margin-bottom: 20px; }
          h1 { margin: 0 0 10px 0; font-size: 24px; }
          p { margin: 0; opacity: 0.9; font-size: 14px; max-width: 300px; }
          .return-btn {
            margin-top: 30px;
            padding: 15px 30px;
            background: white;
            color: #e74c3c;
            border: none;
            border-radius: 8px;
            font-size: 16px;
            font-weight: 600;
            cursor: pointer;
          }
        </style>
      </head>
      <body>
        <div class="icon">✗</div>
        <h1>Connection Failed</h1>
        <p>#{ERB::Util.html_escape(error_message)}</p>
        <button class="return-btn" onclick="window.close()">Close Window</button>
      </body>
      </html>
    HTML
  end

  def exchange_code_for_token(code, oauth_data = {})
    credentials = build_oauth_credentials
    oauth_config = OauthConfiguration.find_by(integration: @integration)
    required_params = oauth_data[:required_params] || {}

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
