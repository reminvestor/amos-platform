module Api
  module V1
    class ContactsController < Api::BaseController
      respond_to :json
      protect_from_forgery with: :null_session
      skip_before_action :verify_authenticity_token
      before_action :authenticate_api_request
      
      def create
        begin
          # Log all incoming parameters
          Rails.logger.info("API CONTACT CREATE: Received parameters: #{params.to_json}")
          
          ActiveRecord::Base.transaction do
            contacts = []
            errors = []
            
            # Check if contacts parameter is present
            unless params[:contacts].present? && params[:contacts].is_a?(Array)
              render json: {
                success: false,
                message: "Missing or invalid contacts parameter"
              }, status: :bad_request
              return
            end
            
            # Get the user's active entity or default entity
            user_entity_id = determine_entity_id
            
            # Step 1: Create or find the target group
            target_group = if params[:contact_group_id].present?
              # Find existing group
              group = current_user.contact_groups.find_by(id: params[:contact_group_id])
              unless group
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
            
            Rails.logger.info("API CONTACT CREATE: Using group ID: #{target_group.id}")
            
            # Step 2: Process each contact
            params[:contacts].each do |contact_params|
              begin
                # Find or create the contact
                contact = Contact.find_or_initialize_by(
                  email: contact_params[:email].strip,
                  user_id: current_user.id,
                  entity_id: user_entity_id
                )
                
                # Update contact attributes
                contact.first_name = contact_params[:first_name] if contact_params[:first_name].present?
                contact.last_name = contact_params[:last_name] if contact_params[:last_name].present?
                contact.status = contact_params[:status] || 'active'
                
                # Set metadata for corporation info
                contact.metadata ||= {}
                contact.metadata = contact.metadata.merge({
                  corporation_id: contact_params[:corporation_id],
                  corporation_name: contact_params[:corporation_name]
                }.compact)
                
                if contact.save
                  # Step 3: Handle group membership - simple approach
                  if user_entity_id.present?
                    # If we have an entity, remove from all groups in that entity
                    group_scope = ContactGroup.where(entity_id: user_entity_id)
                  else
                    # If no entity, only remove from global groups
                    group_scope = ContactGroup.where(entity_id: nil)
                  end
                  
                  # Get all relevant group IDs the contact belongs to except the target group
                  current_group_ids = contact.contact_groups.where(id: group_scope.pluck(:id)).pluck(:id)
                  current_group_ids -= [target_group.id]
                  
                  # Remove from other groups in one operation if needed
                  if current_group_ids.any?
                    contact.contact_groups.delete(ContactGroup.where(id: current_group_ids))
                    Rails.logger.info("API CONTACT CREATE: Removed contact #{contact.id} from groups: #{current_group_ids.join(',')}")
                  end
                  
                  # Add to target group if not already in it
                  unless contact.contact_groups.include?(target_group)
                    target_group.contacts << contact
                    Rails.logger.info("API CONTACT CREATE: Added contact #{contact.id} to group #{target_group.id}")
                  end
                  
                  contacts << contact
                else
                  errors << {
                    email: contact_params[:email],
                    errors: contact.errors.full_messages
                  }
                  Rails.logger.error("API CONTACT CREATE: Failed to save contact: #{contact.errors.full_messages}")
                end
              rescue => e
                errors << {
                  email: contact_params[:email],
                  errors: [e.message]
                }
                Rails.logger.error("API CONTACT CREATE: Exception processing contact: #{e.message}")
              end
            end
            
            if errors.any?
              render json: {
                success: false,
                message: "Some contacts failed to process",
                contacts_created: contacts.length,
                group_id: target_group.id,
                errors: errors
              }, status: :unprocessable_entity
            else
              render json: {
                success: true,
                message: "Successfully processed #{contacts.length} contacts",
                group_id: target_group.id,
                group_name: target_group.name,
                contacts: contacts.map { |c| contact_response(c) }
              }, status: :created
            end
          end
        rescue => e
          Rails.logger.error("API Error: #{e.message}\n#{e.backtrace.join("\n")}")
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