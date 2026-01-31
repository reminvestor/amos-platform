# frozen_string_literal: true

class AddSolanaWalletToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :solana_wallet_address, :string
    add_column :users, :wallet_verified_at, :datetime
    add_column :users, :wallet_verification_message, :string
    add_column :users, :wallet_verification_signature, :string
    
    add_index :users, :solana_wallet_address, unique: true
  end
end
