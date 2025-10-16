class AddOptOutFieldsToContacts < ActiveRecord::Migration[8.0]
  def change
    add_column :contacts, :opted_out, :boolean, default: false
    add_column :contacts, :opted_out_at, :datetime

    # Add an index to speed up queries
    add_index :contacts, :opted_out
  end
end
