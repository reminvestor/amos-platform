class ProcessCampaignJob < ApplicationJob
  include JobErrorHandling

  queue_as :default

  # Ensure we're using the correct queue
  def self.queue_name
    "default"
  end

  def perform(campaign_id, batch_size = 200, correlation_id = nil)
    # Build a context prefix for all log messages in this job
    log_context = "[ProcessCampaignJob][Campaign##{campaign_id}]"
    log_context += "[#{correlation_id}]" if correlation_id.present?

    Rails.logger.info("#{log_context} starting for campaign #{campaign_id}")
    Rails.logger.info("#{log_context} Job ID: #{provider_job_id}")
    Rails.logger.info("#{log_context} Queue name: #{self.class.queue_name}")

    # Log the current process info
    begin
      process = Solid::Queue::Process.current
      Rails.logger.info("#{log_context} Running in process: #{process.id} (#{process.type})")
    rescue => e
      Rails.logger.error("#{log_context} Error getting process info: #{e.message}")
    end

    campaign = Campaign.find_by(id: campaign_id)
    if campaign.nil?
      raise ArgumentError, "Campaign #{campaign_id} not found"
    end

    # Skip if campaign is not active
    unless [ "scheduled", "in_progress" ].include?(campaign.status)
      Rails.logger.info("#{log_context} Campaign #{campaign_id} is not active (status: #{campaign.status})")
      return
    end

    # If scheduled but not yet time to run
    if campaign.status == "scheduled" && campaign.scheduled_at > Time.current
      Rails.logger.info("#{log_context} Campaign #{campaign_id} is scheduled for #{campaign.scheduled_at}, rescheduling")
      # Re-schedule for later
      self.class.set(wait_until: campaign.scheduled_at).perform_later(campaign_id, batch_size, correlation_id)
      return
    end

    # Update status to in_progress if it was scheduled
    if campaign.status == "scheduled"
      Rails.logger.info("#{log_context} Updating campaign #{campaign_id} status to in_progress")
      unless campaign.update(status: "in_progress")
        error_message = campaign.errors.full_messages.join(", ")
        Rails.logger.error("#{log_context} Failed to update campaign status to in_progress: #{error_message}")
        raise ActiveRecord::RecordInvalid, "Failed to update campaign: #{error_message}"
      end
    end

    # Log campaign processing start
    Rails.logger.info("#{log_context} Starting campaign processing: ID=#{campaign.id}, Name=#{campaign.name}, Batch Size=#{batch_size}")

    # Process the campaign
    service = CampaignService.new(campaign)
    sent_count = service.process_pending_deliveries(batch_size)

    # Log batch completion
    pending_count = campaign.email_deliveries.where(status: "pending").count
    Rails.logger.info("#{log_context} Campaign batch processed: ID=#{campaign.id}, Sent=#{sent_count}, Remaining=#{pending_count}")

    # If there are more emails to send, schedule another job
    if pending_count > 0
      Rails.logger.info("#{log_context} Scheduling next batch for campaign #{campaign.id}")
      self.class.set(wait: 1.minute).perform_later(campaign_id, batch_size, correlation_id)
    else
      # Mark as completed if all emails have been processed
      Rails.logger.info("#{log_context} Campaign #{campaign.id} completed - all emails processed")
      unless campaign.update(status: "completed")
        error_message = campaign.errors.full_messages.join(", ")
        Rails.logger.error("#{log_context} Failed to update campaign status to completed: #{error_message}")
        raise ActiveRecord::RecordInvalid, "Failed to update campaign: #{error_message}"
      end
    end

    Rails.logger.info("#{log_context} ProcessCampaignJob finished for campaign #{campaign_id}")
  end
end
