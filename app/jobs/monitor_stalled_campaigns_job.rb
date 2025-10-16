class MonitorStalledCampaignsJob < ApplicationJob
  queue_as :monitoring

  def perform(auto_resume: false, notification_email: nil)
    Rails.logger.info("Starting stalled campaign monitoring job")

    # Find campaigns that appear to be stalled
    stalled_campaigns = Campaign.potentially_stalled.includes(:email_deliveries, :user)

    if stalled_campaigns.empty?
      Rails.logger.info("No stalled campaigns found")
      return
    end

    Rails.logger.info("Found #{stalled_campaigns.count} potentially stalled campaigns")

    stalled_info = []
    resumed_count = 0

    stalled_campaigns.each do |campaign|
      # Double-check with the instance method
      next unless campaign.stalled?

      stall_details = campaign.stall_info
      campaign_info = {
        id: campaign.id,
        name: campaign.name,
        user_email: campaign.user.email,
        pending_count: stall_details[:pending_count],
        stalled_for: stall_details[:stalled_for],
        last_activity: stall_details[:last_activity]
      }

      stalled_info << campaign_info

      Rails.logger.warn("Stalled campaign detected: #{campaign.name} (ID: #{campaign.id}) - " \
                       "#{stall_details[:pending_count]} pending emails, " \
                       "inactive for #{time_duration_in_words(stall_details[:stalled_for])}")

      # Auto-resume if enabled
      if auto_resume
        begin
          # Sync with Mailgun first
          campaign.sync_mailgun_stats

          # Check if there are still pending deliveries after sync
          if campaign.pending_deliveries_count > 0
            # Reset failed deliveries to pending for retry
            failed_count = campaign.email_deliveries.where(status: "failed").count
            if failed_count > 0
              campaign.email_deliveries.where(status: "failed").update_all(
                status: "pending",
                error_message: nil
              )
              Rails.logger.info("Reset #{failed_count} failed deliveries to pending for campaign #{campaign.id}")
            end

            # Resume the campaign
            service = CampaignService.new(campaign)
            service.resume_campaign

            resumed_count += 1
            Rails.logger.info("Auto-resumed stalled campaign: #{campaign.name} (ID: #{campaign.id})")
          else
            # No pending deliveries, mark as completed
            campaign.update(status: "completed")
            Rails.logger.info("Marked completed campaign with no pending deliveries: #{campaign.name} (ID: #{campaign.id})")
          end
        rescue => e
          Rails.logger.error("Failed to auto-resume campaign #{campaign.id}: #{e.message}")
        end
      end
    end

    # Send notification email if specified
    if notification_email.present? && stalled_info.any?
      send_stalled_campaigns_notification(notification_email, stalled_info, resumed_count, auto_resume)
    end

    Rails.logger.info("Stalled campaign monitoring completed. " \
                     "Found: #{stalled_info.count}, " \
                     "Auto-resumed: #{resumed_count}")
  end

  private

  def time_duration_in_words(duration_in_seconds)
    hours = (duration_in_seconds / 1.hour).to_i
    minutes = ((duration_in_seconds % 1.hour) / 1.minute).to_i

    if hours > 0
      "#{hours} hour#{'s' if hours != 1}#{minutes > 0 ? " and #{minutes} minute#{'s' if minutes != 1}" : ''}"
    else
      "#{minutes} minute#{'s' if minutes != 1}"
    end
  end

  def send_stalled_campaigns_notification(email, stalled_info, resumed_count, auto_resume)
    # This would send an email notification about stalled campaigns
    # You could create a mailer for this or use a simple notification service
    Rails.logger.info("Would send stalled campaigns notification to #{email} " \
                     "(#{stalled_info.count} stalled, #{resumed_count} resumed)")

    # Example: AdminMailer.stalled_campaigns_alert(email, stalled_info, resumed_count, auto_resume).deliver_now
  end
end
