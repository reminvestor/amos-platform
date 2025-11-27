# frozen_string_literal: true

class RenameHashColumnsInAgentEnergyTransactions < ActiveRecord::Migration[8.0]
  def change
    # Rename 'hash' to 'ledger_hash' to avoid conflict with Ruby's built-in hash method
    rename_column :agent_energy_transactions, :hash, :ledger_hash
    rename_column :agent_energy_transactions, :previous_hash, :previous_ledger_hash
  end
end

