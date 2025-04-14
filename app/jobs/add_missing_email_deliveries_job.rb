class AddMissingEmailDeliveriesJob < ApplicationJob
  queue_as :maintenance
  
  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user&.admin?
    
    # Log the start of the job
    Rails.logger.info("Starting AddMissingEmailDeliveriesJob by user #{user.email}")
    
    # Get all completed campaigns that have drip sequences
    campaigns_with_drips = Campaign.joins(:parent_drip_sequences)
                                  .where(status: 'completed')
                                  .distinct
    
    campaigns_with_drips.each do |campaign|
      # Get all contacts from contact groups associated with this campaign
      contact_ids = campaign.contacts.pluck(:id)
      
      # Get existing email deliveries for this campaign
      existing_deliveries = campaign.email_deliveries.pluck(:contact_id)
      
      # Find contact_ids that don't have email deliveries
      missing_contacts = contact_ids - existing_deliveries
      
      if missing_contacts.any?
        Rails.logger.info("Campaign #{campaign.id}: Found #{missing_contacts.count} contacts missing email deliveries")
        
        # Create email deliveries in batches to avoid memory issues
        missing_contacts.each_slice(1000) do |contact_batch|
          deliveries = contact_batch.map do |contact_id|
            {
              campaign_id: campaign.id,
              contact_id: contact_id,
              status: 'delivered',
              sent_at: campaign.updated_at,
              created_at: Time.current,
              updated_at: Time.current
            }
          end
          
          EmailDelivery.insert_all(deliveries)
        end
        
        Rails.logger.info("Campaign #{campaign.id}: Added #{missing_contacts.count} email deliveries")
      end
    end
    
    Rails.logger.info("Completed AddMissingEmailDeliveriesJob by user #{user.email}")
  end
end 