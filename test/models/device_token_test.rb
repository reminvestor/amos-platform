# frozen_string_literal: true

require "test_helper"

class DeviceTokenTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @entity = entities(:one)
  end

  test "validates presence of token" do
    device = DeviceToken.new(user: @user, entity: @entity, platform: 'ios')
    assert_not device.valid?
    assert_includes device.errors[:token], "can't be blank"
  end

  test "validates presence of platform" do
    device = DeviceToken.new(user: @user, entity: @entity, token: 'test-token')
    assert_not device.valid?
    assert_includes device.errors[:platform], "can't be blank"
  end

  test "validates platform inclusion" do
    device = DeviceToken.new(user: @user, entity: @entity, token: 'test-token', platform: 'windows')
    assert_not device.valid?
    assert_includes device.errors[:platform], "is not included in the list"
  end

  test "validates token uniqueness" do
    DeviceToken.create!(user: @user, entity: @entity, token: 'unique-token', platform: 'ios')
    device = DeviceToken.new(user: @user, entity: @entity, token: 'unique-token', platform: 'ios')
    assert_not device.valid?
    assert_includes device.errors[:token], "has already been taken"
  end

  test "creates device token successfully" do
    device = DeviceToken.new(
      user: @user,
      entity: @entity,
      token: 'new-device-token-123',
      platform: 'ios',
      device_name: 'iPhone 15 Pro',
      device_model: 'iPhone15,3',
      os_version: '17.2'
    )
    
    # Skip SNS registration in tests
    device.stubs(:register_with_sns).returns(true)
    
    assert device.save
    assert device.active?
  end

  test "register class method creates new device" do
    DeviceToken.any_instance.stubs(:register_with_sns).returns(true)
    
    device = DeviceToken.register(
      user: @user,
      entity: @entity,
      token: 'brand-new-token',
      platform: 'ios',
      device_info: { device_name: 'Test Device' }
    )
    
    assert device.persisted?
    assert_equal 'brand-new-token', device.token
    assert_equal 'Test Device', device.device_name
  end

  test "register class method updates existing device" do
    DeviceToken.any_instance.stubs(:register_with_sns).returns(true)
    
    existing = DeviceToken.create!(
      user: @user,
      entity: @entity,
      token: 'existing-token',
      platform: 'ios',
      device_name: 'Old Name'
    )
    
    device = DeviceToken.register(
      user: @user,
      entity: @entity,
      token: 'existing-token',
      platform: 'ios',
      device_info: { device_name: 'New Name' }
    )
    
    assert_equal existing.id, device.id
    assert_equal 'New Name', device.reload.device_name
  end

  test "deactivate! sets active to false and reason" do
    DeviceToken.any_instance.stubs(:register_with_sns).returns(true)
    DeviceToken.any_instance.stubs(:unregister_from_sns).returns({ success: true })
    
    device = DeviceToken.create!(
      user: @user,
      entity: @entity,
      token: 'to-deactivate',
      platform: 'ios'
    )
    
    device.deactivate!('user_logout')
    
    assert_not device.active?
    assert_equal 'user_logout', device.deactivation_reason
    assert device.deactivated_at.present?
  end

  test "active scope returns only active devices" do
    DeviceToken.any_instance.stubs(:register_with_sns).returns(true)
    
    active_device = DeviceToken.create!(user: @user, entity: @entity, token: 'active-1', platform: 'ios', active: true)
    inactive_device = DeviceToken.create!(user: @user, entity: @entity, token: 'inactive-1', platform: 'ios', active: false)
    
    assert_includes DeviceToken.active, active_device
    assert_not_includes DeviceToken.active, inactive_device
  end

  test "for_user scope returns devices for specific user" do
    DeviceToken.any_instance.stubs(:register_with_sns).returns(true)
    
    user2 = users(:two)
    
    device1 = DeviceToken.create!(user: @user, entity: @entity, token: 'user1-device', platform: 'ios')
    device2 = DeviceToken.create!(user: user2, entity: @entity, token: 'user2-device', platform: 'ios')
    
    assert_includes DeviceToken.for_user(@user.id), device1
    assert_not_includes DeviceToken.for_user(@user.id), device2
  end
end
