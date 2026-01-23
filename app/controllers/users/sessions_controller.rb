# frozen_string_literal: true

class Users::SessionsController < Devise::SessionsController
  layout "devise"

  # Handle subdomain redirects for already-signed-in users
  before_action :redirect_if_signed_in, only: [:new]

  # Override create to check for MFA
  def create
    self.resource = warden.authenticate!(auth_options)

    if resource.mfa_enabled?
      # Store user ID in session for MFA verification
      session[:mfa_user_id] = resource.id
      session[:mfa_remember_me] = params[:user][:remember_me] if params[:user]
      sign_out(resource) # Sign out until MFA is verified

      redirect_to verify_otp_user_session_path, allow_other_host: true
    else
      # Normal sign in flow
      set_flash_message!(:notice, :signed_in)
      sign_in(resource_name, resource)
      yield resource if block_given?
      # Use redirect_to with allow_other_host for subdomain redirects (e.g., app.localhost)
      redirect_to after_sign_in_path_for(resource), allow_other_host: true
    end
  end

  # Show the OTP verification page
  def verify_otp
    unless session[:mfa_user_id]
      redirect_to new_user_session_path, alert: "Please sign in first."
      return
    end

    @user = User.find_by(id: session[:mfa_user_id])
    unless @user
      session.delete(:mfa_user_id)
      redirect_to new_user_session_path, alert: "Session expired. Please sign in again."
      return
    end

    # Email hint (mask the email)
    email_parts = @user.email.split("@")
    masked_local = email_parts[0][0..1] + "***"
    @email_hint = "#{masked_local}@#{email_parts[1]}"
  end

  # Verify submitted OTP code
  def submit_otp
    unless session[:mfa_user_id]
      redirect_to new_user_session_path, alert: "Session expired. Please sign in again."
      return
    end

    @user = User.find_by(id: session[:mfa_user_id])
    unless @user
      session.delete(:mfa_user_id)
      redirect_to new_user_session_path, alert: "Session expired. Please sign in again."
      return
    end

    code = params[:code]&.strip
    method = params[:method]

    # Rate limiting check
    if @user.otp_locked?
      flash.now[:alert] = "Too many failed attempts. Please try again later."
      render :verify_otp
      return
    end

    verified = case method
               when "totp"
                 @user.verify_totp(code)
               when "email"
                 @user.verify_email_otp(code)
               else
                 false
               end

    if verified
      @user.reset_otp_failed_attempts!
      complete_sign_in(@user)
    else
      @user.increment_otp_failed_attempts!

      # Show appropriate error
      remaining_attempts = User::OTP_MAX_FAILED_ATTEMPTS - @user.otp_failed_attempts
      if remaining_attempts > 0
        flash.now[:alert] = "Invalid verification code. #{remaining_attempts} attempts remaining."
      else
        flash.now[:alert] = "Too many failed attempts. Your account is temporarily locked."
      end

      # Re-set email hint for view
      email_parts = @user.email.split("@")
      masked_local = email_parts[0][0..1] + "***"
      @email_hint = "#{masked_local}@#{email_parts[1]}"

      render :verify_otp
    end
  end

  # Send OTP via email
  def send_email_otp
    unless session[:mfa_user_id]
      render json: { success: false, error: "Session expired" }, status: :unauthorized
      return
    end

    user = User.find_by(id: session[:mfa_user_id])
    unless user
      render json: { success: false, error: "Session expired" }, status: :unauthorized
      return
    end

    # Rate limit email sending (max 3 per 5 minutes)
    email_otp_key = "mfa_email_sent:#{user.id}"
    email_count = Rails.cache.read(email_otp_key).to_i

    if email_count >= 3
      render json: { success: false, error: "Please wait before requesting another code" }
      return
    end

    begin
      user.send_email_otp!
      Rails.cache.write(email_otp_key, email_count + 1, expires_in: 5.minutes)
      render json: { success: true }
    rescue StandardError => e
      Rails.logger.error("Failed to send email OTP: #{e.message}")
      render json: { success: false, error: "Failed to send code. Please try again." }
    end
  end

  # Use a backup code
  def use_backup_code
    unless session[:mfa_user_id]
      redirect_to new_user_session_path, alert: "Session expired. Please sign in again."
      return
    end

    @user = User.find_by(id: session[:mfa_user_id])
    unless @user
      session.delete(:mfa_user_id)
      redirect_to new_user_session_path, alert: "Session expired. Please sign in again."
      return
    end

    backup_code = params[:backup_code]&.strip&.downcase

    if @user.consume_backup_code!(backup_code)
      @user.reset_otp_failed_attempts!
      complete_sign_in(@user)
    else
      flash[:alert] = "Invalid backup code. Please check and try again."

      # Re-set email hint for view
      email_parts = @user.email.split("@")
      masked_local = email_parts[0][0..1] + "***"
      @email_hint = "#{masked_local}@#{email_parts[1]}"

      render :verify_otp
    end
  end

  private

  # Redirect already-signed-in users to their dashboard
  # Uses allow_other_host for subdomain redirects (e.g., app.localhost)
  def redirect_if_signed_in
    if user_signed_in?
      redirect_to after_sign_in_path_for(current_user), allow_other_host: true
    end
  end

  def complete_sign_in(user)
    # Clear MFA session data
    remember_me = session.delete(:mfa_remember_me)
    session.delete(:mfa_user_id)

    # Sign in the user
    sign_in(resource_name, user)

    # Handle remember me
    user.remember_me! if remember_me == "1"

    set_flash_message!(:notice, :signed_in)
    # Use allow_other_host for subdomain redirects (e.g., app.localhost)
    redirect_to after_sign_in_path_for(user), allow_other_host: true
  end
end
