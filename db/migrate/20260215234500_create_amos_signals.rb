# frozen_string_literal: true

class CreateAmosSignals < ActiveRecord::Migration[8.0]
  def change
    create_table :amos_signals do |t|
      t.references :entity, null: false, foreign_key: true

      t.string :signal_type, null: false    # 'error_spike', 'bounty_stale', 'integration_failure', etc.
      t.string :source, null: false          # 'support_ticket', 'integration_log', 'bounty', etc.
      t.float :strength, default: 0.5        # 0.0-1.0
      t.string :status, default: 'pending'   # 'pending', 'acknowledged', 'acted_on', 'dismissed', 'expired'
      t.text :summary                        # Human-readable description
      t.jsonb :data, default: {}             # Signal-specific payload
      t.jsonb :context, default: {}          # Additional context for processing

      # Deduplication
      t.string :fingerprint                  # Hash of signal_type + key data, for debounce
      t.datetime :first_seen_at              # When this signal pattern first appeared
      t.integer :occurrence_count, default: 1 # How many times this signal fired

      # Processing
      t.datetime :acknowledged_at
      t.datetime :acted_on_at
      t.bigint :thinking_session_id          # Which session processed this
      t.bigint :working_memory_id            # Thought created from this signal

      t.timestamps
    end

    add_index :amos_signals, [:entity_id, :status]
    add_index :amos_signals, [:entity_id, :signal_type]
    add_index :amos_signals, :fingerprint
    add_index :amos_signals, [:entity_id, :created_at]
    add_index :amos_signals, :strength
  end
end
