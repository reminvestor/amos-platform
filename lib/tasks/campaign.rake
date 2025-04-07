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
  
  desc "Relaunch a campaign for recipients who haven't opened the initial email"
  task :relaunch_for_unopened, [:campaign_id, :subject_prefix] => :environment do |t, args|
    if args[:campaign_id].blank?
      puts "Please provide a campaign ID"
      puts "Usage: rake campaign:relaunch_for_unopened[campaign_id,subject_prefix]"
      puts "Example: rake campaign:relaunch_for_unopened[42,\"[REMINDER] \"]"
      exit 1
    end
    
    # Default subject prefix if none provided
    subject_prefix = args[:subject_prefix] || "[REMINDER] "
    
    # Find the original campaign
    original_campaign = Campaign.find(args[:campaign_id])
    puts "Original campaign: #{original_campaign.name} (ID: #{original_campaign.id})"
    puts "Original campaign status: #{original_campaign.status}"
    
    # Find all email deliveries that haven't been opened
    unopened_deliveries = original_campaign.email_deliveries.where(opened_at: nil)
    
    if unopened_deliveries.empty?
      puts "No unopened emails found for campaign #{original_campaign.id}"
      exit 0
    end
    
    puts "Found #{unopened_deliveries.count} unopened emails out of #{original_campaign.email_deliveries.count} total"
    
    # Collect the recipient IDs (contacts) who haven't opened
    recipient_ids = unopened_deliveries.pluck(:contact_id).uniq
    puts "Creating new campaign targeting #{recipient_ids.count} unique recipients"
    
    # Create a new campaign as a follow-up
    new_campaign = original_campaign.dup
    new_campaign.name = "Follow-up: #{original_campaign.name}"
    new_campaign.subject = "#{subject_prefix}#{original_campaign.subject}"
    
    # Add a note to the body mentioning this is a follow-up
    if new_campaign.body.present?
      followup_note = "<p><em>This is a follow-up to our previous email that you may have missed.</em></p>"
      
      # Insert follow-up note after the first paragraph or at the beginning
      if new_campaign.body.include?("</p>")
        # Insert after the first paragraph
        new_campaign.body = new_campaign.body.sub("</p>", "</p>\n#{followup_note}")
      else
        # Insert at the beginning
        new_campaign.body = "#{followup_note}\n#{new_campaign.body}"
      end
    end
    
    # Set to draft status initially
    new_campaign.status = 'draft'
    
    # Reset various tracking fields
    new_campaign.sent_count = 0
    new_campaign.open_count = 0
    new_campaign.click_count = 0
    new_campaign.bounce_count = 0
    new_campaign.started_at = nil
    new_campaign.completed_at = nil
    
    # Save the new campaign
    if new_campaign.save
      puts "Created new follow-up campaign with ID: #{new_campaign.id}"
      
      # Create contact group with the targeted recipients
      contact_group = ContactGroup.new(
        name: "Follow-up group for campaign #{original_campaign.id}",
        entity_id: original_campaign.entity_id,
        user_id: original_campaign.user_id
      )
      
      if contact_group.save
        puts "Created contact group with ID: #{contact_group.id}"
        
        # Associate the contacts with the group
        if recipient_ids.any?
          # Build the association records
          associations = recipient_ids.map do |contact_id|
            {
              contact_id: contact_id,
              contact_group_id: contact_group.id,
              created_at: Time.current,
              updated_at: Time.current
            }
          end
          
          # Bulk insert the associations
          if ContactGroupsContact.insert_all(associations)
            puts "Added #{recipient_ids.count} contacts to the group"
            
            # Associate the group with the campaign
            if new_campaign.update(contact_group_id: contact_group.id)
              puts "Associated contact group with the new campaign"
              puts "\nDone! Your follow-up campaign (ID: #{new_campaign.id}) has been created."
              puts "It is currently in 'draft' status. You can review and launch it from the admin interface."
            else
              puts "Error: Could not associate contact group with campaign"
            end
          else
            puts "Error: Could not add contacts to the group"
          end
        end
      else
        puts "Error: Could not create contact group - #{contact_group.errors.full_messages.join(', ')}"
      end
    else
      puts "Error: Could not create follow-up campaign - #{new_campaign.errors.full_messages.join(', ')}"
    end
  end
  
  desc "Setup a drip campaign sequence"
  task :setup_drip, [:campaign_id, :delay_days, :condition] => :environment do |t, args|
    if args[:campaign_id].blank?
      puts "Please provide a campaign ID"
      puts "Usage: rake campaign:setup_drip[campaign_id,delay_days,condition]"
      puts "Example: rake campaign:setup_drip[42,3,not_opened]"
      puts "Valid conditions: not_opened, not_clicked, opened, clicked, always"
      exit 1
    end
    
    # Default values
    delay_days = (args[:delay_days] || 3).to_i
    condition = args[:condition] || 'not_opened'
    
    # Find the original campaign
    campaign = Campaign.find(args[:campaign_id])
    puts "Setting up drip sequence for campaign: #{campaign.name} (ID: #{campaign.id})"
    
    # Create the drip follow-up
    drip_campaign = campaign.create_drip_follow_up(
      delay_days: delay_days,
      condition: condition,
      subject_prefix: "[Reminder] "
    )
    
    if drip_campaign
      puts "Successfully created drip campaign sequence!"
      puts "Original campaign: #{campaign.id}"
      puts "Follow-up template: #{drip_campaign.follow_up_campaign_id}"
      puts "Delay days: #{drip_campaign.delay_days}"
      puts "Condition: #{drip_campaign.condition}"
      puts "Scheduled for: #{drip_campaign.scheduled_at}"
      puts "\nThe follow-up will be automatically sent #{delay_days} days after the original campaign completes."
    else
      puts "Error: Could not create drip campaign. #{campaign.errors.full_messages.join(', ')}"
    end
  end
  
  desc "Process scheduled drip campaigns"
  task process_drips: :environment do
    puts "Looking for drip campaigns to process..."
    
    # Find all active drip campaigns that are due to be processed
    due_drips = DrippedCampaign.where(active: true)
                                .where("scheduled_at <= ?", Time.current)
    
    if due_drips.empty?
      puts "No drip campaigns are due for processing."
      exit 0
    end
    
    processed_count = 0
    error_count = 0
    
    due_drips.each do |drip|
      begin
        # Check if original campaign is completed (a requirement for processing)
        if ['completed', 'in_progress'].include?(drip.original_campaign.status)
          puts "Processing drip campaign: #{drip.id} (#{drip.original_campaign.name} → follow-up #{drip.sequence_position})"
          
          # Create the next follow-up
          new_campaign = drip.create_next_follow_up!
          
          if new_campaign
            puts "Created follow-up campaign: #{new_campaign.id}"
            processed_count += 1
            
            # Mark this drip as processed (deactivate it)
            drip.update(active: false)
          else
            puts "No follow-up needed for drip #{drip.id} (no matching contacts)"
            # Mark as processed even though no campaign was created
            drip.update(active: false)
          end
        else
          puts "Skipping drip #{drip.id} - original campaign is not completed/in progress (status: #{drip.original_campaign.status})"
        end
      rescue => e
        puts "Error processing drip #{drip.id}: #{e.message}"
        error_count += 1
      end
    end
    
    puts "Drip processing complete. Processed: #{processed_count}, Errors: #{error_count}"
  end
end 