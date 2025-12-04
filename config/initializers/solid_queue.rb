# Solid Queue Configuration
# This initializer is for Solid Queue configuration.

# Configure logging for Solid Queue workers
if defined?(SolidQueue)
  # Set the logger for Solid Queue to use Rails logger
  SolidQueue.logger = Rails.logger
  Rails.logger.info "SolidQueue: Initialized with Rails logger"
end

# Configure recurring jobs
# Run during server/worker startup, but not during rake tasks, generators, or asset precompilation
Rails.application.config.after_initialize do
  next unless defined?(SolidQueue)
  next if $PROGRAM_NAME =~ /rake|rails\:generate|rails\:template|rails\:update|spring/
  next if Rails.env.test?
  
  # Skip during asset precompilation (no database available during Docker build)
  next if ENV['SECRET_KEY_BASE_DUMMY'].present?
  next if defined?(Rake) && Rake.application.top_level_tasks.any? { |t| t.include?('assets') }
  
  # Wait for database to be ready - wrap in rescue to handle build-time execution
  begin
    next unless ActiveRecord::Base.connection.table_exists?('solid_queue_recurring_tasks')
  rescue ActiveRecord::NoDatabaseError, PG::ConnectionBad, ActiveRecord::ConnectionNotEstablished => e
    Rails.logger.info "SolidQueue: Skipping recurring task setup (no database connection): #{e.class}"
    next
  end
  
  Rails.logger.info "SolidQueue: Configuring recurring tasks..."
  
  recurring_jobs = [
    {
      key: "scheduled_task_dispatcher",
      class_name: "ScheduledTaskDispatcherJob",
      schedule: "* * * * *", # Every minute
      queue: "default",
      description: "Check for due scheduled tasks and dispatch them"
    },
    {
      key: "process_drip_campaigns",
      class_name: "ProcessDripCampaignsJob",
      schedule: "0 * * * *", # Every hour
      queue: "default",
      description: "Process drip campaigns due to be sent"
    },
    {
      key: "visualization_refresh",
      class_name: "RefreshVisualizationsJob",
      schedule: "*/15 * * * *", # Every 15 minutes
      queue: "maintenance",
      description: "Refresh auto-refresh visualizations"
    },
    {
      key: "cleanup_temporary_uploads",
      class_name: "CleanupTemporaryUploadsJob",
      schedule: "0 * * * *", # Every hour
      queue: "maintenance",
      description: "Clean up temporary upload files"
    },
    {
      key: "agent_energy_regeneration",
      class_name: "EnergyRegenerationJob",
      schedule: "0 * * * *", # Every hour
      queue: "agents",
      description: "Regenerate energy for all agents"
    }
  ]

  begin
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
    
    count = ActiveRecord::Base.connection.execute("SELECT COUNT(*) FROM solid_queue_recurring_tasks").first["count"]
    Rails.logger.info "SolidQueue: ✅ Configured #{recurring_jobs.size} recurring tasks (#{count} total in database)"
  rescue => e
    Rails.logger.error "SolidQueue: ❌ Error configuring recurring tasks: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
  end
end
