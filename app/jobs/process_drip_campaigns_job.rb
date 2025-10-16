class ProcessDripCampaignsJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "Starting drip campaign processing job"

    # Find all active drip campaigns that are due to be processed
    due_drips = DrippedCampaign.where(active: true)
                              .where("scheduled_at <= ?", Time.current)

    if due_drips.empty?
      Rails.logger.info "No drip campaigns are due for processing."
      return
    end

    processed_count = 0
    error_count = 0

    due_drips.each do |drip|
      begin
        # Check if original campaign is completed (a requirement for processing)
        if [ "completed", "in_progress" ].include?(drip.original_campaign.status)
          Rails.logger.info "Processing drip campaign: #{drip.id} (#{drip.original_campaign.name} → follow-up #{drip.sequence_position})"

          # Create the next follow-up
          new_campaign = drip.create_next_follow_up!

          if new_campaign
            Rails.logger.info "Created follow-up campaign: #{new_campaign.id}"
            processed_count += 1

            # Mark this drip as processed (deactivate it)
            drip.update(active: false)
          else
            Rails.logger.info "No follow-up needed for drip #{drip.id} (no matching contacts)"
            # Mark as processed even though no campaign was created
            drip.update(active: false)
          end
        else
          Rails.logger.info "Skipping drip #{drip.id} - original campaign is not completed/in progress (status: #{drip.original_campaign.status})"
        end
      rescue => e
        Rails.logger.error "Error processing drip #{drip.id}: #{e.message}"
        error_count += 1
      end
    end

    Rails.logger.info "Drip processing complete. Processed: #{processed_count}, Errors: #{error_count}"
  end
end
