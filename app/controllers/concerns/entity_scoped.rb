module EntityScoped
  extend ActiveSupport::Concern
  
  included do
    before_action :set_current_entity
    helper_method :current_entity if respond_to?(:helper_method)
  end
  
  protected
  
  # Get clean subdomain without any possible parent domains
  def extract_subdomain
    return nil unless request.subdomain.present?
    
    # Handle possible nested subdomains
    subdomain = request.subdomain.split('.')
    subdomain.first # Return just the first part
  end
  
  # Check if the request is using a valid subdomain
  def using_subdomain?
    subdomain = extract_subdomain
    subdomain.present? && subdomain != 'www'
  end
  
  # Ensure the subdomain is valid for authenticated users
  def check_subdomain
    return if controller_path.start_with?('marketing') || !using_subdomain?
    
    # Redirect to marketing site if accessing authenticated routes without subdomain
    if controller_path == 'home' && action_name == 'index' && !current_entity
      # If user has no entities, create one
      if user_signed_in? && current_user.entities.none?
        # Redirect to entity creation
        redirect_to new_entity_path
      end
    end
  end
  
  # Determine the current entity from the session or subdomain
  def current_entity
    @current_entity ||= begin
      if session[:entity_id].present? && current_user
        current_user.entities.find_by(id: session[:entity_id])
      elsif using_subdomain? && current_user
        # Try to find entity by subdomain
        subdomain = extract_subdomain
        entity = Entity.find_by(subdomain: subdomain)
        if entity && current_user.entities.include?(entity)
          session[:entity_id] = entity.id
          entity
        elsif current_user.entities.count == 1
          # Default to the user's only entity
          entity = current_user.entities.first
          session[:entity_id] = entity.id
          entity
        end
      end
    end
  end
  
  def set_current_entity
    # Make sure we have a current entity, or redirect to entity selection
    unless current_entity.present? || controller_path == 'entities'
      redirect_to entities_path, notice: "Please select an entity to work with."
    end
  end
  
  # Define a method to scope resources by the current entity
  def entity_scope(resource_class)
    if current_entity
      resource_class.where(entity_id: current_entity.id)
    else
      resource_class.none
    end
  end
  
  # Use this to require ownership or admin role on the current entity
  def require_entity_admin
    return unless current_entity
    
    unless current_user.entity_admin?(current_entity)
      redirect_to root_path, alert: "You don't have permission to manage this entity."
    end
  end
end 