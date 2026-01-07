class Entity::BaseController < ApplicationController
  # Skip default authenticate_user! since we handle auth ourselves (supports mobile API)
  skip_before_action :authenticate_user!, raise: false

  before_action :authenticate_user_or_api!
  before_action :require_entity_admin
  layout 'customer_admin'

  private

  # Support both Devise (web) and API key (mobile) authentication
  def authenticate_user_or_api!
    token = request.headers["Authorization"]&.gsub(/^Bearer /, "")

    if token.present?
      # Mobile API authentication via api_key
      @current_user = User.find_by(api_key: token)
      unless @current_user
        respond_to do |format|
          format.html { redirect_to new_user_session_path, alert: "Please sign in" }
          format.json { render json: { error: "Invalid token" }, status: :unauthorized }
        end
      end
    else
      # Fall back to Devise session authentication (web)
      authenticate_user!
    end
  end

  def current_entity
    @current_entity ||= current_user&.entity
  end

  def require_entity_admin
    unless current_user&.entity_admin?
      respond_to do |format|
        format.html { redirect_to root_path, alert: "You must be an entity admin to access this section." }
        format.json { render json: { error: "Admin access required" }, status: :forbidden }
      end
    end
  end
end
