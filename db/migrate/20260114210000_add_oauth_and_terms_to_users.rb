# frozen_string_literal: true

class AddOauthAndTermsToUsers < ActiveRecord::Migration[8.0]
  def change
    # OAuth fields for Google SSO
    add_column :users, :provider, :string
    add_column :users, :uid, :string
    add_column :users, :avatar_url, :string
    
    # Legal agreement fields
    add_column :users, :terms_accepted_at, :datetime
    add_column :users, :terms_version, :string
    add_column :users, :privacy_accepted_at, :datetime
    add_column :users, :privacy_version, :string
    
    # Index for OAuth lookups
    add_index :users, [:provider, :uid], unique: true, where: "provider IS NOT NULL"
  end
end

