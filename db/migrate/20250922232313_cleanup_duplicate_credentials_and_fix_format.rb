class CleanupDuplicateCredentialsAndFixFormat < ActiveRecord::Migration[8.0]
  def up
    # First, fix the format of existing credentials
    IntegrationCredential.find_each do |cred|
      # Access the raw database value, not the parsed value from our getter
      raw_credentials = cred.read_attribute(:credentials)
      next if raw_credentials.blank?
      
      begin
        # Try to parse as JSON first
        parsed = JSON.parse(raw_credentials)
        # If it parses successfully, we're good
        next
      rescue JSON::ParserError
        # It's not valid JSON, try to fix it
        begin
          # Evaluate the Ruby hash string
          hash = eval(raw_credentials)
          # Convert to proper JSON
          cred.update_column(:credentials, hash.to_json)
          puts "Fixed credentials format for IntegrationCredential ##{cred.id}"
        rescue => e
          puts "Could not fix IntegrationCredential ##{cred.id}: #{e.message}"
        end
      end
    end
    
    # Now clean up duplicates - keep only the most recent active credential per connection
    Connection.find_each do |connection|
      active_credentials = connection.integration_credentials.active.order(created_at: :desc)
      
      if active_credentials.count > 1
        # Keep the first (most recent) one
        keeper = active_credentials.first
        duplicates = active_credentials.offset(1)
        
        puts "Connection ##{connection.id} has #{active_credentials.count} active credentials"
        puts "Keeping credential ##{keeper.id}, deactivating #{duplicates.count} duplicates"
        
        # Deactivate duplicates
        duplicates.update_all(status: IntegrationCredential.statuses[:expired])
      end
    end
  end
  
  def down
    # This migration is not reversible
    raise ActiveRecord::IrreversibleMigration
  end
end