# frozen_string_literal: true

class CreateBenchmarkResults < ActiveRecord::Migration[8.0]
  def change
    create_table :benchmark_runs do |t|
      t.references :entity, null: false, foreign_key: true
      t.string :run_id, null: false  # UUID for grouping results
      t.string :run_type, null: false  # 'single', 'category', 'full', 'ab_comparison'
      t.string :benchmark_category  # 'gsm8k', 'hotpot', 'tool_use', 'collaboration'
      t.string :agent_slug
      t.boolean :collaboration_enabled, default: true
      
      # Summary metrics
      t.integer :total_tasks, default: 0
      t.integer :correct_count, default: 0
      t.integer :failed_count, default: 0
      t.float :accuracy_percentage
      t.integer :avg_execution_time_ms
      t.integer :total_tokens_used, default: 0
      t.float :total_cost_cents, default: 0.0
      
      # Collaboration metrics
      t.integer :collaboration_requests, default: 0
      t.integer :collaboration_helped_count, default: 0
      
      # Environment info
      t.string :environment  # 'development', 'staging', 'production'
      t.string :model_used
      t.string :git_commit
      t.jsonb :metadata, default: {}
      
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end

    create_table :benchmark_task_results do |t|
      t.references :benchmark_run, null: false, foreign_key: true
      t.references :agent_plugin, foreign_key: true
      t.references :agent_plugin_execution, foreign_key: true
      
      t.string :task_id, null: false  # e.g., 'gsm8k_001'
      t.string :category  # 'gsm8k', 'hotpot', etc.
      t.string :difficulty  # 'easy', 'medium', 'hard'
      t.text :question
      t.text :expected_answer
      t.text :actual_answer
      t.boolean :correct, default: false
      
      # Execution details
      t.integer :execution_time_ms
      t.integer :tokens_used
      t.float :cost_cents
      
      # Collaboration details
      t.boolean :asked_for_help, default: false
      t.string :helper_agent_slug
      t.boolean :collaboration_helped, default: false
      
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :benchmark_runs, :run_id, unique: true
    add_index :benchmark_runs, [:entity_id, :created_at]
    add_index :benchmark_runs, :benchmark_category
    add_index :benchmark_runs, :run_type
    add_index :benchmark_task_results, :task_id
    add_index :benchmark_task_results, [:benchmark_run_id, :task_id]
  end
end

