# frozen_string_literal: true

class CreateAmosThinkingSessions < ActiveRecord::Migration[7.1]
  def change
    create_table :amos_thinking_sessions do |t|
      t.references :entity, null: false, foreign_key: true

      # Session tracking
      t.string :session_type, null: false, default: 'nightly'  # nightly, triggered, weekly_review
      t.string :status, default: 'running'                      # running, completed, failed

      # What AMOS analyzed
      t.jsonb :context_analyzed, default: {}   # Logs, tickets, metrics, etc.
      t.integer :errors_analyzed, default: 0
      t.integer :tickets_analyzed, default: 0
      t.integer :feature_requests_analyzed, default: 0

      # What AMOS produced
      t.text :reflection_summary              # AI's summary of the day/period
      t.text :improvement_ideas               # Ideas generated
      t.integer :bounties_created, default: 0
      t.integer :total_points_allocated, default: 0

      # Performance tracking
      t.datetime :started_at
      t.datetime :completed_at
      t.integer :duration_seconds
      t.integer :llm_tokens_used, default: 0
      t.decimal :llm_cost, precision: 10, scale: 4, default: 0

      # Full thinking log (for debugging/transparency)
      t.text :thinking_log

      t.timestamps
    end

    add_index :amos_thinking_sessions, :session_type
    add_index :amos_thinking_sessions, :status
    add_index :amos_thinking_sessions, :created_at
  end
end
