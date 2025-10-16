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
  before_action :check_subscription_status
  before_action :check_onboarding_status
  before_action :configure_permitted_parameters, if: :devise_controller?

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
    # Check if we're on the app subdomain (or localhost without subdomain for testing)
    if request.subdomain == "app" || request.subdomain.blank?
      # First check if user needs onboarding (regardless of subdomain)
      unless resource.onboarded?
        return onboarding_path
      end

      # Check if user needs subscription
      entity = resource.entity
      if entity && !['active', 'trialing'].include?(entity.subscription_status)
        return new_subscription_path
      end

      # User is onboarded and has subscription, proceed with entity logic
      if resource.entity
        # User has an entity, go to dashboard
        root_path
      else
        # User has no entity, redirect to entity creation
        new_entity_path
      end
    else
      # Not on app subdomain, go to app subdomain root
      app_url = root_url(subdomain: "app")
      app_url
    end
  end

  # Override the default devise sign out redirect
  def after_sign_out_path_for(resource_or_scope)
    # Check if we're on the app subdomain (or localhost without subdomain for testing)
    if request.subdomain == "app" || request.subdomain.blank?
      # Redirect to login page on app subdomain
      new_user_session_path
    else
      # Not on app subdomain, redirect to marketing site
      root_path
    end
  end

  # Helper to determine if we're on the app subdomain
  def app_subdomain?
    # TEMP: For local testing without subdomains
    request.subdomain == "app" || request.subdomain.blank?
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
    # TEMP: For local testing without subdomains
    if request.subdomain == "app" || request.subdomain.blank?
      # On app subdomain or no subdomain (localhost), redirect to login
      Rails.logger.info "🔄 Redirecting to login page for app subdomain"
      redirect_to new_user_session_path
    else
      # On other subdomains, redirect to marketing site
      Rails.logger.info "🔄 Redirecting to marketing site for non-app subdomain"
      redirect_to root_url(subdomain: false)
    end
  end

  def check_subscription_status
    return unless user_signed_in?
    return if devise_controller? && (action_name == 'destroy' || controller_name == 'sessions')
    return if controller_name == 'subscriptions' # Allow subscription pages
    return if controller_name == 'stripe_webhooks' # Allow webhooks
    return if controller_name == 'stripe_checkout' # Allow checkout pages
    return if request.path.start_with?('/api/')
    return if request.path.start_with?('/stripe/')

    entity = current_entity
    return unless entity

    # Allow access if subscription is active or in trial
    return if ['active', 'trialing'].include?(entity.subscription_status)

    # Redirect to subscription page if no active subscription
    redirect_to new_subscription_path, alert: "Please select a plan to continue."
  end

  def check_onboarding_status
    return unless user_signed_in?
    return if devise_controller? && (action_name == "destroy" || controller_name == "sessions") # Allow logout
    return if controller_name == "onboarding" # Don't redirect from onboarding pages
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

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [ :first_name, :last_name, :role ])
    devise_parameter_sanitizer.permit(:account_update, keys: [ :first_name, :last_name, :role ])
  end
end
