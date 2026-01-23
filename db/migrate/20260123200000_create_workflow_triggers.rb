# frozen_string_literal: true

class CreateWorkflowTriggers < ActiveRecord::Migration[8.0]
  def change
    # WorkflowTrigger - Polymorphic association between triggerable entities and workflows
    create_table :workflow_triggers do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :automation_code, null: false, foreign_key: true
      
      # Polymorphic reference to what triggers this workflow
      t.references :triggerable, polymorphic: true, null: true
      
      # For webhook triggers - unique path
      t.string :webhook_path, index: { unique: true, where: "webhook_path IS NOT NULL" }
      t.string :webhook_secret
      
      # Trigger configuration
      t.string :trigger_type, null: false  # form, webhook, schedule, record, manual
      t.jsonb :trigger_config, default: {}
      
      # For schedule triggers
      t.string :cron_expression
      t.datetime :next_trigger_at
      t.datetime :last_triggered_at
      
      # Status
      t.string :status, default: 'active'  # active, paused, disabled
      t.boolean :enabled, default: true
      
      # Metrics
      t.integer :trigger_count, default: 0
      t.integer :success_count, default: 0
      t.integer :error_count, default: 0
      
      t.timestamps
    end

    add_index :workflow_triggers, [:triggerable_type, :triggerable_id]
    add_index :workflow_triggers, [:trigger_type, :status]
    add_index :workflow_triggers, [:entity_id, :status]
    
    # Add compiled workflow fields to automation_codes
    add_column :automation_codes, :compiled_steps, :jsonb, default: []
    add_column :automation_codes, :compiled_at, :datetime
    add_column :automation_codes, :compilation_errors, :jsonb, default: []
    add_column :automation_codes, :is_compiled, :boolean, default: false
    add_column :automation_codes, :design_mode, :boolean, default: true  # true = visual designer, false = code mode
  end
end
