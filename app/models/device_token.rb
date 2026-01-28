class DeviceToken < ApplicationRecord
  belongs_to :user

  PLATFORMS = %w[ios android].freeze

  validates :token, presence: true, uniqueness: true
  validates :platform, presence: true, inclusion: { in: PLATFORMS }

  scope :active, -> { where(active: true) }
  scope :ios, -> { where(platform: "ios") }
  scope :android, -> { where(platform: "android") }
  scope :with_endpoint, -> { where.not(endpoint_arn: nil) }

  # Deactivate this token (e.g., when SNS reports it as invalid)
  def deactivate!
    update!(active: false)
  end

  # Check if this token can receive push notifications
  def pushable?
    active? && endpoint_arn.present?
  end
end
