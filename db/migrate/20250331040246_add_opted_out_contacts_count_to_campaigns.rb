class AddOptedOutContactsCountToCampaigns < ActiveRecord::Migration[8.0]
  def change
    add_column :campaigns, :opted_out_contacts_count, :integer, default: 0, null: false
  end
end
