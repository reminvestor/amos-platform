class RemoveEntityFromOauthConfigurations < ActiveRecord::Migration[8.0]
  def change
    remove_index :oauth_configurations, name: 'index_oauth_configs_on_entity_and_integration', if_exists: true
    remove_reference :oauth_configurations, :entity, foreign_key: true
    
    # Remove non-unique index and add unique index (platform-wide config)
    remove_index :oauth_configurations, :integration_id, if_exists: true
    add_index :oauth_configurations, :integration_id, unique: true
  end
end
