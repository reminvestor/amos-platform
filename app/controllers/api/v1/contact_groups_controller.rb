# frozen_string_literal: true

module Api
  module V1
    class ContactGroupsController < BaseController
      before_action :set_contact_group, only: [:show, :update, :destroy, :add_contacts, :remove_contacts]

      # GET /api/v1/contact_groups
      def index
        @contact_groups = current_entity.contact_groups
                                        .order(name: :asc)
                                        .page(params[:page] || 1)
                                        .per(params[:per_page] || 50)

        if params[:search].present?
          @contact_groups = @contact_groups.where("name ILIKE ?", "%#{params[:search]}%")
        end

        render json: {
          data: @contact_groups.map { |g| group_json(g) },
          meta: {
            current_page: @contact_groups.current_page,
            total_pages: @contact_groups.total_pages,
            total_count: @contact_groups.total_count
          }
        }
      end

      # GET /api/v1/contact_groups/:id
      def show
        contacts = @contact_group.contacts
                                 .order(last_name: :asc, first_name: :asc)
                                 .page(params[:page] || 1)
                                 .per(params[:per_page] || 50)

        render json: {
          **group_json(@contact_group),
          contacts: contacts.map { |c| contact_json(c) },
          meta: {
            current_page: contacts.current_page,
            total_pages: contacts.total_pages,
            total_count: contacts.total_count
          }
        }
      end

      # POST /api/v1/contact_groups
      def create
        @contact_group = current_user.contact_groups.new(contact_group_params)
        @contact_group.entity = current_entity

        if @contact_group.save
          render json: group_json(@contact_group), status: :created
        else
          render json: { errors: @contact_group.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # PATCH/PUT /api/v1/contact_groups/:id
      def update
        if @contact_group.update(contact_group_params)
          render json: group_json(@contact_group)
        else
          render json: { errors: @contact_group.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/contact_groups/:id
      def destroy
        if @contact_group.contacts.any?
          render json: { error: "Cannot delete group with contacts. Remove contacts first." }, status: :unprocessable_entity
        elsif @contact_group.destroy
          render json: { success: true }
        else
          render json: { errors: @contact_group.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/contact_groups/:id/add_contacts
      def add_contacts
        contact_ids = params[:contact_ids] || []
        contacts = current_entity.contacts.where(id: contact_ids)

        added_count = 0
        contacts.each do |contact|
          unless @contact_group.contacts.include?(contact)
            @contact_group.contacts << contact
            added_count += 1
          end
        end

        render json: {
          success: true,
          added_count: added_count,
          total_count: @contact_group.contacts.count
        }
      end

      # POST /api/v1/contact_groups/:id/remove_contacts
      def remove_contacts
        contact_ids = params[:contact_ids] || []
        contacts = @contact_group.contacts.where(id: contact_ids)

        removed_count = contacts.count
        @contact_group.contacts.delete(contacts)

        render json: {
          success: true,
          removed_count: removed_count,
          total_count: @contact_group.contacts.count
        }
      end

      private

      def set_contact_group
        @contact_group = current_entity.contact_groups.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Contact group not found" }, status: :not_found
      end

      def contact_group_params
        params.permit(:name, :description)
      end

      def group_json(group)
        {
          id: group.id,
          name: group.name,
          description: group.description,
          contacts_count: group.contacts.count,
          created_at: group.created_at,
          updated_at: group.updated_at
        }
      end

      def contact_json(contact)
        {
          id: contact.id,
          email: contact.email,
          first_name: contact.first_name,
          last_name: contact.last_name,
          name: "#{contact.first_name} #{contact.last_name}".strip,
          company: contact.company,
          status: contact.status,
          created_at: contact.created_at
        }
      end
    end
  end
end
