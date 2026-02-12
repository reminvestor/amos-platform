class IntegrationCredential < ApplicationRecord
  belongs_to :connection

  # Encryption - Rails 7+ built-in encryption
  # Encrypts OAuth tokens, API keys, and other sensitive credentials at rest
  # Requires: ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY, DETERMINISTIC_KEY, KEY_DERIVATION_SALT
  encrypts :credentials

  # Parse JSON credentials
  def credentials
    return {} if self[:credentials].blank?

    # Handle both hash and string formats
    if self[:credentials].is_a?(Hash)
      self[:credentials]
    elsif self[:credentials].is_a?(String)
      # Only accept JSON format - no eval() for security
      begin
        JSON.parse(self[:credentials])
      rescue JSON::ParserError => e
        Rails.logger.error("Invalid credentials JSON for IntegrationCredential #{id}: #{e.message}")
        {}
      end
    else
      {}
    end
  end

  # Store credentials as JSON
  def credentials=(value)
    self[:credentials] = value.is_a?(Hash) ? value.to_json : value
  end

  # Validations
  validates :name, presence: true
  validates :status, presence: true
  validates :auth_method, inclusion: { in: %w[header query body bearer basic] }

  # Enums
  enum :status, {
    active: 0,
    expired: 1,
    revoked: 2,
    rotating: 3
  }

  # Scopes
  scope :active, -> { where(status: :active) }
  scope :expiring_soon, -> { where(expires_at: ..7.days.from_now) }
  scope :needs_rotation, -> { where(rotates_at: ..Time.current) }

  # Default values
  after_initialize :set_defaults, if: :new_record?

  # Callbacks
  before_validation :set_rotation_schedule

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  def needs_refresh?
    return false unless connection.integration.oauth?

    # OAuth tokens typically need refresh before expiry
    expires_at.present? && expires_at < 1.hour.from_now
  end

  def refresh_token!
    return unless connection.integration.oauth?
    return unless credentials["refresh_token"].present?

    # This would call the OAuth provider to refresh
    # For now, just mark it as needing implementation
    raise NotImplementedError, "OAuth token refresh not yet implemented"
  end

  def build_auth_header
    headers = {}
    
    # Get auth_configs from integration's oauth_configuration
    oauth_config = connection.integration.oauth_configurations.first
    
    if oauth_config && oauth_config.auth_configs.any?
      # Basic auth needs special handling — Base64 encode username:password
      if connection.integration.auth_type == 'basic_auth'
        # Read placeholder names from the auth_configs (e.g. {organization_id}, {api_key})
        header_configs = oauth_config.auth_configs.where(auth_placement: 'header').order(:position).to_a
        user_key = header_configs.first&.auth_value&.scan(/\{(\w+)\}/)&.flatten&.first || 'username'
        pass_key = header_configs.second&.auth_value&.scan(/\{(\w+)\}/)&.flatten&.first || 'password'

        username = credentials[user_key] || credentials['username'] || credentials['api_key'] || ''
        password = credentials[pass_key] || credentials['password'] || ''
        encoded = Base64.strict_encode64("#{username}:#{password}")
        return { 'Authorization' => "Basic #{encoded}" }
      end

      # Use database-driven auth_configs for all other auth types
      oauth_config.auth_configs.where(auth_placement: 'header').each do |auth_config|
        # Replace placeholders in auth_value with actual credential values
        value = auth_config.auth_value
        
        # Find all placeholders like {api_key}, {token}, etc.
        placeholders = value.scan(/\{(\w+)\}/).flatten
        
        placeholders.each do |placeholder|
          credential_value = credentials[placeholder] || credentials[placeholder.to_sym] || ''
          value = value.gsub("{#{placeholder}}", credential_value)
        end
        
        headers[auth_config.auth_key] = value
      end
      
      return headers
    end
    
    # Fallback to legacy auth_method logic if no auth_configs
    case auth_method
    when "bearer"
      { "Authorization" => "Bearer #{credentials['access_token'] || credentials['token']}" }
    when "basic"
      # For Stripe, the API key is the username, password is empty
      username = credentials["username"] || credentials["api_key"] || ""
      password = credentials["password"] || ""

      encoded = Base64.strict_encode64("#{username}:#{password}")

      { "Authorization" => "Basic #{encoded}" }
    when "header"
      { auth_field_name => credentials["api_key"] || credentials["token"] }
    else
      {}
    end
  end

  def build_auth_params
    return {} unless auth_method == "query"

    { auth_field_name => credentials["api_key"] || credentials["token"] }
  end

  def rotate!
    update!(status: :rotating, rotated_at: Time.current)
    # Trigger rotation job
    RotateCredentialJob.perform_later(self)
  end

  def mask_for_display
    return {} if credentials.blank?

    credentials.transform_values do |value|
      next value unless value.is_a?(String)
      next value if value.length < 8

      # Show first 4 and last 4 characters
      "#{value[0..3]}...#{value[-4..]}"
    end
  end

  private

  def set_defaults
    self.status ||= :active
    self.metadata ||= {}
    self[:credentials] ||= "{}"
  end

  def set_rotation_schedule
    return unless new_record?
    return if rotates_at.present?

    # Default rotation schedule based on credential type
    self.rotates_at = case connection.integration.auth_type
    when "api_key"
      90.days.from_now
    when "oauth2", "oauth2_custom"
      # OAuth tokens rotate with refresh
      nil
    else
      180.days.from_now
    end
  end
end
