# frozen_string_literal: true

# Service for sending push notifications via AWS SNS
# SNS handles the actual delivery to APNs (iOS) and FCM (Android)
class SnsPushNotificationService
  class NotConfiguredError < StandardError; end
  class EndpointDisabledError < StandardError; end

  def initialize
    @sns_client = nil
  end

  # Check if push notifications are configured
  def self.configured?
    ENV["AWS_SNS_IOS_PLATFORM_ARN"].present? || ENV["AWS_SNS_ANDROID_PLATFORM_ARN"].present?
  end

  # Register a device token with SNS and return the endpoint ARN
  def register_device(device_token)
    return nil unless self.class.configured?

    platform_arn = platform_arn_for(device_token.platform)
    return nil unless platform_arn

    begin
      response = sns_client.create_platform_endpoint(
        platform_application_arn: platform_arn,
        token: device_token.token,
        custom_user_data: device_token.user_id.to_s
      )

      endpoint_arn = response.endpoint_arn
      device_token.update!(endpoint_arn: endpoint_arn)

      Rails.logger.info "[SNS] Registered device #{device_token.id} with endpoint: #{endpoint_arn}"
      endpoint_arn
    rescue Aws::SNS::Errors::InvalidParameter => e
      # Token might already be registered - try to find existing endpoint
      if e.message.include?("already exists")
        handle_existing_endpoint(device_token, platform_arn)
      else
        Rails.logger.error "[SNS] Failed to register device #{device_token.id}: #{e.message}"
        nil
      end
    rescue Aws::SNS::Errors::ServiceError => e
      Rails.logger.error "[SNS] Failed to register device #{device_token.id}: #{e.message}"
      nil
    end
  end

  # Unregister a device from SNS
  def unregister_device(device_token)
    return unless device_token.endpoint_arn.present?

    begin
      sns_client.delete_endpoint(endpoint_arn: device_token.endpoint_arn)
      Rails.logger.info "[SNS] Unregistered device #{device_token.id}"
    rescue Aws::SNS::Errors::ServiceError => e
      Rails.logger.error "[SNS] Failed to unregister device #{device_token.id}: #{e.message}"
    end
  end

  # Send a push notification to a specific user
  def send_to_user(user, title:, body:, data: {}, badge: nil)
    return { sent: 0, failed: 0 } unless self.class.configured?

    results = { sent: 0, failed: 0 }

    user.device_tokens.active.with_endpoint.find_each do |device_token|
      if send_to_device(device_token, title: title, body: body, data: data, badge: badge)
        results[:sent] += 1
      else
        results[:failed] += 1
      end
    end

    results
  end

  # Send a push notification to a specific device
  def send_to_device(device_token, title:, body:, data: {}, badge: nil)
    return false unless device_token.pushable?

    message = build_message(
      device_token.platform,
      title: title,
      body: body,
      data: data,
      badge: badge
    )

    begin
      sns_client.publish(
        target_arn: device_token.endpoint_arn,
        message: message.to_json,
        message_structure: "json"
      )

      Rails.logger.info "[SNS] Sent push to device #{device_token.id}: #{title}"
      true
    rescue Aws::SNS::Errors::EndpointDisabled => e
      # Token is no longer valid - deactivate it
      Rails.logger.warn "[SNS] Endpoint disabled for device #{device_token.id}, deactivating"
      device_token.deactivate!
      false
    rescue Aws::SNS::Errors::ServiceError => e
      Rails.logger.error "[SNS] Failed to send push to device #{device_token.id}: #{e.message}"
      false
    end
  end

  private

  def sns_client
    @sns_client ||= Aws::SNS::Client.new(
      region: ENV.fetch("AWS_REGION", "us-east-1"),
      access_key_id: ENV["AWS_ACCESS_KEY_ID"],
      secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"]
    )
  end

  def platform_arn_for(platform)
    case platform
    when "ios"
      ENV["AWS_SNS_IOS_PLATFORM_ARN"]
    when "android"
      ENV["AWS_SNS_ANDROID_PLATFORM_ARN"]
    end
  end

  def handle_existing_endpoint(device_token, platform_arn)
    # List endpoints to find the existing one
    # This is a fallback - normally we'd get the ARN from the error
    Rails.logger.warn "[SNS] Token already registered, attempting to find endpoint"

    # For now, just log - in production you might want to
    # parse the endpoint ARN from the error message
    nil
  end

  def build_message(platform, title:, body:, data: {}, badge: nil)
    case platform
    when "ios"
      build_apns_message(title: title, body: body, data: data, badge: badge)
    when "android"
      build_fcm_message(title: title, body: body, data: data)
    else
      { default: body }
    end
  end

  def build_apns_message(title:, body:, data: {}, badge: nil)
    apns_payload = {
      aps: {
        alert: {
          title: title,
          body: body
        },
        sound: "default"
      }
    }

    apns_payload[:aps][:badge] = badge if badge
    apns_payload.merge!(data) if data.present?

    {
      default: body,
      APNS: apns_payload.to_json,
      APNS_SANDBOX: apns_payload.to_json  # For development
    }
  end

  def build_fcm_message(title:, body:, data: {})
    fcm_payload = {
      notification: {
        title: title,
        body: body
      },
      data: data
    }

    {
      default: body,
      GCM: fcm_payload.to_json
    }
  end
end
