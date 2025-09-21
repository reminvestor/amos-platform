class CreatePolicyRules < ActiveRecord::Migration[8.0]
  def change
    create_table :policy_rules do |t|
      t.belongs_to :entity, null: false, foreign_key: true
      t.string :name
      t.string :resource_type
      t.string :resource_id
      t.string :agent_role
      t.string :action
      t.jsonb :conditions
      t.integer :max_daily_calls
      t.integer :max_write_calls
      t.boolean :requires_confirmation
      t.boolean :is_active

      t.timestamps
    end
  end
end
