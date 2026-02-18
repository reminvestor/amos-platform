class ContactImportJob < ApplicationJob
  queue_as :default

  # Define a method to retrieve the current job ID safely
  def current_job_id
    begin
      # Try to get the job ID from SolidQueue
      provider_job_id || job_id || SecureRandom.uuid
    rescue => e
      Rails.logger.error("Failed to get job ID: #{e.message}")
      # Fallback to a UUID if we can't get the job ID
      SecureRandom.uuid
    end
  end

  def perform(params)
    start_time = Time.current
    job_id = current_job_id
    Rails.logger.info("CONTACT IMPORT JOB [#{start_time.iso8601(3)}] [JOB:#{job_id}]: Starting import job")

    begin
      # Extract parameters
      user_id = params[:user_id]
      entity_id = params[:entity_id]
      contact_group_id = params[:contact_group_id]
      contacts_data = params[:contacts]

      Rails.logger.info("CONTACT IMPORT JOB [#{Time.current.iso8601(3)}] [JOB:#{job_id}]: Processing #{contacts_data.size} contacts for user #{user_id}")

      # Find the user
      user = User.find_by(id: user_id)
      unless user
        error_msg = "User with ID #{user_id} not found"
        store_error_result(job_id, error_msg)
        raise error_msg
      end

      # Process contacts in batches to avoid memory issues
      results = {
        contacts_created: 0,
        contacts_updated: 0,
        errors: []
      }

      # Create or find the target group
      target_group = if contact_group_id.present?
        begin
          group = user.contact_groups.find_by(id: contact_group_id)
          unless group
            error_msg = "Contact group not found: #{contact_group_id}"
            store_error_result(job_id, error_msg)
            raise error_msg
          end
          group
        rescue => e
          Rails.logger.error("CONTACT IMPORT JOB [#{Time.current.iso8601(3)}] [JOB:#{job_id}]: Error finding group - #{e.message}")
          store_error_result(job_id, e.message)
          raise e
        end
      else
        # Create a new group
        begin
          group_name = "API Import #{Time.current.strftime('%Y-%m-%d %H:%M')}"
          user.contact_groups.create!(
            name: group_name,
            description: "API Import on #{Time.current.strftime('%Y-%m-%d')}",
            entity_id: entity_id
          )
        rescue => e
          Rails.logger.error("CONTACT IMPORT JOB [#{Time.current.iso8601(3)}] [JOB:#{job_id}]: Error creating group - #{e.message}")
          store_error_result(job_id, e.message)
          raise e
        end
      end

      Rails.logger.info("CONTACT IMPORT JOB [#{Time.current.iso8601(3)}] [JOB:#{job_id}]: Using group #{target_group.id}, name: #{target_group.name}")

      # Process in batches of 100
      contacts_data.in_groups_of(100, false) do |batch|
        batch_start = Time.current
        Rails.logger.info("CONTACT IMPORT JOB [#{batch_start.iso8601(3)}] [JOB:#{job_id}]: Processing batch of #{batch.size} contacts")

        created = 0
        updated = 0
        batch_errors = []

        begin
          ActiveRecord::Base.transaction do
            # Process contacts in the batch
            updated_contacts = []
            new_contacts = []

            # First pass: Find or create contacts
            batch.each do |contact_data|
              begin
                contact_data = contact_data.with_indifferent_access if contact_data.is_a?(Hash)
                email = contact_data[:email].to_s.strip.downcase
                next if email.blank?

                contact = Contact.find_by(
                  email: email,
                  user_id: user_id,
                  entity_id: entity_id
                )

                metadata = {}
                metadata["phone"] = contact_data[:phone].to_s.strip if contact_data[:phone].present?
                metadata["company"] = contact_data[:company].to_s.strip if contact_data[:company].present?
                metadata["corporation_id"] = contact_data[:corporation_id].to_s.strip if contact_data[:corporation_id].present?
                metadata["corporation_name"] = contact_data[:corporation_name].to_s.strip if contact_data[:corporation_name].present?

                if contact
                  contact.first_name = contact_data[:first_name] if contact_data[:first_name].present?
                  contact.last_name = contact_data[:last_name] if contact_data[:last_name].present?
                  contact.status = contact_data[:status] || "active"
                  contact.metadata = (contact.metadata || {}).merge(metadata) if metadata.any?
                  if contact_data[:custom_fields].present?
                    contact.custom_fields = (contact.custom_fields || {}).merge(contact_data[:custom_fields])
                  end

                  if contact.save
                    updated_contacts << contact
                    updated += 1
                  else
                    batch_errors << { email: email, errors: contact.errors.full_messages }
                  end
                else
                  contact = Contact.new(
                    email: email,
                    first_name: contact_data[:first_name],
                    last_name: contact_data[:last_name],
                    tags: contact_data[:tags].to_s,
                    status: contact_data[:status] || "active",
                    user_id: user_id,
                    entity_id: entity_id,
                    metadata: metadata.presence || {},
                    custom_fields: contact_data[:custom_fields] || {}
                  )

                  if contact.save
                    new_contacts << contact
                    created += 1
                  else
                    batch_errors << { email: email, errors: contact.errors.full_messages }
                  end
                end
              rescue => e
                Rails.logger.error("CONTACT IMPORT JOB [#{Time.current.iso8601(3)}] [JOB:#{job_id}]: Error processing contact - #{e.message}")
                batch_errors << {
                  email: contact_data[:email] || "unknown",
                  errors: [ e.message ]
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
        rescue => e
          Rails.logger.error("CONTACT IMPORT JOB [#{Time.current.iso8601(3)}] [JOB:#{job_id}]: Batch error - #{e.message}")
          # Add the error but continue processing other batches
          batch_errors << {
            email: "batch_error",
            errors: [ e.message ]
          }
        end

        # Update results
        results[:contacts_created] += created
        results[:contacts_updated] += updated
        results[:errors].concat(batch_errors)

        batch_end = Time.current
        Rails.logger.info("CONTACT IMPORT JOB [#{batch_end.iso8601(3)}] [JOB:#{job_id}]: Batch completed in #{(batch_end - batch_start).round(2)}s, created: #{created}, updated: #{updated}, errors: #{batch_errors.size}")
      end

      # All done
      end_time = Time.current
      Rails.logger.info("CONTACT IMPORT JOB [#{end_time.iso8601(3)}] [JOB:#{job_id}]: Import completed in #{(end_time - start_time).round(2)}s, created: #{results[:contacts_created]}, updated: #{results[:contacts_updated]}, errors: #{results[:errors].size}")

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
      store_result(job_id, import_results)

      import_results
    rescue => e
      Rails.logger.error("CONTACT IMPORT JOB ERROR [#{Time.current.iso8601(3)}] [JOB:#{job_id}]: #{e.class.name}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))

      # Store the error result
      store_error_result(job_id, e.message)

      # Re-raise to mark the job as failed
      raise e
    end
  end

  private

  def store_result(job_id, results)
    begin
      redis = safe_redis
      if redis
        key = "contact_import:#{job_id}"
        redis.set(key, results.to_json)
        redis.expire(key, 24.hours.to_i)
        Rails.logger.info("CONTACT IMPORT JOB [#{Time.current.iso8601(3)}] [JOB:#{job_id}]: Stored results in Redis")
      else
        Rails.logger.warn("CONTACT IMPORT JOB [#{Time.current.iso8601(3)}] [JOB:#{job_id}]: Redis not available, results will not be stored")
      end
    rescue => e
      Rails.logger.error("CONTACT IMPORT JOB [#{Time.current.iso8601(3)}] [JOB:#{job_id}]: Failed to store results in Redis - #{e.message}")
    end
  end

  def store_error_result(job_id, error_message)
    error_result = {
      job_id: job_id,
      status: "failed",
      error: error_message,
      failed_at: Time.current.iso8601
    }

    store_result(job_id, error_result)
  end
end
