class AddCreationLimitsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :agents_limit, :integer, default: 5
    add_column :users, :tools_limit, :integer, default: 5
    add_column :users, :integrations_limit, :integer, default: 5
  end
end
