# frozen_string_literal: true

class AddDisbursementPreferences < ActiveRecord::Migration[8.0]
  def change
    # User disbursement preferences
    add_column :users, :preferred_disbursement_currency, :string, default: 'amos'
    add_column :users, :auto_convert_to_stable, :boolean, default: false
    
    # Token claim disbursement options
    add_column :token_claims, :disbursement_currency, :string, default: 'amos'
    add_column :token_claims, :swap_quote, :jsonb
    add_column :token_claims, :swap_transaction_signature, :string
    add_column :token_claims, :final_amount, :decimal, precision: 18, scale: 9
    add_column :token_claims, :swap_rate, :decimal, precision: 18, scale: 9
    
    add_index :token_claims, :disbursement_currency
  end
end
