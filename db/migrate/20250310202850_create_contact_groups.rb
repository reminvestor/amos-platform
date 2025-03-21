class CreateContactGroups < ActiveRecord::Migration[8.0]
  def change
    create_table :contact_groups do |t|
      t.string :name
      t.text :description
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
