# frozen_string_literal: true

class CreateDynamicContents < ActiveRecord::Migration[8.0]
  def change
    create_table :dynamic_contents do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :scout_conversation, foreign_key: true
      t.references :agent_plugin_execution, foreign_key: true
      t.references :scheduled_task_run, foreign_key: true
      
      t.string :content_type, null: false  # visualization, report, dashboard, analysis, table
      t.string :title, null: false
      t.text :subtitle
      
      # The actual content
      t.text :html_content, null: false
      t.jsonb :data_snapshot, default: {}    # The data used to generate it
      t.jsonb :generation_context, default: {}  # Tool calls, prompts, etc.
      
      # Session tracking
      t.string :session_id
      t.integer :message_index              # Which message in the conversation
      
      # Metadata
      t.string :category                    # sales, marketing, analytics, etc.
      t.jsonb :tags, default: []
      t.jsonb :metadata, default: {}
      
      t.timestamps
    end

    add_index :dynamic_contents, :content_type
    add_index :dynamic_contents, :session_id
    add_index :dynamic_contents, :category
    add_index :dynamic_contents, [:entity_id, :user_id]
    add_index :dynamic_contents, :created_at
    
    # Update saved_visualizations to reference dynamic_contents
    add_reference :saved_visualizations, :dynamic_content, foreign_key: true
  end
end

