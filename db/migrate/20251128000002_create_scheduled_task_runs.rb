# frozen_string_literal: true

class CreateScheduledTaskRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :scheduled_task_runs do |t|
      t.references :scheduled_agent_task, null: false, foreign_key: true
      t.references :agent_plugin_execution, foreign_key: true  # Links to actual execution
      t.references :user, null: false, foreign_key: true
      
      t.string :status, null: false, default: 'pending'  # pending, running, completed, failed, cancelled
      t.datetime :started_at
      t.datetime :completed_at
      t.integer :duration_ms
      
      # Results
      t.text :result_summary           # Brief summary of what was done
      t.jsonb :result_data, default: {}  # Full result data
      t.text :error_message
      
      # Delivery tracking
      t.boolean :notification_sent, default: false
      t.datetime :notification_sent_at
      t.string :notification_method     # email, in_app, both
      
      t.timestamps
    end

    add_index :scheduled_task_runs, :status
    add_index :scheduled_task_runs, :started_at
    add_index :scheduled_task_runs, [:scheduled_agent_task_id, :status]
  end
end

