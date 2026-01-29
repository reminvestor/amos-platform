# frozen_string_literal: true

module Api
  class MfaController < ApplicationController
    skip_before_action :authenticate_user!
    skip_before_action :verify_authenticity_token

    before_action :authenticate_api_user!

    # GET /api/mfa/status
    # Get current MFA status
    def status
      render json: {
        mfa_enabled: @current_user.mfa_enabled?,
        backup_codes_remaining: @current_user.backup_codes_remaining,
        email_otp_enabled: @current_user.otp_email_enabled?
      }
    end

    # POST /api/mfa/enable
    # Start MFA setup - generate secret and return QR code data
    def enable
      if @current_user.mfa_enabled?
        render json: { message: "Two-factor authentication is already enabled" }, status: :unprocessable_entity
        return
      end

      # Only generate new secret if one doesn't exist (don't overwrite partial setup)
      @current_user.setup_totp! unless @current_user.otp_secret.present?

      # Generate otpauth URI for QR code
      issuer = "Amos"
      otp_uri = "otpauth://totp/#{issuer}:#{@current_user.email}?secret=#{@current_user.otp_secret}&issuer=#{issuer}&algorithm=SHA1&digits=6&period=30"

      render json: {
        secret: @current_user.otp_secret,
        otp_uri: otp_uri,
        message: "Scan the QR code or enter the secret manually in your authenticator app"
      }
    end

    # POST /api/mfa/confirm
    # Confirm TOTP setup with valid code
    def confirm
      code = params[:code]&.gsub(/\s/, "")

      unless code.present?
        render json: { message: "Verification code is required" }, status: :unprocessable_entity
        return
      end

      if @current_user.confirm_totp!(code)
        backup_codes = @current_user.generate_backup_codes!

        # Clear the user cache so /api/auth/me returns fresh data
        Rails.cache.delete("api_user:#{@current_user.api_key}")

        render json: {
          success: true,
          message: "Two-factor authentication has been enabled",
          backup_codes: backup_codes,
          mfa_enabled: true
        }
      else
        render json: {
          success: false,
          message: "Invalid verification code. Please try again."
        }, status: :unprocessable_entity
      end
    end

    # DELETE /api/mfa/disable
    # Disable MFA (requires password confirmation)
    def disable
      unless params[:password].present?
        render json: { message: "Password is required to disable 2FA" }, status: :unprocessable_entity
        return
      end

      if @current_user.valid_password?(params[:password])
        @current_user.disable_mfa!
        render json: {
          success: true,
          message: "Two-factor authentication has been disabled"
        }
      else
        render json: {
          success: false,
          message: "Incorrect password"
        }, status: :unauthorized
      end
    end

    # POST /api/mfa/regenerate_backup_codes
    # Generate new backup codes (requires password)
    def regenerate_backup_codes
      unless @current_user.mfa_enabled?
        render json: { message: "MFA is not enabled" }, status: :unprocessable_entity
        return
      end

      unless params[:password].present?
        render json: { message: "Password is required" }, status: :unprocessable_entity
        return
      end

      if @current_user.valid_password?(params[:password])
        backup_codes = @current_user.generate_backup_codes!
        render json: {
          success: true,
          message: "New backup codes have been generated. Your old codes are no longer valid.",
          backup_codes: backup_codes
        }
      else
        render json: {
          success: false,
          message: "Incorrect password"
        }, status: :unauthorized
      end
    end

    # POST /api/mfa/trust_device
    # Create a trusted device token after successful MFA verification
    # This allows bypassing MFA on this device using Face ID/biometrics
    def trust_device
      device_name = params[:device_name] || "Mobile Device"
      device_identifier = params[:device_identifier]
      platform = params[:platform] || "unknown"

      trusted_device = TrustedDevice.create_for_user!(
        @current_user,
        device_name: device_name,
        device_identifier: device_identifier,
        platform: platform
      )

      render json: {
        success: true,
        device_token: trusted_device.token,
        expires_at: trusted_device.expires_at,
        message: "Device trusted successfully. You can now use biometrics to sign in."
      }
    rescue => e
      Rails.logger.error("Failed to create trusted device: #{e.message}")
      render json: {
        success: false,
        message: "Failed to trust device"
      }, status: :unprocessable_entity
    end

    # GET /api/mfa/trusted_devices
    # List all trusted devices for the current user
    def trusted_devices
      devices = @current_user.trusted_devices.active.order(last_used_at: :desc).map do |device|
        {
          id: device.id,
          device_name: device.device_name,
          platform: device.platform,
          last_used_at: device.last_used_at,
          expires_at: device.expires_at,
          created_at: device.created_at
        }
      end

      render json: { trusted_devices: devices }
    end

    # DELETE /api/mfa/trusted_devices/:id
    # Revoke a specific trusted device
    def revoke_trusted_device
      device = @current_user.trusted_devices.find_by(id: params[:id])

      unless device
        render json: { message: "Device not found" }, status: :not_found
        return
      end

      device.destroy
      render json: {
        success: true,
        message: "Device trust has been revoked"
      }
    end

    # DELETE /api/mfa/trusted_devices
    # Revoke all trusted devices (useful if phone is lost)
    def revoke_all_trusted_devices
      count = @current_user.trusted_devices.destroy_all.count
      render json: {
        success: true,
        message: "#{count} trusted device(s) have been revoked"
      }
    end

    private

    def authenticate_api_user!
      token = request.headers["Authorization"]&.gsub(/^Bearer /, "")

      unless token.present?
        render json: { message: "Authorization token required" }, status: :unauthorized
        return
      end

      @current_user = Rails.cache.fetch("api_user:#{token}", expires_in: 5.minutes) do
        User.includes(:entity).find_by(api_key: token)
      end

      unless @current_user
        render json: { message: "Invalid token" }, status: :unauthorized
        return
      end
    end
  end
end
