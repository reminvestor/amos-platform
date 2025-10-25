class Integration < ApplicationRecord
  # Associations
  has_many :connections, dependent: :destroy
  has_many :integration_operations, dependent: :destroy
  has_many :entities, through: :connections
  has_many :oauth_configurations, dependent: :destroy

  # Validations
  validates :name, :slug, presence: true, uniqueness: true
  validates :auth_type, :api_base_url, presence: true
  validates :category, inclusion: { in: %w[payment ecommerce crm communication productivity marketing analytics custom] }

  # Enums
  enum :auth_type, {
    api_key: 0,
    bearer_token: 1,
    basic_auth: 2,
    oauth2: 3,
    custom: 4  # Reserved for user-managed OAuth apps (future)
  }

  # Scopes
  scope :active, -> { where(is_active: true) }
  scope :verified, -> { where(is_verified: true) }
  scope :by_category, ->(category) { where(category: category) }

  # Default values
  after_initialize :set_defaults, if: :new_record?

  def oauth?
    oauth2?
  end

  def requires_admin_config?
    # All auth types can be configured by admin
    true
  end

  # Get current auth configuration from database
  def current_auth_params
    oauth_config = OauthConfiguration.find_by(integration: self)
    
    return [] unless oauth_config
    
    oauth_config.auth_configs.order(:position).map do |ac|
      {
        key: ac.auth_key,
        value: ac.auth_value,
        placement: ac.auth_placement
      }
    end
  end

  def connected_for?(user)
    connections.joins(:integration_credentials)
               .where(entity_id: user.entity_ids)
               .where(integration_credentials: { status: :active })
               .exists?
  end

  def host_allowed?(host)
    return true if allowed_hosts.blank?

    allowed_hosts.any? do |pattern|
      if pattern.include?("*")
        # Convert wildcard to regex
        regex_pattern = pattern.gsub(".", '\.').gsub("*", ".*")
        host.match?(/\A#{regex_pattern}\z/)
      else
        host == pattern
      end
    end
  end

  private

  def set_defaults
    self.is_active = true if is_active.nil?
    self.is_verified = false if is_verified.nil?
    self.allowed_hosts ||= []
    self.auth_config ||= {}
    self.metadata ||= {}
  end
end
