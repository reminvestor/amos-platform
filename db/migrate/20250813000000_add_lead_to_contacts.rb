class AddLeadToContacts < ActiveRecord::Migration[8.0]
  def change
    add_column :contacts, :lead, :boolean, default: true, null: false
    add_index :contacts, :lead
  end
end
