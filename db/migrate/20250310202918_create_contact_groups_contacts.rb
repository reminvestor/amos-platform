class CreateContactGroupsContacts < ActiveRecord::Migration[8.0]
  def change
    create_table :contact_groups_contacts do |t|
      t.references :contact, null: false, foreign_key: true
      t.references :contact_group, null: false, foreign_key: true

      t.timestamps
    end

    add_index :contact_groups_contacts, [ :contact_id, :contact_group_id ], unique: true, name: 'index_contacts_groups_uniqueness'
  end
end
