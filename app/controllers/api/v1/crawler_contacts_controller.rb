module Api
  module V1
    class CrawlerContactsController < Api::BaseController
      # Authenticate user via API key before processing the request
      before_action :authenticate_user_via_api_key!

      # POST /api/v1/crawler_contacts
      def create
        # Ensure we have an entity context from the authenticated user
        unless @current_entity
          render json: { error: "User entity context not found." }, status: :unprocessable_entity
          return
        end

        contact_params = params.require(:contact).permit(:first_name, :last_name, :email)

        # Validate email presence
        if contact_params[:email].blank?
          render json: { error: "Email cannot be blank." }, status: :unprocessable_entity
          return
        end

        # Find or initialize contact within the user's current entity
        contact = @current_entity.contacts.find_or_initialize_by(email: contact_params[:email])

        # Assign attributes (this will update if found, or prepare if new)
        contact.assign_attributes(
          first_name: contact_params[:first_name],
          last_name: contact_params[:last_name]
          # Add any other relevant default fields if needed, e.g., source
          # contact.source = 'web_crawler'
        )

        if contact.save
          render json: { message: "Contact processed successfully.", contact: contact.as_json(only: [ :id, :first_name, :last_name, :email ]) }, status: contact.persisted? ? :ok : :created
        else
          render json: { error: "Failed to save contact.", details: contact.errors.full_messages }, status: :unprocessable_entity
        end
      rescue ActionController::ParameterMissing => e
        render json: { error: "Invalid request format.", details: e.message }, status: :bad_request
      end

      private

      def authenticate_user_via_api_key!
        api_key = request.headers["Authorization"]&.split(" ")&.last

        if api_key.blank?
          render json: { error: "API key missing" }, status: :unauthorized
          return
        end

        @current_user = User.find_by(api_key: api_key)

        unless @current_user
          render json: { error: "Invalid API key" }, status: :unauthorized
          return
        end

        # Assuming user has a current_entity or similar association
        @current_entity = @current_user.current_entity

        unless @current_entity
          # Handle case where user might not have a selected entity
          # This might depend on your application logic. Maybe default to first entity?
          # For now, render an error.
          render json: { error: "User entity context not established." }, status: :unprocessable_entity
        end
      end
    end
  end
end
