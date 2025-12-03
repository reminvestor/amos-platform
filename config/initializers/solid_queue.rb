# Solid Queue Configuration
# This initializer is for Solid Queue configuration.
# Note: For scheduling, we use the rake task approach instead of RecurringTask.

# Configure logging for Solid Queue workers
if defined?(SolidQueue)
  # Set the logger for Solid Queue to use Rails logger
  SolidQueue.logger = Rails.logger

  # Log when SolidQueue is loaded
  Rails.logger.info "SolidQueue: Initialized with Rails logger"
end

# Add any additional Solid Queue configuration here if needed.

# Configure recurring jobs
# Only execute this code during initialization (not during migrations)
if defined?(SolidQueue) && !($PROGRAM_NAME =~ /rake|rails\:generate|rails\:template|rails\:update|spring/)
  begin
    # Define recurring tasks
    recurring_jobs = [
      {
        key: "process_drip_campaigns",
        class_name: "ProcessDripCampaignsJob",
        schedule: "0 * * * *", # Run at the top of every hour
        queue: "default",
        description: "Process drip campaigns due to be sent"
      },
      {
        key: "scheduled_task_dispatcher",
        class_name: "ScheduledTaskDispatcherJob",
        schedule: "* * * * *", # Run every minute
        queue: "default",
        description: "Check for due scheduled tasks and dispatch them"
      },
      {
        key: "visualization_refresh",
        class_name: "RefreshVisualizationsJob",
        schedule: "*/15 * * * *", # Run every 15 minutes
        queue: "maintenance",
        description: "Refresh auto-refresh visualizations"
      },
      {
        key: "cleanup_temporary_uploads",
        class_name: "CleanupTemporaryUploadsJob",
        schedule: "0 * * * *", # Run every hour
        queue: "maintenance",
        description: "Clean up temporary upload files"
      },
      {
        key: "agent_energy_regeneration",
        class_name: "EnergyRegenerationJob",
        schedule: "0 * * * *", # Run every hour
        queue: "agents",
        description: "Regenerate energy for all agents"
      }
    ]

    recurring_jobs.each do |job|
      ActiveRecord::Base.connection.execute(<<~SQL)
        INSERT INTO solid_queue_recurring_tasks
          (key, class_name, schedule, queue_name, description, created_at, updated_at, static)
        VALUES
          ('#{job[:key]}', '#{job[:class_name]}', '#{job[:schedule]}',
           '#{job[:queue]}', '#{job[:description]}', NOW(), NOW(), true)
        ON CONFLICT (key)
        DO UPDATE SET
          class_name = '#{job[:class_name]}',
          schedule = '#{job[:schedule]}',
          queue_name = '#{job[:queue]}',
          description = '#{job[:description]}',
          updated_at = NOW();
      SQL
    end

    Rails.logger.info "Configured #{recurring_jobs.size} recurring jobs including ScheduledTaskDispatcherJob"
  rescue => e
    Rails.logger.error "Error configuring recurring tasks: #{e.message}"
  end
end
