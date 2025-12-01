# frozen_string_literal: true

class CreateScheduledAgentTasks < ActiveRecord::Migration[8.0]
  def change
    create_table :scheduled_agent_tasks do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :agent_plugin, foreign_key: true  # Optional - if nil, Scout handles it

      t.string :name, null: false
      t.text :description
      t.string :task_type, null: false  # email_summary, report_generation, data_sync, custom
      t.text :prompt, null: false       # The actual instruction for the agent
      
      # Scheduling configuration
      t.string :schedule_type, null: false  # once, daily, weekly, monthly, cron
      t.string :cron_expression              # For complex schedules
      t.time :run_at_time                    # Time of day to run (for daily/weekly/monthly)
      t.integer :run_on_day                  # Day of week (0-6) or day of month (1-31)
      t.string :timezone, default: 'UTC'
      
      # Execution tracking
      t.datetime :next_run_at
      t.datetime :last_run_at
      t.integer :run_count, default: 0
      t.integer :failure_count, default: 0
      t.integer :consecutive_failures, default: 0
      
      # Configuration
      t.jsonb :input_context, default: {}    # Additional context for the task
      t.jsonb :output_config, default: {}    # How to deliver results (email, notification, etc.)
      t.jsonb :metadata, default: {}
      
      # Status
      t.string :status, default: 'active'    # active, paused, completed, failed, archived
      t.boolean :enabled, default: true
      t.integer :max_runs                     # Optional limit on number of executions
      t.datetime :expires_at                  # Optional expiration date
      
      t.timestamps
    end

    add_index :scheduled_agent_tasks, :status
    add_index :scheduled_agent_tasks, :enabled
    add_index :scheduled_agent_tasks, :next_run_at
    add_index :scheduled_agent_tasks, :task_type
    add_index :scheduled_agent_tasks, [:entity_id, :status]
    add_index :scheduled_agent_tasks, [:entity_id, :next_run_at]
  end
end

