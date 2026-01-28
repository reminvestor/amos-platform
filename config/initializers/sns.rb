# frozen_string_literal: true

# AWS SNS Configuration for Push Notifications
#
# Required environment variables:
#   AWS_SNS_IOS_PLATFORM_ARN - ARN for iOS APNs platform application
#   AWS_SNS_ANDROID_PLATFORM_ARN - ARN for Android FCM platform application (optional)
#
# The platform ARNs are created in AWS Console:
# SNS → Push notifications → Platform applications
#
# Example:
#   AWS_SNS_IOS_PLATFORM_ARN=arn:aws:sns:us-east-1:123456789:app/APNS/amos-ios-production
#
# For iOS, you need:
# 1. Apple Push Notification Service (APNs) authentication key (.p8 file)
# 2. Key ID from Apple Developer Portal
# 3. Team ID from Apple Developer Portal
#
# AWS credentials are inherited from existing configuration:
#   AWS_REGION, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY (or IAM role in ECS)
#

Rails.application.config.after_initialize do
  if defined?(SnsPushNotificationService)
    if SnsPushNotificationService.configured?
      platforms = []
      platforms << "iOS" if SnsPushNotificationService.ios_configured?
      platforms << "Android" if SnsPushNotificationService.android_configured?
      Rails.logger.info "[SNS] Push notifications configured for: #{platforms.join(', ')}"
    else
      Rails.logger.warn "[SNS] Push notifications not configured - set AWS_SNS_IOS_PLATFORM_ARN and/or AWS_SNS_ANDROID_PLATFORM_ARN"
    end
  end
end
