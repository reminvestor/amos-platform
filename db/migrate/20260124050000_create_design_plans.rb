# frozen_string_literal: true

class CreateDesignPlans < ActiveRecord::Migration[8.0]
  def change
    create_table :design_plans do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :landing_page, foreign_key: true # Set when built

      t.string :name, null: false
      t.string :design_type, null: false, default: 'landing_page' # landing_page, website, portfolio
      t.text :description
      t.jsonb :plan_data, null: false, default: {} # The full plan structure
      t.string :status, null: false, default: 'draft' # draft, building, completed, failed
      t.text :error_message

      t.timestamps
    end

    add_index :design_plans, :status
    add_index :design_plans, [:entity_id, :user_id, :status]
  end
end
