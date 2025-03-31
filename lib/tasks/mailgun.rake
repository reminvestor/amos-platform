namespace :mailgun do
  desc "Sync campaign statistics from Mailgun"
  task sync_stats: :environment do
    puts "Starting Mailgun stats sync for all active campaigns..."
    
    # Queue the sync job
    SyncMailgunStatsJob.perform_later
    
    puts "Sync job has been queued!"
  end
  
  desc "Sync a specific campaign's statistics from Mailgun"
  task :sync_campaign, [:campaign_id] => :environment do |t, args|
    campaign_id = args[:campaign_id]
    
    unless campaign_id.present?
      puts "Error: Campaign ID is required. Usage: rake mailgun:sync_campaign[123]"
      exit 1
    end
    
    campaign = Campaign.find_by(id: campaign_id)
    
    unless campaign
      puts "Error: Campaign with ID #{campaign_id} not found"
      exit 1
    end
    
    puts "Starting Mailgun stats sync for campaign #{campaign.id} (#{campaign.name})..."
    
    # Queue the sync job
    SyncMailgunStatsJob.perform_later(campaign.id)
    
    puts "Sync job has been queued for campaign #{campaign.id}!"
  end
end 