class TrustedDevice < ApplicationRecord
  belongs_to :user

  validates :token, presence: true, uniqueness: true
  validates :user_id, presence: true

  # Token expires after 90 days by default
  DEFAULT_EXPIRY_DAYS = 90

  scope :active, -> { where("expires_at > ?", Time.current) }
  scope :for_device, ->(identifier) { where(device_identifier: identifier) }

  before_create :set_expiry

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  def active?
    !expired?
  end

  def touch_last_used!
    update!(last_used_at: Time.current)
  end

  def self.generate_token
    SecureRandom.urlsafe_base64(32)
  end

  def self.create_for_user!(user, device_name: nil, device_identifier: nil, platform: nil)
    # Remove any existing trust for this device
    if device_identifier.present?
      user.trusted_devices.for_device(device_identifier).destroy_all
    end

    create!(
      user: user,
      token: generate_token,
      device_name: device_name,
      device_identifier: device_identifier,
      platform: platform,
      last_used_at: Time.current
    )
  end

  private

  def set_expiry
    self.expires_at ||= DEFAULT_EXPIRY_DAYS.days.from_now
  end
end
