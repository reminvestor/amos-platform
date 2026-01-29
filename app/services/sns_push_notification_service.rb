# frozen_string_literal: true

# SnsPushNotificationService handles sending push notifications via AWS SNS.
#
# This service:
# - Registers device tokens with SNS platform applications
# - Sends push notifications to individual devices or broadcast to all user devices
# - Handles APNs (iOS) and FCM (Android) payloads
# - Manages endpoint lifecycle (create, update, delete)
#
# Configuration (environment variables):
#   AWS_SNS_IOS_PLATFORM_ARN - ARN for iOS APNs platform application
#   AWS_SNS_ANDROID_PLATFORM_ARN - ARN for Android FCM platform application (future)
#   AWS_REGION, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY - AWS credentials
#
class SnsPushNotificationService
  class << self
    # ============================================
    # DEVICE REGISTRATION
    # ============================================

    # Register a device token with AWS SNS
    # @param device_token [DeviceToken] The device token model
    # @return [Hash] { success: true, platform_arn: "..." } or { success: false, error: "..." }
    def register_device(device_token)
      return { success: false, error: "SNS not configured" } unless configured?

      platform_arn = platform_application_arn(device_token.platform)
      return { success: false, error: "Platform #{device_token.platform} not configured" } unless platform_arn

      begin
        response = sns_client.create_platform_endpoint(
          platform_application_arn: platform_arn,
          token: device_token.token,
          custom_user_data: {
            user_id: device_token.user_id,
            entity_id: device_token.entity_id,
            device_id: device_token.device_id
          }.to_json
        )

        Rails.logger.info "[SNS] Registered device #{device_token.id} -> #{response.endpoint_arn}"
        { success: true, platform_arn: response.endpoint_arn }

      rescue Aws::SNS::Errors::InvalidParameter => e
        # Token may already be registered - try to get existing endpoint
        handle_existing_endpoint(device_token, platform_arn)
      rescue Aws::SNS::Errors::ServiceError => e
        Rails.logger.error "[SNS] Registration failed: #{e.message}"
        { success: false, error: e.message }
      end
    end

    # Unregister a device token from AWS SNS
    # @param device_token [DeviceToken] The device token model
    # @return [Hash] { success: true } or { success: false, error: "..." }
    def unregister_device(device_token)
      return { success: true } unless device_token.platform_arn.present?
      return { success: false, error: "SNS not configured" } unless configured?

      begin
        sns_client.delete_endpoint(endpoint_arn: device_token.platform_arn)
        Rails.logger.info "[SNS] Unregistered device #{device_token.id}"
        { success: true }

      rescue Aws::SNS::Errors::ServiceError => e
        Rails.logger.error "[SNS] Unregistration failed: #{e.message}"
        { success: false, error: e.message }
      end
    end

    # ============================================
    # SENDING NOTIFICATIONS
    # ============================================

    # Send a push notification to a specific device
    # @param device_token [DeviceToken] The target device
    # @param title [String] Notification title
    # @param body [String] Notification body
    # @param data [Hash] Additional data payload
    # @param options [Hash] Additional options (badge, sound, etc.)
    # @return [Hash] { success: true, message_id: "..." } or { success: false, error: "..." }
    def send_to_device(device_token:, title:, body:, data: {}, options: {})
      return { success: false, error: "Device not registered with SNS" } unless device_token.platform_arn.present?
      return { success: false, error: "SNS not configured" } unless configured?

      payload = build_payload(
        platform: device_token.platform,
        title: title,
        body: body,
        data: data,
        options: options
      )

      begin
        response = sns_client.publish(
          target_arn: device_token.platform_arn,
          message: payload.to_json,
          message_structure: 'json'
        )

        device_token.touch_last_used!
        Rails.logger.info "[SNS] Sent notification to device #{device_token.id}: #{response.message_id}"
        { success: true, message_id: response.message_id }

      rescue Aws::SNS::Errors::EndpointDisabled => e
        # Endpoint was disabled - deactivate the device token
        device_token.deactivate!('token_invalid')
        { success: false, error: "Device token disabled", disabled: true }

      rescue Aws::SNS::Errors::ServiceError => e
        Rails.logger.error "[SNS] Send failed: #{e.message}"
        { success: false, error: e.message }
      end
    end

    # Send a push notification to all active devices for a user
    # @param user [User] The target user
    # @param title [String] Notification title
    # @param body [String] Notification body
    # @param data [Hash] Additional data payload
    # @param options [Hash] Additional options
    # @return [Hash] { success: true, sent: 2, failed: 0 } or { success: false, error: "..." }
    def send_to_user(user:, title:, body:, data: {}, options: {})
      return { success: false, error: "SNS not configured" } unless configured?

      devices = DeviceToken.active.for_user(user.id).where.not(platform_arn: nil)
      return { success: true, sent: 0, failed: 0, message: "No registered devices" } if devices.empty?

      results = { sent: 0, failed: 0, errors: [] }

      devices.find_each do |device|
        result = send_to_device(
          device_token: device,
          title: title,
          body: body,
          data: data,
          options: options
        )

        if result[:success]
          results[:sent] += 1
        else
          results[:failed] += 1
          results[:errors] << { device_id: device.id, error: result[:error] }
        end
      end

      Rails.logger.info "[SNS] Broadcast to user #{user.id}: #{results[:sent]} sent, #{results[:failed]} failed"
      { success: true, **results }
    end

    # Send notification to multiple users (e.g., entity-wide announcement)
    # @param user_ids [Array<Integer>] List of user IDs
    # @param title [String] Notification title
    # @param body [String] Notification body
    # @param data [Hash] Additional data payload
    # @return [Hash] { success: true, users_notified: 5, devices_sent: 8 }
    def send_to_users(user_ids:, title:, body:, data: {}, options: {})
      return { success: false, error: "SNS not configured" } unless configured?

      results = { users_notified: 0, devices_sent: 0, devices_failed: 0 }

      user_ids.each do |user_id|
        user = User.find_by(id: user_id)
        next unless user

        result = send_to_user(
          user: user,
          title: title,
          body: body,
          data: data,
          options: options
        )

        if result[:success] && result[:sent] > 0
          results[:users_notified] += 1
          results[:devices_sent] += result[:sent]
          results[:devices_failed] += result[:failed]
        end
      end

      { success: true, **results }
    end

    # ============================================
    # NOTIFICATION TYPES
    # ============================================

    # Send a chat message notification
    def notify_chat_message(user:, sender_name:, message_preview:, conversation_id:)
      send_to_user(
        user: user,
        title: sender_name,
        body: message_preview.truncate(100),
        data: {
          type: 'chat_message',
          conversation_id: conversation_id
        },
        options: {
          category: 'chat',
          sound: 'default'
        }
      )
    end

    # Send a task/reminder notification
    def notify_reminder(user:, title:, body:, reminder_id:)
      send_to_user(
        user: user,
        title: title,
        body: body,
        data: {
          type: 'reminder',
          reminder_id: reminder_id
        },
        options: {
          category: 'reminder',
          sound: 'default'
        }
      )
    end

    # Send a workflow completion notification
    def notify_workflow_complete(user:, workflow_name:, status:, workflow_id:)
      title = status == 'success' ? "✅ #{workflow_name} completed" : "❌ #{workflow_name} failed"
      body = status == 'success' ? "Your workflow has finished successfully." : "Your workflow encountered an error."

      send_to_user(
        user: user,
        title: title,
        body: body,
        data: {
          type: 'workflow_complete',
          workflow_id: workflow_id,
          status: status
        },
        options: {
          category: 'workflow',
          sound: 'default'
        }
      )
    end

    # Send a lead/contact notification
    def notify_new_lead(user:, lead_name:, source:, lead_id:)
      send_to_user(
        user: user,
        title: "🎯 New Lead: #{lead_name}",
        body: "New lead from #{source}",
        data: {
          type: 'new_lead',
          lead_id: lead_id,
          source: source
        },
        options: {
          category: 'crm',
          sound: 'default'
        }
      )
    end

    # Send a general notification
    def notify_general(user:, title:, body:, action_url: nil, category: 'general')
      send_to_user(
        user: user,
        title: title,
        body: body,
        data: {
          type: 'general',
          action_url: action_url
        }.compact,
        options: {
          category: category,
          sound: 'default'
        }
      )
    end

    # ============================================
    # CONFIGURATION
    # ============================================

    def configured?
      ios_configured? || android_configured?
    end

    def ios_configured?
      ENV['AWS_SNS_IOS_PLATFORM_ARN'].present?
    end

    def android_configured?
      ENV['AWS_SNS_ANDROID_PLATFORM_ARN'].present?
    end

    private

    def sns_client
      @sns_client ||= Aws::SNS::Client.new(
        region: ENV.fetch('AWS_REGION', 'us-east-1'),
        credentials: aws_credentials
      )
    end

    def aws_credentials
      if ENV['AWS_ACCESS_KEY_ID'].present? && ENV['AWS_SECRET_ACCESS_KEY'].present?
        Aws::Credentials.new(
          ENV['AWS_ACCESS_KEY_ID'],
          ENV['AWS_SECRET_ACCESS_KEY']
        )
      else
        # Use IAM role credentials (for ECS/EC2)
        Aws::InstanceProfileCredentials.new
      end
    end

    def platform_application_arn(platform)
      case platform.to_s.downcase
      when 'ios'
        ENV['AWS_SNS_IOS_PLATFORM_ARN']
      when 'android'
        ENV['AWS_SNS_ANDROID_PLATFORM_ARN']
      end
    end

    def build_payload(platform:, title:, body:, data: {}, options: {})
      case platform.to_s.downcase
      when 'ios'
        build_apns_payload(title: title, body: body, data: data, options: options)
      when 'android'
        build_fcm_payload(title: title, body: body, data: data, options: options)
      else
        { default: body }
      end
    end

    def build_apns_payload(title:, body:, data: {}, options: {})
      apns_payload = {
        aps: {
          alert: {
            title: title,
            body: body
          },
          sound: options[:sound] || 'default',
          badge: options[:badge],
          category: options[:category],
          'mutable-content': options[:mutable_content] ? 1 : 0,
          'content-available': options[:content_available] ? 1 : 0
        }.compact
      }.merge(data)

      # SNS expects the payload wrapped in the platform key
      {
        'APNS' => apns_payload.to_json,
        'APNS_SANDBOX' => apns_payload.to_json,  # For development
        'default' => body
      }
    end

    def build_fcm_payload(title:, body:, data: {}, options: {})
      fcm_payload = {
        notification: {
          title: title,
          body: body,
          sound: options[:sound] || 'default',
          icon: options[:icon] || 'ic_notification',
          click_action: options[:click_action]
        }.compact,
        data: data.transform_values(&:to_s),
        priority: options[:priority] || 'high'
      }

      {
        'GCM' => fcm_payload.to_json,
        'default' => body
      }
    end

    def handle_existing_endpoint(device_token, platform_arn)
      # Try to find existing endpoint and update it
      # This is a simplified approach - in production you might want more robust handling
      Rails.logger.warn "[SNS] Token may already exist, attempting to find existing endpoint"

      # For now, just fail gracefully - the token might already be registered
      { success: false, error: "Token may already be registered with another endpoint" }
    end
  end
end
