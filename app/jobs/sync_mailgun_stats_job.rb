class SyncMailgunStatsJob < ApplicationJob
  queue_as :default

  def perform(campaign_id = nil)
    service = MailgunService.new

    if campaign_id.present?
      # Sync a specific campaign
      campaign = Campaign.find_by(id: campaign_id)
      return unless campaign

      Rails.logger.info "Syncing Mailgun stats for campaign #{campaign.id} (#{campaign.name})"
      service.sync_campaign_stats(campaign)
    else
      # Sync all active campaigns
      active_campaigns = Campaign.where(status: [ "scheduled", "in_progress" ]).where.not(mailgun_tag: nil)
      Rails.logger.info "Syncing Mailgun stats for #{active_campaigns.count} active campaigns"

      active_campaigns.find_each do |campaign|
        service.sync_campaign_stats(campaign)
      end

      # Also sync recently completed campaigns (completed within the last 7 days)
      recent_campaigns = Campaign.where(status: "completed")
                                .where("updated_at > ?", 7.days.ago)
                                .where.not(mailgun_tag: nil)

      Rails.logger.info "Syncing Mailgun stats for #{recent_campaigns.count} recent campaigns"
      recent_campaigns.find_each do |campaign|
        service.sync_campaign_stats(campaign)
      end
    end
  end
end
