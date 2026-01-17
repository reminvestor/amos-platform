class AddPublishStatusToToolDefinitions < ActiveRecord::Migration[8.0]
  def change
    add_column :tool_definitions, :publish_status, :string
  end
end
