# frozen_string_literal: true

class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  skip_before_action :verify_authenticity_token, only: [:google]

  def google
    handle_oauth("Google")
  end

  def failure
    redirect_to new_user_session_path, alert: "Authentication failed: #{failure_message}"
  end

  private

  def handle_oauth(provider)
    @user = User.from_omniauth(request.env["omniauth.auth"])

    if @user.persisted?
      # Check if terms need to be accepted
      if !@user.terms_accepted?
        # Store user ID in session and redirect to terms acceptance
        session[:pending_user_id] = @user.id
        redirect_to accept_terms_path and return
      end

      flash[:notice] = I18n.t("devise.omniauth_callbacks.success", kind: provider)
      sign_in_and_redirect @user, event: :authentication
    else
      # Store OAuth data in session for retry
      session["devise.#{provider.downcase}_data"] = request.env["omniauth.auth"].except(:extra)
      redirect_to new_user_registration_path, alert: @user.errors.full_messages.join("\n")
    end
  rescue StandardError => e
    Rails.logger.error "OAuth error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    
    # Provide user-friendly error message
    error_message = case e.message
    when /unknown attribute/i
      "Account setup failed. Please try again or contact support."
    when /validation failed/i
      "Could not create your account. #{e.message.gsub('Validation failed: ', '')}"
    when /email.*taken/i
      "An account with this email already exists. Try signing in instead."
    else
      "Authentication failed. Please try again or use a different sign-in method."
    end
    
    redirect_to new_user_session_path, alert: error_message
  end

  def failure_message
    exception = request.env["omniauth.error"]
    if exception.respond_to?(:message)
      exception.message
    elsif exception.is_a?(String)
      exception
    else
      "Unknown error"
    end
  end
end

