class Entity::BaseController < ApplicationController
  before_action :authenticate_user!
  before_action :require_entity_admin
  layout 'customer_admin'
  
  private
  
  def require_entity_admin
    unless current_user.entity_admin?
      redirect_to root_path, alert: "You must be an entity admin to access this section."
    end
  end
end
