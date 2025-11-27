class CreateAgentDecisionBoundaries < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_decision_boundaries do |t|
      t.references :agent_plugin, null: false, foreign_key: true

      # Bayesian parameters for ask-for-help decision
      t.float :ask_alpha, default: 1.0, null: false
      t.float :ask_beta, default: 1.0, null: false
      t.float :solo_alpha, default: 1.0, null: false
      t.float :solo_beta, default: 1.0, null: false

      # Current computed threshold
      t.float :current_threshold, default: 50.0

      # History for analysis
      t.jsonb :decision_history, default: []
      t.integer :total_decisions, default: 0
      t.integer :correct_decisions, default: 0

      t.timestamps
    end

    # Index already created by t.references with unique constraint
    # add_index :agent_decision_boundaries, [:agent_plugin_id], unique: true
  end
end

