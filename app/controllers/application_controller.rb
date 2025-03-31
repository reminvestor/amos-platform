class ApplicationController < ActionController::Base
  # Include the entity scoped functionality
  include EntityScoped
  
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  
  # Require authentication for all controllers except API ones
  # Note: API controllers will override this with skip_before_action
  before_action :authenticate_user!, unless: :api_request?
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
      # If user has entities, go to dashboard or entities page
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
  
  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:first_name, :last_name, :role])
    devise_parameter_sanitizer.permit(:account_update, keys: [:first_name, :last_name, :role])
  end
end
