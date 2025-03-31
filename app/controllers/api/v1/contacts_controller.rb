module Api
  module V1
    class ContactsController < Api::BaseController
      respond_to :json
      protect_from_forgery with: :null_session
      skip_before_action :verify_authenticity_token
      before_action :authenticate_api_request
      
      def create
        begin
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
            
            # Process each contact in the request
            params[:contacts].each do |contact_params|
              begin
                # Get the user's active entity or default entity
                user_entity_id = determine_entity_id
                
                # Find or create contact, scoped by entity and email
                find_params = { email: contact_params[:email] }
                
                # Only add entity scope if an entity was found
                find_params[:entity_id] = user_entity_id if user_entity_id.present?
                
                # Always include user association
                find_params[:user_id] = current_user.id
                
                contact = Contact.find_or_initialize_by(find_params)
                
                # Update contact attributes
                contact.first_name = contact_params[:first_name]
                contact.last_name = contact_params[:last_name]
                
                # Set entity_id from user's active entity
                contact.entity_id = user_entity_id
                
                # Store corporation info in metadata
                contact.metadata ||= {}
                contact.metadata = contact.metadata.merge({
                  corporation_id: contact_params[:corporation_id],
                  corporation_name: contact_params[:corporation_name]
                })
                
                contact.status = contact_params[:status] || 'active'
                
                if contact.save
                  contacts << contact
                  
                  # Handle group assignment
                  if params[:contact_group_id].present?
                    # Add to specified group
                    target_group = current_user.contact_groups.find(params[:contact_group_id])
                    
                    # Only remove from groups in the same entity
                    if user_entity_id
                      entity_groups = contact.contact_groups.where(entity_id: user_entity_id)
                      contact.contact_groups.delete(entity_groups) if entity_groups.any?
                    else
                      # For global contacts (no entity), clear all groups
                      contact.contact_groups.clear if contact.contact_groups.any?
                    end
                    
                    # Add to target group
                    target_group.contacts << contact
                  else
                    # Create new group if none specified
                    group = current_user.contact_groups.create!(
                      name: "API Import #{Time.current.strftime('%Y-%m-%d %H:%M')}",
                      description: "Automatically created group for API import",
                      entity_id: user_entity_id # Set entity_id on new group
                    )
                    
                    # Only remove from groups in the same entity
                    if user_entity_id
                      entity_groups = contact.contact_groups.where(entity_id: user_entity_id)
                      contact.contact_groups.delete(entity_groups) if entity_groups.any?
                    else
                      # For global contacts (no entity), clear all groups
                      contact.contact_groups.clear if contact.contact_groups.any?
                    end
                    
                    # Add to new group
                    group.contacts << contact
                  end
                else
                  errors << {
                    email: contact_params[:email],
                    errors: contact.errors.full_messages
                  }
                end
              rescue => e
                errors << {
                  email: contact_params[:email],
                  errors: [e.message]
                }
              end
            end
            
            if errors.any?
              render json: {
                success: false,
                message: "Some contacts failed to process",
                contacts_created: contacts.length,
                errors: errors
              }, status: :unprocessable_entity
            else
              render json: {
                success: true,
                message: "Successfully processed #{contacts.length} contacts",
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
    end
  end
end 