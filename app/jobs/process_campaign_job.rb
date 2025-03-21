class ProcessCampaignJob < ApplicationJob
  queue_as :default

  def perform(campaign_id, batch_size = 50)
    campaign = Campaign.find_by(id: campaign_id)
    return unless campaign
    
    # Skip if campaign is not active
    return unless ['scheduled', 'in_progress'].include?(campaign.status)
    
    # If scheduled but not yet time to run
    if campaign.status == 'scheduled' && campaign.scheduled_at > Time.current
      # Re-schedule for later
      self.class.set(wait_until: campaign.scheduled_at).perform_later(campaign_id, batch_size)
      return
    end
    
    # Update status to in_progress if it was scheduled
    campaign.update(status: 'in_progress') if campaign.status == 'scheduled'
    
    # Process the campaign
    service = CampaignService.new(campaign)
    sent_count = service.process_pending_deliveries(batch_size)
    
    # If there are more emails to send, schedule another job
    if campaign.email_deliveries.where(status: 'pending').exists?
      self.class.set(wait: 1.minute).perform_later(campaign_id, batch_size)
    else
      # Mark as completed if all emails have been processed
      campaign.update(status: 'completed')
    end
  end
end
