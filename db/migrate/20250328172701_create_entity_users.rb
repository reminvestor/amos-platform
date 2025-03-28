class CreateEntityUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :entity_users do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :role, default: 'member'

      t.timestamps
    end
    
    add_index :entity_users, [:entity_id, :user_id], unique: true
  end
end
