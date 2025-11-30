# frozen_string_literal: true

class CreateAgentWorkItems < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_work_items do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :agent_plugin, foreign_key: true
      t.references :scheduled_task_run, foreign_key: true  # If from scheduled task
      t.references :agent_plugin_execution, foreign_key: true
      t.references :scout_conversation, foreign_key: true  # If from conversation
      
      # Work item details
      t.string :work_type, null: false  # task_completed, asset_created, report_generated, email_sent, etc.
      t.string :title, null: false
      t.text :summary
      t.text :details
      
      # What was created/affected
      t.string :asset_type              # landing_page, campaign, integration, tool, agent, etc.
      t.bigint :asset_id
      t.jsonb :asset_data, default: {}  # Snapshot of created asset
      
      # User interaction
      t.boolean :read, default: false
      t.datetime :read_at
      t.boolean :starred, default: false
      t.boolean :archived, default: false
      t.datetime :archived_at
      
      # Importance/Priority
      t.string :priority, default: 'normal'  # low, normal, high, urgent
      t.boolean :requires_action, default: false
      t.string :action_type              # review, approve, respond, etc.
      t.datetime :action_due_at
      
      t.jsonb :metadata, default: {}
      
      t.timestamps
    end

    add_index :agent_work_items, :work_type
    add_index :agent_work_items, :read
    add_index :agent_work_items, :starred
    add_index :agent_work_items, :archived
    add_index :agent_work_items, :priority
    add_index :agent_work_items, :requires_action
    add_index :agent_work_items, [:entity_id, :user_id, :read]
    add_index :agent_work_items, [:entity_id, :user_id, :archived]
    add_index :agent_work_items, [:asset_type, :asset_id]
    add_index :agent_work_items, :created_at
  end
end

