class Entity::ObservabilityController < Entity::BaseController

  def index
    redirect_to chat_mode_path, status: :moved_permanently
  end
end
