class OauthConfiguration < ApplicationRecord
  belongs_to :integration

  # Validations
  validates :client_id, :client_secret, :redirect_uri, presence: true
  validates :integration_id, uniqueness: { message: "already has an OAuth configuration" }

  # Enums
  enum :status, {
    active: 0,
    inactive: 1,
    revoked: 2
  }, _type: :integer

  # Scopes
  scope :active, -> { where(status: :active) }

  # Default values
  after_initialize :set_defaults, if: :new_record?

  # Return credentials in the format expected by OAuth controller
  def credentials
    base_credentials = {
      "client_id" => client_id,
      "client_secret" => client_secret,
      "redirect_uri" => redirect_uri,
      "scopes" => scopes&.split(",")&.map(&:strip) || []
    }
    
    # Add URLs - use saved values or fall back to integration defaults
    if integration.present? && integration.auth_config.present?
      base_credentials["authorize_url"] = authorize_url.presence || integration.auth_config["authorize_url"]
      base_credentials["token_url"] = token_url.presence || integration.auth_config["token_url"]
      base_credentials["access_type"] = integration.auth_config["access_type"] || "offline"
    else
      base_credentials["authorize_url"] = authorize_url
      base_credentials["token_url"] = token_url
      base_credentials["access_type"] = "offline"
    end
    
    base_credentials.merge(self[:credentials] || {})
  end

  private

  def set_defaults
    self.status ||= :active
    self.credentials ||= {}
    self.metadata ||= {}
    
    # Pre-fill URLs from integration if not set and integration is available
    if integration.present? && integration.auth_config.present?
      self.authorize_url ||= integration.auth_config["authorize_url"]
      self.token_url ||= integration.auth_config["token_url"]
    end
  end
end
