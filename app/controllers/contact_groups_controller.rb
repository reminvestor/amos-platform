class ContactGroupsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_contact_group, only: [:show, :edit, :update, :destroy, :upload_csv]
  
  # Add a rescue_from to catch any unhandled errors in this controller
  rescue_from Exception do |exception|
    # Log the full error details
    Rails.logger.error("UNHANDLED EXCEPTION in ContactGroupsController: #{exception.class.name}: #{exception.message}")
    Rails.logger.error(exception.backtrace.join("\n"))
    
    # Redirect with an error message
    redirect_to contact_groups_path, alert: "An unexpected error occurred. Our team has been notified."
  end
  
  def index
    Rails.logger.info("INDEX: Loading contact groups for user #{current_user.id} and entity #{current_entity&.id}")
    @contact_groups = entity_scope(ContactGroup).order(name: :asc).page(params[:page])
  end

  def show
    Rails.logger.info("SHOW: Starting show action for contact group #{params[:id]}")
    
    begin
      # Ensure the contact group is loaded correctly
      unless @contact_group
        Rails.logger.error("SHOW ERROR: @contact_group is nil after set_contact_group")
        redirect_to contact_groups_path, alert: "Contact group not found"
        return
      end
      
      Rails.logger.info("SHOW: Contact group found - ID: #{@contact_group.id}, Entity: #{@contact_group.entity_id}, Name: #{@contact_group.name}")
      
      # Call debug method
      @contact_group.debug_contacts
      
      # Log contact count before query
      contact_count = @contact_group.contacts.count
      Rails.logger.info("SHOW: Contact group has #{contact_count} contacts")
      
      # Get contacts with error handling
      begin
        @contacts = @contact_group.contacts
                    .includes(:contact_groups) # Eager load to reduce N+1 queries
                    .order(last_name: :asc, first_name: :asc)
                    .page(params[:page])
        
        # Log successful retrieval
        Rails.logger.info("SHOW: Successfully loaded #{@contacts.size} contacts for page #{params[:page] || 1}")
      rescue => query_error
        Rails.logger.error("SHOW ERROR: Error querying contacts: #{query_error.class.name}: #{query_error.message}")
        Rails.logger.error(query_error.backtrace.join("\n"))
        
        # Fall back to a simpler query
        begin
          Rails.logger.info("SHOW: Trying simpler query without includes, order, or pagination")
          @contacts = @contact_group.contacts.to_a
          Rails.logger.info("SHOW: Simpler query successful, got #{@contacts.size} contacts")
        rescue => fallback_error
          Rails.logger.error("SHOW ERROR: Even simple query failed: #{fallback_error.class.name}: #{fallback_error.message}")
          Rails.logger.error(fallback_error.backtrace.join("\n"))
          @contacts = []
        end
      end
    rescue => e
      # Log the error for debugging
      Rails.logger.error("SHOW ERROR: Error in contact_groups#show: #{e.class.name}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      
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
    Rails.logger.info("SET_CONTACT_GROUP: Finding contact group #{params[:id]} for user #{current_user.id}")
    
    begin
      Rails.logger.info("SET_CONTACT_GROUP: Trying to find with entity scope (entity_id: #{current_entity&.id})")
      @contact_group = entity_scope(ContactGroup).find(params[:id])
      Rails.logger.info("SET_CONTACT_GROUP: Found group with entity scope: #{@contact_group.id}")
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.info("SET_CONTACT_GROUP: Not found with entity scope, trying user scope")
      
      # If not found with entity scope, try to find by user scope as fallback
      begin
        @contact_group = current_user.contact_groups.find(params[:id])
        Rails.logger.info("SET_CONTACT_GROUP: Found with user scope. Group ID: #{@contact_group.id}, Entity ID: #{@contact_group.entity_id}")
        
        # If the group belongs to another entity, redirect with notice
        if @contact_group.entity_id.present? && current_entity && @contact_group.entity_id != current_entity.id
          Rails.logger.warn("SET_CONTACT_GROUP: Group belongs to different entity (#{@contact_group.entity_id} vs current #{current_entity.id})")
          redirect_to contact_groups_path, alert: "That contact group belongs to a different entity."
          return
        end
      rescue ActiveRecord::RecordNotFound => user_scope_error
        Rails.logger.error("SET_CONTACT_GROUP: Not found with user scope either: #{user_scope_error.message}")
        redirect_to contact_groups_path, alert: "Contact group not found."
        return
      end
    rescue => e
      Rails.logger.error("SET_CONTACT_GROUP ERROR: Unexpected error in set_contact_group: #{e.class.name}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      redirect_to contact_groups_path, alert: "Error finding contact group: #{e.message}"
      return
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
