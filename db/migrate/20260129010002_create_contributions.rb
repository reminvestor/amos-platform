# frozen_string_literal: true

class CreateContributions < ActiveRecord::Migration[8.0]
  def change
    create_table :contributions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :entity, foreign_key: true
      t.references :reviewed_by, foreign_key: { to_table: :users }

      t.string :contribution_type, null: false
      t.string :title, null: false
      t.text :description, null: false
      t.integer :status, default: 0, null: false

      t.decimal :stake_value, precision: 18, scale: 4
      t.decimal :complexity_multiplier, precision: 5, scale: 2, default: 1.0

      t.string :external_reference  # GitHub PR, commit hash, etc.
      t.string :external_url
      t.text :review_notes

      t.datetime :reviewed_at
      t.datetime :merged_at
      
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :contributions, :contribution_type
    add_index :contributions, :status
    add_index :contributions, [:user_id, :status]
    add_index :contributions, [:user_id, :contribution_type]
    add_index :contributions, :external_reference
  end
end
