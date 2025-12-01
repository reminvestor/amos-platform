# frozen_string_literal: true

module Api
  module V1
    class ContactsListController < BaseController
      before_action :set_contact, only: [:show, :update, :destroy]

      def index
        @contacts = current_entity.contacts
                                  .includes(:contact_groups)
                                  .order(created_at: :desc)
                                  .page(params[:page] || 1)
                                  .per(params[:per_page] || 20)

        if params[:search].present?
          search_term = "%#{params[:search]}%"
          @contacts = @contacts.where(
            "email ILIKE ? OR first_name ILIKE ? OR last_name ILIKE ?",
            search_term, search_term, search_term
          )
        end

        if params[:group_id].present?
          @contacts = @contacts.joins(:contact_groups).where(contact_groups: { id: params[:group_id] })
        end

        render json: {
          data: @contacts.map { |c| contact_json(c) },
          pagination: {
            current_page: @contacts.current_page,
            total_pages: @contacts.total_pages,
            total_count: @contacts.total_count,
            per_page: @contacts.limit_value
          }
        }
      end

      def show
        render json: contact_json(@contact)
      end

      def create
        @contact = current_entity.contacts.build(contact_params)

        if @contact.save
          render json: contact_json(@contact), status: :created
        else
          render json: { errors: @contact.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        if @contact.update(contact_params)
          render json: contact_json(@contact)
        else
          render json: { errors: @contact.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        @contact.destroy
        head :no_content
      end

      private

      def set_contact
        @contact = current_entity.contacts.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { message: "Contact not found" }, status: :not_found
      end

      def contact_params
        params.permit(:email, :first_name, :last_name, :phone, :company, :notes)
      end

      def contact_json(contact)
        {
          id: contact.id,
          email: contact.email,
          first_name: contact.first_name,
          last_name: contact.last_name,
          name: "#{contact.first_name} #{contact.last_name}".strip,
          phone: contact.phone,
          company: contact.company,
          status: contact.status,
          groups: contact.contact_groups.map { |g| { id: g.id, name: g.name } },
          created_at: contact.created_at,
          updated_at: contact.updated_at
        }
      end

    end
  end
end
