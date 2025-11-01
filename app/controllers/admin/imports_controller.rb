module Admin
  class ImportsController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_admin

    def index
    end

    def elearning
      # Start the import in a background job to avoid timeout
      ImportUsersJob.perform_later(current_user.id)

      redirect_to admin_imports_path, notice: "Import from eLearning platform has been started. This may take some time."
    end

    private

    def ensure_admin
      unless current_user&.admin?
        redirect_to chat_mode_path, alert: "You don't have permission to access this page."
      end
    end
  end
end
