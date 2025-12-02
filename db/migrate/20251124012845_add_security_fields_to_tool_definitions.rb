class AddSecurityFieldsToToolDefinitions < ActiveRecord::Migration[8.0]
  def change
    add_column :tool_definitions, :security_rating, :string
    add_column :tool_definitions, :security_reason, :text
  end
end
