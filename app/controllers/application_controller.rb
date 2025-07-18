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
  before_action :check_onboarding_status
  before_action :configure_permitted_parameters, if: :devise_controller?
  
  protected
  
  # Check if this is an API request based on the path
  def api_request?
    request.path.start_with?('/api/')
  end
  
  # Override the default devise redirect to avoid /entities being appended
  def after_sign_in_path_for(resource)
    # Check if we're on the app subdomain
    if request.subdomain == 'app'
      # First check if user needs onboarding
      unless resource.onboarded?
        return onboarding_path
      end
      
      # User is onboarded, proceed with entity logic
      if resource.entities.count == 1
        # Set the entity in session and go to dashboard
        session[:entity_id] = resource.entities.first.id
        root_path
      elsif resource.entities.any?
        # User has multiple entities, let them choose
        entities_path
      else
        # User has no entities, create one
        new_entity_path
      end
    else
      # Not on app subdomain, go to app subdomain root
      app_url = root_url(subdomain: 'app')
      app_url
    end
  end
  
  # Helper to determine if we're on the app subdomain
  def app_subdomain?
    request.subdomain == 'app'
  end
  
  # Debug action to check user status without redirects (add this to routes as needed)
  def debug_user_status
    skip_before_action :check_onboarding_status
    
    render json: {
      user_id: current_user&.id,
      user_email: current_user&.email,
      onboarded: current_user&.onboarded?,
      entities_count: current_user&.entities&.count || 0,
      current_entity_id: session[:entity_id],
      has_business_profile: current_user&.business_profile&.present?,
      subdomain: request.subdomain,
      domain: request.domain,
      path: request.path,
      user_agent: request.user_agent
    }
  end
  
  private
  
  def check_onboarding_status
    return unless user_signed_in?
    return if devise_controller? && (action_name == 'destroy' || controller_name == 'sessions') # Allow logout
    return if controller_name == 'onboarding' # Don't redirect from onboarding pages
    return if controller_name == 'campaign_tracking' # Allow campaign tracking
    return if request.path.start_with?('/api/') # Skip API requests
    return if request.path == '/scout' # Don't redirect from scout path to prevent loops
    return if request.path == '/onboarding/debug_status' # Allow debug status check
    
    # Debug logging for production troubleshooting
    Rails.logger.info "🔍 Onboarding check - User: #{current_user.id}, Onboarded: #{current_user.onboarded?}, Path: #{request.path}, Domain: #{request.domain}"
    
    return if current_user.onboarded? # User has completed onboarding
    
    # Prevent redirect loops by checking if we're already being redirected to onboarding
    return if request.path == onboarding_path || request.path.start_with?('/onboarding')
    
    # Debug redirect
    Rails.logger.info "🔄 Redirecting to onboarding - User: #{current_user.id} not onboarded"
    
    # Redirect to onboarding if user hasn't completed it
    redirect_to onboarding_path
  end

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:first_name, :last_name, :role])
    devise_parameter_sanitizer.permit(:account_update, keys: [:first_name, :last_name, :role])
  end
end
