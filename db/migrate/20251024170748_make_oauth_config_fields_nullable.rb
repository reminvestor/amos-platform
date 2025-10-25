class MakeOauthConfigFieldsNullable < ActiveRecord::Migration[8.0]
  def change
    # Make OAuth-specific fields nullable since non-OAuth integrations
    # won't use client_id, client_secret, redirect_uri, or scopes
    change_column_null :oauth_configurations, :client_id, true
    change_column_null :oauth_configurations, :client_secret, true
    change_column_null :oauth_configurations, :redirect_uri, true
  end
end
