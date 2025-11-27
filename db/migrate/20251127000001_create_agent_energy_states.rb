class CreateAgentEnergyStates < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_energy_states do |t|
      t.references :agent_plugin, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true

      # Current state
      t.float :current_energy, default: 50.0, null: false
      t.float :max_energy, default: 100.0, null: false
      t.float :regeneration_rate, default: 2.0, null: false  # per hour
      t.boolean :in_debt, default: false

      # Lifetime stats
      t.float :total_earned, default: 0.0, null: false
      t.float :total_spent, default: 0.0, null: false
      t.integer :tasks_completed, default: 0, null: false
      t.integer :tasks_failed, default: 0, null: false
      t.integer :tasks_delegated, default: 0, null: false
      t.integer :help_given, default: 0, null: false
      t.integer :help_received, default: 0, null: false

      # Performance metrics
      t.float :success_rate, default: 0.0
      t.float :avg_quality, default: 0.5
      t.float :collaboration_score, default: 0.5
      t.float :elo_rating, default: 1000.0  # For slow-moving reputation

      # Timestamps
      t.datetime :last_energy_update_at
      t.datetime :debt_started_at

      t.timestamps
    end

    # agent_plugin_id index already created by t.references
    add_index :agent_energy_states, [:entity_id, :current_energy], name: 'idx_energy_entity_current'
    add_index :agent_energy_states, :in_debt, name: 'idx_energy_in_debt'
  end
end

