# frozen_string_literal: true

# Sends a push notification to a user via AWS SNS
class SendPushNotificationJob < ApplicationJob
  queue_as :default

  # @param user_id [Integer] The user to notify
  # @param title [String] Notification title
  # @param body [String] Notification body
  # @param data [Hash] Additional data payload
  # @param badge [Integer, nil] Badge count to display
  def perform(user_id, title:, body:, data: {}, badge: nil)
    return unless SnsPushNotificationService.configured?

    user = User.find_by(id: user_id)
    return unless user

    service = SnsPushNotificationService.new
    results = service.send_to_user(
      user,
      title: title,
      body: body,
      data: data,
      badge: badge
    )

    Rails.logger.info "[Push] Sent to user #{user_id}: #{results[:sent]} delivered, #{results[:failed]} failed"
  end
end
