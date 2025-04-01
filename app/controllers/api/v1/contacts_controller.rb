module Api
  module V1
    class ContactsController < Api::BaseController
      respond_to :json
      protect_from_forgery with: :null_session
      skip_before_action :verify_authenticity_token
      before_action :authenticate_api_request
      
      def create
        begin
          start_time = Time.current
          Rails.logger.info("API CONTACT CREATE [#{start_time.iso8601(3)}]: Starting request processing")
          
          # Log all incoming parameters
          contacts_count = params[:contacts].is_a?(Array) ? params[:contacts].length : 0
          Rails.logger.info("API CONTACT CREATE [#{Time.current.iso8601(3)}]: Received #{contacts_count} contacts")
          
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
            
            # Create a job to process this in the background
            job = ContactImportJob.perform_later(
              user_id: current_user.id,
              entity_id: determine_entity_id,
              contact_group_id: params[:contact_group_id],
              contacts: params[:contacts]
            )
            
            # Return early with job info
            render json: {
              success: true,
              message: "Processing #{params[:contacts].size} contacts in the background",
              job_id: job.job_id,
              status_url: "/api/v1/jobs/#{job.job_id}"
            }, status: :accepted
            return
          end
          
          # For smaller batches, process immediately
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
            else
              # Create a new group
              group_name = "API Import #{Time.current.strftime('%Y-%m-%d %H:%M')}"
              current_user.contact_groups.create!(
                name: group_name,
                description: "API Import on #{Time.current.strftime('%Y-%m-%d')}",
                entity_id: user_entity_id
              )
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
            params[:contacts].each do |contact_params|
              # Find if contact exists
              existing = Contact.find_by(
                email: contact_params[:email].strip,
                user_id: current_user.id,
                entity_id: user_entity_id
              )
              
              if existing
                contacts_to_update << {contact: existing, params: contact_params}
              else
                contacts_to_create << contact_params
              end
            end
            batch_prep_end = Time.current
            Rails.logger.info("API CONTACT CREATE [#{batch_prep_end.iso8601(3)}]: Batch preparation took #{(batch_prep_end - batch_prep_start).round(2)}s, creating: #{contacts_to_create.size}, updating: #{contacts_to_update.size}")
            
            # Process updates first
            update_start = Time.current
            updated_contacts = []
            update_errors = []
            
            contacts_to_update.each do |item|
              begin
                contact = item[:contact]
                params = item[:params]
                
                # Update attributes
                contact.first_name = params[:first_name] if params[:first_name].present?
                contact.last_name = params[:last_name] if params[:last_name].present?
                contact.status = params[:status] || 'active'
                
                # Update metadata
                contact.metadata ||= {}
                contact.metadata = contact.metadata.merge({
                  corporation_id: params[:corporation_id],
                  corporation_name: params[:corporation_name]
                }.compact)
                
                if contact.save
                  updated_contacts << contact
                else
                  update_errors << {
                    email: params[:email],
                    errors: contact.errors.full_messages
                  }
                end
              rescue => e
                update_errors << {
                  email: item[:params][:email],
                  errors: [e.message]
                }
              end
            end
            update_end = Time.current
            Rails.logger.info("API CONTACT CREATE [#{update_end.iso8601(3)}]: Updates took #{(update_end - update_start).round(2)}s, succeeded: #{updated_contacts.size}, failed: #{update_errors.size}")
            
            # Process new contacts
            create_start = Time.current
            new_contacts = []
            create_errors = []
            
            if contacts_to_create.any?
              contacts_to_create.each do |params|
                begin
                  # Create new contact
                  contact = Contact.new(
                    email: params[:email].strip,
                    first_name: params[:first_name],
                    last_name: params[:last_name],
                    status: params[:status] || 'active',
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
                    create_errors << {
                      email: params[:email],
                      errors: contact.errors.full_messages
                    }
                  end
                rescue => e
                  create_errors << {
                    email: params[:email],
                    errors: [e.message]
                  }
                end
              end
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
                
                # Use bulk insert
                ContactGroupsContact.insert_all(values)
              end
              
              add_end = Time.current
              Rails.logger.info("API CONTACT CREATE [#{add_end.iso8601(3)}]: Added #{contacts_to_add.size} contacts to group in #{(add_end - add_start).round(2)}s")
              
              group_assign_end = Time.current
              Rails.logger.info("API CONTACT CREATE [#{group_assign_end.iso8601(3)}]: Group assignment completed in #{(group_assign_end - group_assign_start).round(2)}s")
            end
            
            # Log transaction completion time
            transaction_end = Time.current
            Rails.logger.info("API CONTACT CREATE [#{transaction_end.iso8601(3)}]: Transaction completed in #{(transaction_end - transaction_start).round(2)}s")
            
            if all_errors.any?
              render json: {
                success: false,
                message: "Some contacts failed to process",
                contacts_created: new_contacts.length,
                contacts_updated: updated_contacts.length,
                total_processed: all_contacts.length,
                group_id: target_group.id,
                errors: all_errors
              }, status: :unprocessable_entity
            else
              render json: {
                success: true,
                message: "Successfully processed all contacts",
                contacts_created: new_contacts.length,
                contacts_updated: updated_contacts.length,
                total_processed: all_contacts.length,
                group_id: target_group.id,
                group_name: target_group.name,
                contacts: all_contacts.map { |c| contact_response(c) }
              }, status: :created
            end
          end
          
          # Log total request time
          end_time = Time.current
          Rails.logger.info("API CONTACT CREATE [#{end_time.iso8601(3)}]: Request completed in #{(end_time - start_time).round(2)}s")
        rescue => e
          Rails.logger.error("API ERROR [#{Time.current.iso8601(3)}]: #{e.message}\n#{e.backtrace.join("\n")}")
          render json: {
            success: false,
            message: "Error processing contacts",
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
        
        # Or use the first entity if one exists
        if current_user.entities.any?
          return current_user.entities.first.id
        end
        
        # Return nil if no entity is available (global contact)
        nil
      end
      
      def authenticate_api_request
        # Get the API key from the Authorization header
        auth_header = request.headers['Authorization']
        
        # Better header parsing
        if auth_header.blank?
          render json: { error: 'Missing Authorization header' }, status: :unauthorized
          return
        end
        
        # Support both "Bearer <key>" and just "<key>" formats
        api_key = if auth_header.start_with?('Bearer ')
          auth_header.gsub('Bearer ', '')
        else
          auth_header
        end
        
        if api_key.blank?
          render json: { error: 'Invalid Authorization header format' }, status: :unauthorized
          return
        end
        
        # Find user by API key
        @current_user = User.find_by(api_key: api_key)
        
        unless @current_user
          render json: { error: 'Invalid API key' }, status: :unauthorized
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
          corporation_id: contact.metadata&.dig('corporation_id'),
          corporation_name: contact.metadata&.dig('corporation_name'),
          status: contact.status,
          contact_groups: contact.contact_groups.map { |g| { id: g.id, name: g.name } }
        }
      end
      
      # Help convert string boolean values to actual booleans
      def parse_boolean(value)
        return nil if value.nil?
        return value if value.is_a?(TrueClass) || value.is_a?(FalseClass)
        
        case value.to_s.downcase.strip
        when 'true', 'yes', '1', 'on'
          true
        when 'false', 'no', '0', 'off'
          false
        else
          value # Return original value if not a boolean string
        end
      end
    end
  end
end 