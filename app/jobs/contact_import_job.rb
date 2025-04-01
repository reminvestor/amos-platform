class ContactImportJob < ApplicationJob
  queue_as :default
  
  def perform(params)
    start_time = Time.current
    Rails.logger.info("CONTACT IMPORT JOB [#{start_time.iso8601(3)}]: Starting import job")
    
    # Extract parameters
    user_id = params[:user_id]
    entity_id = params[:entity_id]
    contact_group_id = params[:contact_group_id]
    contacts_data = params[:contacts]
    
    Rails.logger.info("CONTACT IMPORT JOB [#{Time.current.iso8601(3)}]: Processing #{contacts_data.size} contacts for user #{user_id}")
    
    # Find the user
    user = User.find_by(id: user_id)
    unless user
      raise "User with ID #{user_id} not found"
    end
    
    # Process contacts in batches to avoid memory issues
    results = {
      contacts_created: 0,
      contacts_updated: 0,
      errors: []
    }
    
    # Create or find the target group
    target_group = if contact_group_id.present?
      group = user.contact_groups.find_by(id: contact_group_id)
      unless group
        raise "Contact group not found: #{contact_group_id}"
      end
      group
    else
      # Create a new group
      group_name = "API Import #{Time.current.strftime('%Y-%m-%d %H:%M')}"
      user.contact_groups.create!(
        name: group_name,
        description: "API Import on #{Time.current.strftime('%Y-%m-%d')}",
        entity_id: entity_id
      )
    end
    
    Rails.logger.info("CONTACT IMPORT JOB [#{Time.current.iso8601(3)}]: Using group #{target_group.id}, name: #{target_group.name}")
    
    # Process in batches of 100
    contacts_data.in_groups_of(100, false) do |batch|
      batch_start = Time.current
      Rails.logger.info("CONTACT IMPORT JOB [#{batch_start.iso8601(3)}]: Processing batch of #{batch.size} contacts")
      
      created = 0
      updated = 0
      batch_errors = []
      
      ActiveRecord::Base.transaction do
        # Process contacts in the batch
        updated_contacts = []
        new_contacts = []
        
        # First pass: Find or create contacts
        batch.each do |contact_data|
          begin
            # Find existing contact
            contact = Contact.find_by(
              email: contact_data[:email].to_s.strip,
              user_id: user_id,
              entity_id: entity_id
            )
            
            if contact
              # Update existing contact
              contact.first_name = contact_data[:first_name] if contact_data[:first_name].present?
              contact.last_name = contact_data[:last_name] if contact_data[:last_name].present?
              contact.status = contact_data[:status] || 'active'
              
              # Update metadata
              contact.metadata ||= {}
              contact.metadata = contact.metadata.merge({
                corporation_id: contact_data[:corporation_id],
                corporation_name: contact_data[:corporation_name]
              }.compact)
              
              if contact.save
                updated_contacts << contact
                updated += 1
              else
                batch_errors << {
                  email: contact_data[:email],
                  errors: contact.errors.full_messages
                }
              end
            else
              # Create new contact
              contact = Contact.new(
                email: contact_data[:email].to_s.strip,
                first_name: contact_data[:first_name],
                last_name: contact_data[:last_name],
                status: contact_data[:status] || 'active',
                user_id: user_id,
                entity_id: entity_id,
                metadata: {
                  corporation_id: contact_data[:corporation_id],
                  corporation_name: contact_data[:corporation_name]
                }.compact
              )
              
              if contact.save
                new_contacts << contact
                created += 1
              else
                batch_errors << {
                  email: contact_data[:email],
                  errors: contact.errors.full_messages
                }
              end
            end
          rescue => e
            batch_errors << {
              email: contact_data[:email] || "unknown",
              errors: [e.message]
            }
          end
        end
        
        # Second pass: Handle group assignments
        all_contacts = updated_contacts + new_contacts
        if all_contacts.any?
          # Get all contact IDs
          contact_ids = all_contacts.map(&:id)
          
          # Find group scope
          if entity_id.present?
            other_groups = ContactGroup.where(entity_id: entity_id).where.not(id: target_group.id)
          else
            other_groups = ContactGroup.where(entity_id: nil).where.not(id: target_group.id)
          end
          
          # Remove from other groups
          if other_groups.any?
            existing_memberships = ContactGroupsContact.where(
              contact_id: contact_ids,
              contact_group_id: other_groups.map(&:id)
            )
            
            if existing_memberships.any?
              existing_memberships.delete_all
            end
          end
          
          # Add to target group
          existing_in_group = ContactGroupsContact.where(
            contact_id: contact_ids,
            contact_group_id: target_group.id
          ).pluck(:contact_id)
          
          contacts_to_add = all_contacts.reject { |c| existing_in_group.include?(c.id) }
          
          if contacts_to_add.any?
            values = contacts_to_add.map do |contact| 
              {
                contact_id: contact.id,
                contact_group_id: target_group.id,
                created_at: Time.current,
                updated_at: Time.current
              }
            end
            
            # Bulk insert
            ContactGroupsContact.insert_all(values)
          end
        end
      end
      
      # Update results
      results[:contacts_created] += created
      results[:contacts_updated] += updated
      results[:errors].concat(batch_errors)
      
      batch_end = Time.current
      Rails.logger.info("CONTACT IMPORT JOB [#{batch_end.iso8601(3)}]: Batch completed in #{(batch_end - batch_start).round(2)}s, created: #{created}, updated: #{updated}, errors: #{batch_errors.size}")
    end
    
    # All done
    end_time = Time.current
    Rails.logger.info("CONTACT IMPORT JOB [#{end_time.iso8601(3)}]: Import completed in #{(end_time - start_time).round(2)}s, created: #{results[:contacts_created]}, updated: #{results[:contacts_updated]}, errors: #{results[:errors].size}")
    
    # Store results in Redis or some other accessible storage for status checking
    import_results = {
      job_id: job_id,
      status: "completed",
      group_id: target_group.id,
      group_name: target_group.name,
      contacts_created: results[:contacts_created],
      contacts_updated: results[:contacts_updated],
      total_processed: results[:contacts_created] + results[:contacts_updated],
      error_count: results[:errors].size,
      completed_at: end_time.iso8601,
      processing_time_seconds: (end_time - start_time).round(2)
    }
    
    # Store in Redis with a 24-hour expiration
    if defined?(Redis) && Redis.current.present?
      key = "contact_import:#{job_id}"
      Redis.current.set(key, import_results.to_json)
      Redis.current.expire(key, 24.hours.to_i)
    end
    
    return import_results
  end
end 