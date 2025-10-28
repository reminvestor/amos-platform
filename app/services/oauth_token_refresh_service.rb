class OauthTokenRefreshService
  def initialize(credential)
    @credential = credential
    @connection = credential.connection
    @integration = @connection.integration
  end

  def refresh_if_needed!
    # Check if token needs refresh (expired or expiring soon)
    return unless needs_refresh?

    Rails.logger.info "🔄 Refreshing OAuth token for #{@integration.name} connection ##{@connection.id}"
    
    refresh_token!
  end

  def needs_refresh?
    return false unless @credential.expires_at.present?
    
    # Refresh if expired or expiring within 5 minutes
    @credential.expires_at <= 5.minutes.from_now
  end

  def refresh_token!
    oauth_config = @integration.oauth_configurations.first
    
    unless oauth_config
      raise "No OAuth configuration found for #{@integration.name}"
    end

    refresh_token = @credential.credentials["refresh_token"] || @credential.credentials[:refresh_token]
    
    unless refresh_token
      raise "No refresh token available for #{@integration.name}"
    end

    # Build the refresh request
    token_url = oauth_config.token_url
    client_id = oauth_config.client_id
    client_secret = oauth_config.client_secret

    Rails.logger.info "🔍 Token Refresh Request:"
    Rails.logger.info "  Token URL: #{token_url}"
    Rails.logger.info "  Client ID: #{client_id&.first(10)}..."
    Rails.logger.info "  Refresh Token present: #{refresh_token.present?}"

    # QuickBooks and many OAuth providers use HTTP Basic Auth for refresh
    auth_string = Base64.strict_encode64("#{client_id}:#{client_secret}")
    
    body_params = {
      grant_type: "refresh_token",
      refresh_token: refresh_token
    }

    response = HTTParty.post(
      token_url,
      body: body_params,
      headers: {
        "Content-Type" => "application/x-www-form-urlencoded",
        "Accept" => "application/json",
        "Authorization" => "Basic #{auth_string}"
      }
    )

    Rails.logger.info "🔍 Token Refresh Response:"
    Rails.logger.info "  Status: #{response.code}"
    Rails.logger.info "  Body: #{response.body}"

    unless response.success?
      # Token refresh failed - mark credential as expired
      @credential.update(status: :expired)
      raise "Token refresh failed: #{response.code} - #{response.body}"
    end

    token_response = response.parsed_response

    # Update credentials with new token
    updated_credentials = @credential.credentials.merge(
      access_token: token_response["access_token"],
      token_type: token_response["token_type"]
    )

    # Some OAuth providers issue a new refresh token
    if token_response["refresh_token"].present?
      updated_credentials[:refresh_token] = token_response["refresh_token"]
    end

    # Update expiration
    new_expires_at = if token_response["expires_in"].present?
      Time.current + token_response["expires_in"].seconds
    else
      @credential.expires_at # Keep existing if not provided
    end

    @credential.update!(
      credentials: updated_credentials,
      expires_at: new_expires_at,
      status: :active
    )

    Rails.logger.info "✅ Token refreshed successfully for #{@integration.name}"
    
    true
  rescue => e
    Rails.logger.error "❌ Token refresh failed: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    
    # Mark credential as expired
    @credential.update(status: :expired) if @credential.persisted?
    
    raise e
  end
end

