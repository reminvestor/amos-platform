class CampaignService
  def initialize(campaign)
    @campaign = campaign
  end

  # Create email deliveries for all contacts in the campaign's groups
  def prepare_email_deliveries
    Rails.logger.info("Campaign #{@campaign.id}: Preparing email deliveries with BULK INSERT")
    
    # Get all contacts from the campaign's contact groups
    contacts = @campaign.contacts
    active_contacts = contacts.where(opted_out: false)
    
    # Store count of opted-out contacts for the warning
    opted_out_count = contacts.count - active_contacts.count
    @campaign.update(opted_out_contacts_count: opted_out_count) if @campaign.respond_to?(:opted_out_contacts_count)
    
    # Get all contact IDs from campaign's contact groups
    contact_ids = active_contacts.pluck(:id)
    
    Rails.logger.info("Campaign #{@campaign.id}: Found #{contact_ids.count} active contacts")
    
    # Get existing delivery contact_ids in ONE query
    existing_contact_ids = @campaign.email_deliveries.pluck(:contact_id)
    
    # Find contacts that need deliveries (set difference - O(n) not O(n²)!)
    missing_contact_ids = contact_ids - existing_contact_ids
    
    Rails.logger.info("Campaign #{@campaign.id}: Need to create #{missing_contact_ids.count} new deliveries")
    
    if missing_contact_ids.any?
      
      if missing_contact_ids.count > 50_000
        Rails.logger.info("Campaign #{@campaign.id}: Large campaign detected (#{missing_contact_ids.count} contacts), creating deliveries in background")
        # Create a job to handle the bulk insert
        CreateEmailDeliveriesJob.perform_later(@campaign.id, missing_contact_ids)
        return @campaign.email_deliveries.count
      end
      
      # Build delivery records for bulk insert
      timestamp = Time.current
      deliveries_data = missing_contact_ids.map do |contact_id|
        {
          campaign_id: @campaign.id,
          contact_id: contact_id,
          email_template_id: @campaign.email_template_id,
          status: 'pending',
          created_at: timestamp,
          updated_at: timestamp
        }
      end
      
      # Bulk insert in smaller batches to avoid timeouts
      batch_size = missing_contact_ids.count > 10_000 ? 1_000 : 10_000
      deliveries_data.each_slice(batch_size) do |batch|
        EmailDelivery.insert_all(batch)
        Rails.logger.info("Campaign #{@campaign.id}: Inserted batch of #{batch.size} deliveries")
        
        # Add small delay for large campaigns to prevent timeouts
        if missing_contact_ids.count > 10_000
          sleep(0.1)
        end
      end
      
      Rails.logger.info("Campaign #{@campaign.id}: ✅ Created #{missing_contact_ids.count} deliveries via BULK INSERT")
    end
    
    # Return the total count
    total_count = @campaign.email_deliveries.count
    Rails.logger.info("Campaign #{@campaign.id}: Total deliveries: #{total_count}")
    total_count
  end

  # Process pending email deliveries
  def process_pending_deliveries(batch_size = 200)
    return 0 unless @campaign.status == "in_progress"

    Rails.logger.info("Processing pending deliveries for campaign #{@campaign.id}: #{@campaign.name}")

    # Get pending deliveries with rate limiting
    pending_deliveries = @campaign.email_deliveries
      .where(status: "pending")
      .includes(:contact)
      .limit(batch_size)

    sent_count = 0
    error_count = 0

    pending_deliveries.each do |delivery|
      begin
        # Check if campaign was stopped
        @campaign.reload
        if @campaign.status != "in_progress"
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
        delivery.update(status: "failed", error_message: e.message)
      end
    end

    # Log final batch results
    Rails.logger.info("Campaign #{@campaign.id} batch complete: #{sent_count} sent, #{error_count} errors")

    sent_count
  end

  def stop_campaign
    Rails.logger.info("Stopping campaign #{@campaign.id}: #{@campaign.name}")

    # Update campaign status
    @campaign.update(status: "stopped")

    # Cancel any pending jobs
    cancel_scheduled_jobs

    Rails.logger.info("Campaign #{@campaign.id} stopped successfully")
  end

  def pause_campaign
    Rails.logger.info("Pausing campaign #{@campaign.id}: #{@campaign.name}")

    # Update campaign status
    @campaign.update(status: "paused")

    # Cancel any pending jobs
    cancel_scheduled_jobs

    Rails.logger.info("Campaign #{@campaign.id} paused successfully")
  end

  def resume_campaign
    Rails.logger.info("Resuming campaign #{@campaign.id}: #{@campaign.name}")

    # Update campaign status
    @campaign.update(status: "in_progress")

    # Schedule a new job to process pending deliveries
    ProcessCampaignJob.perform_later(@campaign.id)
    Rails.logger.info("Scheduled new job for campaign #{@campaign.id}")
  end

  # Start a campaign
  def start_campaign
    Rails.logger.info("Starting campaign #{@campaign.id}: #{@campaign.name}")

    # Prepare deliveries if needed
    if @campaign.email_deliveries.empty?
      Rails.logger.info("Preparing email deliveries for campaign #{@campaign.id}")
      prepare_email_deliveries
    end

    # Update campaign status
    Rails.logger.info("Updating campaign #{@campaign.id} status to in_progress")
    @campaign.update(status: "in_progress")

    # Schedule the job to process emails
    Rails.logger.info("Queuing ProcessCampaignJob for campaign #{@campaign.id}")
    job = ProcessCampaignJob.perform_later(@campaign.id)
    Rails.logger.info("ProcessCampaignJob queued with ID: #{job.provider_job_id}")

    # Log the current queue status
    begin
      # Check jobs table
      job_count = SolidQueue::Job.count
      Rails.logger.info("Current SolidQueue job count: #{job_count}")

      # Check if our specific job exists
      if job.provider_job_id
        job_record = SolidQueue::Job.find_by(id: job.provider_job_id)
        if job_record
          Rails.logger.info("Found job in database with status: #{job_record.status}")
        else
          Rails.logger.error("Job not found in database despite being queued!")
        end
      end

      # Check processes
      process_count = SolidQueue::Process.count
      Rails.logger.info("Current SolidQueue process count: #{process_count}")

      # Check dispatchers
      dispatcher_count = SolidQueue::Process.where(type: "Dispatcher").count
      Rails.logger.info("Current dispatcher count: #{dispatcher_count}")

      # Check workers
      worker_count = SolidQueue::Process.where(type: "Worker").count
      Rails.logger.info("Current worker count: #{worker_count}")
    rescue => e
      Rails.logger.error("Error checking queue status: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
    end
  end

  # Schedule a campaign
  def schedule_campaign(scheduled_at)
    # Prepare deliveries
    prepare_email_deliveries

    # Update campaign status and scheduled time
    @campaign.update(status: "scheduled", scheduled_at: scheduled_at)

    # Schedule the job to process emails at the scheduled time
    ProcessCampaignJob.set(wait_until: scheduled_at).perform_later(@campaign.id)
  end

  private

  def process_and_send_email(delivery)
    Rails.logger.info("Processing email delivery #{delivery.id} for contact #{delivery.contact.email}")

    # Send the email using the mailer
    mail_message = CampaignMailer.campaign_email(delivery).deliver_now

    # Try to get the message ID from the response
    # AWS SDK Rails adapter should put the message ID in the message object after delivery
    ses_message_id = mail_message.message_id

    # Mark as sent and save SES message ID
    delivery.update(
      status: "sent", 
      sent_at: Time.current,
      ses_message_id: ses_message_id
    )

    Rails.logger.info("Successfully sent email delivery #{delivery.id} (SES ID: #{ses_message_id})")
  end

  def cancel_scheduled_jobs
    # Look for campaign jobs in SolidQueue
    # Implementation depends on queue adapter (SolidQueue in this case)
    # This is tricky because finding scheduled jobs by args is not straightforward
    # in all queue backends. For now, we rely on status check in perform.
  end
end
