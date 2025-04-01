class ProcessCampaignJob < ApplicationJob
  queue_as :default
  
  # Ensure we're using the correct queue
  def self.queue_name
    'default'
  end

  def perform(campaign_id, batch_size = 200)
    Rails.logger.info("ProcessCampaignJob starting for campaign #{campaign_id}")
    Rails.logger.info("Job ID: #{provider_job_id}")
    Rails.logger.info("Queue name: #{self.class.queue_name}")
    
    # Log the current process info
    begin
      process = Solid::Queue::Process.current
      Rails.logger.info("Running in process: #{process.id} (#{process.type})")
    rescue => e
      Rails.logger.error("Error getting process info: #{e.message}")
    end
    
    campaign = Campaign.find_by(id: campaign_id)
    unless campaign
      Rails.logger.error("Campaign #{campaign_id} not found")
      return
    end
    
    # Skip if campaign is not active
    unless ['scheduled', 'in_progress'].include?(campaign.status)
      Rails.logger.info("Campaign #{campaign_id} is not active (status: #{campaign.status})")
      return
    end
    
    # If scheduled but not yet time to run
    if campaign.status == 'scheduled' && campaign.scheduled_at > Time.current
      Rails.logger.info("Campaign #{campaign_id} is scheduled for #{campaign.scheduled_at}, rescheduling")
      # Re-schedule for later
      self.class.set(wait_until: campaign.scheduled_at).perform_later(campaign_id, batch_size)
      return
    end
    
    # Update status to in_progress if it was scheduled
    if campaign.status == 'scheduled'
      Rails.logger.info("Updating campaign #{campaign_id} status to in_progress")
      campaign.update(status: 'in_progress')
    end
    
    # Log campaign processing start
    Rails.logger.info("Starting campaign processing: ID=#{campaign.id}, Name=#{campaign.name}, Batch Size=#{batch_size}")
    
    # Process the campaign
    service = CampaignService.new(campaign)
    sent_count = service.process_pending_deliveries(batch_size)
    
    # Log batch completion
    Rails.logger.info("Campaign batch processed: ID=#{campaign.id}, Sent=#{sent_count}, Remaining=#{campaign.email_deliveries.where(status: 'pending').count}")
    
    # If there are more emails to send, schedule another job
    if campaign.email_deliveries.where(status: 'pending').exists?
      Rails.logger.info("Scheduling next batch for campaign #{campaign.id}")
      self.class.set(wait: 1.minute).perform_later(campaign_id, batch_size)
    else
      # Mark as completed if all emails have been processed
      Rails.logger.info("Campaign #{campaign.id} completed - all emails processed")
      campaign.update(status: 'completed')
    end
  end
end
