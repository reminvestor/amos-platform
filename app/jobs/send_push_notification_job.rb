# frozen_string_literal: true

# SendPushNotificationJob sends push notifications asynchronously via AWS SNS.
#
# This job handles sending notifications to individual users or devices,
# with retry logic and error handling.
#
# Usage:
#   SendPushNotificationJob.perform_later(
#     user_id: 123,
#     title: "New Message",
#     body: "You have a new message from John",
#     data: { type: 'chat', conversation_id: 456 },
#     options: { category: 'chat', sound: 'default' }
#   )
#
class SendPushNotificationJob < ApplicationJob
  queue_as :notifications

  # Retry on network errors, but not on endpoint disabled
  retry_on Aws::SNS::Errors::ServiceError, wait: :polynomially_longer, attempts: 3
  discard_on Aws::SNS::Errors::EndpointDisabled

  def perform(user_id:, title:, body:, data: {}, options: {})
    user = User.find_by(id: user_id)
    return unless user

    result = SnsPushNotificationService.send_to_user(
      user: user,
      title: title,
      body: body,
      data: data,
      options: options
    )

    if result[:success]
      Rails.logger.info "[PushNotification] Sent to user #{user_id}: #{result[:sent]} devices"
    else
      Rails.logger.warn "[PushNotification] Failed for user #{user_id}: #{result[:error]}"
    end

    result
  end
end
