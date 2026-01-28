# frozen_string_literal: true

require "test_helper"

class Users::SessionsControllerMfaTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  TEST_PASSWORD = "TestPassword123!"

  def setup
    @user = users(:one)
    # Set a known password for the test user
    @user.password = TEST_PASSWORD
    @user.password_confirmation = TEST_PASSWORD
    @user.update!(
      otp_required_for_login: false,
      otp_secret: nil,
      otp_backup_codes: nil,
      otp_failed_attempts: 0,
      otp_locked_at: nil
    )
    # Set host to app subdomain for routes inside subdomain constraint
    host! "app.example.com"
    # Use memory store for caching in tests
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  def teardown
    Rails.cache = @original_cache
  end

  # Login without MFA Tests
  test "login without MFA goes directly to dashboard" do
    post user_session_path, params: {
      user: { email: @user.email, password: TEST_PASSWORD }
    }
    # Should redirect to root (dashboard), not OTP verification
    follow_redirect!
    assert_response :success
  end

  # Login with MFA Tests
  test "login with MFA enabled redirects to OTP verification" do
    enable_mfa_for_user(@user)

    post user_session_path, params: {
      user: { email: @user.email, password: TEST_PASSWORD }
    }
    assert_redirected_to verify_otp_user_session_path
  end

  test "login with MFA stores user ID in session" do
    enable_mfa_for_user(@user)

    post user_session_path, params: {
      user: { email: @user.email, password: TEST_PASSWORD }
    }
    assert_equal @user.id, session[:mfa_user_id]
  end

  # Verify OTP Page Tests
  test "verify_otp page requires mfa session" do
    get verify_otp_user_session_path
    assert_redirected_to new_user_session_path
  end

  test "verify_otp page displays verification form" do
    enable_mfa_for_user(@user)
    start_mfa_session(@user)

    get verify_otp_user_session_path
    assert_response :success
  end

  # Submit OTP Tests
  test "submit_otp with valid TOTP code signs in user" do
    enable_mfa_for_user(@user)
    start_mfa_session(@user)
    totp = ROTP::TOTP.new(@user.otp_secret)

    post users_sessions_verify_otp_path, params: { code: totp.now, method: "totp" }
    # Should redirect to dashboard on success
    assert_response :redirect
    follow_redirect!
    assert_response :success
  end

  test "submit_otp with invalid TOTP code shows error" do
    enable_mfa_for_user(@user)
    start_mfa_session(@user)
    initial_attempts = @user.reload.otp_failed_attempts

    post users_sessions_verify_otp_path, params: { code: "000000", method: "totp" }
    assert_response :success # Re-renders verify_otp
    # Verify failed attempts incremented (error was handled)
    assert @user.reload.otp_failed_attempts > initial_attempts
  end

  test "submit_otp increments failed attempts" do
    enable_mfa_for_user(@user)
    @user.update!(otp_failed_attempts: 0)
    start_mfa_session(@user)

    post users_sessions_verify_otp_path, params: { code: "000000", method: "totp" }
    # start_mfa_session already triggers one failed attempt check, so we verify increment
    assert @user.reload.otp_failed_attempts >= 1
  end

  test "submit_otp locks account after max attempts" do
    enable_mfa_for_user(@user)
    @user.update!(otp_failed_attempts: User::OTP_MAX_FAILED_ATTEMPTS - 1)
    start_mfa_session(@user)

    post users_sessions_verify_otp_path, params: { code: "000000", method: "totp" }
    assert @user.reload.otp_locked?
  end

  test "submit_otp resets failed attempts on success" do
    enable_mfa_for_user(@user)
    @user.update!(otp_failed_attempts: 3)
    start_mfa_session(@user)
    totp = ROTP::TOTP.new(@user.otp_secret)

    post users_sessions_verify_otp_path, params: { code: totp.now, method: "totp" }
    assert_equal 0, @user.reload.otp_failed_attempts
  end

  # Email OTP Tests
  test "submit_otp with valid email code signs in user" do
    enable_mfa_for_user(@user)
    @user.update!(otp_email_enabled: true)
    start_mfa_session(@user)
    @user.send_email_otp!
    code = Rails.cache.read("email_otp:#{@user.id}")

    post users_sessions_verify_otp_path, params: { code: code, method: "email" }
    assert_response :redirect
    follow_redirect!
    assert_response :success
  end

  test "send_email_otp sends email code" do
    enable_mfa_for_user(@user)
    @user.update!(otp_email_enabled: true)
    start_mfa_session(@user)

    assert_enqueued_emails 1 do
      post users_sessions_send_email_otp_path
    end
    assert_response :success
    json = JSON.parse(response.body)
    assert json["success"]
  end

  test "send_email_otp rate limits requests" do
    enable_mfa_for_user(@user)
    @user.update!(otp_email_enabled: true)
    start_mfa_session(@user)

    # Fill up rate limit
    Rails.cache.write("mfa_email_sent:#{@user.id}", 3, expires_in: 5.minutes)

    post users_sessions_send_email_otp_path
    json = JSON.parse(response.body)
    assert_not json["success"]
  end

  test "send_email_otp requires mfa session" do
    post users_sessions_send_email_otp_path
    assert_response :unauthorized
    json = JSON.parse(response.body)
    assert_not json["success"]
  end

  # Backup Code Tests
  test "use_backup_code with valid code signs in user" do
    enable_mfa_for_user(@user)
    codes = @user.generate_backup_codes!
    start_mfa_session(@user)

    post users_sessions_use_backup_code_path, params: { backup_code: codes.first }
    assert_response :redirect
    follow_redirect!
    assert_response :success
  end

  test "use_backup_code with invalid code shows error" do
    enable_mfa_for_user(@user)
    @user.generate_backup_codes!
    start_mfa_session(@user)

    post users_sessions_use_backup_code_path, params: { backup_code: "invalidcode" }
    # Re-renders verify_otp page or shows error
    assert_response :success
  end

  test "use_backup_code consumes the code" do
    enable_mfa_for_user(@user)
    codes = @user.generate_backup_codes!
    start_mfa_session(@user)

    post users_sessions_use_backup_code_path, params: { backup_code: codes.first }
    assert_equal 7, @user.reload.backup_codes_remaining
  end

  # Session Expiry Tests
  test "submit_otp handles expired session" do
    post users_sessions_verify_otp_path, params: { code: "123456", method: "totp" }
    assert_redirected_to new_user_session_path
  end

  test "use_backup_code handles expired session" do
    post users_sessions_use_backup_code_path, params: { backup_code: "12345678" }
    assert_redirected_to new_user_session_path
  end

  # Remember Me Tests
  test "remember_me is preserved through MFA flow" do
    enable_mfa_for_user(@user)

    post user_session_path, params: {
      user: { email: @user.email, password: TEST_PASSWORD, remember_me: "1" }
    }
    assert_equal "1", session[:mfa_remember_me]
  end

  private

  def enable_mfa_for_user(user)
    user.setup_totp!
    totp = ROTP::TOTP.new(user.otp_secret)
    user.confirm_totp!(totp.now)
  end

  def start_mfa_session(user)
    # Simulate the session state after password auth
    post user_session_path, params: {
      user: { email: user.email, password: TEST_PASSWORD }
    }
  end
end
