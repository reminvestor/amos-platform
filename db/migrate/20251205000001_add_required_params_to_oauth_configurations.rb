# frozen_string_literal: true

class AddRequiredParamsToOauthConfigurations < ActiveRecord::Migration[8.0]
  def change
    add_column :oauth_configurations, :required_params, :jsonb, default: [], null: false
    add_index :oauth_configurations, :required_params, using: :gin
    
    # Add a comment explaining the difference:
    # - required_params: Parameters to collect BEFORE OAuth starts (e.g., shop_domain for Shopify)
    # - callback_params: Parameters to capture FROM the OAuth callback URL (e.g., realmId for QuickBooks)
  end
end

