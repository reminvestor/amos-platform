# frozen_string_literal: true

class CreateSavedVisualizations < ActiveRecord::Migration[8.0]
  def change
    create_table :saved_visualizations do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      
      # Source reference - where the visualization data lives
      t.references :scout_message, foreign_key: true       # The message containing the visualization
      t.references :scout_conversation, foreign_key: true  # The conversation it came from
      t.references :agent_work_item, foreign_key: true     # Optional - link to work item
      t.references :agent_plugin_execution, foreign_key: true  # If created by an agent
      
      t.string :name, null: false
      t.text :description
      t.string :visualization_type, null: false  # dashboard, report, comparison, chart, custom
      
      # Canvas reference - points to the original canvas_data
      t.string :source_type, null: false         # message_metadata, artifact, inline
      t.string :source_session_id                # session_id for looking up the message
      t.integer :source_message_index            # which message in the session (if multiple)
      
      # Only store inline if source is lost or for quick access
      t.text :html_content_cache                 # Cached copy (optional, for performance)
      t.jsonb :canvas_data_cache, default: {}    # Cached canvas_data
      t.datetime :cache_expires_at
      
      # Regeneration config - how to recreate this visualization
      t.text :original_prompt                    # The user prompt that created it
      t.jsonb :generation_config, default: {}   # Tool calls, parameters used
      
      # Refresh settings
      t.boolean :auto_refresh, default: false
      t.string :refresh_schedule                 # cron expression for auto-refresh
      t.datetime :last_refreshed_at
      t.datetime :next_refresh_at
      
      # Organization
      t.string :category                         # sales, marketing, operations, etc.
      t.jsonb :tags, default: []
      t.boolean :pinned, default: false
      t.boolean :shared, default: false          # Visible to other users in entity
      t.boolean :archived, default: false
      
      t.jsonb :metadata, default: {}
      
      t.timestamps
    end

    add_index :saved_visualizations, :visualization_type
    add_index :saved_visualizations, :source_type
    add_index :saved_visualizations, :source_session_id
    add_index :saved_visualizations, :category
    add_index :saved_visualizations, :pinned
    add_index :saved_visualizations, :shared
    add_index :saved_visualizations, :archived
    add_index :saved_visualizations, [:entity_id, :user_id]
    add_index :saved_visualizations, [:entity_id, :shared]
    add_index :saved_visualizations, :auto_refresh
  end
end

