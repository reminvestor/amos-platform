class AddAuthUrlsToOauthConfigurations < ActiveRecord::Migration[8.0]
  def change
    add_column :oauth_configurations, :authorize_url, :string
    add_column :oauth_configurations, :token_url, :string
  end
end
