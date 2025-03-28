module EntityScoped
  extend ActiveSupport::Concern
  
  included do
    before_action :set_current_entity
    helper_method :current_entity if respond_to?(:helper_method)
  end
  
  protected
  
  # Ensure we have a current entity selected
  def check_subdomain
    return if controller_path.start_with?('marketing')
    
    # Redirect to entity selection if no entity is selected and we're on the dashboard
    if controller_path == 'home' && action_name == 'index' && !current_entity
      # If user has no entities, redirect to entity creation
      if user_signed_in? && current_user.entities.none?
        redirect_to new_entity_path
      elsif user_signed_in? && current_user.entities.count > 1
        # If user has multiple entities but none selected, redirect to entity selection
        redirect_to entities_path, notice: "Please select an entity to work with."
      end
    end
  end
  
  # Determine the current entity from the session
  def current_entity
    @current_entity ||= begin
      if session[:entity_id].present? && current_user
        # Try to find entity by session
        entity = current_user.entities.find_by(id: session[:entity_id])
        entity
      elsif current_user && current_user.entities.count == 1
        # Default to the user's only entity
        entity = current_user.entities.first
        session[:entity_id] = entity.id
        entity
      end
    end
  end
  
  def set_current_entity
    # Skip entity check for public routes, marketing, devise, and entities controller
    return if !user_signed_in? || 
              controller_path.start_with?('marketing') || 
              controller_path.start_with?('devise') || 
              controller_path == 'entities'
              
    # Make sure we have a current entity for authenticated app routes
    unless current_entity.present?
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