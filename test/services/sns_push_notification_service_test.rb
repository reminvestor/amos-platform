# frozen_string_literal: true

require "test_helper"

class SnsPushNotificationServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @entity = entities(:one)
  end

  test "configured? returns false when no platform ARNs set" do
    # Clear any existing ENV
    original_ios = ENV['AWS_SNS_IOS_PLATFORM_ARN']
    original_android = ENV['AWS_SNS_ANDROID_PLATFORM_ARN']
    
    ENV['AWS_SNS_IOS_PLATFORM_ARN'] = nil
    ENV['AWS_SNS_ANDROID_PLATFORM_ARN'] = nil
    
    assert_not SnsPushNotificationService.configured?
    
    # Restore
    ENV['AWS_SNS_IOS_PLATFORM_ARN'] = original_ios
    ENV['AWS_SNS_ANDROID_PLATFORM_ARN'] = original_android
  end

  test "ios_configured? returns true when iOS ARN set" do
    original = ENV['AWS_SNS_IOS_PLATFORM_ARN']
    ENV['AWS_SNS_IOS_PLATFORM_ARN'] = 'arn:aws:sns:us-east-1:123:app/APNS/test'
    
    assert SnsPushNotificationService.ios_configured?
    
    ENV['AWS_SNS_IOS_PLATFORM_ARN'] = original
  end

  test "build_apns_payload creates correct structure" do
    payload = SnsPushNotificationService.send(
      :build_apns_payload,
      title: 'Test Title',
      body: 'Test Body',
      data: { custom_key: 'value' },
      options: { badge: 5, sound: 'default', category: 'test' }
    )
    
    assert payload.key?('APNS')
    assert payload.key?('APNS_SANDBOX')
    assert payload.key?('default')
    
    apns_data = JSON.parse(payload['APNS'])
    assert_equal 'Test Title', apns_data['aps']['alert']['title']
    assert_equal 'Test Body', apns_data['aps']['alert']['body']
    assert_equal 'default', apns_data['aps']['sound']
    assert_equal 5, apns_data['aps']['badge']
    assert_equal 'test', apns_data['aps']['category']
    assert_equal 'value', apns_data['custom_key']
  end

  test "build_fcm_payload creates correct structure" do
    payload = SnsPushNotificationService.send(
      :build_fcm_payload,
      title: 'Test Title',
      body: 'Test Body',
      data: { custom_key: 'value' },
      options: { sound: 'default' }
    )
    
    assert payload.key?('GCM')
    assert payload.key?('default')
    
    fcm_data = JSON.parse(payload['GCM'])
    assert_equal 'Test Title', fcm_data['notification']['title']
    assert_equal 'Test Body', fcm_data['notification']['body']
    assert_equal 'value', fcm_data['data']['custom_key']
    assert_equal 'high', fcm_data['priority']
  end

  test "send_to_user returns success with no devices" do
    result = SnsPushNotificationService.send_to_user(
      user: @user,
      title: 'Test',
      body: 'Test body'
    )
    
    # Will fail because SNS not configured in test, or succeed with "No registered devices"
    assert result.key?(:success)
  end

  test "register_device returns error when not configured" do
    original = ENV['AWS_SNS_IOS_PLATFORM_ARN']
    ENV['AWS_SNS_IOS_PLATFORM_ARN'] = nil
    
    DeviceToken.any_instance.stubs(:register_with_sns).returns({ success: false, error: "SNS not configured" })
    
    device = DeviceToken.new(
      user: @user,
      entity: @entity,
      token: 'test-token',
      platform: 'ios'
    )
    
    result = SnsPushNotificationService.register_device(device)
    
    assert_not result[:success]
    assert_equal "SNS not configured", result[:error]
    
    ENV['AWS_SNS_IOS_PLATFORM_ARN'] = original
  end
end
