class SocialMediaAccount < ApplicationRecord
  belongs_to :user

  # Constants
  PLATFORMS = %w[facebook instagram linkedin twitter].freeze
  STATUSES = %w[connected disconnected expired].freeze

  # Validations
  validates :platform, presence: true, inclusion: { in: PLATFORMS }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :username, presence: true
  validates :access_token, presence: true

  # Scopes
  scope :connected, -> { where(status: "connected") }
  scope :by_platform, ->(platform) { where(platform: platform) }

  # Initialize settings
  before_validation :initialize_settings, on: :create

  # Check if token is expired
  def expired?
    token_expires_at.present? && token_expires_at < Time.current
  end

  # Update token expiration status
  def update_expiration_status
    update(status: "expired") if expired? && status != "expired"
  end

  # Refresh access token using refresh token if available
  def refresh_access_token
    return false unless refresh_token.present?

    # Each platform has its own refresh token implementation
    case platform
    when "facebook", "instagram"
      refresh_facebook_token
    when "linkedin"
      refresh_linkedin_token
    when "twitter"
      refresh_twitter_token
    else
      false
    end
  end

  # Store additional settings
  def update_settings(key, value)
    current_settings = settings || {}
    current_settings[key] = value
    update(settings: current_settings)
  end

  # Get platform-specific client
  def api_client
    SocialMedia::ServiceFactory.create_service(platform, user, self)
  end

  private

  def initialize_settings
    self.settings ||= {}
  end

  # Platform-specific token refresh methods
  def refresh_facebook_token
    # Facebook token refresh implementation
    # Return true if successful, false otherwise
    false
  end

  def refresh_linkedin_token
    # LinkedIn token refresh implementation
    # Return true if successful, false otherwise
    false
  end

  def refresh_twitter_token
    # Twitter token refresh implementation
    # Return true if successful, false otherwise
    false
  end
end
