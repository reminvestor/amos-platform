# Solid Queue Configuration
# This initializer is for Solid Queue configuration.

# Configure logging for Solid Queue workers
if defined?(SolidQueue)
  # Set the logger for Solid Queue to use Rails logger
  SolidQueue.logger = Rails.logger
  Rails.logger.info "SolidQueue: Initialized with Rails logger"
end

# NOTE: Recurring tasks are configured directly in lib/tasks/solid_queue.rake
# when creating the Dispatcher. SolidQueue 0.3.x expects recurring tasks to be 
# passed to the Dispatcher constructor, not stored in the database.
#
# The recurring tasks are:
# - scheduled_task_dispatcher: Every minute - checks for due scheduled agent tasks
# - process_drip_campaigns: Every hour - processes drip campaigns
# - visualization_refresh: Every 15 minutes - refreshes auto-refresh visualizations
# - cleanup_temporary_uploads: Every hour - cleans up temp files
# - agent_energy_regeneration: Every hour - regenerates agent energy
