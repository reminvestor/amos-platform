# frozen_string_literal: true

# IntegrationStagingRecord - Holds imported data awaiting human approval
#
# When sync is configured with requires_approval=true, records are staged
# here instead of being immediately imported. Users can:
#   - Review the data
#   - Approve/reject individual records or in bulk
#   - See validation warnings before commit
#
class IntegrationStagingRecord < ApplicationRecord
  belongs_to :entity
  belongs_to :connection
  belongs_to :scheduled_agent_task, optional: true
  belongs_to :reviewed_by, class_name: 'User', optional: true

  # Validations
  validates :external_id, presence: true
  validates :external_type, presence: true
  validates :target_type, presence: true
  validates :staged_data, presence: true
  validates :status, inclusion: { in: %w[pending approved rejected imported error] }

  # Scopes
  scope :for_entity, ->(entity) { where(entity: entity) }
  scope :for_connection, ->(connection) { where(connection: connection) }
  scope :pending, -> { where(status: 'pending') }
  scope :approved, -> { where(status: 'approved') }
  scope :rejected, -> { where(status: 'rejected') }
  scope :imported, -> { where(status: 'imported') }
  scope :reviewable, -> { where(status: %w[pending approved]) }
  scope :recent, -> { order(created_at: :desc) }

  # ============================================
  # APPROVAL WORKFLOW
  # ============================================

  def approve!(user:, notes: nil)
    update!(
      status: 'approved',
      reviewed_by: user,
      reviewed_at: Time.current,
      review_notes: notes
    )
  end

  def reject!(user:, notes: nil)
    update!(
      status: 'rejected',
      reviewed_by: user,
      reviewed_at: Time.current,
      review_notes: notes
    )
  end

  # Import the staged record into the actual system
  def import!
    return { success: false, error: 'Not approved' } unless status == 'approved'

    begin
      # Create the actual record
      record = IntegrationSyncRecord.create_internal_record(target_type, staged_data.symbolize_keys, entity)

      unless record
        update!(status: 'error')
        return { success: false, error: 'Failed to create record' }
      end

      # Create sync record to track this
      sync_record = IntegrationSyncRecord.create!(
        entity: entity,
        connection: connection,
        external_id: external_id,
        external_type: external_type,
        external_data: staged_data,
        external_hash: Digest::SHA256.hexdigest(staged_data.to_json),
        internal_type: target_type,
        internal_id: record.id,
        sync_status: 'synced',
        sync_direction: 'inbound',
        last_synced_at: Time.current,
        sync_count: 1,
        metadata: { imported_from_staging: id, field_mappings: field_mappings }
      )

      update!(
        status: 'imported',
        created_record_id: record.id,
        imported_at: Time.current
      )

      { success: true, record: record, sync_record: sync_record }
    rescue => e
      Rails.logger.error "IntegrationStagingRecord#import! failed: #{e.message}"
      update!(status: 'error')
      { success: false, error: e.message }
    end
  end

  # ============================================
  # BULK OPERATIONS
  # ============================================

  def self.bulk_approve!(ids, user:)
    where(id: ids, status: 'pending').update_all(
      status: 'approved',
      reviewed_by_id: user.id,
      reviewed_at: Time.current
    )
  end

  def self.bulk_reject!(ids, user:, notes: nil)
    where(id: ids, status: 'pending').update_all(
      status: 'rejected',
      reviewed_by_id: user.id,
      reviewed_at: Time.current,
      review_notes: notes
    )
  end

  def self.import_all_approved!(entity:)
    results = { imported: 0, failed: 0, errors: [] }

    where(entity: entity, status: 'approved').find_each do |staged|
      result = staged.import!
      if result[:success]
        results[:imported] += 1
      else
        results[:failed] += 1
        results[:errors] << { id: staged.id, error: result[:error] }
      end
    end

    results
  end

  # ============================================
  # HELPERS
  # ============================================

  def pending?
    status == 'pending'
  end

  def approved?
    status == 'approved'
  end

  def rejected?
    status == 'rejected'
  end

  def imported?
    status == 'imported'
  end

  def valid_for_import?
    validation_results['valid'] == true
  end

  def validation_errors
    validation_results['errors'] || []
  end

  def validation_warnings
    validation_results['warnings'] || []
  end

  def display_data
    staged_data.map do |key, value|
      { field: key.to_s.humanize, value: value }
    end
  end
end

