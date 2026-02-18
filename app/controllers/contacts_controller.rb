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
        rows = CSV.read(file.path, headers: true, header_converters: :symbol)
        column_mapping = compute_column_mapping(rows)

        rows.each do |row|
          result = import_contact_row(row.to_h, column_mapping)
          if result[:success]
            imported_count += 1
          else
            skipped_count += 1
            errors << result[:error] if errors.length < 5
          end
        end
      else
        if defined?(Roo)
          spreadsheet = Roo::Spreadsheet.open(file.path)
          headers = spreadsheet.row(1).map { |h| h.to_s.downcase.gsub(/\s+/, '_').to_sym }

          all_rows = (2..spreadsheet.last_row).map { |i| Hash[headers.zip(spreadsheet.row(i))] }
          column_mapping = compute_column_mapping_from_arrays(headers, all_rows)

          all_rows.each do |row_data|
            result = import_contact_row(row_data, column_mapping)
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

  def import_contact_row(row, column_mapping = {})
    if column_mapping.present?
      email = read_mapped_field(row, column_mapping, :email)
      first_name = read_mapped_field(row, column_mapping, :first_name)
      last_name = read_mapped_field(row, column_mapping, :last_name)
      phone = read_mapped_field(row, column_mapping, :phone)
      tags = read_mapped_field(row, column_mapping, :tags)
      company = read_mapped_field(row, column_mapping, :company)

      if first_name.blank? && last_name.blank? && column_mapping[:name_column]
        full_name = row[column_mapping[:name_column].to_sym]
        if full_name.present?
          parts = full_name.to_s.strip.split(/\s+/, 2)
          first_name = parts[0]
          last_name = parts[1]
        end
      end
    else
      email = extract_field_by_scan(row, /\A(email|e_mail|email_address)\z/i, /e?mail.*value/i)
      first_name = row[:first_name] || row[:firstname] || row[:given_name]
      last_name = row[:last_name] || row[:lastname] || row[:family_name]
      phone = extract_field_by_scan(row, /\A(phone|mobile|cell)\z/i, /phone.*value/i)
      tags = row[:tags] || row[:tag]
      company = nil
    end

    return { success: false, error: "No email address" } unless email.present?

    existing = current_entity.contacts.find_by(email: email.to_s.strip.downcase)
    return { success: false, error: "#{email} already exists" } if existing

    # Everything not in the mapping goes to custom_fields
    mapped_headers = column_mapping.values.map { |v| v.to_s.downcase }
    extra_fields = {}
    row.each do |key, value|
      next if value.blank?
      next if mapped_headers.include?(key.to_s.downcase)
      extra_fields[key.to_s] = value.to_s.strip
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
    if company.present?
      contact.metadata = (contact.metadata || {}).merge("company" => company.to_s.strip)
    end

    if contact.save
      { success: true, contact: contact }
    else
      { success: false, error: "#{email}: #{contact.errors.full_messages.join(', ')}" }
    end
  end

  def read_mapped_field(row, mapping, field)
    header = mapping[field]
    return nil unless header.present?
    row[header.to_sym].presence
  end

  def extract_field_by_scan(row, *patterns)
    row.each do |key, value|
      next if value.blank?
      key_str = key.to_s
      return value if patterns.any? { |p| key_str.match?(p) }
    end
    nil
  end

  def compute_column_mapping(csv_table)
    headers = csv_table.headers.map(&:to_s)
    sample_rows = csv_table.first(5).map(&:to_h)

    mapper = CsvColumnMapperService.new(
      headers: headers,
      sample_rows: sample_rows,
      entity: current_entity
    )
    mapper.compute_mapping
  end

  def compute_column_mapping_from_arrays(headers, rows)
    mapper = CsvColumnMapperService.new(
      headers: headers.map(&:to_s),
      sample_rows: rows.first(5),
      entity: current_entity
    )
    mapper.compute_mapping
  end
end
