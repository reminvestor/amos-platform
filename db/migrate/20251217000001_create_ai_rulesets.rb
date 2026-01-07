class CreateAiRulesets < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_rulesets do |t|
      t.references :entity, null: true, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.string :category, null: false
      t.text :rules, array: true, default: []
      t.boolean :is_active, default: true
      t.integer :priority, default: 0
      t.boolean :is_system, default: false
      t.timestamps

      t.index [:entity_id, :is_active]
      t.index [:category]
      t.index [:is_system]
    end
  end
end
