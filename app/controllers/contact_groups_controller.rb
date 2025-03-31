class ContactGroupsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_contact_group, only: [:show, :edit, :update, :destroy, :upload_csv]
  
  def index
    @contact_groups = entity_scope(ContactGroup).order(name: :asc).page(params[:page])
  end

  def show
    begin
      # Ensure the contact group is loaded correctly
      unless @contact_group
        redirect_to contact_groups_path, alert: "Contact group not found"
        return
      end
      
      # Get contacts with error handling
      @contacts = @contact_group.contacts
                  .includes(:contact_groups) # Eager load to reduce N+1 queries
                  .order(last_name: :asc, first_name: :asc)
                  .page(params[:page])
    rescue => e
      # Log the error for debugging
      Rails.logger.error("Error in contact_groups#show: #{e.message}\n#{e.backtrace.join("\n")}")
      
      # Redirect with error message
      redirect_to contact_groups_path, alert: "Error loading contact group: #{e.message}"
    end
  end

  def new
    @contact_group = current_user.contact_groups.new
    # Initialize with empty contact selection
    @selected_contact_ids = []
    load_filtered_contacts
  end

  def create
    @contact_group = current_user.contact_groups.new(contact_group_params)
    @contact_group.entity = current_entity if current_entity
    
    if @contact_group.save
      redirect_to contact_groups_path, notice: 'Contact group was successfully created.'
    else
      @selected_contact_ids = params[:contact_group][:contact_ids] || []
      load_filtered_contacts
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @selected_contact_ids = @contact_group.contact_ids
    load_filtered_contacts
  end

  def update
    if @contact_group.update(contact_group_params)
      redirect_to contact_groups_path, notice: 'Contact group was successfully updated.'
    else
      @selected_contact_ids = params[:contact_group][:contact_ids] || @contact_group.contact_ids
      load_filtered_contacts
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @contact_group.destroy
      redirect_to contact_groups_path, notice: 'Contact group was successfully deleted.'
    else
      redirect_to contact_groups_path, alert: @contact_group.errors.full_messages.to_sentence
    end
  end
  
  def upload_csv
    if params[:file].blank?
      redirect_to @contact_group, alert: 'Please select a CSV file to upload.'
      return
    end

    begin
      require 'csv'
      csv_file = params[:file]
      success_count = 0
      error_count = 0
      errors = []

      CSV.foreach(csv_file.path, headers: true) do |row|
        begin
          # Find or create contact
          contact = Contact.find_or_initialize_by(
            email: row['email'],
            user: current_user
          )

          # Update contact attributes
          contact.name = row['name']
          contact.corporation_id = row['corporation_id']
          contact.corporation_name = row['corporation_name']

          if contact.save
            # Remove from other groups in the same entity
            if @contact_group.entity_id.present?
              # Only remove from groups in the same entity
              same_entity_groups = ContactGroup.where(
                user: current_user, 
                entity_id: @contact_group.entity_id
              ).where.not(id: @contact_group.id)
              
              same_entity_groups.each do |group|
                group.contacts.delete(contact) if group.contacts.include?(contact)
              end
            else
              # For global groups (no entity), only remove from other global groups
              global_groups = ContactGroup.where(
                user: current_user,
                entity_id: nil
              ).where.not(id: @contact_group.id)
              
              global_groups.each do |group|
                group.contacts.delete(contact) if group.contacts.include?(contact)
              end
            end
            
            # Add to current group
            @contact_group.contacts << contact unless @contact_group.contacts.include?(contact)
            success_count += 1
          else
            error_count += 1
            errors << "Row #{row.to_h}: #{contact.errors.full_messages.join(', ')}"
          end
        rescue => e
          error_count += 1
          errors << "Row #{row.to_h}: #{e.message}"
        end
      end

      if error_count > 0
        flash[:alert] = "Upload completed with #{success_count} successful and #{error_count} failed records. #{errors.join('; ')}"
      else
        flash[:notice] = "Successfully uploaded #{success_count} contacts."
      end

      redirect_to @contact_group
    rescue => e
      redirect_to @contact_group, alert: "Error processing CSV: #{e.message}"
    end
  end
  
  # AJAX endpoint for contacts search
  def search_contacts
    Rails.logger.debug "Search params: #{params.inspect}"
    @selected_contact_ids = params[:selected_ids] || []
    load_filtered_contacts
    
    respond_to do |format|
      format.html do
        if turbo_frame_request?
          Rails.logger.debug "Rendering Turbo Frame response"
          render partial: "contacts_results", locals: { 
            contacts: @contacts, 
            selected_contact_ids: @selected_contact_ids 
          }, layout: false
        else
          Rails.logger.debug "Rendering HTML partial"
          render partial: "contacts_selection", locals: { 
            contacts: @contacts, 
            selected_contact_ids: @selected_contact_ids 
          }
        end
      end
      format.js do
        Rails.logger.debug "Rendering JS response"
        render partial: "contacts_selection", locals: { 
          contacts: @contacts, 
          selected_contact_ids: @selected_contact_ids 
        }
      end
      format.turbo_stream do
        Rails.logger.debug "Rendering Turbo Stream"
        render turbo_stream: turbo_stream.replace(
          "contacts_results",
          partial: "contacts_results",
          locals: { 
            contacts: @contacts, 
            selected_contact_ids: @selected_contact_ids 
          }
        )
      end
    end
  end
  
  private
  
  def set_contact_group
    begin
      @contact_group = entity_scope(ContactGroup).find(params[:id])
    rescue ActiveRecord::RecordNotFound
      # If not found with entity scope, try to find by user scope as fallback
      # This can happen if a contact group exists but is not associated with the current entity
      @contact_group = current_user.contact_groups.find(params[:id])
      
      # If the group belongs to another entity, redirect with notice
      if @contact_group.entity_id.present? && current_entity && @contact_group.entity_id != current_entity.id
        redirect_to contact_groups_path, alert: "That contact group belongs to a different entity."
        return
      end
    end
  end
  
  def contact_group_params
    params.require(:contact_group).permit(:name, :description, contact_ids: [])
  end
  
  def load_filtered_contacts
    # Start with basic scope
    contacts_scope = entity_scope(Contact)
    
    # Apply search if present
    if params[:search].present?
      search_term = "%#{params[:search]}%"
      contacts_scope = contacts_scope.where(
        "first_name ILIKE ? OR last_name ILIKE ? OR email ILIKE ?",
        search_term, search_term, search_term
      )
    end
    
    # Apply any other filters
    if params[:status].present?
      contacts_scope = contacts_scope.where(status: params[:status])
    end
    
    # Order and paginate
    @contacts = contacts_scope.order(last_name: :asc, first_name: :asc)
                             .page(params[:page])
                             .per(100)
  end
end
