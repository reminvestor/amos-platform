class CreateSystemSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :system_settings do |t|
      t.string :key
      t.text :value
      t.text :encrypted_value
      t.string :category
      t.text :description
      t.boolean :is_sensitive
      t.integer :last_updated_by

      t.timestamps
    end
    add_index :system_settings, :key, unique: true
  end
end
