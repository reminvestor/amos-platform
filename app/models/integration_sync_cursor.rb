# frozen_string_literal: true

# IntegrationSyncCursor - Tracks sync position for incremental data fetching
#
# For large datasets, we don't want to re-sync everything every time.
# This cursor remembers where we left off, enabling:
#   - Incremental syncs (only new/updated records)
#   - Resume after failure
#   - Efficient pagination handling
#
class IntegrationSyncCursor < ApplicationRecord
  belongs_to :entity
  belongs_to :connection

  # Validations
  validates :resource_type, presence: true
  validates :resource_type, uniqueness: { scope: :connection_id }
  validates :cursor_type, inclusion: { in: %w[timestamp offset token page] }

  # Scopes
  scope :for_connection, ->(connection) { where(connection: connection) }
  scope :for_resource, ->(resource) { where(resource_type: resource) }

  # ============================================
  # CURSOR MANAGEMENT
  # ============================================

  # Get the cursor value for API calls
  def cursor_value
    case cursor_type
    when 'timestamp'
      cursor_timestamp&.iso8601
    when 'offset'
      cursor_offset || 0
    when 'token', 'page'
      cursor_token
    else
      cursor_data
    end
  end

  # Update cursor after successful sync
  def advance!(new_value:, records_fetched: 0)
    case cursor_type
    when 'timestamp'
      update!(
        cursor_timestamp: parse_timestamp(new_value),
        last_incremental_sync_at: Time.current,
        total_records_synced: total_records_synced + records_fetched,
        records_synced_in_last_run: records_fetched
      )
    when 'offset'
      update!(
        cursor_offset: new_value.to_i,
        last_incremental_sync_at: Time.current,
        total_records_synced: total_records_synced + records_fetched,
        records_synced_in_last_run: records_fetched
      )
    when 'token', 'page'
      update!(
        cursor_token: new_value.to_s,
        last_incremental_sync_at: Time.current,
        total_records_synced: total_records_synced + records_fetched,
        records_synced_in_last_run: records_fetched
      )
    end
  end

  # Reset cursor for a full re-sync
  def reset!
    update!(
      cursor_timestamp: nil,
      cursor_offset: nil,
      cursor_token: nil,
      cursor_data: {},
      last_full_sync_at: Time.current,
      records_synced_in_last_run: 0
    )
  end

  # Mark full sync complete
  def mark_full_sync_complete!(records_fetched)
    update!(
      last_full_sync_at: Time.current,
      cursor_timestamp: Time.current,  # Start incremental from now
      total_records_synced: total_records_synced + records_fetched,
      records_synced_in_last_run: records_fetched
    )
  end

  # ============================================
  # QUERY HELPERS
  # ============================================

  # Build API params for fetching next batch
  def api_params
    case cursor_type
    when 'timestamp'
      return {} unless cursor_timestamp
      { updated_after: cursor_timestamp.iso8601, order: 'updated_at:asc' }
    when 'offset'
      { offset: cursor_offset || 0, limit: 100 }
    when 'token'
      cursor_token.present? ? { cursor: cursor_token } : {}
    when 'page'
      { page: cursor_token.present? ? cursor_token.to_i : 1 }
    else
      {}
    end
  end

  # Check if we should do a full sync
  def needs_full_sync?
    # Never synced, or been more than 7 days since full sync
    last_full_sync_at.nil? || last_full_sync_at < 7.days.ago
  end

  # Check if incremental sync is available
  def can_do_incremental?
    cursor_value.present? && !needs_full_sync?
  end

  private

  def parse_timestamp(value)
    case value
    when Time, DateTime
      value.to_time
    when String
      Time.parse(value)
    when Integer
      Time.at(value)
    else
      Time.current
    end
  rescue
    Time.current
  end
end

