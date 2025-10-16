module Api
  module V1
    class ContactsController < Api::BaseController
      respond_to :json
      protect_from_forgery with: :null_session
      before_action :authenticate_api_request

      def create
        begin
          start_time = Time.current
          Rails.logger.info("API CONTACT CREATE [#{start_time.iso8601(3)}]: Starting request processing")

          # Log request headers and parameters for debugging
          Rails.logger.info("API CONTACT CREATE [#{Time.current.iso8601(3)}]: Headers: #{request.headers.select { |k, v| k.start_with?('HTTP_') }.to_json}")
          Rails.logger.info("API CONTACT CREATE [#{Time.current.iso8601(3)}]: Raw params: #{params.to_unsafe_h.except(:controller, :action).to_json}")

          # Check for the current user
          unless current_user
            Rails.logger.error("API CONTACT CREATE [#{Time.current.iso8601(3)}]: No current_user found")
            render json: {
              success: false,
              message: "Authentication failed"
            }, status: :unauthorized
            return
          end

          # Log all incoming parameters
          contacts_count = params[:contacts].is_a?(Array) ? params[:contacts].length : 0
          Rails.logger.info("API CONTACT CREATE [#{Time.current.iso8601(3)}]: Received #{contacts_count} contacts for user ID: #{current_user.id}")

          # Check if contacts parameter is present
          unless params[:contacts].present? && params[:contacts].is_a?(Array)
            Rails.logger.info("API CONTACT CREATE [#{Time.current.iso8601(3)}]: Missing contacts parameter")
            render json: {
              success: false,
              message: "Missing or invalid contacts parameter"
            }, status: :bad_request
            return
          end

          # Handle large batches by implementing batch processing
          if params[:contacts].size > 100
            Rails.logger.info("API CONTACT CREATE [#{Time.current.iso8601(3)}]: Large batch detected (#{params[:contacts].size} contacts), using background job")

            begin
              # Create a job to process this in the background
              entity_id = determine_entity_id
              Rails.logger.info("API CONTACT CREATE [#{Time.current.iso8601(3)}]: Using entity_id: #{entity_id} for background job")

              job = ContactImportJob.perform_later(
                user_id: current_user.id,
                entity_id: entity_id,
                contact_group_id: params[:contact_group_id],
                contacts: params[:contacts]
              )

              # Return early with job info
              job_id = job.try(:job_id) || "unknown"
              Rails.logger.info("API CONTACT CREATE [#{Time.current.iso8601(3)}]: Created background job with ID: #{job_id}")

              render json: {
                success: true,
                message: "Processing #{params[:contacts].size} contacts in the background",
                job_id: job_id,
                status_url: "/api/v1/jobs/#{job_id}"
              }, status: :accepted
              return
            rescue => e
              Rails.logger.error("API CONTACT CREATE [#{Time.current.iso8601(3)}]: Failed to create background job - #{e.class.name}: #{e.message}")
              Rails.logger.error(e.backtrace.join("\n"))

              render json: {
                success: false,
                message: "Failed to create background processing job",
                error: e.message
              }, status: :internal_server_error
              return
            end
          end

          # For smaller batches, process immediately
          begin
            ActiveRecord::Base.transaction do
              contacts = []
              errors = []
              transaction_start = Time.current
              Rails.logger.info("API CONTACT CREATE [#{transaction_start.iso8601(3)}]: Starting transaction")

              # Get the user's active entity or default entity
              user_entity_id = determine_entity_id
              Rails.logger.info("API CONTACT CREATE [#{Time.current.iso8601(3)}]: Using entity_id: #{user_entity_id}")

              # Step 1: Create or find the target group
              group_start = Time.current
              Rails.logger.info("API CONTACT CREATE [#{group_start.iso8601(3)}]: Finding/creating group")

              target_group = if params[:contact_group_id].present?
                # Find existing group
                begin
                  group = current_user.contact_groups.find_by(id: params[:contact_group_id])
                  unless group
                    Rails.logger.info("API CONTACT CREATE [#{Time.current.iso8601(3)}]: Group not found: #{params[:contact_group_id]}")
                    render json: {
                      success: false,
                      message: "Contact group not found",
                      error: "Invalid contact_group_id: #{params[:contact_group_id]}"
                    }, status: :not_found
                    return
                  end
                  group
                rescue => e
                  Rails.logger.error("API CONTACT CREATE [#{Time.current.iso8601(3)}]: Error finding group - #{e.class.name}: #{e.message}")
                  raise e
                end
              else
                # Create a new group
                begin
                  group_name = "API Import #{Time.current.strftime('%Y-%m-%d %H:%M')}"
                  Rails.logger.info("API CONTACT CREATE [#{Time.current.iso8601(3)}]: Creating new group: #{group_name}")

                  current_user.contact_groups.create!(
                    name: group_name,
                    description: "API Import on #{Time.current.strftime('%Y-%m-%d')}",
                    entity_id: user_entity_id
                  )
                rescue => e
                  Rails.logger.error("API CONTACT CREATE [#{Time.current.iso8601(3)}]: Error creating group - #{e.class.name}: #{e.message}")
                  raise e
                end
              end

              group_end = Time.current
              Rails.logger.info("API CONTACT CREATE [#{group_end.iso8601(3)}]: Group operation took #{(group_end - group_start).round(2)}s, using group ID: #{target_group.id}")

              # Step 2: Process each contact - now with batch processing
              Rails.logger.info("API CONTACT CREATE [#{Time.current.iso8601(3)}]: Starting to process #{params[:contacts].size} contacts")

              # First, create all contacts in a batch if possible
              contacts_to_create = []
              contacts_to_update = []

              # Separate existing contacts from new ones
              batch_prep_start = Time.current
              begin
                params[:contacts].each do |contact_params|
                  # Ensure we have a valid email
                  unless contact_params[:email].present?
                    errors << {
                      email: "missing",
                      errors: [ "Email is required" ]
                    }
                    next
                  end

                  # Find if contact exists
                  existing = Contact.find_by(
                    email: contact_params[:email].to_s.strip,
                    user_id: current_user.id,
                    entity_id: user_entity_id
                  )

                  if existing
                    contacts_to_update << { contact: existing, params: contact_params }
                  else
                    contacts_to_create << contact_params
                  end
                end
              rescue => e
                Rails.logger.error("API CONTACT CREATE [#{Time.current.iso8601(3)}]: Error in batch preparation - #{e.class.name}: #{e.message}")
                raise e
              end

              batch_prep_end = Time.current
              Rails.logger.info("API CONTACT CREATE [#{batch_prep_end.iso8601(3)}]: Batch preparation took #{(batch_prep_end - batch_prep_start).round(2)}s, creating: #{contacts_to_create.size}, updating: #{contacts_to_update.size}")

              # Process updates first
              update_start = Time.current
              updated_contacts = []
              update_errors = []

              begin
                contacts_to_update.each do |item|
                  begin
                    contact = item[:contact]
                    params = item[:params]

                    # Update attributes
                    contact.first_name = params[:first_name] if params[:first_name].present?
                    contact.last_name = params[:last_name] if params[:last_name].present?
                    contact.status = params[:status] || "active"

                    # Update metadata
                    contact.metadata ||= {}
                    contact.metadata = contact.metadata.merge({
                      corporation_id: params[:corporation_id],
                      corporation_name: params[:corporation_name]
                    }.compact)

                    if contact.save
                      updated_contacts << contact
                    else
                      Rails.logger.warn("API CONTACT CREATE: Failed to update contact #{params[:email]} - #{contact.errors.full_messages.join(', ')}")
                      update_errors << {
                        email: params[:email],
                        errors: contact.errors.full_messages
                      }
                    end
                  rescue => e
                    Rails.logger.error("API CONTACT CREATE: Error updating contact #{item[:params][:email]} - #{e.class.name}: #{e.message}")
                    update_errors << {
                      email: item[:params][:email],
                      errors: [ e.message ]
                    }
                  end
                end
              rescue => e
                Rails.logger.error("API CONTACT CREATE [#{Time.current.iso8601(3)}]: Error in update processing - #{e.class.name}: #{e.message}")
                raise e
              end

              update_end = Time.current
              Rails.logger.info("API CONTACT CREATE [#{update_end.iso8601(3)}]: Updates took #{(update_end - update_start).round(2)}s, succeeded: #{updated_contacts.size}, failed: #{update_errors.size}")

              # Process new contacts
              create_start = Time.current
              new_contacts = []
              create_errors = []

              begin
                if contacts_to_create.any?
                  contacts_to_create.each do |params|
                    begin
                      # Ensure we have all required fields
                      unless params[:first_name].present? && params[:last_name].present?
                        missing_fields = []
                        missing_fields << "first_name" unless params[:first_name].present?
                        missing_fields << "last_name" unless params[:last_name].present?

                        create_errors << {
                          email: params[:email],
                          errors: [ "Missing required fields: #{missing_fields.join(', ')}" ]
                        }
                        next
                      end

                      # Create new contact
                      contact = Contact.new(
                        email: params[:email].to_s.strip,
                        first_name: params[:first_name],
                        last_name: params[:last_name],
                        status: params[:status] || "active",
                        lead: params.key?(:lead) ? parse_boolean(params[:lead]) : true,
                        user_id: current_user.id,
                        entity_id: user_entity_id,
                        metadata: {
                          corporation_id: params[:corporation_id],
                          corporation_name: params[:corporation_name]
                        }.compact
                      )

                      if contact.save
                        new_contacts << contact
                      else
                        Rails.logger.warn("API CONTACT CREATE: Failed to create contact #{params[:email]} - #{contact.errors.full_messages.join(', ')}")
                        create_errors << {
                          email: params[:email],
                          errors: contact.errors.full_messages
                        }
                      end
                    rescue => e
                      Rails.logger.error("API CONTACT CREATE: Error creating contact #{params[:email]} - #{e.class.name}: #{e.message}")
                      create_errors << {
                        email: params[:email],
                        errors: [ e.message ]
                      }
                    end
                  end
                end
              rescue => e
                Rails.logger.error("API CONTACT CREATE [#{Time.current.iso8601(3)}]: Error in create processing - #{e.class.name}: #{e.message}")
                raise e
              end

              create_end = Time.current
              Rails.logger.info("API CONTACT CREATE [#{create_end.iso8601(3)}]: Creates took #{(create_end - create_start).round(2)}s, succeeded: #{new_contacts.size}, failed: #{create_errors.size}")

              # Combine all contacts and errors
              all_contacts = updated_contacts + new_contacts
              all_errors = update_errors + create_errors

              # Step 3: Handle group membership - in batch if possible
              if all_contacts.any?
                group_assign_start = Time.current
                Rails.logger.info("API CONTACT CREATE [#{group_assign_start.iso8601(3)}]: Starting group assignment for #{all_contacts.size} contacts")

                begin
                  # Get all contact IDs
                  contact_ids = all_contacts.map(&:id)

                  # Efficiently find existing group memberships
                  if user_entity_id.present?
                    # Find all groups in this entity
                    other_groups = ContactGroup.where(entity_id: user_entity_id).where.not(id: target_group.id)
                  else
                    # Find all global groups
                    other_groups = ContactGroup.where(entity_id: nil).where.not(id: target_group.id)
                  end

                  if other_groups.any?
                    # Get all existing memberships
                    existing_memberships = ContactGroupsContact.where(
                      contact_id: contact_ids,
                      contact_group_id: other_groups.map(&:id)
                    )

                    # Delete them in one operation
                    if existing_memberships.any?
                      delete_start = Time.current
                      membership_count = existing_memberships.count
                      existing_memberships.delete_all
                      delete_end = Time.current
                      Rails.logger.info("API CONTACT CREATE [#{delete_end.iso8601(3)}]: Deleted #{membership_count} group memberships in #{(delete_end - delete_start).round(2)}s")
                    end
                  end

                  # Add all contacts to the target group
                  add_start = Time.current

                  # First, find which contacts are already in the group
                  existing_in_group = ContactGroupsContact.where(
                    contact_id: contact_ids,
                    contact_group_id: target_group.id
                  ).pluck(:contact_id)

                  # Determine which need to be added
                  contacts_to_add = all_contacts.reject { |c| existing_in_group.include?(c.id) }

                  # Add them all at once if needed
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
                    Rails.logger.info("API CONTACT CREATE [#{Time.current.iso8601(3)}]: Inserting #{values.size} new contact group associations")
                    ContactGroupsContact.insert_all(values)
                  end

                  add_end = Time.current
                  Rails.logger.info("API CONTACT CREATE [#{add_end.iso8601(3)}]: Group assignment took #{(add_end - add_start).round(2)}s")

                  # Final step - build response with newly created/updated contacts
                  response_start = Time.current
                  contacts_response = all_contacts.map { |c| contact_response(c) }
                  response_end = Time.current

                  Rails.logger.info("API CONTACT CREATE [#{response_end.iso8601(3)}]: Response preparation took #{(response_end - response_start).round(2)}s")

                  # Calculate total time
                  total_time = Time.current - start_time

                  # Return success response with created/updated contacts and any errors
                  render json: {
                    success: true,
                    message: "Processed contacts successfully",
                    created: new_contacts.size,
                    updated: updated_contacts.size,
                    errors: all_errors,
                    group: {
                      id: target_group.id,
                      name: target_group.name
                    },
                    contacts: contacts_response,
                    processing_time_seconds: total_time.round(2)
                  }
                rescue => e
                  Rails.logger.error("API CONTACT CREATE [#{Time.current.iso8601(3)}]: Error in group assignment - #{e.class.name}: #{e.message}")
                  raise e
                end
              else
                # No contacts were created or updated, but return success with warnings
                render json: {
                  success: true,
                  message: "No contacts were created or updated",
                  created: 0,
                  updated: 0,
                  errors: all_errors,
                  group: {
                    id: target_group.id,
                    name: target_group.name
                  },
                  contacts: []
                }
              end
            end
          rescue ActiveRecord::RecordNotFound => e
            Rails.logger.error("API CONTACT CREATE [#{Time.current.iso8601(3)}]: Record not found - #{e.class.name}: #{e.message}")
            Rails.logger.error(e.backtrace.join("\n"))

            render json: {
              success: false,
              message: "Resource not found",
              error: e.message
            }, status: :not_found
          rescue ActiveRecord::RecordInvalid => e
            Rails.logger.error("API CONTACT CREATE [#{Time.current.iso8601(3)}]: Validation error - #{e.class.name}: #{e.message}")
            Rails.logger.error(e.backtrace.join("\n"))

            render json: {
              success: false,
              message: "Validation error",
              error: e.message
            }, status: :unprocessable_entity
          rescue => e
            Rails.logger.error("API CONTACT CREATE [#{Time.current.iso8601(3)}]: Unexpected error - #{e.class.name}: #{e.message}")
            Rails.logger.error(e.backtrace.join("\n"))

            render json: {
              success: false,
              message: "An error occurred while processing contacts",
              error: e.message
            }, status: :internal_server_error
          end
        rescue => e
          Rails.logger.error("API CONTACT CREATE CRITICAL ERROR: #{e.class.name}: #{e.message}")
          Rails.logger.error(e.backtrace.join("\n"))

          render json: {
            success: false,
            message: "A critical error occurred",
            error: e.message
          }, status: :internal_server_error
        end
      end

      private

      # Determine which entity_id to use based on user's associations
      def determine_entity_id
        # Try to get user's primary entity
        if current_user.respond_to?(:primary_entity) && current_user.primary_entity.present?
          return current_user.primary_entity.id
        end

        # Or use the user's entity if one exists (1:1 relationship)
        if current_user.entity
          return current_user.entity.id
        end

        # Return nil if no entity is available (global contact)
        nil
      end

      def authenticate_api_request
        # Get the API key from the Authorization header
        auth_header = request.headers["Authorization"]

        # Better header parsing
        if auth_header.blank?
          render json: { error: "Missing Authorization header" }, status: :unauthorized
          return
        end

        # Support both "Bearer <key>" and just "<key>" formats
        api_key = if auth_header.start_with?("Bearer ")
          auth_header.gsub("Bearer ", "")
        else
          auth_header
        end

        if api_key.blank?
          render json: { error: "Invalid Authorization header format" }, status: :unauthorized
          return
        end

        # Find user by API key
        @current_user = User.find_by(api_key: api_key)

        unless @current_user
          render json: { error: "Invalid API key" }, status: :unauthorized
          return
        end

        # Set current_user for the application controller
        Thread.current[:current_user] = @current_user
      end

      def current_user
        @current_user
      end

      def contact_response(contact)
        {
          id: contact.id,
          email: contact.email,
          first_name: contact.first_name,
          last_name: contact.last_name,
          corporation_id: contact.metadata&.dig("corporation_id"),
          corporation_name: contact.metadata&.dig("corporation_name"),
          status: contact.status,
          contact_groups: contact.contact_groups.map { |g| { id: g.id, name: g.name } }
        }
      end

      # Help convert string boolean values to actual booleans
      def parse_boolean(value)
        return nil if value.nil?
        return value if value.is_a?(TrueClass) || value.is_a?(FalseClass)

        case value.to_s.downcase.strip
        when "true", "yes", "1", "on"
          true
        when "false", "no", "0", "off"
          false
        else
          value # Return original value if not a boolean string
        end
      end
    end
  end
end
