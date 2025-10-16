class AddIsEnabledToIntegrationOperations < ActiveRecord::Migration[8.0]
  def change
    add_column :integration_operations, :is_enabled, :boolean, default: true, null: false
    
    # Backfill existing records
    reversible do |dir|
      dir.up do
        IntegrationOperation.update_all(is_enabled: true)
      end
    end
    
    add_index :integration_operations, :is_enabled
  end
end
