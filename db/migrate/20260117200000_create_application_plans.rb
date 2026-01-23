# frozen_string_literal: true

class CreateApplicationPlans < ActiveRecord::Migration[7.1]
  def change
    create_table :application_plans do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      
      # Plan basics
      t.string :name, null: false
      t.text :description
      t.string :archetype # knowledge_base, crm, inventory, project_mgmt, custom
      
      # Status: drafting → pending_approval → approved → building → completed → failed
      t.string :status, null: false, default: 'drafting'
      
      # The full plan specification
      t.jsonb :plan_spec, null: false, default: {}
      # Structure:
      # {
      #   modules: [{ name, description, fields, views }],
      #   website: { pages, theme, features },
      #   agent: { name, capabilities, personality },
      #   tools: [{ name, description, type }],
      #   integrations: [{ slug, purpose, is_critical }],
      #   workflows: [{ name, trigger, actions }],
      #   scheduled_tasks: [{ name, schedule, action }]
      # }
      
      # Refinement history (user feedback during planning)
      t.jsonb :refinement_history, null: false, default: []
      # [{ iteration, feedback, timestamp, changes_made }]
      
      # Build results
      t.jsonb :build_results, null: false, default: {}
      # { modules: [], agent_id, tools: [], integrations: [], workflows: [], tasks: [] }
      
      # Error tracking
      t.text :error_message
      t.jsonb :build_log, null: false, default: []
      
      # Timestamps
      t.datetime :approved_at
      t.datetime :build_started_at
      t.datetime :completed_at
      
      t.timestamps
    end
    
    add_index :application_plans, :status
    add_index :application_plans, :archetype
    add_index :application_plans, [:entity_id, :status]
  end
end

