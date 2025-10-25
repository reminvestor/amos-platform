# Adding New Integrations to Amos Labs

This guide explains how to add new OAuth integrations without touching code or ENV variables.

## Overview

All OAuth integrations use `oauth2`, which means credentials are stored in the database and configured through the admin panel. Additionally, admins can configure auth parameters for ALL integration types (API key, Bearer token, Basic auth, etc.) through the UI.

## Steps to Add a New OAuth Integration

### 1. Create the Integration Record

Go to `/admin/integrations` and click "Add Integration" or use the Rails console:

```ruby
rails console

Integration.create!(
  name: 'Google Sheets',
  slug: 'google_sheets',
  category: 'productivity',  # payment, ecommerce, crm, communication, productivity, marketing, analytics, custom
  auth_type: 'oauth2',
  api_base_url: 'https://sheets.googleapis.com/v4',
  allowed_hosts: ['sheets.googleapis.com'],
  documentation_url: 'https://developers.google.com/sheets/api',
  icon_url: 'https://www.gstatic.com/images/branding/product/1x/sheets_48dp.png',
  description: 'Create and manage spreadsheets',
  is_active: true,
  is_verified: true,
  auth_config: {
    authorize_url: 'https://accounts.google.com/o/oauth2/v2/auth',
    token_url: 'https://oauth2.googleapis.com/token',
    scopes: ['https://www.googleapis.com/auth/spreadsheets'],
    access_type: 'offline'
  }
)
```

### 2. Configure OAuth Credentials

1. Register an OAuth app with the provider (Google, QuickBooks, etc.)
2. Get your `client_id` and `client_secret`
3. Set the redirect URI to: `https://app.agentmarketing.com/integrations/callback/{slug}`
   - Example: `https://app.agentmarketing.com/integrations/callback/google_sheets`

4. Go to `/admin/integrations`
5. Find your integration and click "OAuth Config"
6. Fill in the form:
   - **Authorize URL**: The OAuth authorization endpoint (pre-filled)
   - **Token URL**: The OAuth token exchange endpoint (pre-filled)
   - **Client ID**: From your OAuth app
   - **Client Secret**: From your OAuth app
   - **Redirect URI**: Pre-filled, must match what you registered
   - **Scopes**: Comma-separated list of required scopes
   - **Status**: Active

7. Click "Create OAuth Configuration"

### 3. Test the Integration

1. Go to the main app as a regular user
2. Navigate to integrations
3. Click "Connect" on your new integration
4. You should be redirected to the provider's authorization page
5. Authorize the app
6. You should be redirected back with a success message

## Available Auth Types

- **`api_key`**: Simple API key in header/query - Configurable in admin UI
- **`bearer_token`**: Bearer token authentication - Configurable in admin UI
- **`basic_auth`**: Username/password (like Stripe) - Configurable in admin UI
- **`oauth2`**: OAuth 2.0 with database-stored credentials ✅ **Use this for OAuth**
- **`custom`**: Reserved for user-managed OAuth apps (future feature)

## Common OAuth Providers

### Google APIs
```ruby
authorize_url: 'https://accounts.google.com/o/oauth2/v2/auth'
token_url: 'https://oauth2.googleapis.com/token'
access_type: 'offline'
```

### Microsoft/Azure
```ruby
authorize_url: 'https://login.microsoftonline.com/common/oauth2/v2.0/authorize'
token_url: 'https://login.microsoftonline.com/common/oauth2/v2.0/token'
```

### QuickBooks
```ruby
authorize_url: 'https://appcenter.intuit.com/connect/oauth2'
token_url: 'https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer'
use_basic_auth: true
```

### Salesforce
```ruby
authorize_url: 'https://login.salesforce.com/services/oauth2/authorize'
token_url: 'https://login.salesforce.com/services/oauth2/token'
```

## Troubleshooting

### "OAuth configuration not found"
- Make sure you created the OAuth configuration in `/admin/integrations/{id}/oauth_configurations/new`

### "Invalid client_id"
- Check that the client_id in the admin panel matches your OAuth app
- Verify the OAuth app is active in the provider's dashboard

### "Redirect URI mismatch"
- The redirect URI must exactly match what's registered in your OAuth app
- Format: `https://app.agentmarketing.com/integrations/callback/{slug}`

### "Invalid scopes"
- Check the provider's documentation for required scope format
- Google uses URLs: `https://www.googleapis.com/auth/spreadsheets`
- Microsoft uses short names: `Files.ReadWrite.All`

## Need Help?

- Check the provider's OAuth documentation
- Look at existing integrations in `/admin/integrations` for examples
- Contact the dev team on Slack

## Benefits of This Approach

✅ **No code changes needed** - Add integrations through admin UI
✅ **No ENV variables** - All credentials in database
✅ **Team can add integrations** - Anyone with admin access
✅ **Easy to update** - Change credentials without deployment
✅ **Scalable** - Add 100s of integrations easily

