class AddMetadataToContacts < ActiveRecord::Migration[8.0]
  def change
    add_column :contacts, :metadata, :jsonb
  end
end
