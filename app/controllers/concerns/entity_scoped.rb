module EntityScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_current_entity
    before_action :set_rls_context
    after_action :reset_rls_context
    helper_method :current_entity if respond_to?(:helper_method)
    helper_method :current_entity_user if respond_to?(:helper_method)
  end

  protected

  # Ensure we have a current entity selected
  def check_subdomain
    return if controller_path.start_with?("marketing")

    # Redirect to entity creation if no entity is selected and we're on the dashboard
    if controller_path == "home" && action_name == "index" && !current_entity
      # If user has no entity, redirect to entity creation
      if user_signed_in? && !current_user.entity
        redirect_to new_entity_path
      end
    end
  end

  # Determine the current entity from the user
  def current_entity
    @current_entity ||= current_user&.entity
  end

  # Get the current user's EntityUser record for the current entity
  def current_entity_user
    return nil unless current_user && current_entity
    @current_entity_user ||= EntityUser.find_by(user: current_user, entity: current_entity)
  end

  def set_current_entity
    # Skip entity check for public routes, marketing, devise, entities, and hub controllers
    return if !user_signed_in? ||
              controller_path.start_with?("marketing") ||
              controller_path.start_with?("devise") ||
              controller_path == "entities" ||
              controller_path == "hub"

    # Ensure user is in entity_users table (handles legacy users)
    if current_user.entity_id.present?
      current_user.ensure_entity_membership
    end

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

    unless current_user.entity_admin?
      redirect_to root_path, alert: "You don't have permission to manage this entity."
    end
  end

  # Set RLS context for PostgreSQL Row-Level Security (Story 0.7)
  # Uses session-scoped SET (not SET LOCAL) so context persists across queries
  def set_rls_context
    if current_entity
      ActiveRecord::Base.connection.execute(
        "SET app.current_entity_id = '#{current_entity.id.to_i}'"
      )
    end
  rescue => e
    Rails.logger.error "SECURITY: Failed to set RLS context: #{e.message}"
    raise e if Rails.env.production?
  end

  # Clean up RLS context after each request to prevent leaking between requests
  def reset_rls_context
    ActiveRecord::Base.connection.execute("RESET app.current_entity_id")
  rescue => e
    Rails.logger.error "SECURITY: Failed to reset RLS context: #{e.message}"
  end
end
