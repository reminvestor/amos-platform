module Admin
  class ImportsController < Admin::BaseController

    def index
    end

    def elearning
      # Start the import in a background job to avoid timeout
      ImportUsersJob.perform_later(current_user.id)

      redirect_to admin_imports_path, notice: "Import from eLearning platform has been started. This may take some time."
    end
  end
end
