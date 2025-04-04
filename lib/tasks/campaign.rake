namespace :campaign do
  desc "Retry failed email deliveries for a campaign"
  task :retry_failed_deliveries, [:campaign_id] => :environment do |t, args|
    if args[:campaign_id].blank?
      puts "Please provide a campaign ID"
      puts "Usage: rake campaign:retry_failed_deliveries[campaign_id]"
      exit 1
    end

    campaign = Campaign.find(args[:campaign_id])
    puts "Campaign status: #{campaign.status}"
    
    # Temporarily change campaign status if it's completed
    original_status = campaign.status
    if original_status == 'completed'
      puts "Temporarily changing campaign status from 'completed' to 'in_progress'"
      campaign.update(status: 'in_progress')
    end
    
    # Only include failed status
    failed_deliveries = campaign.email_deliveries.where(status: 'failed')
    
    if failed_deliveries.empty?
      puts "No failed deliveries found for campaign #{campaign.id}"
      
      # Restore original status
      if original_status == 'completed'
        campaign.update(status: original_status)
        puts "Restored campaign status to 'completed'"
      end
      
      exit 0
    end

    puts "Found #{failed_deliveries.count} failed deliveries for campaign #{campaign.id}"
    
    # Reset failed deliveries to pending
    failed_deliveries.update_all(status: 'pending', error_message: nil)
    
    # Queue a new job to process the pending deliveries
    job = ProcessCampaignJob.perform_later(campaign.id)
    
    puts "Reset #{failed_deliveries.count} deliveries to pending and queued new job"
    puts "Job ID: #{job.job_id}"
    
    # Note: We don't restore the status to completed here,
    # as the ProcessCampaignJob may need to process the campaign
    puts "Note: Campaign status is now 'in_progress' to allow processing"
  end
end 