# frozen_string_literal: true

class RenameHashColumnsInAgentEnergyTransactions < ActiveRecord::Migration[8.0]
  def change
    # Only rename if the old column names exist (they may already be ledger_hash if table was created fresh)
    if column_exists?(:agent_energy_transactions, :hash)
      rename_column :agent_energy_transactions, :hash, :ledger_hash
    end
    if column_exists?(:agent_energy_transactions, :previous_hash)
      rename_column :agent_energy_transactions, :previous_hash, :previous_ledger_hash
    end
  end
end

