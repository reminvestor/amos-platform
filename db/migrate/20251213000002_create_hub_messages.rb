# frozen_string_literal: true

class CreateHubMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :hub_messages do |t|
      t.references :hub_thread, null: false, foreign_key: true
      t.references :sender, polymorphic: true, null: false  # User or AgentPlugin
      
      # Message content
      t.text :content, null: false
      t.string :message_type, null: false, default: 'text'
      # Types: text, handoff_request, handoff_complete, question, status_update, 
      #        agent_thinking, system, file_share, reaction_summary
      
      # For threaded replies within a thread
      t.references :reply_to, null: true, foreign_key: { to_table: :hub_messages }
      
      # Agent interaction flags
      t.boolean :needs_response, default: false      # Agent waiting on human
      t.boolean :is_handoff, default: false          # Part of handoff protocol
      t.string :handoff_status                       # pending, accepted, completed, cancelled
      
      # Link to existing agent systems
      t.references :agent_input_request, null: true, foreign_key: true
      t.references :agent_plugin_execution, null: true, foreign_key: true
      
      # Rich content
      t.jsonb :attachments, default: []       # Files, images, documents
      t.jsonb :actions, default: []           # Quick action buttons
      t.jsonb :metadata, default: {}          # Extra data (mentions, formatting, etc.)
      
      # Reactions (emoji -> [user_ids])
      t.jsonb :reactions, default: {}
      
      # Edit tracking
      t.boolean :edited, default: false
      t.datetime :edited_at
      
      # Soft delete for moderation
      t.boolean :deleted, default: false
      t.datetime :deleted_at
      
      t.timestamps
    end

    add_index :hub_messages, :message_type
    add_index :hub_messages, :needs_response
    add_index :hub_messages, :is_handoff
    add_index :hub_messages, [:hub_thread_id, :created_at]
    add_index :hub_messages, [:hub_thread_id, :needs_response], 
              where: "needs_response = true", 
              name: 'idx_hub_messages_pending_responses'
    add_index :hub_messages, [:sender_type, :sender_id, :created_at],
              name: 'idx_hub_messages_by_sender'
  end
end
