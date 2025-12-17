# frozen_string_literal: true

class CreateHubParticipants < ActiveRecord::Migration[8.0]
  def change
    create_table :hub_participants do |t|
      t.references :hub_thread, null: false, foreign_key: true
      t.references :participant, polymorphic: true, null: false  # User or AgentPlugin
      
      # Participation details
      t.string :role, null: false, default: 'member'  # owner, member, observer, mentioned
      t.datetime :joined_at, null: false
      t.datetime :left_at  # null = still active
      
      # Read tracking
      t.datetime :last_read_at
      t.integer :unread_count, default: 0
      
      # Notification preferences for this thread
      t.boolean :notifications_enabled, default: true
      t.boolean :muted, default: false
      t.datetime :muted_until  # Temporary mute
      
      # For agents: track what context they can access
      t.datetime :context_access_from  # Can only see messages from this time
      t.jsonb :permissions, default: {}  # Fine-grained permissions
      
      t.timestamps
    end

    add_index :hub_participants, [:hub_thread_id, :participant_type, :participant_id], 
              unique: true, 
              name: 'idx_hub_participants_unique'
    add_index :hub_participants, [:participant_type, :participant_id]
    add_index :hub_participants, [:participant_type, :participant_id, :left_at],
              where: "left_at IS NULL",
              name: 'idx_hub_participants_active'
    add_index :hub_participants, :unread_count, where: "unread_count > 0"
  end
end
