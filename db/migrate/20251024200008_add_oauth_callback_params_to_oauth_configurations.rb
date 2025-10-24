class AddOauthCallbackParamsToOauthConfigurations < ActiveRecord::Migration[8.0]
  def change
    add_column :oauth_configurations, :callback_params, :jsonb, default: [], null: false
    add_column :oauth_configurations, :test_endpoint, :text
    
    # Add index for callback_params jsonb column for efficient querying
    add_index :oauth_configurations, :callback_params, using: :gin
  end
end
