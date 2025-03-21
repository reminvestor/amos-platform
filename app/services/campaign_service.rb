class CampaignService
  def initialize(campaign)
    @campaign = campaign
  end
  
  # Create email deliveries for all contacts in the campaign's groups
  def prepare_email_deliveries
    # First, get all contacts from the campaign's contact groups
    contacts = @campaign.contacts
    
    # Create an email delivery for each contact
    contacts.each do |contact|
      # Skip if already exists
      next if EmailDelivery.exists?(campaign: @campaign, contact: contact)
      
      EmailDelivery.create!(
        campaign: @campaign,
        contact: contact,
        email_template: @campaign.email_template,
        status: 'pending'
      )
    end
    
    # Return the count of deliveries created
    @campaign.email_deliveries.count
  end
  
  # Process pending email deliveries
  def process_pending_deliveries(batch_size = 50)
    # Get all pending email deliveries for this campaign
    pending_deliveries = @campaign.email_deliveries.where(status: 'pending').limit(batch_size)
    
    sent_count = 0
    
    pending_deliveries.each do |delivery|
      begin
        # Send the email
        CampaignMailer.campaign_email(delivery).deliver_now
        
        # Update delivery status
        delivery.mark_as_sent
        
        sent_count += 1
      rescue => e
        # Handle errors
        delivery.mark_as_failed(e.message)
        Rails.logger.error("Failed to send email to #{delivery.contact.email}: #{e.message}")
      end
    end
    
    sent_count
  end
  
  # Start a campaign
  def start_campaign
    # Prepare deliveries if needed
    prepare_email_deliveries if @campaign.email_deliveries.empty?
    
    # Update campaign status
    @campaign.update(status: 'in_progress')
    
    # Schedule the job to process emails
    ProcessCampaignJob.perform_later(@campaign.id)
  end
  
  # Schedule a campaign
  def schedule_campaign(scheduled_at)
    # Prepare deliveries
    prepare_email_deliveries
    
    # Update campaign status and scheduled time
    @campaign.update(status: 'scheduled', scheduled_at: scheduled_at)
    
    # Schedule the job to process emails at the scheduled time
    ProcessCampaignJob.set(wait_until: scheduled_at).perform_later(@campaign.id)
  end
end 