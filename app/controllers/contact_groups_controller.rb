class ContactGroupsController < ApplicationController
  require 'csv'
  
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
    
    # Debug Contact schema
    begin
      Contact.debug_schema
      ContactGroupsContact.debug_schema
    rescue => schema_error
      Rails.logger.error("SHOW ERROR: Failed to debug schemas: #{schema_error.message}")
    end
    
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
        # Use simple query with basic ordering that won't conflict with DISTINCT
        contact_ids = @contact_group.contact_ids
        @contacts = Contact.where(id: contact_ids)
                          .order(last_name: :asc, first_name: :asc)
                          .page(params[:page])
        
        # Log successful retrieval
        Rails.logger.info("SHOW: Successfully loaded #{@contacts.size} contacts for page #{params[:page] || 1}")
        
        # Support CSV format for export
        respond_to do |format|
          format.html
          format.csv do
            csv_data = CSV.generate(headers: true) do |csv|
              # Add headers
              csv << ["Name", "Email", "Corporation ID", "Corporation Name", "Status", "Created At"]
              
              # Get all contacts without pagination
              all_contacts = Contact.where(id: contact_ids)
                                  .order(last_name: :asc, first_name: :asc)
              all_contacts.each do |contact|
                name = if contact.respond_to?(:name) && contact.name.present?
                  contact.name
                elsif contact.respond_to?(:full_name) && contact.full_name.present?
                  contact.full_name
                else
                  "#{contact.first_name} #{contact.last_name}".strip rescue "Unknown"
                end
                
                corporation_id = contact.respond_to?(:corporation_id) ? contact.corporation_id : contact.metadata&.dig('corporation_id')
                corporation_name = contact.respond_to?(:corporation_name) ? contact.corporation_name : contact.metadata&.dig('corporation_name')
                
                csv << [
                  name,
                  contact.email,
                  corporation_id,
                  corporation_name,
                  contact.status,
                  contact.created_at.strftime("%Y-%m-%d %H:%M:%S")
                ]
              end
            end
            
            send_data csv_data, 
              filename: "contacts_#{@contact_group.name.parameterize}_#{Date.today}.csv",
              type: "text/csv",
              disposition: "attachment"
          end
        end
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

      # Clear existing contacts if requested
      if params[:clear_existing].present? && params[:clear_existing] == "1"
        Rails.logger.info("UPLOAD_CSV: Clearing existing contacts from group #{@contact_group.id}")
        contact_count = @contact_group.contacts.count
        @contact_group.contacts.clear
        Rails.logger.info("UPLOAD_CSV: Cleared #{contact_count} contacts from group #{@contact_group.id}")
      end

      CSV.foreach(csv_file.path, headers: true) do |row|
        begin
          Rails.logger.info("UPLOAD_CSV: Processing row with email #{row['email']}")
          
          # Skip rows with missing email
          if row['email'].blank?
            error_count += 1
            errors << "Row #{$.}: Missing email address"
            next
          end
          
          # Find or create contact
          contact = Contact.find_or_initialize_by(
            email: row['email'].strip,
            user: current_user
          )

          # Set entity_id if we're in an entity context
          contact.entity_id = current_entity.id if current_entity

          # Update contact attributes
          if row['name'].present?
            if row['name'].include?(' ')
              # Split name into first and last name
              name_parts = row['name'].strip.split(' ', 2)
              contact.first_name = name_parts[0]
              contact.last_name = name_parts[1]
            else
              contact.first_name = row['name'].strip
            end
          end
          
          # Store corporation data in metadata
          contact.metadata ||= {}
          if row['corporation_id'].present? || row['corporation_name'].present?
            contact.metadata = contact.metadata.merge({
              'corporation_id' => row['corporation_id'].to_s.strip,
              'corporation_name' => row['corporation_name'].to_s.strip
            })
          end
          
          # Set default status if not present
          contact.status ||= 'active'

          if contact.save
            Rails.logger.info("UPLOAD_CSV: Saved contact #{contact.id} (#{contact.email})")
            
            # Add to current group if not already in it
            unless @contact_group.contacts.include?(contact)
              @contact_group.contacts << contact
              Rails.logger.info("UPLOAD_CSV: Added contact #{contact.id} to group #{@contact_group.id}")
            end
            
            success_count += 1
          else
            error_count += 1
            errors << "Row #{$.}: #{contact.errors.full_messages.join(', ')}"
            Rails.logger.error("UPLOAD_CSV: Error saving contact: #{contact.errors.full_messages.join(', ')}")
          end
        rescue => e
          error_count += 1
          errors << "Row #{$.}: #{e.message}"
          Rails.logger.error("UPLOAD_CSV: Exception processing row: #{e.message}")
        end
      end

      if error_count > 0
        flash[:alert] = "Upload completed with #{success_count} successful and #{error_count} failed records."
        Rails.logger.error("UPLOAD_CSV: Errors: #{errors.join('; ')}")
      else
        flash[:notice] = "Successfully uploaded #{success_count} contacts."
      end

      redirect_to @contact_group
    rescue => e
      Rails.logger.error("UPLOAD_CSV ERROR: #{e.message}\n#{e.backtrace.join("\n")}")
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
