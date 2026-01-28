# frozen_string_literal: true

# Removes a device token from AWS SNS
class UnregisterDeviceTokenJob < ApplicationJob
  queue_as :default

  def perform(device_token_id)
    device_token = DeviceToken.find_by(id: device_token_id)
    return unless device_token

    service = SnsPushNotificationService.new
    service.unregister_device(device_token)
  end
end
