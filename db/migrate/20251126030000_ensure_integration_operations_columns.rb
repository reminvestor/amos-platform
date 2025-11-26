class EnsureIntegrationOperationsColumns < ActiveRecord::Migration[8.0]
  def up
    # Add is_enabled if it doesn't exist
    unless column_exists?(:integration_operations, :is_enabled)
      add_column :integration_operations, :is_enabled, :boolean, default: true, null: false
      add_index :integration_operations, :is_enabled
    end

    # Ensure all existing operations are enabled
    execute "UPDATE integration_operations SET is_enabled = true WHERE is_enabled IS NULL"
  end

  def down
    # We don't remove columns on rollback as they may have been there before
  end
end
