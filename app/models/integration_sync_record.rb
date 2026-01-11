# frozen_string_literal: true

# IntegrationSyncRecord - Tracks which external records have been synced to internal records
#
# This is the core of the iPaaS deduplication and upsert logic.
# For every record we sync from an external system, we create a sync record
# that maps external_id → internal_id, enabling:
#   - Find-or-create-by-external-id (upsert)
#   - Deduplication on re-sync
#   - Change detection via external_hash
#   - Sync history and audit trail
#
class IntegrationSyncRecord < ApplicationRecord
  belongs_to :entity
  belongs_to :connection

  # Validations
  validates :external_id, presence: true
  validates :external_type, presence: true
  validates :internal_type, presence: true
  validates :external_id, uniqueness: { scope: [:connection_id, :external_type] }

  # Scopes
  scope :for_connection, ->(connection) { where(connection: connection) }
  scope :for_entity, ->(entity) { where(entity: entity) }
  scope :for_external_type, ->(type) { where(external_type: type) }
  scope :for_internal_type, ->(type) { where(internal_type: type) }
  scope :synced, -> { where(sync_status: 'synced') }
  scope :pending_approval, -> { where(sync_status: 'pending_approval') }
  scope :errors, -> { where(sync_status: 'error') }
  scope :recently_synced, -> { where('last_synced_at > ?', 24.hours.ago) }
  scope :stale, ->(hours = 24) { where('last_synced_at < ?', hours.hours.ago) }

  # Status constants
  SYNC_STATUSES = %w[synced pending_approval error deleted orphaned].freeze
  SYNC_DIRECTIONS = %w[inbound outbound bidirectional].freeze

  # ============================================
  # CORE UPSERT LOGIC
  # ============================================

  # Find or create internal record based on external data
  # Returns: { action: :created | :updated | :unchanged, record: <ActiveRecord> }
  def self.upsert_from_external!(connection:, external_id:, external_type:, external_data:, internal_type:, field_mapping: {})
    entity = connection.entity

    # Find existing sync record
    sync_record = find_or_initialize_by(
      connection: connection,
      external_type: external_type,
      external_id: external_id
    )

    sync_record.entity = entity
    sync_record.internal_type = internal_type

    # Calculate hash to detect changes
    new_hash = Digest::SHA256.hexdigest(external_data.to_json)

    if sync_record.persisted? && sync_record.external_hash == new_hash
      # No changes detected
      sync_record.touch(:last_synced_at)
      return { action: :unchanged, record: sync_record.find_internal_record, sync_record: sync_record }
    end

    # Map external data to internal fields
    internal_data = map_fields(external_data, field_mapping, internal_type)

    # Find or create internal record
    internal_record = if sync_record.internal_id.present?
      # Update existing
      record = sync_record.find_internal_record
      record&.update!(internal_data)
      record
    else
      # Create new
      create_internal_record(internal_type, internal_data, entity)
    end

    unless internal_record
      sync_record.update!(
        sync_status: 'error',
        last_error: "Failed to create #{internal_type} record",
        last_error_at: Time.current,
        error_count: sync_record.error_count + 1
      )
      return { action: :error, error: "Failed to create internal record", sync_record: sync_record }
    end

    action = sync_record.persisted? ? :updated : :created

    sync_record.update!(
      internal_id: internal_record.id,
      external_data: external_data,
      external_hash: new_hash,
      sync_status: 'synced',
      last_synced_at: Time.current,
      sync_count: sync_record.sync_count + 1,
      last_error: nil,
      last_error_at: nil
    )

    { action: action, record: internal_record, sync_record: sync_record }
  rescue => e
    Rails.logger.error "IntegrationSyncRecord.upsert_from_external! failed: #{e.message}"
    { action: :error, error: e.message }
  end

  # Stage record for approval instead of immediate sync
  def self.stage_for_approval!(connection:, external_id:, external_type:, external_data:, target_type:, field_mapping: {}, scheduled_task: nil)
    entity = connection.entity
    
    # Map the data
    staged_data = map_fields(external_data, field_mapping, target_type)
    
    # Create staging record
    IntegrationStagingRecord.create!(
      entity: entity,
      connection: connection,
      scheduled_agent_task: scheduled_task,
      external_id: external_id,
      external_type: external_type,
      target_type: target_type,
      staged_data: staged_data,
      field_mappings: field_mapping,
      validation_results: validate_staged_data(staged_data, target_type),
      status: 'pending'
    )
  end

  # ============================================
  # INSTANCE METHODS
  # ============================================

  def find_internal_record
    return nil unless internal_id.present? && internal_type.present?

    begin
      internal_type.constantize.find_by(id: internal_id)
    rescue NameError
      # Check if it's a module record
      if internal_type.start_with?('Module::')
        module_slug = internal_type.sub('Module::', '').underscore
        app_module = entity.app_modules.find_by(slug: module_slug)
        app_module&.module_records&.find_by(id: internal_id)
      end
    end
  end

  def external_changed?(new_data)
    new_hash = Digest::SHA256.hexdigest(new_data.to_json)
    external_hash != new_hash
  end

  def mark_synced!
    update!(
      sync_status: 'synced',
      last_synced_at: Time.current,
      sync_count: sync_count + 1,
      last_error: nil
    )
  end

  def mark_error!(error_message)
    update!(
      sync_status: 'error',
      last_error: error_message,
      last_error_at: Time.current,
      error_count: error_count + 1
    )
  end

  def mark_deleted!
    update!(sync_status: 'deleted')
  end

  # ============================================
  # CLASS HELPERS
  # ============================================

  def self.map_fields(external_data, field_mapping, internal_type)
    return external_data if field_mapping.blank?

    mapped = {}
    field_mapping.each do |external_field, internal_field|
      value = external_data[external_field] || external_data[external_field.to_s]
      mapped[internal_field.to_sym] = value if value.present?
    end

    # Add any unmapped fields to metadata/custom_fields
    unmapped_keys = external_data.keys.map(&:to_s) - field_mapping.keys.map(&:to_s)
    if unmapped_keys.any?
      unmapped_data = external_data.slice(*unmapped_keys)
      mapped[:metadata] = (mapped[:metadata] || {}).merge(unmapped_data)
    end

    mapped
  end

  def self.create_internal_record(internal_type, data, entity)
    klass = internal_type.constantize
    
    # Add entity association if the model supports it
    data[:entity] = entity if klass.column_names.include?('entity_id')
    
    klass.create!(data)
  rescue NameError
    # Handle dynamic module records
    if internal_type.start_with?('Module::')
      module_slug = internal_type.sub('Module::', '').underscore
      app_module = entity.app_modules.find_by(slug: module_slug)
      return nil unless app_module
      
      app_module.module_records.create!(data: data, entity: entity)
    end
  rescue => e
    Rails.logger.error "Failed to create #{internal_type}: #{e.message}"
    nil
  end

  def self.validate_staged_data(data, target_type)
    results = { valid: true, errors: [], warnings: [] }
    
    # Basic validation based on target type
    case target_type
    when 'Contact'
      results[:errors] << 'Email is required' unless data[:email].present?
    when 'Campaign'
      results[:errors] << 'Name is required' unless data[:name].present?
    end
    
    results[:valid] = results[:errors].empty?
    results
  end
end

