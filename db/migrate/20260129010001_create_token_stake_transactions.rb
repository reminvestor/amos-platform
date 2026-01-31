# frozen_string_literal: true

class CreateTokenStakeTransactions < ActiveRecord::Migration[8.0]
  def change
    create_table :token_stake_transactions do |t|
      t.references :token_stake, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.string :transaction_type, null: false
      t.decimal :amount, precision: 18, scale: 4, null: false
      t.decimal :balance_before, precision: 18, scale: 4, null: false
      t.decimal :balance_after, precision: 18, scale: 4, null: false

      t.string :description
      t.string :external_reference
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :token_stake_transactions, :transaction_type
    add_index :token_stake_transactions, :created_at
    add_index :token_stake_transactions, [:user_id, :transaction_type]
  end
end
