class FixCampaignEntityIdsJob < ApplicationJob
  queue_as :maintenance
  
  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user&.admin?
    
    # Log the start of the job
    Rails.logger.info("Starting FixCampaignEntityIdsJob by user #{user.email}")
    
    # Find campaigns with nil entity_id or where entity_id doesn't match the user's entities
    campaigns_to_fix = Campaign.left_joins(:user)
                              .where('campaigns.entity_id IS NULL OR campaigns.entity_id NOT IN (SELECT entity_id FROM entity_users WHERE user_id = campaigns.user_id)')
    
    fixed_count = 0
    error_count = 0
    
    campaigns_to_fix.find_each do |campaign|
      # Find the campaign owner
      owner = campaign.user
      next unless owner
      
      # Find the owner's entity (1:1 relationship)
      primary_entity = owner.entity
      
      if primary_entity
        # Update the campaign's entity ID
        if campaign.update(entity_id: primary_entity.id)
          fixed_count += 1
          Rails.logger.info("Fixed Campaign ##{campaign.id}: Set entity_id to #{primary_entity.id} (#{primary_entity.name})")
        else
          error_count += 1
          Rails.logger.error("Error fixing Campaign ##{campaign.id}: #{campaign.errors.full_messages.join(', ')}")
        end
      else
        error_count += 1
        Rails.logger.error("Error fixing Campaign ##{campaign.id}: Owner #{owner.id} has no entities")
      end
    end
    
    Rails.logger.info("Completed FixCampaignEntityIdsJob by user #{user.email}. Fixed: #{fixed_count}, Errors: #{error_count}")
  end
end 