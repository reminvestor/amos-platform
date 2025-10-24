class OauthConfiguration < ApplicationRecord
  belongs_to :integration
  has_many :auth_configs, dependent: :destroy
  
  accepts_nested_attributes_for :auth_configs, allow_destroy: true, reject_if: :all_blank

  # Validations
  validates :integration_id, uniqueness: { message: "already has an OAuth configuration" }
  
  # OAuth-specific validations
  with_options if: -> { integration&.oauth? } do
    validates :client_id, :client_secret, :redirect_uri, presence: true
  end

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

  # Get list of OAuth callback parameter names to capture
  # e.g., ["realmId", "instance_url", "organization_id"]
  def callback_param_names
    callback_params || []
  end

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
    self.callback_params ||= []
    
    # Pre-fill URLs from integration if not set and integration is available
    if integration.present? && integration.auth_config.present?
      self.authorize_url ||= integration.auth_config["authorize_url"]
      self.token_url ||= integration.auth_config["token_url"]
      self.test_endpoint ||= integration.auth_config["test_endpoint"]
    end
  end
end
