# frozen_string_literal: true

# DeviceToken represents a registered mobile device for push notifications.
#
# When a user logs into the mobile app, the app registers its APNs/FCM token
# with this model. The token is then registered with AWS SNS to create a
# platform endpoint, which is used to send push notifications.
#
class DeviceToken < ApplicationRecord
  # Associations
  belongs_to :user
  belongs_to :entity

  # Platforms
  PLATFORMS = %w[ios android].freeze

  # Validations
  validates :token, presence: true, uniqueness: true
  validates :platform, presence: true, inclusion: { in: PLATFORMS }
  validates :platform_arn, uniqueness: true, allow_nil: true

  # Scopes
  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :ios, -> { where(platform: 'ios') }
  scope :android, -> { where(platform: 'android') }
  scope :for_user, ->(user_id) { where(user_id: user_id) }

  # Callbacks
  after_create :register_with_sns
  after_destroy :unregister_from_sns
  before_update :handle_token_change, if: :token_changed?

  # ============================================
  # STATUS MANAGEMENT
  # ============================================

  def activate!
    update!(active: true, deactivated_at: nil, deactivation_reason: nil)
    register_with_sns unless platform_arn.present?
  end

  def deactivate!(reason = 'manual')
    update!(
      active: false,
      deactivated_at: Time.current,
      deactivation_reason: reason
    )
    unregister_from_sns
  end

  def touch_last_used!
    update_column(:last_used_at, Time.current)
  end

  # ============================================
  # SNS REGISTRATION
  # ============================================

  def register_with_sns
    return unless active?
    return if platform_arn.present?

    result = SnsPushNotificationService.register_device(self)
    if result[:success]
      update_column(:platform_arn, result[:platform_arn])
    else
      Rails.logger.error "[DeviceToken] Failed to register with SNS: #{result[:error]}"
    end
  end

  def unregister_from_sns
    return unless platform_arn.present?

    result = SnsPushNotificationService.unregister_device(self)
    if result[:success]
      update_column(:platform_arn, nil)
    else
      Rails.logger.error "[DeviceToken] Failed to unregister from SNS: #{result[:error]}"
    end
  end

  # ============================================
  # NOTIFICATION PREFERENCES
  # ============================================

  def notifications_enabled_for?(category)
    # Check device-specific preferences first, then fall back to user preferences
    device_pref = notification_preferences&.dig(category.to_s)
    return device_pref unless device_pref.nil?

    # Fall back to user's global notification preferences
    user.notification_preferences&.dig(category.to_s) != false
  end

  def update_notification_preference(category, enabled)
    prefs = notification_preferences || {}
    prefs[category.to_s] = enabled
    update!(notification_preferences: prefs)
  end

  # ============================================
  # CLASS METHODS
  # ============================================

  # Register or update a device token
  def self.register(user:, entity:, token:, platform:, device_info: {})
    existing = find_by(token: token)

    if existing
      # Token exists - update ownership if needed
      if existing.user_id != user.id
        # Token transferred to new user
        existing.update!(
          user: user,
          entity: entity,
          active: true,
          deactivated_at: nil,
          deactivation_reason: nil,
          **device_info.slice(:device_id, :device_name, :device_model, :os_version, :app_version)
        )
      else
        # Same user - just update metadata
        existing.update!(
          active: true,
          deactivated_at: nil,
          deactivation_reason: nil,
          **device_info.slice(:device_id, :device_name, :device_model, :os_version, :app_version)
        )
      end
      existing.touch_last_used!
      existing
    else
      # New token
      create!(
        user: user,
        entity: entity,
        token: token,
        platform: platform,
        active: true,
        **device_info.slice(:device_id, :device_name, :device_model, :os_version, :app_version)
      )
    end
  end

  # Deactivate all tokens for a user (e.g., on logout from all devices)
  def self.deactivate_all_for_user(user)
    active.for_user(user.id).find_each do |token|
      token.deactivate!('user_logout_all')
    end
  end

  private

  def handle_token_change
    # If token changed, we need to re-register with SNS
    unregister_from_sns if platform_arn.present?
    self.platform_arn = nil
    # After save, the after_create-like logic will register the new token
    # But since this is an update, we need to manually trigger it
    register_with_sns_after_save
  end

  def register_with_sns_after_save
    # Schedule registration after commit
    after_commit -> { register_with_sns }, on: :update
  end
end
