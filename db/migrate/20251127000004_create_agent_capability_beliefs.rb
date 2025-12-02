class CreateAgentCapabilityBeliefs < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_capability_beliefs do |t|
      t.references :agent_plugin, null: false, foreign_key: true

      t.string :task_type, null: false
      t.integer :attempts, default: 0, null: false
      t.integer :successes, default: 0, null: false
      t.float :total_quality, default: 0.0
      t.float :avg_quality, default: 0.5
      t.jsonb :confidence_interval, default: [0.0, 1.0]

      # Specialization tracking
      t.boolean :is_specialty, default: false
      t.boolean :is_weakness, default: false
      t.float :z_score  # How many std devs from population mean

      t.timestamps
    end

    add_index :agent_capability_beliefs, [:agent_plugin_id, :task_type], unique: true
    add_index :agent_capability_beliefs, :is_specialty
    add_index :agent_capability_beliefs, :is_weakness
  end
end

