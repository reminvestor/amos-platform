# frozen_string_literal: true

class CreateApps < ActiveRecord::Migration[7.0]
  def change
    create_table :apps do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }
      
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :icon, default: 'grid'
      t.string :color, default: '#6366f1'
      
      # Status tracking
      t.string :status, default: 'designing', null: false
      # designing, planning, building, preview, active, archived
      
      # Discovery & Planning
      t.jsonb :intent, default: {}        # Discovery conversation results
      t.jsonb :blueprint, default: {}     # Full design specification
      t.jsonb :user_stories, default: []  # What users need to do
      t.jsonb :personas, default: []      # User roles/types
      
      # Build tracking
      t.datetime :blueprint_approved_at
      t.datetime :build_started_at
      t.datetime :build_completed_at
      t.datetime :published_at
      
      # Configuration
      t.jsonb :settings, default: {}      # App-level settings
      t.jsonb :metadata, default: {}      # Additional data
      
      # Versioning
      t.integer :version, default: 1
      t.jsonb :changelog, default: []
      
      t.timestamps
    end
    
    add_index :apps, [:entity_id, :slug], unique: true
    add_index :apps, :status
    add_index :apps, :name
    
    # Add app_id to app_modules to allow grouping
    add_reference :app_modules, :app, foreign_key: true, null: true
    
    # Add app_id to agent_plugins for app assistants
    add_reference :agent_plugins, :app, foreign_key: true, null: true
  end
end





