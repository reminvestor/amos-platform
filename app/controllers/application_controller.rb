class ApplicationController < ActionController::Base
  # Include the entity scoped functionality
  include EntityScoped

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Set up CSRF protection properly
  # Note: API controllers will handle this themselves
  protect_from_forgery with: :exception, unless: :api_request?
  skip_before_action :verify_authenticity_token, if: :api_request?

  # Require authentication for all controllers except API ones
  before_action :authenticate_user!, unless: :api_request?
  before_action :check_token_balance
  before_action :check_onboarding_status
  before_action :configure_permitted_parameters, if: :devise_controller?

  # Handle CSRF token failures (Story 0.5)
  rescue_from ActionController::InvalidAuthenticityToken do |exception|
    respond_to do |format|
      format.html { redirect_to root_path, alert: 'Session expired. Please try again.' }
      format.json { render json: { error: 'Invalid CSRF token' }, status: :forbidden }
    end
  end

  # Handle Warden authentication failures gracefully
  rescue_from Warden::NotAuthenticated do |exception|
    Rails.logger.info "🚨 Warden authentication failure - Subdomain: #{request.subdomain}, Path: #{request.path}, User-Agent: #{request.user_agent}"
    handle_authentication_failure
  end

  # Handle uncaught Warden throws (UncaughtThrowError)
  rescue_from UncaughtThrowError do |exception|
    if exception.tag == :warden
      Rails.logger.info "🚨 Uncaught Warden throw - Subdomain: #{request.subdomain}, Path: #{request.path}"
      handle_authentication_failure
    else
      # Re-raise if it's not a Warden throw
      raise exception
    end
  end

  protected

  # Check if this is an API request based on the path
  def api_request?
    request.path.start_with?("/api/")
  end

  # Override the default devise redirect to avoid /entities being appended
  def after_sign_in_path_for(resource)
    # First check if user needs onboarding (regardless of subdomain)
    unless resource.onboarded?
      return onboarding_path
    end

    # NOTE: Removed automatic billing redirect on login
    # Users can always access billing from the sidebar menu if needed
    # We don't want to interrupt the user experience with billing prompts on every login

    # Check if we're on the app subdomain
    if SubdomainConfig.app_subdomains.include?(request.subdomain)
      # User is onboarded and has subscription, proceed with entity logic
      if resource.entity
        # User has an entity, go to chat (default mode)
        chat_mode_path
      else
        # User has no entity, redirect to entity creation
        new_entity_path
      end
    else
      # Not on app subdomain, redirect to default app subdomain
      # In production: app.amoslabs.com or stay on current if dev
      # In development: app.localhost:3000
      if Rails.env.production?
        # If we're on dev.amoslabs.com in production (dev environment), stay there
        if ENV['APP_DOMAIN']&.start_with?('dev.')
          root_url
        else
          root_url(subdomain: "app")
        end
      else
        # For development, use root_url with subdomain
        # This requires allow_other_host: true on the redirect_to call
        root_url(subdomain: "app", host: "localhost", port: request.port)
      end
    end
  end

  # Override the default devise sign out redirect
  def after_sign_out_path_for(resource_or_scope)
    # Redirect to login page (marketing site is now external)
    new_user_session_path
  end

  # Helper to determine if we're on the app subdomain
  def app_subdomain?
    request.subdomain == "app"
  end

  # Debug action to check user status without redirects (add this to routes as needed)
  def debug_user_status
    skip_before_action :check_onboarding_status

    render json: {
      user_id: current_user&.id,
      user_email: current_user&.email,
      onboarded: current_user&.onboarded?,
      has_entity: current_user&.entity&.present? || false,
      current_entity_id: session[:entity_id],
      has_business_profile: current_user&.business_profile&.present?,
      subdomain: request.subdomain,
      domain: request.domain,
      path: request.path,
      user_agent: request.user_agent
    }
  end

  private

  def handle_authentication_failure
    # Marketing site is now external - always redirect to login
    Rails.logger.info "🔄 Redirecting to login page"
    redirect_to new_user_session_path
  end

  def check_token_balance
    return unless user_signed_in?
    return if Rails.env.development? # Skip token check in development
    return if current_user.admin? # Skip token check for site admins (Amos internal)
    return if devise_controller? && (action_name == 'destroy' || controller_name == 'sessions')
    return if controller_name == 'billing' # Allow billing pages
    return if controller_name == 'stripe_webhooks' # Allow webhooks
    return if controller_name == 'stripe_checkout' # Allow checkout pages
    return if controller_name == 'team_invites' # Allow team invite acceptance
    return if request.path.start_with?('/api/')
    return if request.path.start_with?('/stripe/')
    return if request.path.start_with?('/billing')
    return if request.path.start_with?('/invite/')

    # Check if entity uses shared token pool
    entity = current_user.entity
    if entity&.use_shared_token_pool
      # Use entity billing account
      billing_account = EntityBillingAccount.find_by(entity: entity)
      billing_account ||= EntityBillingAccount.for_entity(entity)
      
      # Check entity admin for billing redirect (only admins can purchase for entity)
      entity_user = EntityUser.find_by(entity: entity, user: current_user)
      is_admin = entity_user&.admin?
      
      # If entity has positive balance, always allow
      return if billing_account.work_token_balance > 0
      
      # If entity has a payment method AND auto-replenish enabled, allow
      return if billing_account.has_payment_method? && billing_account.auto_replenish_enabled?
      
      # At this point: balance <= 0 AND (no payment method OR no auto-replenish)
      if !billing_account.has_payment_method?
        message = is_admin ? "Your team needs a payment method to continue." : "Your team needs a payment method. Please contact your team admin."
        redirect_path = is_admin ? setup_payment_billing_path : root_path
        return handle_insufficient_tokens(redirect_path, message)
      elsif !billing_account.auto_replenish_enabled?
        message = is_admin ? "Please enable auto-replenish or purchase tokens for your team." : "Your team is out of tokens. Please contact your team admin."
        redirect_path = is_admin ? setup_payment_billing_path : root_path
        return handle_insufficient_tokens(redirect_path, message)
      end
      
      message = is_admin ? "Your team is out of tokens. Please purchase tokens." : "Your team is out of tokens. Please contact your team admin."
      redirect_path = is_admin ? setup_payment_billing_path : root_path
      handle_insufficient_tokens(redirect_path, message)
    else
      # Use individual user billing account
      billing_account = UserBillingAccount.find_by(user: current_user)
      billing_account ||= UserBillingAccount.for_user(current_user)

      # If user has positive balance, always allow
      return if billing_account.work_token_balance > 0
      
      # If user has a payment method AND auto-replenish enabled, allow
      # (auto-replenish will cover future usage)
      return if billing_account.has_payment_method? && billing_account.auto_replenish_enabled?

      # At this point: balance <= 0 AND (no payment method OR no auto-replenish)
      # User needs to set up payment method with auto-replenish enabled
      if !billing_account.has_payment_method?
        handle_insufficient_tokens(
          setup_payment_billing_path,
          "Please add a payment method to continue using AMOS."
        )
      elsif !billing_account.auto_replenish_enabled?
        handle_insufficient_tokens(
          setup_payment_billing_path,
          "Please enable auto-replenish or purchase tokens to continue using AMOS."
        )
      else
        handle_insufficient_tokens(
          setup_payment_billing_path,
          "You're out of tokens. Please purchase tokens to continue."
        )
      end
    end
  end

  # Handle insufficient token balance - returns JSON for AJAX, redirect for regular requests
  def handle_insufficient_tokens(redirect_path, message)
    if request.xhr? || request.format.json? || request.content_type&.include?('application/json')
      # For AJAX/JSON requests, return JSON that the frontend can handle
      render json: {
        error: 'insufficient_tokens',
        message: message,
        redirect_url: redirect_path
      }, status: :payment_required and return
    else
      # For regular requests, do a standard redirect
      redirect_to redirect_path, alert: message and return
    end
  end

  def check_onboarding_status
    return unless user_signed_in?
    return if devise_controller? && (action_name == "destroy" || controller_name == "sessions") # Allow logout
    return if controller_name == "onboarding" # Don't redirect from onboarding pages
    return if controller_name == "onboarding_wizard" # Don't redirect from onboarding wizard
    return if controller_name == "legal" # Allow legal pages (terms, privacy)
    return if controller_name == "campaign_tracking" # Allow campaign tracking
    return if controller_name == "subscriptions" # Allow subscription pages
    return if controller_name == "stripe_webhooks" # Allow Stripe webhooks
    return if controller_name == "stripe_checkout" # Allow Stripe checkout
    return if request.path.start_with?("/api/") # Skip API requests
    return if request.path.start_with?("/subscriptions") # Allow all subscription paths
    return if request.path == "/scout" # Don't redirect from scout path to prevent loops
    return if request.path == "/onboarding/debug_status" # Allow debug status check

    # Debug logging for production troubleshooting
    Rails.logger.info "🔍 Onboarding check - Controller: #{controller_name}, User: #{current_user.id}, Onboarded: #{current_user.onboarded?}, Path: #{request.path}, Domain: #{request.domain}"

    return if current_user.onboarded? # User has completed onboarding

    # Prevent redirect loops by checking if we're already being redirected to onboarding
    return if request.path == onboarding_path || request.path.start_with?("/onboarding")

    # Debug redirect
    Rails.logger.info "🔄 Redirecting to onboarding - User: #{current_user.id} not onboarded"

    # Redirect to onboarding if user hasn't completed it
    redirect_to onboarding_path
  end

  # Require 2FA to be enabled for sensitive operations (like connecting integrations)
  def require_two_factor!
    return if current_user&.mfa_enabled?
    
    # Store where they were trying to go
    session[:after_mfa_path] = request.fullpath
    
    flash[:alert] = "Two-factor authentication is required before connecting integrations. This protects your external accounts."
    redirect_to users_two_factor_path
  end

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [ :first_name, :last_name, :role ])
    devise_parameter_sanitizer.permit(:account_update, keys: [ :first_name, :last_name, :role ])
  end
end
