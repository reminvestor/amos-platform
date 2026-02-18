class ContactsController < ApplicationController
  include Authorizable
  before_action :authenticate_user!
  layout 'customer_admin'
  before_action :set_contact, only: [ :show, :edit, :update, :destroy ]
  before_action :authorize_destroy!, only: [:destroy]

  def index
    @contacts = current_entity.contacts.order(created_at: :desc).page(params[:page])
  end

  def import
    unless params[:file].present?
      return render json: { success: false, error: "No file provided" }, status: :unprocessable_entity
    end

    file = params[:file]
    extension = File.extname(file.original_filename).downcase

    unless ['.csv', '.xlsx', '.xls'].include?(extension)
      return render json: { success: false, error: "Invalid file type. Please upload a CSV or Excel file." }, status: :unprocessable_entity
    end

    begin
      imported_count = 0
      skipped_count = 0
      errors = []

      if extension == '.csv'
        require 'csv'
        CSV.foreach(file.path, headers: true, header_converters: :symbol) do |row|
          result = import_contact_row(row.to_h)
          if result[:success]
            imported_count += 1
          else
            skipped_count += 1
            errors << result[:error] if errors.length < 5
          end
        end
      else
        # Excel file - use roo gem if available
        if defined?(Roo)
          spreadsheet = Roo::Spreadsheet.open(file.path)
          headers = spreadsheet.row(1).map { |h| h.to_s.downcase.gsub(/\s+/, '_').to_sym }
          
          (2..spreadsheet.last_row).each do |i|
            row_data = Hash[headers.zip(spreadsheet.row(i))]
            result = import_contact_row(row_data)
            if result[:success]
              imported_count += 1
            else
              skipped_count += 1
              errors << result[:error] if errors.length < 5
            end
          end
        else
          return render json: { success: false, error: "Excel import not supported. Please use CSV format." }, status: :unprocessable_entity
        end
      end

      render json: {
        success: true,
        imported: imported_count,
        skipped: skipped_count,
        errors: errors,
        message: "Successfully imported #{imported_count} contacts. #{skipped_count} skipped."
      }
    rescue => e
      Rails.logger.error "Contact import error: #{e.message}"
      render json: { success: false, error: "Import failed: #{e.message}" }, status: :unprocessable_entity
    end
  end

  def show
  end

  def new
    @contact = current_entity.contacts.new
    @contact_groups = current_entity.contact_groups
  end

  def create
    @contact = current_entity.contacts.new(contact_params)

    if @contact.save
      redirect_to contacts_path, notice: "Contact was successfully created."
    else
      @contact_groups = current_entity.contact_groups
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @contact_groups = current_entity.contact_groups
  end

  def update
    if @contact.update(contact_params)
      redirect_to contacts_path, notice: "Contact was successfully updated."
    else
      @contact_groups = current_entity.contact_groups
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @contact.destroy
    redirect_to contacts_path, notice: "Contact was successfully deleted."
  end

  private

  def set_contact
    @contact = current_entity.contacts.find(params[:id])
  end

  def contact_params
    params.require(:contact).permit(:email, :first_name, :last_name, :status, :tags, contact_group_ids: [])
  end

  def import_contact_row(row)
    email = extract_email(row)
    first_name = row[:first_name] || row[:firstname] || row[:first] || row[:given_name]
    last_name = row[:last_name] || row[:lastname] || row[:last] || row[:family_name]
    tags = row[:tags] || row[:tag]
    phone = extract_phone(row)

    # If no direct name fields, try splitting a "name" column
    if first_name.blank? && last_name.blank? && row[:name].present?
      parts = row[:name].to_s.strip.split(/\s+/, 2)
      first_name = parts[0]
      last_name = parts[1]
    end

    return { success: false, error: "No email address" } unless email.present?

    existing = current_entity.contacts.find_by(email: email.to_s.strip.downcase)
    if existing
      return { success: false, error: "#{email} already exists" }
    end

    # Collect any extra columns into custom_fields
    known_keys = %i[email email_address e_mail first_name firstname first given_name
                     last_name lastname last family_name name tags tag phone phone_number
                     status lifecycle_stage lead_source]
    extra_fields = {}
    row.each do |key, value|
      next if value.blank?
      key_str = key.to_s
      next if known_keys.include?(key)
      next if key_str.match?(/e?mail.*(?:value|type|label)/i)
      next if key_str.match?(/phone.*(?:value|type|label)/i)
      extra_fields[key_str] = value.to_s.strip
    end

    contact = current_entity.contacts.new(
      email: email.to_s.strip.downcase,
      first_name: first_name.to_s.strip,
      last_name: last_name.to_s.strip,
      tags: tags.to_s.strip,
      status: 'active',
      custom_fields: extra_fields.presence || {}
    )

    if phone.present?
      contact.metadata = (contact.metadata || {}).merge("phone" => phone.to_s.strip)
    end

    if contact.save
      { success: true, contact: contact }
    else
      { success: false, error: "#{email}: #{contact.errors.full_messages.join(', ')}" }
    end
  end

  def extract_email(row)
    # Direct column matches
    email = row[:email] || row[:email_address] || row[:e_mail]
    return email if email.present?

    # Google Contacts / vCard format: "E-mail 1 - Value" → :email_1__value etc.
    row.each do |key, value|
      next if value.blank?
      key_str = key.to_s
      if key_str.match?(/e?mail.*value/i) || key_str.match?(/email_?\d/i)
        return value
      end
    end

    nil
  end

  def extract_phone(row)
    phone = row[:phone] || row[:phone_number] || row[:mobile]
    return phone if phone.present?

    row.each do |key, value|
      next if value.blank?
      key_str = key.to_s
      if key_str.match?(/phone.*value/i)
        return value
      end
    end

    nil
  end
end
