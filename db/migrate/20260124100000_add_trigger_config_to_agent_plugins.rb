class AddTriggerConfigToAgentPlugins < ActiveRecord::Migration[8.0]
  def change
    # Add trigger configuration for user-created loadouts
    # This allows users to specify when their loadout should be auto-injected
    add_column :agent_plugins, :trigger_config, :jsonb, default: {}, null: false
    
    # Distinguish user-created loadouts from system loadouts
    add_column :agent_plugins, :is_user_created, :boolean, default: false, null: false
    
    # Track usage for optimization
    add_column :agent_plugins, :usage_count, :integer, default: 0, null: false
    
    # Index for efficient trigger lookups
    add_index :agent_plugins, :trigger_config, using: :gin
    add_index :agent_plugins, :is_user_created
    
    # Mark existing user-created loadouts
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE agent_plugins 
          SET is_user_created = true 
          WHERE user_id IS NOT NULL OR (created_by_type = 'User' AND created_by_id IS NOT NULL)
        SQL
      end
    end
  end
end
