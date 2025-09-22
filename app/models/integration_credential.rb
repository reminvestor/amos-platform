class IntegrationCredential < ApplicationRecord
  belongs_to :connection
  
  # Encryption - Rails 7+ built-in encryption
  # TODO: Configure encryption keys in credentials
  # encrypts :credentials
  
  # Parse JSON credentials
  def credentials
    return {} if self[:credentials].blank?
    
    # Handle both hash and string formats
    if self[:credentials].is_a?(Hash)
      self[:credentials]
    elsif self[:credentials].is_a?(String)
      # Try to parse as JSON first
      begin
        JSON.parse(self[:credentials])
      rescue JSON::ParserError
        # If it fails, try to evaluate as Ruby hash string (legacy format)
        begin
          eval(self[:credentials])
        rescue
          {}
        end
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
    return unless credentials['refresh_token'].present?
    
    # This would call the OAuth provider to refresh
    # For now, just mark it as needing implementation
    raise NotImplementedError, "OAuth token refresh not yet implemented"
  end
  
  def build_auth_header
    case auth_method
    when 'bearer'
      { 'Authorization' => "Bearer #{credentials['access_token'] || credentials['token']}" }
    when 'basic'
      # For Stripe, the API key is the username, password is empty
      username = credentials['username'] || ''
      password = credentials['password'] || ''
      
      encoded = Base64.strict_encode64("#{username}:#{password}")
      
      { 'Authorization' => "Basic #{encoded}" }
    when 'header'
      { auth_field_name => credentials['api_key'] || credentials['token'] }
    else
      {}
    end
  end
  
  def build_auth_params
    return {} unless auth_method == 'query'
    
    { auth_field_name => credentials['api_key'] || credentials['token'] }
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
    self[:credentials] ||= '{}'
  end
  
  def set_rotation_schedule
    return unless new_record?
    return if rotates_at.present?
    
    # Default rotation schedule based on credential type
    self.rotates_at = case connection.integration.auth_type
    when 'api_key'
      90.days.from_now
    when 'oauth2', 'oauth2_custom'
      # OAuth tokens rotate with refresh
      nil
    else
      180.days.from_now
    end
  end
end
