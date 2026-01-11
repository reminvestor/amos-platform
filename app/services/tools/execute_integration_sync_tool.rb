# frozen_string_literal: true

module Tools
  class ExecuteIntegrationSyncTool < BaseTool
    def self.metadata
      {
        name: "execute_integration_sync",
        description: "Execute a data sync between an external integration and the platform. Syncs records from external systems (like Stripe, HubSpot) into internal records (like Contacts, Orders). Supports incremental sync, approval workflows, and upsert logic.",
        category: "integration",
        input_schema: {
          type: "object",
          properties: {
            sync_config_id: {
              type: "integer",
              description: "ID of an existing sync configuration to execute"
            },
            connection_id: {
              type: "integer",
              description: "Connection ID for the integration (alternative to sync_config_id)"
            },
            resource_type: {
              type: "string",
              description: "External resource to sync (e.g., 'customers', 'orders'). Required if not using sync_config_id."
            },
            target_type: {
              type: "string",
              description: "Internal model to create (e.g., 'Contact', 'Order'). Required if not using sync_config_id."
            },
            field_mapping: {
              type: "object",
              description: "Map external fields to internal fields. Example: { 'email': 'email', 'name': 'full_name' }"
            },
            sync_mode: {
              type: "string",
              enum: ["full", "incremental"],
              description: "Full sync fetches everything; incremental only fetches new/updated records."
            },
            require_approval: {
              type: "boolean",
              description: "If true, stage records for human approval before importing."
            },
            limit: {
              type: "integer",
              description: "Maximum number of records to sync in this run."
            }
          },
          required: []
        }
      }
    end

    def execute(args)
      log_execution(args)

      sync_config_id = get_arg(args, :sync_config_id)
      connection_id = get_arg(args, :connection_id)
      resource_type = get_arg(args, :resource_type)
      target_type = get_arg(args, :target_type)
      field_mapping = get_arg(args, :field_mapping, {})
      sync_mode = get_arg(args, :sync_mode, 'incremental')
      require_approval = get_arg(args, :require_approval, false)
      limit = get_arg(args, :limit)

      # Option 1: Use existing sync config
      if sync_config_id.present?
        return execute_from_config(sync_config_id)
      end

      # Option 2: Ad-hoc sync
      unless connection_id.present? && resource_type.present? && target_type.present?
        return error_response(
          "Either sync_config_id or (connection_id, resource_type, target_type) are required"
        )
      end

      execute_adhoc_sync(
        connection_id: connection_id,
        resource_type: resource_type,
        target_type: target_type,
        field_mapping: field_mapping,
        sync_mode: sync_mode,
        require_approval: require_approval,
        limit: limit
      )
    end

    private

    def execute_from_config(sync_config_id)
      config = IntegrationSyncConfig.find_by(id: sync_config_id)

      unless config
        return error_response("Sync config #{sync_config_id} not found")
      end

      unless config.entity_id == entity&.id
        return error_response("Access denied to sync config #{sync_config_id}")
      end

      result = config.execute_sync!(user: user)

      if result[:success]
        success_response(
          message: build_success_message(result),
          **result
        )
      else
        error_response(result[:error])
      end
    end

    def execute_adhoc_sync(connection_id:, resource_type:, target_type:, field_mapping:, sync_mode:, require_approval:, limit:)
      connection = entity&.connections&.find_by(id: connection_id)

      unless connection
        return error_response("Connection #{connection_id} not found")
      end

      unless connection.status == 'connected'
        return error_response("Connection is not active. Status: #{connection.status}")
      end

      Rails.logger.info "[IntegrationSync] Ad-hoc sync: #{connection.integration.name} / #{resource_type} → #{target_type}"

      # Fetch data from integration
      fetched_data = fetch_data(connection, resource_type, limit)

      unless fetched_data[:success]
        return error_response("Failed to fetch data: #{fetched_data[:error]}")
      end

      records = fetched_data[:records] || []
      Rails.logger.info "[IntegrationSync] Fetched #{records.length} records"

      if records.empty?
        return success_response(
          message: "No records found to sync from #{connection.integration.name}",
          records_fetched: 0,
          records_synced: 0,
          records_staged: 0
        )
      end

      # Build field mapping if not provided
      if field_mapping.blank? && records.first.is_a?(Hash)
        field_mapping = auto_detect_mapping(records.first, target_type)
      end

      # Process records
      results = process_records(
        connection: connection,
        records: records,
        resource_type: resource_type,
        target_type: target_type,
        field_mapping: field_mapping,
        require_approval: require_approval
      )

      success_response(
        message: build_success_message(results),
        integration: connection.integration.name,
        resource_type: resource_type,
        target_type: target_type,
        **results
      )
    end

    def fetch_data(connection, resource_type, limit)
      # Find the list operation
      integration = connection.integration
      operation = integration.integration_operations.find_by(
        "name ILIKE ? OR name ILIKE ?",
        "list_#{resource_type}",
        "get_#{resource_type}"
      )

      unless operation
        # Try generic list
        operation = integration.integration_operations.find_by("name ILIKE ?", "%list%")
      end

      unless operation
        return { success: false, error: "No list operation found for #{resource_type}" }
      end

      # Execute the operation
      executor = UniversalIntegrationExecutor.new(connection)
      params = limit ? { limit: limit } : {}

      result = executor.execute(operation, params)

      if result[:success]
        records = extract_records(result[:data], resource_type)
        { success: true, records: records }
      else
        { success: false, error: result[:error] }
      end
    rescue => e
      { success: false, error: e.message }
    end

    def extract_records(data, resource_type)
      case data
      when Array
        data
      when Hash
        data['data'] || data['records'] || data['items'] || 
        data[resource_type] || data[resource_type.singularize] || 
        [data]
      else
        []
      end
    end

    def auto_detect_mapping(sample_record, target_type)
      mapping = {}

      # Common field mappings
      case target_type
      when 'Contact'
        %w[email name first_name last_name phone company title].each do |field|
          if sample_record.key?(field)
            mapping[field] = field
          end
        end
        # Alternative names
        mapping['email_address'] = 'email' if sample_record.key?('email_address')
        mapping['full_name'] = 'name' if sample_record.key?('full_name')
        mapping['phone_number'] = 'phone' if sample_record.key?('phone_number')
      else
        # Generic: map same-named fields
        sample_record.keys.each do |key|
          mapping[key] = key unless key == 'id'
        end
      end

      mapping
    end

    def process_records(connection:, records:, resource_type:, target_type:, field_mapping:, require_approval:)
      synced = 0
      staged = 0
      errors = []

      records.each_with_index do |record, idx|
        external_id = record['id'] || record['_id'] || idx.to_s

        begin
          if require_approval
            IntegrationSyncRecord.stage_for_approval!(
              connection: connection,
              external_id: external_id,
              external_type: resource_type,
              external_data: record,
              target_type: target_type,
              field_mapping: field_mapping
            )
            staged += 1
          else
            result = IntegrationSyncRecord.upsert_from_external!(
              connection: connection,
              external_id: external_id,
              external_type: resource_type,
              external_data: record,
              internal_type: target_type,
              field_mapping: field_mapping
            )

            if result[:action] == :error
              errors << { external_id: external_id, error: result[:error] }
            else
              synced += 1
            end
          end
        rescue => e
          errors << { external_id: external_id, error: e.message }
        end
      end

      {
        records_fetched: records.length,
        records_synced: synced,
        records_staged: staged,
        errors: errors
      }
    end

    def build_success_message(result)
      parts = []

      if result[:records_synced].to_i > 0
        parts << "synced #{result[:records_synced]} records"
      end

      if result[:records_staged].to_i > 0
        parts << "staged #{result[:records_staged]} for approval"
      end

      if result[:errors]&.any?
        parts << "#{result[:errors].length} errors"
      end

      if parts.empty?
        "Sync complete, no records processed"
      else
        "Sync complete: #{parts.join(', ')}"
      end
    end
  end
end

