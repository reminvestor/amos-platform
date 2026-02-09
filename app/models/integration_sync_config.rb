# frozen_string_literal: true

# IntegrationSyncConfig - Defines how a specific integration should sync
#
# This is the "recipe" for syncing data from an external system:
#   - What external resource to sync (e.g., 'customers')
#   - What internal model to create (e.g., 'Contact')
#   - How to map fields
#   - When to sync (manual, scheduled, realtime)
#   - Whether to require approval
#
class IntegrationSyncConfig < ApplicationRecord
  belongs_to :entity
  belongs_to :connection
  belongs_to :scheduled_agent_task, optional: true

  # Validations
  validates :resource_type, presence: true
  validates :target_type, presence: true
  validates :field_mappings, presence: true
  validates :sync_direction, inclusion: { in: %w[inbound outbound bidirectional] }
  validates :sync_mode, inclusion: { in: %w[full incremental] }
  validates :conflict_resolution, inclusion: { in: %w[external_wins internal_wins manual newest] }
  validates :schedule_type, inclusion: { in: %w[manual scheduled realtime] }, allow_nil: true

  # Scopes
  scope :for_connection, ->(connection) { where(connection: connection) }
  scope :for_entity, ->(entity) { where(entity: entity) }
  scope :enabled, -> { where(enabled: true) }
  scope :scheduled, -> { where(schedule_type: 'scheduled') }
  scope :inbound, -> { where(sync_direction: %w[inbound bidirectional]) }
  scope :outbound, -> { where(sync_direction: %w[outbound bidirectional]) }

  # Callbacks
  after_save :sync_scheduled_task, if: -> { saved_change_to_schedule_type? || saved_change_to_cron_expression? }

  # ============================================
  # SYNC EXECUTION
  # ============================================

  # Execute a sync based on this config
  def execute_sync!(user: nil)
    return { success: false, error: 'Sync config is disabled' } unless enabled?

    Rails.logger.info "[SyncConfig] Starting sync: #{integration_name} / #{resource_type} → #{target_type}"

    cursor = get_or_create_cursor
    records_synced = 0
    records_staged = 0
    errors = []

    begin
      # Determine sync mode
      do_full_sync = sync_mode == 'full' || cursor.needs_full_sync?

      # Fetch data from integration
      fetched_data = fetch_from_integration(cursor, full_sync: do_full_sync)

      unless fetched_data[:success]
        return { success: false, error: fetched_data[:error] }
      end

      records = fetched_data[:records] || []
      Rails.logger.info "[SyncConfig] Fetched #{records.length} records"

      # Process each record
      records.each do |external_record|
        if requires_approval && (approval_threshold.nil? || records.length > approval_threshold)
          # Stage for approval
          IntegrationSyncRecord.stage_for_approval!(
            connection: connection,
            external_id: extract_external_id(external_record),
            external_type: resource_type,
            external_data: external_record,
            target_type: target_type,
            field_mapping: field_mappings,
            scheduled_task: scheduled_agent_task
          )
          records_staged += 1
        else
          # Direct sync
          result = IntegrationSyncRecord.upsert_from_external!(
            connection: connection,
            external_id: extract_external_id(external_record),
            external_type: resource_type,
            external_data: external_record,
            internal_type: target_type,
            field_mapping: field_mappings
          )

          if result[:action] == :error
            errors << result[:error]
          else
            records_synced += 1
          end
        end
      end

      # Update cursor
      if records.any?
        if do_full_sync
          cursor.mark_full_sync_complete!(records.length)
        else
          last_record = records.last
          cursor.advance!(
            new_value: extract_cursor_value(last_record),
            records_fetched: records.length
          )
        end
      end

      {
        success: true,
        records_fetched: records.length,
        records_synced: records_synced,
        records_staged: records_staged,
        errors: errors,
        full_sync: do_full_sync
      }
    rescue => e
      Rails.logger.error "[SyncConfig] Sync failed: #{e.message}"
      { success: false, error: e.message }
    end
  end

  # ============================================
  # HELPERS
  # ============================================

  def integration_name
    connection&.integration&.name || 'Unknown'
  end

  def get_or_create_cursor
    IntegrationSyncCursor.find_or_create_by!(
      connection: connection,
      resource_type: resource_type
    ) do |cursor|
      cursor.entity = entity
      cursor.cursor_type = determine_cursor_type
    end
  end

  def mapped_fields
    field_mappings.map do |external, internal|
      { external: external, internal: internal }
    end
  end

  # Create a scheduled task for this sync
  def create_scheduled_task!(user:)
    return scheduled_agent_task if scheduled_agent_task.present?

    task = ScheduledAgentTask.create!(
      entity: entity,
      user: user,
      name: "Sync #{integration_name} #{resource_type}",
      description: "Automated sync of #{resource_type} from #{integration_name} to #{target_type}",
      task_type: 'data_sync',
      prompt: build_sync_prompt,
      schedule_type: schedule_type == 'scheduled' ? 'cron' : 'once',
      cron_expression: cron_expression,
      enabled: true,
      input_context: {
        sync_config_id: id,
        execution_mode: 'tool_only',
        required_tools: ['execute_integration_sync']
      }
    )

    update!(scheduled_agent_task: task)
    task
  end

  private

  def fetch_from_integration(cursor, full_sync:)
    integration = connection.integration

    # Build API params from cursor (for incremental syncs)
    cursor_params = full_sync ? {} : cursor.api_params

    # ─── Try IntegrationAction first (has smart mapping code) ───
    action = find_list_action(integration)
    if action
      Rails.logger.info "[SyncConfig] Using IntegrationAction '#{action.slug}' for fetch"

      # Build normalized inputs that the action's mapping_code will translate
      inputs = {}
      inputs.merge!(cursor_params)
      inputs.merge!(filter_conditions) if filter_conditions.present?

      # Execute through the action (gets mapping, validation, response normalization)
      execution = action.execute!(
        inputs: inputs,
        connection: connection,
        user: entity.users.first, # Sync runs as entity owner
        entity: entity
      )

      if execution.success?
        data = execution.normalized_response || execution.raw_response
        return { success: true, records: extract_records(data) }
      else
        Rails.logger.warn "[SyncConfig] Action execution failed: #{execution.error_message}, falling back to direct operation"
      end
    end

    # ─── Fallback: direct operation execution ───
    operation = find_list_operation(integration)
    unless operation
      return { success: false, error: "No list operation found for '#{resource_type}'. Add a list operation for this resource." }
    end

    params = cursor_params
    params.merge!(filter_conditions) if filter_conditions.present?

    executor = UniversalIntegrationExecutor.new(connection)
    result = executor.execute(operation, params)

    if result[:success]
      { success: true, records: extract_records(result[:data]) }
    else
      { success: false, error: result[:error] }
    end
  end

  def find_list_action(integration)
    # Search for an action that lists this resource type
    resource = resource_type.to_s.underscore
    IntegrationAction
      .where(integration: integration)
      .for_entity(entity)
      .usable
      .where("action_name ILIKE ? OR action_name ILIKE ? OR slug ILIKE ?",
             "list_#{resource}", "get_#{resource}", "%list_#{resource}%")
      .first
  end

  def find_list_operation(integration)
    ops = integration.integration_operations
    resource = resource_type.to_s.underscore

    # Try exact operation_id match first (e.g., "stripe.list_customers")
    ops.find_by(operation_id: "#{integration.slug}.list_#{resource}") ||
    # Try operation_id without prefix
    ops.find_by(operation_id: "list_#{resource}") ||
    # Try name match (case insensitive, multiple patterns)
    ops.where(
      "name ILIKE ? OR name ILIKE ? OR name ILIKE ? OR operation_id ILIKE ? OR operation_id ILIKE ?",
      "list_#{resource}", "get_#{resource}", "list #{resource}",
      "%list_#{resource}%", "%get_#{resource}%"
    ).first
  end

  def extract_records(data)
    # Handle various API response formats
    case data
    when Array
      data
    when Hash
      data['data'] || data['records'] || data['items'] || data[resource_type] || [data]
    else
      []
    end
  end

  def extract_external_id(record)
    record['id'] || record['_id'] || record['external_id'] || record.hash.to_s
  end

  def extract_cursor_value(record)
    record['updated_at'] || record['modified_at'] || record['created_at'] || Time.current
  end

  def determine_cursor_type
    # Default to timestamp for most APIs
    'timestamp'
  end

  def build_sync_prompt
    <<~PROMPT
      Execute sync for #{integration_name} #{resource_type}.
      
      Sync Config ID: #{id}
      Target: #{target_type}
      Direction: #{sync_direction}
      Mode: #{sync_mode}
      Requires Approval: #{requires_approval}
    PROMPT
  end

  def sync_scheduled_task
    return unless scheduled_agent_task.present?
    return unless schedule_type == 'scheduled' && cron_expression.present?

    scheduled_agent_task.update!(
      cron_expression: cron_expression,
      enabled: enabled?
    )
  end
end

