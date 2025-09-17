# frozen_string_literal: true

class Users::PasswordsController < Devise::PasswordsController
  # POST /resource/password
  def create
    begin
      super do |resource|
        if resource.errors.empty?
          flash[:notice] = "If your email address exists in our database, you will receive a password recovery link at your email address in a few minutes."
          redirect_to new_user_session_path and return
        end
      end
    rescue => e
      Rails.logger.error "Password reset email error: #{e.message}"
      flash[:notice] = "If your email address exists in our database, you will receive a password recovery link at your email address in a few minutes."
      redirect_to new_user_session_path
    end
  end

  protected

  # Override to always show the same message regardless of whether the email exists
  def successfully_sent?(resource)
    true
  end
end
