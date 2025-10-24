class UpdateQuickBooksToOAuth2Custom < ActiveRecord::Migration[8.0]
  def up
    # Update QuickBooks integration to use oauth2_custom instead of oauth2
    quickbooks = Integration.find_by(slug: 'quickbooks')
    if quickbooks
      quickbooks.update!(
        auth_type: 'oauth2_custom',
        auth_config: {
          requires_user_app: true,
          auth_provider: 'quickbooks',
          setup_instructions: <<~INSTRUCTIONS
            1. Go to QuickBooks Developer Dashboard
            2. Create a new app or use existing app
            3. Set redirect URI to: https://app.agentmarketing.com/integrations/callback/quickbooks
            4. Copy Client ID and Client Secret
            5. Configure OAuth app in the system
          INSTRUCTIONS
        }
      )
    end
  end

  def down
    # Revert QuickBooks integration back to oauth2
    quickbooks = Integration.find_by(slug: 'quickbooks')
    if quickbooks
      quickbooks.update!(
        auth_type: 'oauth2',
        auth_config: {
          authorize_url: 'https://appcenter.intuit.com/connect/oauth2',
          token_url: 'https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer',
          scopes: [ 'com.intuit.quickbooks.accounting' ],
          client_id: ENV['QUICKBOOKS_CLIENT_ID'],
          client_secret: ENV['QUICKBOOKS_CLIENT_SECRET'],
          redirect_uri: 'https://app.agentmarketing.com/integrations/callback/quickbooks',
          use_basic_auth: true
        }
      )
    end
  end
end
