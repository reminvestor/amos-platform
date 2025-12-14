# frozen_string_literal: true

class CreateHubPresences < ActiveRecord::Migration[8.0]
  def change
    create_table :hub_presences do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :participant, polymorphic: true, null: false  # User or AgentPlugin
      
      # Presence status
      t.string :status, null: false, default: 'offline'
      # User statuses: online, away, busy, offline
      # Agent statuses: online, working, thinking, waiting, offline
      
      t.string :status_message  # Custom status message
      t.string :status_emoji    # Custom emoji for status
      
      # For agents: current activity
      t.string :current_activity  # "Analyzing Q4 data", "Generating report", etc.
      t.references :active_execution, null: true, foreign_key: { to_table: :agent_plugin_executions }
      t.float :activity_progress  # 0.0 to 1.0 for progress tracking
      
      # Timestamps
      t.datetime :last_seen_at
      t.datetime :status_changed_at
      
      # For timeout handling
      t.datetime :expires_at  # Auto-offline after this time
      
      t.timestamps
    end

    add_index :hub_presences, [:entity_id, :status]
    add_index :hub_presences, [:participant_type, :participant_id], unique: true
    add_index :hub_presences, :status
    add_index :hub_presences, :expires_at, where: "expires_at IS NOT NULL"
  end
end
