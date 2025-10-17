require 'clockwork'
require_relative '../../config/boot'
require_relative '../../config/environment'

module Clockwork
  # Configure Clockwork
  configure do |config|
    config[:sleep_timeout] = 5      # seconds between checking for scheduled tasks
    config[:logger] = Logger.new(STDOUT)
    config[:tz] = 'UTC'             # Use UTC for consistency
  end

  # Run every hour
  every(1.hour, 'Sync active campaigns with Mailgun') do
    Rails.logger.info "Syncing active campaigns with Mailgun"
    SyncMailgunStatsJob.perform_later
  end

  # Run daily at midnight UTC
  every(1.day, 'Daily maintenance tasks', at: '00:00') do
    Rails.logger.info "Running daily maintenance tasks"
    # Add other daily tasks here
  end
end
