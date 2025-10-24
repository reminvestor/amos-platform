class OAuthConfiguration < ApplicationRecord
  belongs_to :entity
  belongs_to :integration

  # Validations
  validates :client_id, :client_secret, :redirect_uri, :authorize_url, :token_url, presence: true
  validates :integration_id, uniqueness: { scope: :entity_id, message: "OAuth configuration already exists for this integration" }

  # Scopes
  scope :for_integration, ->(integration) { where(integration: integration) }
  scope :active, -> { where.not(client_id: nil) }

  # Parse scopes as JSON array
  def scopes_array
    return [] if scopes.blank?
    
    if scopes.is_a?(String)
      begin
        JSON.parse(scopes)
      rescue JSON::ParserError
        scopes.split(',').map(&:strip)
      end
    else
      scopes
    end
  end

  def scopes_array=(value)
    self.scopes = value.is_a?(Array) ? value.to_json : value
  end

  # Parse credentials as JSON
  def credentials_hash
    return {} if credentials.blank?
    
    if credentials.is_a?(String)
      begin
        JSON.parse(credentials)
      rescue JSON::ParserError
        {}
      end
    else
      credentials
    end
  end

  def credentials_hash=(value)
    self.credentials = value.is_a?(Hash) ? value.to_json : value
  end

  # Build OAuth credentials for the OAuth flow
  def oauth_credentials
    {
      client_id: client_id,
      client_secret: client_secret,
      redirect_uri: redirect_uri,
      authorize_url: authorize_url,
      token_url: token_url,
      scopes: scopes_array,
      access_type: 'offline' # Default for OAuth2
    }.merge(credentials_hash)
  end

  # Mask sensitive data for display
  def masked_client_secret
    return client_secret if client_secret.blank?
    "#{client_secret[0..3]}...#{client_secret[-4..]}"
  end
end
