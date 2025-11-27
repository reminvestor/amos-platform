class CreateAgentAbTests < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_ab_tests do |t|
      t.references :control_agent, null: false, foreign_key: { to_table: :agent_plugins }
      t.references :variant_agent, null: false, foreign_key: { to_table: :agent_plugins }
      t.references :enrollment, foreign_key: { to_table: :agent_school_enrollments }
      t.references :entity, null: false, foreign_key: true

      # Test configuration
      t.string :status, default: 'pending', null: false  # pending, running, completed, cancelled
      t.integer :target_tasks, default: 50, null: false
      t.jsonb :metrics_to_compare, default: ['success_rate', 'quality_score', 'efficiency']

      # Progress tracking
      t.integer :control_tasks_completed, default: 0
      t.integer :variant_tasks_completed, default: 0

      # Results
      t.jsonb :control_results, default: {}
      t.jsonb :variant_results, default: {}
      t.jsonb :statistical_analysis, default: {}
      t.string :winner  # control, variant, tie

      # Timestamps
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :agent_ab_tests, :status
    add_index :agent_ab_tests, [:control_agent_id, :status]
    add_index :agent_ab_tests, [:variant_agent_id, :status]
  end
end

