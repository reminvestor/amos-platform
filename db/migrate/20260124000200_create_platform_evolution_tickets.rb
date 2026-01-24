# frozen_string_literal: true

class CreatePlatformEvolutionTickets < ActiveRecord::Migration[8.0]
  def change
    create_table :platform_evolution_tickets do |t|
      t.references :entity, null: false, foreign_key: true
      t.string :ticket_type, null: false  # 'new_tool', 'new_loadout', 'tool_improvement', 'bug_fix', 'feature_request'
      t.string :status, null: false, default: 'open'  # 'open', 'in_progress', 'completed', 'rejected', 'blocked'
      t.string :priority, null: false, default: 'medium'  # 'low', 'medium', 'high', 'critical'
      t.string :title, null: false
      t.text :description
      t.jsonb :evidence, default: {}  # Data that triggered this ticket (metrics, user requests, etc.)
      t.jsonb :proposed_solution, default: {}  # AI-generated solution proposal
      t.jsonb :implementation_details, default: {}  # How it was implemented
      t.string :source  # 'auto_detected', 'user_request', 'admin_created', 'ai_suggested'
      t.string :target_area  # 'loadout', 'tool', 'canvas', 'integration', 'core'
      t.string :target_slug  # e.g., 'landing_page_manager' or 'edit_landing_page_section'
      t.references :assigned_to, polymorphic: true  # User or Agent that's working on it
      t.references :created_by, polymorphic: true  # Who/what created the ticket
      t.references :completed_by, polymorphic: true  # Who/what completed it
      t.datetime :started_at
      t.datetime :completed_at
      t.integer :estimated_hours
      t.integer :actual_hours
      t.float :impact_score  # Estimated improvement impact (0-1)
      t.timestamps
    end

    add_index :platform_evolution_tickets, [:entity_id, :status]
    add_index :platform_evolution_tickets, [:status, :priority]
    add_index :platform_evolution_tickets, [:ticket_type, :status]
    add_index :platform_evolution_tickets, [:target_area, :target_slug]
  end
end
