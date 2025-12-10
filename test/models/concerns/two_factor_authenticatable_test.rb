# frozen_string_literal: true

require "test_helper"

class TwoFactorAuthenticatableTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  def setup
    @user = users(:one)
    @user.update!(otp_required_for_login: false, otp_secret: nil, otp_email_enabled: true)
    # Use memory store for tests that need caching (test environment uses null_store by default)
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  def teardown
    Rails.cache = @original_cache
  end

  # MFA Status Tests
  test "mfa_enabled? returns false when otp_required_for_login is false" do
    assert_not @user.mfa_enabled?
  end

  test "mfa_enabled? returns true when otp_required_for_login is true" do
    @user.update!(otp_required_for_login: true, otp_secret: ROTP::Base32.random)
    assert @user.mfa_enabled?
  end

  # TOTP Setup Tests
  test "setup_totp! generates an OTP secret" do
    assert_nil @user.otp_secret
    @user.setup_totp!
    assert_not_nil @user.otp_secret
    assert_equal 32, @user.otp_secret.length
  end

  test "setup_totp! does not enable MFA yet" do
    @user.setup_totp!
    assert_not @user.otp_required_for_login
  end

  # TOTP QR Code Tests
  test "otp_qr_code returns nil when no secret" do
    assert_nil @user.otp_qr_code
  end

  test "otp_qr_code generates QR code when secret exists" do
    @user.setup_totp!
    qr_code = @user.otp_qr_code
    assert_not_nil qr_code
    assert_kind_of RQRCode::QRCode, qr_code
  end

  test "otp_qr_code_svg generates SVG when secret exists" do
    @user.setup_totp!
    qr_svg = @user.otp_qr_code_svg
    assert_not_nil qr_svg
    assert qr_svg.include?("<svg")
  end

  test "otp_provisioning_uri includes app name and email" do
    @user.setup_totp!
    uri = @user.otp_provisioning_uri
    assert uri.include?("AMOS%20Labs")
    assert uri.include?(CGI.escape(@user.email))
  end

  # TOTP Verification Tests
  test "verify_totp returns false with nil secret" do
    assert_not @user.verify_totp("123456")
  end

  test "verify_totp returns false with invalid code" do
    @user.setup_totp!
    assert_not @user.verify_totp("000000")
  end

  test "verify_totp returns true with valid code" do
    @user.setup_totp!
    totp = ROTP::TOTP.new(@user.otp_secret)
    valid_code = totp.now
    assert @user.verify_totp(valid_code)
  end

  test "verify_totp allows time drift" do
    @user.setup_totp!
    totp = ROTP::TOTP.new(@user.otp_secret)
    # Generate a code from 30 seconds ago (within drift window)
    code = totp.at(Time.now - 30)
    assert @user.verify_totp(code)
  end

  # Confirm TOTP Tests
  test "confirm_totp! enables MFA with valid code" do
    @user.setup_totp!
    totp = ROTP::TOTP.new(@user.otp_secret)
    valid_code = totp.now

    assert @user.confirm_totp!(valid_code)
    assert @user.otp_required_for_login
  end

  test "confirm_totp! returns false with invalid code" do
    @user.setup_totp!
    assert_not @user.confirm_totp!("000000")
    assert_not @user.otp_required_for_login
  end

  # Email OTP Tests
  test "send_email_otp! generates and stores a 6-digit code" do
    @user.update!(otp_email_enabled: true)
    @user.send_email_otp!
    cached_code = Rails.cache.read("email_otp:#{@user.id}")
    assert_not_nil cached_code
    assert_match(/^\d{6}$/, cached_code)
  end

  test "send_email_otp! sends email" do
    @user.update!(otp_email_enabled: true)
    assert_enqueued_emails 1 do
      @user.send_email_otp!
    end
  end

  test "verify_email_otp returns true with valid code" do
    @user.update!(otp_email_enabled: true)
    @user.send_email_otp!
    code = Rails.cache.read("email_otp:#{@user.id}")
    assert @user.verify_email_otp(code)
  end

  test "verify_email_otp returns false with invalid code" do
    @user.update!(otp_email_enabled: true)
    @user.send_email_otp!
    assert_not @user.verify_email_otp("000000")
  end

  test "verify_email_otp clears code after successful verification" do
    @user.update!(otp_email_enabled: true)
    @user.send_email_otp!
    code = Rails.cache.read("email_otp:#{@user.id}")
    @user.verify_email_otp(code)
    assert_nil Rails.cache.read("email_otp:#{@user.id}")
  end

  # Backup Codes Tests
  test "generate_backup_codes! creates 8 codes" do
    codes = @user.generate_backup_codes!
    assert_equal 8, codes.length
  end

  test "generate_backup_codes! stores hashed codes" do
    codes = @user.generate_backup_codes!
    stored_codes = @user.otp_backup_codes
    assert_equal 8, stored_codes.length
    # Stored codes should be hashed (different from plaintext)
    assert_not_equal codes.first, stored_codes.first
  end

  test "consume_backup_code! returns true with valid code" do
    codes = @user.generate_backup_codes!
    assert @user.consume_backup_code!(codes.first)
  end

  test "consume_backup_code! returns false with invalid code" do
    @user.generate_backup_codes!
    assert_not @user.consume_backup_code!("invalidcode")
  end

  test "consume_backup_code! removes used code" do
    codes = @user.generate_backup_codes!
    @user.consume_backup_code!(codes.first)

    stored_codes = @user.otp_backup_codes
    assert_equal 7, stored_codes.length
  end

  test "consume_backup_code! code can only be used once" do
    codes = @user.generate_backup_codes!
    code = codes.first

    assert @user.consume_backup_code!(code)
    assert_not @user.consume_backup_code!(code)
  end

  test "backup_codes_remaining returns count of remaining codes" do
    @user.generate_backup_codes!
    assert_equal 8, @user.backup_codes_remaining

    # Manually set fewer codes
    @user.update!(otp_backup_codes: @user.otp_backup_codes[0..4])
    assert_equal 5, @user.backup_codes_remaining
  end

  # Disable MFA Tests
  test "disable_mfa! clears all MFA data" do
    @user.setup_totp!
    @user.confirm_totp!(ROTP::TOTP.new(@user.otp_secret).now)
    @user.generate_backup_codes!

    @user.disable_mfa!

    assert_nil @user.otp_secret
    assert_not @user.otp_required_for_login
    assert_nil @user.otp_backup_codes
    assert_equal 0, @user.otp_failed_attempts
    assert_nil @user.otp_locked_at
  end

  # Rate Limiting Tests
  test "otp_locked? returns false when not locked" do
    assert_not @user.otp_locked?
  end

  test "otp_locked? returns true when locked" do
    @user.update!(otp_locked_at: Time.current)
    assert @user.otp_locked?
  end

  test "otp_locked? returns false when lock has expired" do
    @user.update!(otp_locked_at: 20.minutes.ago)
    assert_not @user.otp_locked?
  end

  test "increment_otp_failed_attempts! increments counter" do
    assert_equal 0, @user.otp_failed_attempts
    @user.increment_otp_failed_attempts!
    assert_equal 1, @user.reload.otp_failed_attempts
  end

  test "increment_otp_failed_attempts! locks account after max attempts" do
    User::OTP_MAX_FAILED_ATTEMPTS.times do
      @user.increment_otp_failed_attempts!
    end

    assert @user.otp_locked?
  end

  test "reset_otp_failed_attempts! clears attempts and lock" do
    @user.update!(otp_failed_attempts: 5, otp_locked_at: Time.current)
    @user.reset_otp_failed_attempts!

    assert_equal 0, @user.otp_failed_attempts
    assert_nil @user.otp_locked_at
  end

  # OTP Verification Combined Tests
  test "verify_otp with totp method calls verify_totp" do
    @user.setup_totp!
    @user.update!(otp_required_for_login: true)
    totp = ROTP::TOTP.new(@user.otp_secret)

    assert @user.verify_otp(totp.now, method: "totp")
  end

  test "verify_otp with email method calls verify_email_otp" do
    @user.update!(otp_email_enabled: true)
    @user.send_email_otp!
    code = Rails.cache.read("email_otp:#{@user.id}")

    assert @user.verify_otp(code, method: "email")
  end

  test "verify_otp with backup_code method calls consume_backup_code!" do
    codes = @user.generate_backup_codes!
    assert @user.verify_otp(codes.first, method: "backup_code")
  end
end
