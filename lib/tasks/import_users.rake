namespace :import do
  desc "Import users from main eLearning application API"
  task users: :environment do
    require 'uri'
    require 'net/http'
    require 'json'
    
    # Create an instance of the import service
    service = ElearningImportService.new
    
    # Run the import
    service.import_users
  end
end 