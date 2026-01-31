# frozen_string_literal: true

class AddWealthPreservationToTokenStakes < ActiveRecord::Migration[8.0]
  def change
    # Staking vault columns
    change_table :token_stakes do |t|
      t.string :staking_tier, default: 'none'
      t.datetime :locked_until
      
      # Inheritance/transfer columns  
      t.bigint :beneficiary_id
      t.bigint :transferred_to_id
      t.datetime :transferred_at
      
      # Tracking columns
      t.decimal :permanent_floor, precision: 18, scale: 4
    end

    add_index :token_stakes, :staking_tier
    add_index :token_stakes, :locked_until
    add_index :token_stakes, :beneficiary_id
    add_index :token_stakes, :transferred_to_id
    
    add_foreign_key :token_stakes, :users, column: :beneficiary_id
    add_foreign_key :token_stakes, :users, column: :transferred_to_id
  end
end
