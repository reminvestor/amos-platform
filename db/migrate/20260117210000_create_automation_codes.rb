# frozen_string_literal: true

class CreateAutomationCodes < ActiveRecord::Migration[7.1]
  def change
    create_table :automation_codes do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :web_app, null: true, foreign_key: true
      t.references :app_module, null: true, foreign_key: true
      t.references :created_by, null: true, foreign_key: { to_table: :users }

      # Identity
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description

      # Trigger configuration
      t.string :trigger_type, null: false  # record_created, record_updated, status_changed, schedule, webhook, form_submit
      t.jsonb :trigger_config, default: {}  # { field: 'status', from: 'draft', to: 'published' }

      # The AI-generated Ruby code
      t.text :code, null: false
      t.integer :code_version, default: 1
      t.datetime :code_generated_at
      t.string :code_generated_by  # 'claude-sonnet-4-20250514'

      # Testing/validation
      t.jsonb :sample_input, default: {}
      t.jsonb :sample_output, default: {}
      t.boolean :is_tested, default: false
      t.datetime :last_tested_at

      # Execution tracking
      t.integer :execution_count, default: 0
      t.integer :success_count, default: 0
      t.integer :error_count, default: 0
      t.datetime :last_executed_at
      t.datetime :last_error_at
      t.text :last_error_message
      t.float :avg_execution_time_ms

      # Status
      t.string :status, null: false, default: 'draft'  # draft, testing, active, paused, failed

      t.timestamps
    end

    add_index :automation_codes, [:entity_id, :slug], unique: true
    add_index :automation_codes, [:entity_id, :status]
    add_index :automation_codes, [:trigger_type]
    add_index :automation_codes, [:web_app_id, :trigger_type]
    add_index :automation_codes, [:app_module_id, :trigger_type]

    # Execution log for debugging and auditing
    create_table :automation_executions do |t|
      t.references :automation_code, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.references :triggered_by, null: true, foreign_key: { to_table: :users }

      # Execution context
      t.string :trigger_source  # 'record', 'schedule', 'webhook', 'manual'
      t.jsonb :trigger_data, default: {}
      t.jsonb :execution_result, default: {}

      # Timing
      t.datetime :started_at
      t.datetime :completed_at
      t.float :duration_ms

      # Status
      t.string :status, null: false  # pending, running, success, failed, timeout
      t.text :error_message

      t.timestamps
    end

    add_index :automation_executions, [:automation_code_id, :status]
    add_index :automation_executions, [:entity_id, :created_at]
  end
end

