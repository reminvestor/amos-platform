# frozen_string_literal: true

class CreateTokenStakes < ActiveRecord::Migration[8.0]
  def change
    create_table :token_stakes do |t|
      t.references :user, null: false, foreign_key: true
      t.references :entity, foreign_key: true
      t.references :source, polymorphic: true

      t.string :stake_type, null: false
      t.string :category
      t.decimal :initial_amount, precision: 18, scale: 4, null: false
      t.decimal :current_amount, precision: 18, scale: 4, null: false
      t.decimal :decay_rate, precision: 5, scale: 4, default: 0.5, null: false
      t.decimal :total_decayed, precision: 18, scale: 4, default: 0

      t.datetime :earned_at, null: false
      t.datetime :last_decay_at
      t.datetime :vested_at
      
      t.boolean :is_transferable, default: false
      t.boolean :is_locked, default: false
      t.datetime :lock_until

      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :token_stakes, :stake_type
    add_index :token_stakes, :category
    add_index :token_stakes, :earned_at
    add_index :token_stakes, [:user_id, :stake_type]
    add_index :token_stakes, [:entity_id, :stake_type]
    add_index :token_stakes, :current_amount, where: 'current_amount > 0', name: 'index_token_stakes_active'
  end
end
