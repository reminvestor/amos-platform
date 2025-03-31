class ContactGroupsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_contact_group, only: [:show, :edit, :update, :destroy, :upload_csv]
  
  def index
    @contact_groups = entity_scope(ContactGroup).order(name: :asc).page(params[:page])
  end

  def show
    @contacts = @contact_group.contacts.order(last_name: :asc, first_name: :asc).page(params[:page])
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
            # Remove from other groups and add to current group
            ContactGroup.where(user: current_user).where.not(id: @contact_group.id).each do |group|
              group.contacts.delete(contact)
            end
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
    @contact_group = entity_scope(ContactGroup).find(params[:id])
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
