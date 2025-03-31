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
              }, status: :bad_request, content_type: 'application/json'
              return
            end
            
            # Process each contact in the request
            params[:contacts].each do |contact_params|
              begin
                # Find or create contact
                contact = Contact.find_or_initialize_by(
                  email: contact_params[:email],
                  user: current_user
                )
                
                # Update contact attributes
                contact.first_name = contact_params[:first_name]
                contact.last_name = contact_params[:last_name]
                contact.corporation_id = contact_params[:corporation_id]
                contact.corporation_name = contact_params[:corporation_name]
                contact.status = contact_params[:status] || 'active'
                
                if contact.save
                  contacts << contact
                  
                  # Handle group assignment
                  if params[:contact_group_id].present?
                    # Add to specified group
                    target_group = current_user.contact_groups.find(params[:contact_group_id])
                    target_group.contacts << contact
                  else
                    # Create new group if none specified
                    group = current_user.contact_groups.create!(
                      name: "API Import #{Time.current.strftime('%Y-%m-%d %H:%M')}",
                      description: "Automatically created group for API import"
                    )
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
              }, status: :unprocessable_entity, content_type: 'application/json'
            else
              render json: {
                success: true,
                message: "Successfully processed #{contacts.length} contacts",
                contacts: contacts.map { |c| contact_response(c) }
              }, status: :created, content_type: 'application/json'
            end
          end
        rescue => e
          Rails.logger.error("API Error: #{e.message}\n#{e.backtrace.join("\n")}")
          render json: {
            success: false,
            message: "Error processing contacts",
            error: e.message
          }, status: :internal_server_error, content_type: 'application/json'
        end
      end
      
      private
      
      def authenticate_api_request
        # Get the API key from the Authorization header
        auth_header = request.headers['Authorization']
        
        # Better header parsing
        if auth_header.blank?
          render json: { error: 'Missing Authorization header' }, status: :unauthorized, content_type: 'application/json'
          return
        end
        
        # Support both "Bearer <key>" and just "<key>" formats
        api_key = if auth_header.start_with?('Bearer ')
          auth_header.gsub('Bearer ', '')
        else
          auth_header
        end
        
        if api_key.blank?
          render json: { error: 'Invalid Authorization header format' }, status: :unauthorized, content_type: 'application/json'
          return
        end
        
        # Find user by API key
        @current_user = User.find_by(api_key: api_key)
        
        unless @current_user
          render json: { error: 'Invalid API key' }, status: :unauthorized, content_type: 'application/json'
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
          corporation_id: contact.corporation_id,
          corporation_name: contact.corporation_name,
          status: contact.status,
          contact_groups: contact.contact_groups.map { |g| { id: g.id, name: g.name } }
        }
      end
    end
  end
end 