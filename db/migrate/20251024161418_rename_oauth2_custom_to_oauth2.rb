class RenameOauth2CustomToOauth2 < ActiveRecord::Migration[8.0]
  def up
    # Update all oauth2_custom integrations to oauth2
    execute "UPDATE integrations SET auth_type = 3 WHERE auth_type = 4"
    
    # oauth2_custom (4) becomes available for future user-managed OAuth apps
    # oauth2 (3) is now the standard for all OAuth integrations
  end

  def down
    # Revert oauth2 back to oauth2_custom
    execute "UPDATE integrations SET auth_type = 4 WHERE auth_type = 3"
  end
end
