# frozen_string_literal: true

require "bcrypt"

# Concern for Two-Factor Authentication (TOTP + Email OTP)
# Provides methods for enabling, disabling, and verifying MFA
module TwoFactorAuthenticatable
  extend ActiveSupport::Concern

  BACKUP_CODE_COUNT = 8
  BACKUP_CODE_LENGTH = 8
  OTP_MAX_FAILED_ATTEMPTS = 5
  OTP_LOCKOUT_DURATION = 15.minutes
  EMAIL_OTP_EXPIRY = 5.minutes

  included do
    # Serialize backup codes as JSON
    serialize :otp_backup_codes, coder: JSON
  end

  # Check if MFA is enabled for this user
  def mfa_enabled?
    otp_required_for_login? && otp_secret.present?
  end

  # Check if MFA is set up but not yet confirmed
  def mfa_pending_setup?
    otp_secret.present? && !otp_required_for_login?
  end

  # Check if account is locked due to too many failed OTP attempts
  def otp_locked?
    return false unless otp_locked_at

    otp_locked_at > OTP_LOCKOUT_DURATION.ago
  end

  # ==========================================
  # TOTP Setup Methods
  # ==========================================

  # Generate a new OTP secret for TOTP setup
  def setup_totp!
    self.otp_secret = ROTP::Base32.random
    self.otp_delivery_method = "totp"
    self.otp_required_for_login = false # Not confirmed yet
    save!
  end

  # Get TOTP instance for this user
  def totp
    return nil unless otp_secret

    ROTP::TOTP.new(otp_secret, issuer: "AMOS Labs")
  end

  # Generate provisioning URI for QR code (used by authenticator apps)
  def otp_provisioning_uri
    return nil unless otp_secret

    totp.provisioning_uri(email)
  end

  # Generate QR code for authenticator app setup
  def otp_qr_code
    return nil unless otp_secret

    RQRCode::QRCode.new(otp_provisioning_uri)
  end

  # Generate QR code as SVG for display
  def otp_qr_code_svg(size: 200)
    return nil unless otp_qr_code

    otp_qr_code.as_svg(
      color: "000",
      shape_rendering: "crispEdges",
      module_size: 4,
      standalone: true,
      use_path: true
    )
  end

  # Confirm TOTP setup with a valid code
  def confirm_totp!(code)
    return false unless verify_totp(code)

    self.otp_required_for_login = true
    save!
    true
  end

  # ==========================================
  # OTP Verification Methods
  # ==========================================

  # Verify a TOTP code (from authenticator app)
  def verify_totp(code)
    return false if otp_locked?
    return false unless totp

    # Allow drift of 1 interval (30 seconds) in each direction
    result = totp.verify(code.to_s.gsub(/\s/, ""), drift_behind: 30, drift_ahead: 30)

    if result
      reset_otp_failed_attempts!
      true
    else
      increment_otp_failed_attempts!
      false
    end
  end

  # Verify any OTP (TOTP, email, or backup code)
  def verify_otp(code, method: nil)
    return false if otp_locked?

    # Clean up code (remove spaces, convert to string)
    clean_code = code.to_s.gsub(/\s/, "")

    # Try backup code first (they're longer)
    return true if consume_backup_code!(clean_code)

    # Then try based on method or current preference
    case method || otp_delivery_method
    when "totp"
      verify_totp(clean_code)
    when "email"
      verify_email_otp(clean_code)
    else
      # Try both
      verify_totp(clean_code) || verify_email_otp(clean_code)
    end
  end

  # ==========================================
  # Email OTP Methods
  # ==========================================

  # Generate and send OTP via email
  def send_email_otp!
    return false unless otp_email_enabled?

    code = generate_email_otp
    store_email_otp(code)
    OtpMailer.send_otp(self, code).deliver_later
    true
  end

  # Verify email OTP code
  def verify_email_otp(code)
    return false if otp_locked?

    stored_code = retrieve_email_otp
    return false unless stored_code

    if stored_code == code.to_s.gsub(/\s/, "")
      clear_email_otp
      reset_otp_failed_attempts!
      true
    else
      increment_otp_failed_attempts!
      false
    end
  end

  # ==========================================
  # Backup Codes Methods
  # ==========================================

  # Generate new backup codes
  def generate_backup_codes!
    codes = BACKUP_CODE_COUNT.times.map { SecureRandom.hex(BACKUP_CODE_LENGTH / 2) }

    # Store hashed versions
    self.otp_backup_codes = codes.map { |code| BCrypt::Password.create(code) }
    save!

    # Return plaintext codes (only shown once)
    codes
  end

  # Verify and consume a backup code (single use)
  def consume_backup_code!(code)
    return false unless otp_backup_codes.present?
    return false if otp_locked?

    clean_code = code.to_s.gsub(/\s/, "")
    return false if clean_code.length < 6

    remaining_codes = []
    code_found = false

    otp_backup_codes.each do |hashed_code|
      if !code_found && BCrypt::Password.new(hashed_code) == clean_code
        code_found = true # Don't add this one to remaining codes
      else
        remaining_codes << hashed_code
      end
    end

    if code_found
      self.otp_backup_codes = remaining_codes
      save!
      reset_otp_failed_attempts!
      true
    else
      increment_otp_failed_attempts!
      false
    end
  end

  # Check remaining backup codes count
  def backup_codes_remaining
    otp_backup_codes&.count || 0
  end

  # ==========================================
  # Disable MFA Methods
  # ==========================================

  # Disable MFA for this user
  def disable_mfa!
    self.otp_secret = nil
    self.otp_required_for_login = false
    self.otp_backup_codes = nil
    self.otp_delivery_method = "totp"
    self.otp_failed_attempts = 0
    self.otp_locked_at = nil
    clear_email_otp
    save!
  end

  # ==========================================
  # Rate Limiting / Lockout Methods
  # ==========================================

  # Increment failed OTP attempts and lock if necessary
  def increment_otp_failed_attempts!
    self.otp_failed_attempts += 1

    if otp_failed_attempts >= OTP_MAX_FAILED_ATTEMPTS
      self.otp_locked_at = Time.current
    end

    save!
  end

  # Reset failed OTP attempts after successful verification
  def reset_otp_failed_attempts!
    self.otp_failed_attempts = 0
    self.otp_locked_at = nil
    self.last_otp_at = Time.current
    save!
  end

  # Time until OTP lockout expires
  def otp_unlock_time
    return nil unless otp_locked?

    otp_locked_at + OTP_LOCKOUT_DURATION
  end

  private

  # Generate a 6-digit email OTP code
  def generate_email_otp
    format("%06d", SecureRandom.random_number(1_000_000))
  end

  # Store email OTP in Rails cache
  def store_email_otp(code)
    Rails.cache.write(email_otp_cache_key, code, expires_in: EMAIL_OTP_EXPIRY)
  end

  # Retrieve email OTP from Rails cache
  def retrieve_email_otp
    Rails.cache.read(email_otp_cache_key)
  end

  # Clear email OTP from Rails cache
  def clear_email_otp
    Rails.cache.delete(email_otp_cache_key)
  end

  # Cache key for email OTP storage
  def email_otp_cache_key
    "email_otp:#{id}"
  end
end
