# frozen_string_literal: true

class CreateTokenClaims < ActiveRecord::Migration[8.0]
  def change
    create_table :token_claims do |t|
      t.references :user, null: false, foreign_key: true
      t.references :entity, null: true, foreign_key: true
      
      # Claim details
      t.decimal :amount, precision: 18, scale: 9, null: false
      t.string :wallet_address, null: false
      t.string :status, null: false, default: 'pending'
      
      # Solana transaction details
      t.string :transaction_signature
      t.string :blockhash
      t.bigint :slot
      t.datetime :confirmed_at
      
      # Fee tracking
      t.decimal :network_fee, precision: 18, scale: 9
      t.decimal :platform_fee, precision: 18, scale: 9
      
      # Error handling
      t.text :error_message
      t.integer :retry_count, default: 0
      t.datetime :last_retry_at
      
      # Audit
      t.string :ip_address
      t.string :user_agent
      t.jsonb :metadata, default: {}
      
      t.timestamps
    end

    add_index :token_claims, :wallet_address
    add_index :token_claims, :status
    add_index :token_claims, :transaction_signature, unique: true
    add_index :token_claims, [:user_id, :status]
    add_index :token_claims, :created_at
  end
end
