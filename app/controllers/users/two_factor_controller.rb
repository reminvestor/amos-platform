# frozen_string_literal: true

module Users
  class TwoFactorController < ApplicationController
    before_action :authenticate_user!
    before_action :set_user

    # GET /users/two_factor
    # Show MFA status and options
    def show
      @mfa_enabled = @user.mfa_enabled?
      @backup_codes_remaining = @user.backup_codes_remaining
    end

    # GET /users/two_factor/enable
    # Start MFA setup process - generate secret and show QR code
    def enable
      if @user.mfa_enabled?
        flash[:alert] = "Two-factor authentication is already enabled."
        redirect_to users_two_factor_path
        return
      end

      @user.setup_totp!
      @qr_code_svg = @user.otp_qr_code_svg(size: 200)
      @secret = @user.otp_secret
    end

    # POST /users/two_factor/confirm
    # Confirm TOTP setup with valid code
    def confirm
      code = params[:code]&.gsub(/\s/, "")

      if @user.confirm_totp!(code)
        @backup_codes = @user.generate_backup_codes!
        flash[:notice] = "Two-factor authentication has been enabled."
        render :backup_codes
      else
        flash.now[:alert] = "Invalid verification code. Please try again."
        @qr_code_svg = @user.otp_qr_code_svg(size: 200)
        @secret = @user.otp_secret
        render :enable, status: :unprocessable_entity
      end
    end

    # DELETE /users/two_factor
    # Disable MFA (requires password confirmation)
    def disable
      if @user.valid_password?(params[:password])
        @user.disable_mfa!
        flash[:notice] = "Two-factor authentication has been disabled."
        redirect_to users_two_factor_path
      else
        flash[:alert] = "Incorrect password. Please try again."
        redirect_to users_two_factor_path
      end
    end

    # GET /users/two_factor/backup_codes
    # Show backup codes (only after generation)
    def backup_codes
      unless @user.mfa_enabled?
        redirect_to users_two_factor_path
        return
      end
      @backup_codes = params[:codes]&.split(",") || []
    end

    # POST /users/two_factor/regenerate_backup_codes
    # Generate new backup codes (invalidates old ones)
    def regenerate_backup_codes
      if @user.valid_password?(params[:password])
        @backup_codes = @user.generate_backup_codes!
        flash[:notice] = "New backup codes have been generated. Your old codes are no longer valid."
        render :backup_codes
      else
        flash[:alert] = "Incorrect password. Please try again."
        redirect_to users_two_factor_path
      end
    end

    # GET /users/two_factor/email_settings
    # Manage email OTP preferences
    def email_settings
      @email_enabled = @user.otp_email_enabled?
    end

    # PATCH /users/two_factor/update_email_settings
    # Update email OTP preferences
    def update_email_settings
      @user.update!(otp_email_enabled: params[:otp_email_enabled] == "1")
      flash[:notice] = "Email verification settings updated."
      redirect_to users_two_factor_path
    end

    private

    def set_user
      @user = current_user
    end
  end
end
