# Solid Queue Configuration
# This initializer is for Solid Queue configuration.
# Note: For scheduling, we use the rake task approach instead of RecurringTask.

# Add any additional Solid Queue configuration here if needed.

# Configure recurring drip campaign processing job
# Only execute this code during initialization (not during migrations)
if defined?(SolidQueue) && !($PROGRAM_NAME =~ /rake|rails\:generate|rails\:template|rails\:update|spring/)
  begin
    # Define a recurring task for the drip campaign processor
    # This will run hourly to check for due drip campaigns
    recurring_job = {
      class_name: "ProcessDripCampaignsJob",
      schedule: "0 * * * *", # Cron syntax: Run at the top of every hour
      queue: "default",
      description: "Process drip campaigns due to be sent"
    }
    
    # Create or update the recurring job in the database
    ActiveRecord::Base.connection.execute(<<~SQL)
      INSERT INTO solid_queue_recurring_tasks 
        (key, class_name, schedule, queue_name, description, created_at, updated_at, static)
      VALUES 
        ('process_drip_campaigns', '#{recurring_job[:class_name]}', '#{recurring_job[:schedule]}', 
         '#{recurring_job[:queue]}', '#{recurring_job[:description]}', NOW(), NOW(), true)
      ON CONFLICT (key) 
      DO UPDATE SET 
        class_name = '#{recurring_job[:class_name]}',
        schedule = '#{recurring_job[:schedule]}',
        queue_name = '#{recurring_job[:queue]}',
        description = '#{recurring_job[:description]}',
        updated_at = NOW();
    SQL
    
    Rails.logger.info "Configured recurring drip campaign processor job"
  rescue => e
    Rails.logger.error "Error configuring recurring tasks: #{e.message}"
  end
end 