class CreateAgentEnergyTransactions < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_energy_transactions do |t|
      t.references :agent_plugin, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.references :agent_plugin_execution, foreign_key: true
      t.references :collaboration_request, foreign_key: { to_table: :agent_collaboration_requests }

      t.string :transaction_type, null: false  # earned, spent, penalty, regenerated, tax, redistribution
      t.float :amount, null: false
      t.string :reason, null: false
      t.float :balance_before, null: false
      t.float :balance_after, null: false
      t.jsonb :metadata, default: {}

      # For immutable ledger (use ledger_hash to avoid conflict with Ruby's hash method)
      t.string :ledger_hash
      t.string :previous_ledger_hash

      t.timestamps
    end

    add_index :agent_energy_transactions, :transaction_type
    add_index :agent_energy_transactions, :created_at
    add_index :agent_energy_transactions, [:agent_plugin_id, :created_at]
  end
end

