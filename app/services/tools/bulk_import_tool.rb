# frozen_string_literal: true

module Tools
  class BulkImportTool < BaseTool
    MAX_BATCH_SIZE = 500

    def self.metadata
      {
        name: "bulk_import",
        description: "Import multiple records at once from parsed CSV data or structured arrays. Creates contacts, campaigns, or custom module records in bulk.",
        category: "data",
        input_schema: {
          type: "object",
          properties: {
            object_type: {
              type: "string",
              description: "The type of object to create (e.g., 'contacts', 'campaigns', or a custom module slug)"
            },
            records: {
              type: "array",
              description: "Array of record objects to import. Each object should have the field names as keys."
            },
            field_mapping: {
              type: "object",
              description: "Optional: Map CSV column names to system field names. Example: { 'Email Address': 'email', 'Full Name': 'name' }"
            },
            update_existing: {
              type: "boolean",
              description: "If true, update existing records that match by email/id instead of creating duplicates (default: false)"
            },
            skip_validation: {
              type: "boolean",
              description: "If true, skip validation errors and import valid records only (default: false)"
            },
            dry_run: {
              type: "boolean",
              description: "If true, validate without actually importing (default: false)"
            }
          },
          required: ["object_type", "records"]
        }
      }
    end

    def execute(args)
      log_execution(args)

      object_type = get_arg(args, :object_type)
      records = get_arg(args, :records, [])
      field_mapping = get_arg(args, :field_mapping, {})
      update_existing = get_arg(args, :update_existing, false)
      skip_validation = get_arg(args, :skip_validation, false)
      dry_run = get_arg(args, :dry_run, false)

      if error = validate_required_args(args, [:object_type, :records])
        return error
      end

      unless records.is_a?(Array) && records.any?
        return error_response("Records must be a non-empty array.")
      end

      if records.length > MAX_BATCH_SIZE
        return error_response("Maximum batch size is #{MAX_BATCH_SIZE} records. You provided #{records.length}. Please split into smaller batches.")
      end

      # Apply field mapping
      mapped_records = records.map { |r| apply_mapping(r, field_mapping) }

      # Route to appropriate importer
      case object_type.downcase
      when 'contacts'
        import_contacts(mapped_records, update_existing, skip_validation, dry_run)
      when 'campaigns'
        import_campaigns(mapped_records, skip_validation, dry_run)
      else
        # Try dynamic module
        import_module_records(object_type, mapped_records, skip_validation, dry_run)
      end
    end

    private

    def apply_mapping(record, mapping)
      return record if mapping.empty?

      mapped = {}
      record.each do |key, value|
        mapped_key = mapping[key] || mapping[key.to_s] || key
        mapped[mapped_key.to_s] = value
      end
      mapped
    end

    def import_contacts(records, update_existing, skip_validation, dry_run)
      results = {
        total: records.length,
        created: 0,
        updated: 0,
        skipped: 0,
        errors: []
      }

      created_records = []

      records.each_with_index do |record, idx|
        begin
          # Normalize field names
          normalized = normalize_contact_fields(record)

          # Validate required fields
          unless normalized[:email].present?
            if skip_validation
              results[:skipped] += 1
              results[:errors] << { row: idx + 1, error: "Missing email", record: record }
              next
            else
              return error_response("Row #{idx + 1} is missing required field: email")
            end
          end

          next if dry_run

          # Check for existing
          existing = entity.contacts.find_by(email: normalized[:email].downcase)

          if existing && update_existing
            existing.update!(normalized.except(:email))
            results[:updated] += 1
          elsif existing
            results[:skipped] += 1
            results[:errors] << { row: idx + 1, error: "Duplicate email", email: normalized[:email] }
          else
            contact = entity.contacts.create!(
              normalized.merge(
                source: 'csv_import',
                created_by: user
              )
            )
            results[:created] += 1
            created_records << { id: contact.id, email: contact.email, name: contact.name }
          end

        rescue ActiveRecord::RecordInvalid => e
          if skip_validation
            results[:skipped] += 1
            results[:errors] << { row: idx + 1, error: e.message, record: record }
          else
            return error_response("Row #{idx + 1} validation failed: #{e.message}")
          end
        end
      end

      if dry_run
        success_response(
          dry_run: true,
          would_import: records.length,
          message: "Dry run complete. #{records.length} contacts would be imported."
        )
      else
        success_response(
          object_type: 'contacts',
          **results,
          sample_created: created_records.first(5),
          message: "Import complete! Created: #{results[:created]}, Updated: #{results[:updated]}, Skipped: #{results[:skipped]}"
        )
      end
    end

    def normalize_contact_fields(record)
      normalized = {}

      # Email variations
      normalized[:email] = record['email'] || record['e-mail'] || record['email_address'] || record['mail']

      # Name variations
      if record['name'] || record['full_name'] || record['fullname']
        normalized[:name] = record['name'] || record['full_name'] || record['fullname']
      elsif record['first_name'] && record['last_name']
        normalized[:name] = "#{record['first_name']} #{record['last_name']}".strip
      elsif record['first_name']
        normalized[:name] = record['first_name']
      end

      # Phone variations
      normalized[:phone] = record['phone'] || record['phone_number'] || record['mobile'] || record['cell']

      # Company
      normalized[:company] = record['company'] || record['organization'] || record['company_name']

      # Title
      normalized[:title] = record['title'] || record['job_title'] || record['position']

      # Tags (comma-separated string to array)
      if record['tags'].present?
        tags = record['tags'].is_a?(Array) ? record['tags'] : record['tags'].to_s.split(',').map(&:strip)
        normalized[:tags] = tags
      end

      # Notes
      normalized[:notes] = record['notes'] || record['description'] || record['comments']

      # Custom fields (anything not matched)
      standard_fields = %w[email e-mail email_address mail name full_name fullname first_name last_name 
                           phone phone_number mobile cell company organization company_name 
                           title job_title position tags notes description comments]
      
      custom = record.except(*standard_fields)
      normalized[:custom_fields] = custom if custom.any?

      normalized.compact
    end

    def import_campaigns(records, skip_validation, dry_run)
      results = { total: records.length, created: 0, skipped: 0, errors: [] }

      records.each_with_index do |record, idx|
        begin
          unless record['name'].present?
            if skip_validation
              results[:skipped] += 1
              results[:errors] << { row: idx + 1, error: "Missing name" }
              next
            else
              return error_response("Row #{idx + 1} is missing required field: name")
            end
          end

          next if dry_run

          entity.campaigns.create!(
            name: record['name'],
            description: record['description'],
            status: record['status'] || 'draft',
            campaign_type: record['type'] || record['campaign_type'] || 'general',
            start_date: parse_date(record['start_date']),
            end_date: parse_date(record['end_date']),
            metadata: record.except('name', 'description', 'status', 'type', 'campaign_type', 'start_date', 'end_date')
          )
          results[:created] += 1

        rescue ActiveRecord::RecordInvalid => e
          if skip_validation
            results[:skipped] += 1
            results[:errors] << { row: idx + 1, error: e.message }
          else
            return error_response("Row #{idx + 1} validation failed: #{e.message}")
          end
        end
      end

      if dry_run
        success_response(dry_run: true, would_import: records.length, message: "Dry run complete.")
      else
        success_response(object_type: 'campaigns', **results, message: "Import complete! Created: #{results[:created]}")
      end
    end

    def import_module_records(object_type, records, skip_validation, dry_run)
      # Find the app module
      slug = object_type.singularize
      app_module = entity.app_modules.active.find_by(slug: slug) || 
                   entity.app_modules.active.find_by(slug: object_type)

      unless app_module
        available = entity.app_modules.active.pluck(:slug)
        return error_response(
          "Unknown object type: #{object_type}. Available modules: #{available.join(', ')}",
          available_types: ['contacts', 'campaigns'] + available
        )
      end

      results = { total: records.length, created: 0, skipped: 0, errors: [] }

      records.each_with_index do |record, idx|
        begin
          next if dry_run

          module_record = app_module.module_records.create!(
            data: record,
            entity: entity,
            created_by: user
          )
          results[:created] += 1

        rescue ActiveRecord::RecordInvalid => e
          if skip_validation
            results[:skipped] += 1
            results[:errors] << { row: idx + 1, error: e.message }
          else
            return error_response("Row #{idx + 1} validation failed: #{e.message}")
          end
        end
      end

      if dry_run
        success_response(
          dry_run: true,
          would_import: records.length,
          module: app_module.name,
          message: "Dry run complete. #{records.length} records would be imported into #{app_module.name}."
        )
      else
        success_response(
          object_type: object_type,
          module: app_module.name,
          **results,
          message: "Import complete! Created #{results[:created]} records in #{app_module.name}."
        )
      end
    end

    def parse_date(value)
      return nil if value.blank?
      
      begin
        Date.parse(value.to_s)
      rescue ArgumentError
        nil
      end
    end
  end
end

