class DashboardController < ApplicationController
  before_action :authenticate_user!

  # Advanced Mode dashboard is deprecated — redirect to Chat Mode
  def index
    redirect_to chat_mode_path, status: :moved_permanently
  end
end
