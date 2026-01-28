# frozen_string_literal: true

# Registers a device token with AWS SNS to get an endpoint ARN
class RegisterDeviceTokenJob < ApplicationJob
  queue_as :default

  def perform(device_token_id)
    device_token = DeviceToken.find_by(id: device_token_id)
    return unless device_token&.active?

    service = SnsPushNotificationService.new
    service.register_device(device_token)
  end
end
