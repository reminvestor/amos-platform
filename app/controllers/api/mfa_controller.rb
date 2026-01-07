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
