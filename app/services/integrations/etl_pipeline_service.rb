# frozen_string_literal: true

module Integrations
  # ETLPipelineService - Full Extract-Transform-Load pipeline for iPaaS
  #
  # NO AI REQUIRED during execution. This is pure Ruby ETL.
  # AI is only used during SETUP to generate transform_code.
  #
  # Integrates with:
  # - ScheduledAgentTask (cron triggers)
  # - ModuleWebhook (real-time triggers)
  # - Workflow (complex multi-step with approval)
  #
  class ETLPipelineService
    attr_reader :sync_config, :connection, :entity, :transformer

    def initialize(sync_config)
      @sync_config = sync_config
      @connection = sync_config.connection
      @entity = sync_config.entity
      @transformer = DataTransformService.new(sync_config)
    end

    # Run the full ETL pipeline
    def run!
      Rails.logger.info "[ETL] Starting: #{sync_config.resource_type} → #{sync_config.target_type}"

      result = init_result

      begin
        # EXTRACT
        extracted = extract_data
        unless extracted[:success]
          result[:errors] << "Extract failed: #{extracted[:error]}"
          return finalize(result, :failed)
        end
        result[:extracted] = extracted[:records].length

        return finalize(result, :success) if extracted[:records].empty?

        # TRANSFORM
        transformed = transformer.transform_batch(extracted[:records])
        result[:transformed] = transformed[:successful].length
        result[:errors] += transformed[:failed].map { |f| "Transform[#{f[:index]}]: #{f[:error]}" }

        return finalize(result, :partial) if transformed[:successful].empty?

        # LOAD (or stage for approval)
        if sync_config.requires_approval
          loaded = stage_for_approval(transformed[:successful], extracted[:records])
          result[:staged] = loaded[:staged]
        else
          loaded = load_data(transformed[:successful], extracted[:records])
          result[:loaded] = loaded[:loaded]
          result[:errors] += loaded[:errors]
        end

        # Update cursor
        update_cursor(extracted[:records])

        # Trigger post-sync workflow
        trigger_workflow(result) if sync_config.post_sync_workflow_id.present?

        finalize(result, result[:errors].any? ? :partial : :success)
      rescue => e
        Rails.logger.error "[ETL] Failed: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
        result[:errors] << "Pipeline error: #{e.message}"
        finalize(result, :failed)
      end
    end

    # Process a single record (for webhooks/real-time)
    def process_single(external_record)
      transformed = transformer.transform(external_record)
      return { success: false, error: transformed[:error] } unless transformed[:success]

      if sync_config.requires_approval
        stage_single(transformed[:data], external_record)
      else
        load_single(transformed[:data], external_record)
      end
    end

    private

    def init_result
      {
        started_at: Time.current,
        sync_config_id: sync_config.id,
        resource_type: sync_config.resource_type,
        target_type: sync_config.target_type,
        extracted: 0, transformed: 0, loaded: 0, staged: 0,
        errors: []
      }
    end

    # ============================================
    # EXTRACT
    # ============================================

    def extract_data
      cursor = sync_config.get_or_create_cursor
      full_sync = sync_config.sync_mode == 'full' || cursor.needs_full_sync?

      params = full_sync ? {} : cursor.api_params
      params.merge!(sync_config.filter_conditions) if sync_config.filter_conditions.present?

      executor = UniversalIntegrationExecutor.new(connection)
      operation = find_operation

      return { success: false, error: "No operation for #{sync_config.resource_type}" } unless operation

      result = executor.execute(operation, params)

      if result[:success]
        records = normalize_response(result[:data])
        { success: true, records: records, full_sync: full_sync }
      else
        { success: false, error: result[:error], records: [] }
      end
    end

    def find_operation
      connection.integration.integration_operations.find_by(
        "name ILIKE ? OR name ILIKE ?",
        "list_#{sync_config.resource_type}",
        "get_#{sync_config.resource_type}"
      )
    end

    def normalize_response(data)
      case data
      when Array then data
      when Hash
        data['data'] || data['records'] || data['items'] ||
        data[sync_config.resource_type] || [data]
      else []
      end
    end

    # ============================================
    # LOAD
    # ============================================

    def load_data(transformed, originals)
      loaded = 0
      errors = []

      transformed.each do |item|
        idx = item[:index]
        original = originals[idx]
        ext_id = original['id'] || original['_id'] || idx.to_s

        result = upsert_record(ext_id, original, item[:data])

        if result[:success]
          loaded += 1
        else
          errors << "Load[#{ext_id}]: #{result[:error]}"
        end
      end

      { loaded: loaded, errors: errors }
    end

    def load_single(data, original)
      ext_id = original['id'] || original['_id']
      upsert_record(ext_id, original, data)
    end

    def upsert_record(external_id, external_data, transformed_data)
      # Find or create sync record
      sync_record = IntegrationSyncRecord.find_or_initialize_by(
        connection: connection,
        external_type: sync_config.resource_type,
        external_id: external_id
      )

      sync_record.entity = entity
      sync_record.internal_type = sync_config.target_type

      # Check if data changed
      new_hash = Digest::SHA256.hexdigest(external_data.to_json)
      if sync_record.persisted? && sync_record.external_hash == new_hash
        sync_record.touch(:last_synced_at)
        return { success: true, action: :unchanged }
      end

      # Create or update internal record
      internal_record = if sync_record.internal_id.present?
        update_internal_record(sync_record, transformed_data)
      else
        create_internal_record(transformed_data)
      end

      return { success: false, error: "Failed to save record" } unless internal_record

      action = sync_record.persisted? ? :updated : :created

      sync_record.update!(
        internal_id: internal_record.id,
        external_data: external_data,
        external_hash: new_hash,
        sync_status: 'synced',
        last_synced_at: Time.current,
        sync_count: sync_record.sync_count + 1
      )

      { success: true, action: action, record: internal_record }
    rescue => e
      { success: false, error: e.message }
    end

    def create_internal_record(data)
      klass = sync_config.target_type.constantize
      record = klass.new(data)
      record.entity = entity if record.respond_to?(:entity=)
      record.save ? record : nil
    rescue NameError
      nil
    end

    def update_internal_record(sync_record, data)
      record = sync_record.find_internal_record
      return nil unless record
      record.update(data) ? record : nil
    end

    # ============================================
    # STAGING
    # ============================================

    def stage_for_approval(transformed, originals)
      staged = 0

      transformed.each do |item|
        idx = item[:index]
        original = originals[idx]
        ext_id = original['id'] || original['_id'] || idx.to_s

        IntegrationStagingRecord.create!(
          entity: entity,
          connection: connection,
          scheduled_agent_task: sync_config.scheduled_agent_task,
          external_id: ext_id,
          external_type: sync_config.resource_type,
          target_type: sync_config.target_type,
          staged_data: item[:data],
          field_mappings: sync_config.field_mappings,
          validation_results: validate(item[:data]),
          status: 'pending'
        )
        staged += 1
      end

      { staged: staged }
    end

    def stage_single(data, original)
      ext_id = original['id'] || original['_id']

      staging = IntegrationStagingRecord.create!(
        entity: entity,
        connection: connection,
        external_id: ext_id,
        external_type: sync_config.resource_type,
        target_type: sync_config.target_type,
        staged_data: data,
        status: 'pending'
      )

      { success: true, staged_id: staging.id }
    end

    def validate(data)
      errors = []
      errors << 'Email required' if sync_config.target_type == 'Contact' && data[:email].blank?
      { valid: errors.empty?, errors: errors }
    end

    # ============================================
    # CURSOR & WORKFLOW
    # ============================================

    def update_cursor(records)
      return if records.empty?
      cursor = sync_config.get_or_create_cursor
      last = records.last
      ts = last['updated_at'] || last['created_at'] || Time.current
      cursor.advance!(new_value: ts, records_fetched: records.length)
    end

    def trigger_workflow(result)
      workflow = Workflow.find_by(id: sync_config.post_sync_workflow_id)
      return unless workflow

      WorkflowEngineV2.new(nil).execute_workflow(
        workflow,
        context: { sync_result: result, sync_config_id: sync_config.id }
      )
    rescue => e
      Rails.logger.error "[ETL] Workflow failed: #{e.message}"
    end

    def finalize(result, status)
      result[:ended_at] = Time.current
      result[:duration_seconds] = (result[:ended_at] - result[:started_at]).round(2)
      result[:status] = status.to_s
      Rails.logger.info "[ETL] Complete: #{status} | E:#{result[:extracted]} T:#{result[:transformed]} L:#{result[:loaded]} S:#{result[:staged]}"
      result
    end
  end
end
