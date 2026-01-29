# frozen_string_literal: true

class CreateTokenDeposits < ActiveRecord::Migration[8.0]
  def change
    create_table :token_deposits do |t|
      t.references :user, null: false, foreign_key: true
      t.references :entity, null: true, foreign_key: true
      t.references :token_stake, null: true, foreign_key: true  # Created stake
      
      # Deposit details
      t.decimal :amount, precision: 18, scale: 9, null: false
      t.string :wallet_address, null: false
      t.string :status, null: false, default: 'pending'
      
      # Solana transaction details (incoming tx from user)
      t.string :transaction_signature, null: false
      t.string :blockhash
      t.bigint :slot
      t.datetime :confirmed_at
      
      # Verification
      t.boolean :verified, default: false
      t.datetime :verified_at
      
      # Error handling
      t.text :error_message
      
      # Audit
      t.jsonb :metadata, default: {}
      
      t.timestamps
    end

    add_index :token_deposits, :wallet_address
    add_index :token_deposits, :status
    add_index :token_deposits, :transaction_signature, unique: true
    add_index :token_deposits, [:user_id, :status]
    add_index :token_deposits, :verified
  end
end
