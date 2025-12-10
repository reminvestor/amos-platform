# frozen_string_literal: true

require "test_helper"

class Users::TwoFactorControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  TEST_PASSWORD = "TestPassword123!"

  def setup
    @user = users(:one)
    # Set a known password for the test user
    @user.password = TEST_PASSWORD
    @user.password_confirmation = TEST_PASSWORD
    @user.update!(otp_required_for_login: false, otp_secret: nil, otp_backup_codes: nil)
    # Set host to app subdomain for routes inside subdomain constraint
    host! "app.example.com"
    sign_in @user
    # Use memory store for caching in tests
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  def teardown
    Rails.cache = @original_cache
  end

  # Show Tests
  test "show returns success" do
    get users_two_factor_path
    assert_response :success
  end

  # Enable Tests
  test "enable generates TOTP secret and shows QR code" do
    get enable_users_two_factor_path
    assert_response :success
    assert_not_nil @user.reload.otp_secret
  end

  test "enable redirects if MFA already enabled" do
    enable_mfa_for_user(@user)
    get enable_users_two_factor_path
    assert_redirected_to users_two_factor_path
    assert_equal "Two-factor authentication is already enabled.", flash[:alert]
  end

  # Confirm Tests
  test "confirm enables MFA with valid TOTP code" do
    @user.setup_totp!
    totp = ROTP::TOTP.new(@user.otp_secret)

    post confirm_users_two_factor_path, params: { code: totp.now }
    assert_response :success # Renders backup_codes view
    assert @user.reload.otp_required_for_login
  end

  test "confirm fails with invalid TOTP code" do
    @user.setup_totp!

    post confirm_users_two_factor_path, params: { code: "000000" }
    assert_response :unprocessable_entity
    assert_not @user.reload.otp_required_for_login
  end

  test "confirm generates backup codes" do
    @user.setup_totp!
    totp = ROTP::TOTP.new(@user.otp_secret)

    post confirm_users_two_factor_path, params: { code: totp.now }
    assert_not_nil @user.reload.otp_backup_codes
  end

  # Disable Tests
  test "disable removes MFA with valid password" do
    enable_mfa_for_user(@user)

    delete disable_users_two_factor_path, params: { password: TEST_PASSWORD }
    assert_redirected_to users_two_factor_path
    # Reload to get fresh state
    @user.reload
    assert_not @user.mfa_enabled?
  end

  test "disable requires password" do
    enable_mfa_for_user(@user)

    delete disable_users_two_factor_path, params: { password: "wrong_password" }
    assert_redirected_to users_two_factor_path
    assert @user.reload.mfa_enabled?
  end

  # Backup Codes Tests
  test "backup_codes redirects if MFA not enabled" do
    get backup_codes_users_two_factor_path
    assert_redirected_to users_two_factor_path
  end

  test "backup_codes returns success when MFA is enabled" do
    enable_mfa_for_user(@user)
    @user.generate_backup_codes!

    get backup_codes_users_two_factor_path
    assert_response :success
  end

  # Regenerate Backup Codes Tests
  test "regenerate_backup_codes creates new codes with valid password" do
    enable_mfa_for_user(@user)
    old_codes = @user.generate_backup_codes!

    post regenerate_backup_codes_users_two_factor_path, params: { password: TEST_PASSWORD }
    assert_response :success

    # Verify codes were regenerated
    assert_not_equal old_codes, @user.reload.otp_backup_codes
  end

  test "regenerate_backup_codes requires password" do
    enable_mfa_for_user(@user)
    @user.generate_backup_codes!

    post regenerate_backup_codes_users_two_factor_path, params: { password: "wrong" }
    assert_redirected_to users_two_factor_path
  end

  # Update Email Settings Tests
  test "update_email_settings toggles email OTP" do
    enable_mfa_for_user(@user)
    @user.update!(otp_email_enabled: true)

    patch email_settings_users_two_factor_path, params: { otp_email_enabled: "0" }
    assert_redirected_to users_two_factor_path
    assert_not @user.reload.otp_email_enabled
  end

  # Authentication Tests
  test "requires authentication for all actions" do
    sign_out @user

    get users_two_factor_path
    assert_redirected_to new_user_session_path
  end

  private

  def enable_mfa_for_user(user)
    user.setup_totp!
    totp = ROTP::TOTP.new(user.otp_secret)
    user.confirm_totp!(totp.now)
  end
end
