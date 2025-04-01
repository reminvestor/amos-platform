namespace :campaign do
  desc "Retry failed email deliveries for a campaign"
  task :retry_failed_deliveries, [:campaign_id] => :environment do |t, args|
    if args[:campaign_id].blank?
      puts "Please provide a campaign ID"
      puts "Usage: rake campaign:retry_failed_deliveries[campaign_id]"
      exit 1
    end

    campaign = Campaign.find(args[:campaign_id])
    failed_deliveries = campaign.email_deliveries.where(status: 'failed')
    
    if failed_deliveries.empty?
      puts "No failed deliveries found for campaign #{campaign.id}"
      exit 0
    end

    puts "Found #{failed_deliveries.count} failed deliveries for campaign #{campaign.id}"
    
    # Reset failed deliveries to pending
    failed_deliveries.update_all(status: 'pending', error_message: nil)
    
    # Queue a new job to process the pending deliveries
    ProcessCampaignJob.perform_later(campaign.id)
    
    puts "Reset #{failed_deliveries.count} deliveries to pending and queued new job"
    puts "Job ID: #{ProcessCampaignJob.last&.provider_job_id}"
  end
end 