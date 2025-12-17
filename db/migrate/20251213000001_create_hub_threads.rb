# frozen_string_literal: true

class CreateHubThreads < ActiveRecord::Migration[8.0]
  def change
    create_table :hub_threads do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :team_channel, null: true, foreign_key: true  # nil = DM or standalone
      t.references :started_by, polymorphic: true, null: false   # User or AgentPlugin
      
      # Thread classification
      t.string :thread_type, null: false, default: 'channel'  # channel, dm, agent_handoff, work_stream
      t.string :subject
      t.string :status, null: false, default: 'active'  # active, archived, resolved
      
      # For DMs - cache participant info for quick lookup
      t.jsonb :dm_participant_ids, default: []  # [user_ids] + [agent_ids] for DMs
      
      # Link to agent work if this thread is about a specific task
      t.references :agent_plugin_execution, null: true, foreign_key: true
      t.references :agent_work_item, null: true, foreign_key: true
      
      # Metadata
      t.jsonb :metadata, default: {}
      t.integer :message_count, default: 0
      t.datetime :last_activity_at
      t.boolean :pinned, default: false
      
      t.timestamps
    end

    add_index :hub_threads, :thread_type
    add_index :hub_threads, :status
    add_index :hub_threads, :last_activity_at
    add_index :hub_threads, [:entity_id, :thread_type]
    add_index :hub_threads, [:entity_id, :status, :last_activity_at], name: 'idx_hub_threads_active_recent'
    add_index :hub_threads, :dm_participant_ids, using: :gin
  end
end
