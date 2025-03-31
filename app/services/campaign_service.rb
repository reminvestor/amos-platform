class CampaignService
  def initialize(campaign)
    @campaign = campaign
  end
  
  # Create email deliveries for all contacts in the campaign's groups
  def prepare_email_deliveries
    # First, get all contacts from the campaign's contact groups
    contacts = @campaign.contacts
    
    # Filter out opted-out contacts
    active_contacts = contacts.where(opted_out: false)
    
    # Store count of opted-out contacts for the warning
    opted_out_count = contacts.count - active_contacts.count
    @campaign.update(opted_out_contacts_count: opted_out_count) if @campaign.respond_to?(:opted_out_contacts_count)
    
    # Create an email delivery for each active contact
    active_contacts.each do |contact|
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
  def process_pending_deliveries(batch_size = 200)
    return 0 unless @campaign.status == 'in_progress'
    
    Rails.logger.info("Processing pending deliveries for campaign #{@campaign.id}: #{@campaign.name}")
    
    # Get pending deliveries with rate limiting
    pending_deliveries = @campaign.email_deliveries
      .where(status: 'pending')
      .includes(:contact)
      .limit(batch_size)
    
    sent_count = 0
    error_count = 0
    
    pending_deliveries.each do |delivery|
      begin
        # Check if campaign was stopped
        @campaign.reload
        if @campaign.status != 'in_progress'
          Rails.logger.info("Campaign #{@campaign.id} was stopped. Stopping processing.")
          break
        end
        
        # Process and send the email
        process_and_send_email(delivery)
        sent_count += 1
        
        # Log progress every 50 emails
        if sent_count % 50 == 0
          Rails.logger.info("Campaign #{@campaign.id} progress: #{sent_count} sent, #{error_count} errors")
        end
        
        # Add a small delay between sends to avoid rate limiting
        sleep(0.1)
      rescue StandardError => e
        error_count += 1
        Rails.logger.error("Error processing delivery #{delivery.id} for campaign #{@campaign.id}: #{e.message}")
        delivery.update(status: 'failed', error_message: e.message)
      end
    end
    
    # Log final batch results
    Rails.logger.info("Campaign #{@campaign.id} batch complete: #{sent_count} sent, #{error_count} errors")
    
    sent_count
  end
  
  def stop_campaign
    Rails.logger.info("Stopping campaign #{@campaign.id}: #{@campaign.name}")
    
    # Update campaign status
    @campaign.update(status: 'stopped')
    
    # Cancel any pending jobs
    Sidekiq::ScheduledSet.new.each do |job|
      if job.args.first == @campaign.id && job.queue == 'default'
        job.delete
        Rails.logger.info("Cancelled scheduled job for campaign #{@campaign.id}")
      end
    end
    
    Rails.logger.info("Campaign #{@campaign.id} stopped successfully")
  end
  
  def pause_campaign
    Rails.logger.info("Pausing campaign #{@campaign.id}: #{@campaign.name}")
    
    # Update campaign status
    @campaign.update(status: 'paused')
    
    # Cancel any pending jobs
    Sidekiq::ScheduledSet.new.each do |job|
      if job.args.first == @campaign.id && job.queue == 'default'
        job.delete
        Rails.logger.info("Cancelled scheduled job for campaign #{@campaign.id}")
      end
    end
    
    Rails.logger.info("Campaign #{@campaign.id} paused successfully")
  end
  
  def resume_campaign
    Rails.logger.info("Resuming campaign #{@campaign.id}: #{@campaign.name}")
    
    # Update campaign status
    @campaign.update(status: 'in_progress')
    
    # Schedule a new job to process pending deliveries
    ProcessCampaignJob.perform_later(@campaign.id)
    Rails.logger.info("Scheduled new job for campaign #{@campaign.id}")
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
