# frozen_string_literal: true

class CreateIntegrationSyncInfrastructure < ActiveRecord::Migration[7.1]
  def change
    # =====================================================
    # INTEGRATION SYNC RECORDS
    # Tracks which external records have been synced to which internal records
    # Enables: upsert logic, deduplication, sync history
    # =====================================================
    create_table :integration_sync_records do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :connection, null: false, foreign_key: true  # Which integration connection
      
      # External record identification
      t.string :external_id, null: false              # ID in the external system
      t.string :external_type, null: false            # Type in external system (e.g., 'customer', 'order')
      t.jsonb :external_data, default: {}             # Snapshot of external data at last sync
      t.string :external_hash                         # Hash of external data for change detection
      
      # Internal record identification
      t.string :internal_type, null: false            # Rails model (e.g., 'Contact', 'Order')
      t.bigint :internal_id                           # ID in our system (null if pending approval)
      
      # Sync status
      t.string :sync_status, default: 'synced'        # synced, pending_approval, error, deleted
      t.string :sync_direction, default: 'inbound'    # inbound, outbound, bidirectional
      t.datetime :last_synced_at
      t.datetime :last_external_update_at             # When external record was last updated
      t.integer :sync_count, default: 0
      
      # Error tracking
      t.text :last_error
      t.datetime :last_error_at
      t.integer :error_count, default: 0
      
      # Metadata
      t.jsonb :metadata, default: {}                  # Field mappings used, transformations applied
      
      t.timestamps
      
      # Unique constraint: one sync record per external record per connection
      t.index [:connection_id, :external_type, :external_id], unique: true, name: 'idx_sync_records_unique'
      t.index [:entity_id, :internal_type, :internal_id], name: 'idx_sync_records_internal'
      t.index :sync_status
      t.index :last_synced_at
    end

    # =====================================================
    # INTEGRATION SYNC CURSORS
    # Tracks sync position for incremental data fetching
    # Enables: efficient pagination, resume after failure
    # =====================================================
    create_table :integration_sync_cursors do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :connection, null: false, foreign_key: true
      
      t.string :resource_type, null: false            # What we're syncing (e.g., 'customers', 'orders')
      t.string :cursor_type, default: 'timestamp'     # timestamp, offset, token
      
      # Cursor values (depending on type)
      t.datetime :cursor_timestamp                    # For timestamp-based (e.g., updated_after)
      t.integer :cursor_offset                        # For offset pagination
      t.string :cursor_token                          # For cursor/token pagination
      t.jsonb :cursor_data, default: {}               # Additional cursor state
      
      # Sync metadata
      t.datetime :last_full_sync_at                   # When we last did a full sync
      t.datetime :last_incremental_sync_at            # When we last did incremental
      t.integer :total_records_synced, default: 0
      t.integer :records_synced_in_last_run, default: 0
      
      t.timestamps
      
      t.index [:connection_id, :resource_type], unique: true
    end

    # =====================================================
    # INTEGRATION STAGING RECORDS
    # Holds data awaiting human approval before commit
    # Enables: review queue, bulk approve/reject
    # =====================================================
    create_table :integration_staging_records do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :connection, null: false, foreign_key: true
      t.references :scheduled_agent_task, foreign_key: true  # Which sync task created this
      
      # Record data
      t.string :external_id, null: false
      t.string :external_type, null: false
      t.string :target_type, null: false              # What it will become (Contact, Order, etc.)
      t.jsonb :staged_data, null: false               # The data to be imported
      t.jsonb :field_mappings, default: {}            # How fields were mapped
      t.jsonb :validation_results, default: {}        # Pre-validation results
      
      # Approval workflow
      t.string :status, default: 'pending'            # pending, approved, rejected, imported, error
      t.references :reviewed_by, foreign_key: { to_table: :users }
      t.datetime :reviewed_at
      t.text :review_notes
      
      # After approval
      t.bigint :created_record_id                     # ID of created record after import
      t.datetime :imported_at
      
      t.timestamps
      
      t.index [:entity_id, :status]
      t.index [:connection_id, :external_type, :external_id], name: 'idx_staging_external'
    end

    # =====================================================
    # INTEGRATION SYNC CONFIGS
    # Defines how a specific integration should sync
    # Enables: customizable sync rules per integration
    # =====================================================
    create_table :integration_sync_configs do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :connection, null: false, foreign_key: true
      
      t.string :resource_type, null: false            # External resource (e.g., 'customers')
      t.string :target_type, null: false              # Internal model (e.g., 'Contact')
      
      # Sync settings
      t.boolean :enabled, default: true
      t.string :sync_direction, default: 'inbound'    # inbound, outbound, bidirectional
      t.string :sync_mode, default: 'incremental'     # full, incremental
      t.string :conflict_resolution, default: 'external_wins'  # external_wins, internal_wins, manual
      
      # Scheduling (if automated)
      t.string :schedule_type                         # manual, scheduled, realtime
      t.string :cron_expression                       # If scheduled
      t.references :scheduled_agent_task, foreign_key: true
      
      # Field mappings
      t.jsonb :field_mappings, null: false            # { external_field: internal_field }
      t.jsonb :default_values, default: {}            # Default values for unmapped fields
      t.jsonb :transformations, default: {}           # Field transformations
      
      # Filtering
      t.jsonb :filter_conditions, default: {}         # Only sync records matching these conditions
      
      # Approval settings
      t.boolean :requires_approval, default: false    # Stage for human review?
      t.integer :approval_threshold                   # Auto-approve if under this many records
      
      t.timestamps
      
      t.index [:connection_id, :resource_type, :target_type], unique: true, name: 'idx_sync_config_unique'
    end
  end
end

