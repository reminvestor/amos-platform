# frozen_string_literal: true

class LegalController < ApplicationController
  # Skip authentication for viewing legal pages and accept_terms (for pending OAuth users)
  skip_before_action :authenticate_user!, only: [:terms, :privacy, :support, :accept_terms, :submit_terms]
  skip_before_action :check_onboarding_status, only: [:terms, :privacy, :support, :accept_terms, :submit_terms]
  skip_before_action :check_token_balance, only: [:terms, :privacy, :support, :accept_terms, :submit_terms]

  layout "devise"

  CURRENT_TERMS_VERSION = "1.0"
  CURRENT_PRIVACY_VERSION = "1.0"

  def terms
    # Public terms of service page
  end

  def privacy
    # Public privacy policy page
  end

  def support
    # Public support page
  end

  def accept_terms
    # For users who need to accept terms (new OAuth users or pending users)
    @user = pending_user || current_user
    
    if @user.nil?
      redirect_to new_user_session_path, alert: "Please sign in first."
      return
    end

    if @user.terms_accepted?
      redirect_to after_sign_in_path_for(@user)
    end
  end

  def submit_terms
    @user = pending_user || current_user

    if @user.nil?
      redirect_to new_user_session_path, alert: "Please sign in first."
      return
    end

    unless params[:accept_terms] == "1" && params[:accept_privacy] == "1"
      flash.now[:alert] = "You must accept both the Terms of Service and Privacy Policy to continue."
      render :accept_terms
      return
    end

    @user.accept_terms!(
      terms_ver: CURRENT_TERMS_VERSION,
      privacy_ver: CURRENT_PRIVACY_VERSION
    )

    # If user was pending from OAuth, sign them in now
    if session[:pending_user_id]
      session.delete(:pending_user_id)
      sign_in(@user, event: :authentication)
    end

    # Redirect to onboarding if not completed, otherwise to app
    if @user.onboarded?
      redirect_to chat_mode_path, notice: "Welcome back!"
    else
      redirect_to onboarding_path, notice: "Let's get you set up!"
    end
  end

  private

  def pending_user
    return nil unless session[:pending_user_id]
    User.find_by(id: session[:pending_user_id])
  end
end

