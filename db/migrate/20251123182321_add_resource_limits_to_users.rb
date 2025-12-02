class AddResourceLimitsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :agent_limit, :integer, default: 5
    add_column :users, :tool_limit, :integer, default: 5
    add_column :users, :integration_limit, :integer, default: 5
  end
end
