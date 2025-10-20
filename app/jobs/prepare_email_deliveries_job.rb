class CreateEmailDeliveriesJob < ApplicationJob
  queue_as :default

  def perform(campaign_id, contact_ids)
    campaign = Campaign.find(campaign_id)
    Rails.logger.info("Background job: Preparing #{contact_ids.count} email deliveries for campaign #{campaign_id}")
    
    # Build delivery records for bulk insert
    timestamp = Time.current
    deliveries_data = contact_ids.map do |contact_id|
      {
        campaign_id: campaign_id,
        contact_id: contact_id,
        email_template_id: campaign.email_template_id,
        status: 'pending',
        created_at: timestamp,
        updated_at: timestamp
      }
    end
    
    # Insert in small batches to avoid memory issues
    deliveries_data.each_slice(1_000) do |batch|
      EmailDelivery.insert_all(batch)
      Rails.logger.info("Background job: Inserted batch of #{batch.size} deliveries for campaign #{campaign_id}")
      
      # Small delay to prevent overwhelming the database
      sleep(0.1)
    end
    
    Rails.logger.info("Background job: ✅ Completed #{contact_ids.count} deliveries for campaign #{campaign_id}")
  end
end
