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
  # These are captured FROM the OAuth callback URL
  def callback_param_names
    callback_params || []
  end

  # Get list of required parameters that must be collected BEFORE OAuth starts
  # e.g., ["shop_domain"] for Shopify - user enters their shop domain first
  # Returns array of hashes with :name, :label, :placeholder, :description
  def required_param_definitions
    (required_params || []).map do |param|
      if param.is_a?(Hash)
        param.symbolize_keys
      else
        # Legacy support for simple string arrays
        { name: param.to_s, label: param.to_s.humanize, placeholder: "", description: "" }
      end
    end
  end

  # Check if there are required parameters that need to be collected
  def has_required_params?
    required_params.present? && required_params.any?
  end

  # Substitute placeholders in OAuth URLs with provided params
  # e.g., "https://{shop_domain}/admin/oauth/authorize" with {shop_domain: "mystore.myshopify.com"}
  def authorize_url_with_params(params = {})
    substitute_url_params(authorize_url, params)
  end

  def token_url_with_params(params = {})
    substitute_url_params(token_url, params)
  end

  # Return credentials in the format expected by OAuth controller
  # NOTE: This must be public - called by oauth_controller.rb
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

  def substitute_url_params(url, params)
    return url unless url.present? && params.present?
    
    result = url.dup
    params.each do |key, value|
      result = result.gsub("{#{key}}", value.to_s)
    end
    result
  end

  def set_defaults
    self.status ||= :active
    self.credentials ||= {}
    self.metadata ||= {}
    self.callback_params ||= []
    self.required_params ||= []
    
    # Pre-fill URLs from integration if not set and integration is available
    if integration.present? && integration.auth_config.present?
      self.authorize_url ||= integration.auth_config["authorize_url"]
      self.token_url ||= integration.auth_config["token_url"]
      self.test_endpoint ||= integration.auth_config["test_endpoint"]
    end
  end
end
