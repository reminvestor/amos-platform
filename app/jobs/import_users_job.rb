class ImportUsersJob < ApplicationJob
  queue_as :default

  def perform(admin_user_id)
    admin_user = User.find(admin_user_id)
    
    # Create an instance of the import service
    service = ElearningImportService.new(admin_user: admin_user)
    
    # Run the import
    result = service.import_users
    
    # Notify admin of completion
    # In a real app, you might want to send an email or notification
    Rails.logger.info "Import completed with the following results: #{result.inspect}"
  end
end 