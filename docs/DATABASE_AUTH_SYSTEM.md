# Database-Driven Authentication System

## Overview

**All integration authentication is now 100% database-driven!** 

No more hardcoded auth configs in seed files. Everything is managed through the admin UI with a flexible, dynamic system that adapts to any authentication pattern.

## Architecture

### Database Tables

#### `oauth_configurations`
Stores the main auth configuration for each integration (one per integration).

**Fields:**
- `integration_id` - Foreign key to integration (unique)
- `client_id` - OAuth client ID (nullable for non-OAuth)
- `client_secret` - OAuth client secret (nullable for non-OAuth)
- `redirect_uri` - OAuth redirect URI (nullable for non-OAuth)
- `scopes` - OAuth scopes as comma-separated string
- `authorize_url` - OAuth authorization endpoint
- `token_url` - OAuth token endpoint
- `status` - Enum: active, inactive, revoked
- `credentials` - JSONB for additional OAuth data
- `metadata` - JSONB for other config

#### `auth_configs`
Stores individual authentication parameters (multiple per integration).

**Fields:**
- `oauth_configuration_id` - Foreign key to oauth_configuration
- `auth_key` - The parameter name (e.g., "api_key", "Authorization")
- `auth_value` - The value template (e.g., "Bearer {token}", "{api_key}")
- `auth_placement` - Enum: header, query, url
- `position` - Integer for ordering

### Models

#### `OauthConfiguration`
```ruby
belongs_to :integration
has_many :auth_configs, dependent: :destroy
accepts_nested_attributes_for :auth_configs, allow_destroy: true

# Validations
validates :integration_id, uniqueness: true
# OAuth-specific validations only apply if integration.oauth?
validates :client_id, :client_secret, :redirect_uri, presence: true, if: -> { integration&.oauth? }

# Enum
enum :status, { active: 0, inactive: 1, revoked: 2 }
```

#### `AuthConfig`
```ruby
belongs_to :oauth_configuration

# Enum
enum :auth_placement, { header: 'header', query: 'query', url: 'url' }

# Validations
validates :auth_key, :auth_placement, presence: true
```

#### `Integration`
```ruby
# Get auth params from database
def current_auth_params
  oauth_config = OauthConfiguration.find_by(integration: self)
  return [] unless oauth_config
  
  oauth_config.auth_configs.order(:position).map do |ac|
    { key: ac.auth_key, value: ac.auth_value, placement: ac.auth_placement }
  end
end
```

## Admin UI

### Integrations List (`/admin/integrations`)
- Every integration has an "Auth Config" button
- Works for all auth types: OAuth2, API Key, Bearer Token, Basic Auth, Custom

### Integration Show Page (`/admin/integrations/:id`)
Shows current auth configuration:
- **OAuth integrations**: Client ID (masked), Redirect URI, Status
- **Non-OAuth integrations**: List of auth params with placement badges

### Auth Configuration Form (`/admin/integrations/:id/oauth_configurations/new`)

#### For OAuth Integrations
Shows fields:
- Authorize URL
- Token URL
- Client ID
- Client Secret
- Redirect URI (pre-filled)
- Scopes

#### For Non-OAuth Integrations
Dynamic form with:
- **Key/Field Name** - The parameter name
- **Value Template** - The value with placeholders like `{api_key}`, `Bearer {token}`
- **Placement** - Header, Query Param, or URL Param
- **Add Another Parameter** button for multiple fields
- **Delete** buttons (trash icons) for each parameter

**Common Examples Shown:**
- API Key in Header: `X-API-Key` / `{api_key}` / `header`
- Bearer Token: `Authorization` / `Bearer {token}` / `header`
- Basic Auth: `Authorization` / `Basic {api_key}` / `header`
- Query Parameter: `api_key` / `{api_key}` / `query`

## User-Facing Forms

### Connection Forms
Both the advanced mode (`/integrations/connect/:slug`) and Scout canvas connection form now:

1. **Read from database** - No hardcoded fields!
2. **Dynamically render** - Shows exactly what admin configured
3. **Display helper text** - Shows how the value will be sent
4. **Handle OAuth** - Redirects to OAuth flow automatically

**Example for Stripe:**
```
Connection Name: [Stripe - user@example.com]
Api Key: [password field]
  ℹ️ Will be sent as: Basic [your value] via Header
```

**Example for Shopify:**
```
Connection Name: [Shopify - user@example.com]
Api Key: [password field]
  ℹ️ Sent via Header
```

**If no auth config:**
Shows warning message:
> ⚠️ **Authentication not configured**  
> This integration hasn't been set up yet. Please contact an administrator.

## How It Works

### 1. Admin Configures Integration

Admin goes to `/admin/integrations/:id` → "Auth Config" and sets up:

**For Stripe (Basic Auth):**
- Key: `api_key`
- Value: `Basic {api_key}`
- Placement: `header`

**For Shopify (API Key):**
- Key: `api_key`
- Value: `{api_key}`
- Placement: `header`

**For Slack (Custom):**
- Key: `webhook_url`
- Value: `{webhook_url}`
- Placement: `url`

### 2. User Connects

User clicks "Connect" → Form reads `auth_configs` from database → Dynamically renders input fields.

### 3. User Submits Credentials

Form submits to `/integrations/connect/:slug`:
```json
{
  "connection_name": "Stripe - user@example.com",
  "api_key": "sk_test_abc123..."
}
```

### 4. Credentials Stored

`IntegrationsController#build_credentials_from_params`:
```ruby
def build_credentials_from_params
  oauth_config = OauthConfiguration.includes(:auth_configs).find_by(integration: @integration)
  
  if oauth_config && oauth_config.auth_configs.any?
    # Build from dynamic auth_configs
    credentials = {}
    oauth_config.auth_configs.each do |auth_config|
      param_value = params[auth_config.auth_key]
      credentials[auth_config.auth_key] = param_value if param_value.present?
    end
    return credentials
  end
  
  {}
end
```

Stores in `integration_credentials` table as JSON:
```json
{
  "api_key": "sk_test_abc123..."
}
```

### 5. API Calls Use Configuration

When making API calls, the system:
1. Reads `auth_configs` for the integration
2. Fetches credentials from `integration_credentials`
3. Applies the `auth_value` template
4. Places the value according to `auth_placement`

**Example for Stripe:**
- Template: `Basic {api_key}`
- Credential: `sk_test_abc123...`
- Result: `Authorization: Basic sk_test_abc123...`

## Migration from Seeds

### Automatic Migration Task

```bash
rails integrations:migrate_auth_configs
```

This task:
1. Finds all integrations without `oauth_configurations`
2. Creates `OauthConfiguration` for each
3. Creates appropriate `AuthConfig` records based on `auth_type`
4. Handles Stripe, Shopify, Slack, and other common patterns

### Manual Configuration (for OAuth)

OAuth integrations (QuickBooks, HubSpot, Gmail, etc.) require manual setup:

1. Go to integration provider (e.g., QuickBooks Developer)
2. Create OAuth app
3. Copy Client ID and Client Secret
4. Register the redirect URI (shown in admin form)
5. Enter credentials in admin panel

## Benefits

✅ **No code changes needed** - Update auth configs from UI  
✅ **Flexible** - Supports any auth pattern  
✅ **Multiple parameters** - Add as many fields as needed  
✅ **Dynamic forms** - User sees exactly what you configured  
✅ **Consistent** - Same system for all auth types  
✅ **Maintainable** - No more hunting through seed files  
✅ **Scalable** - Add 100s of integrations easily  

## Auth Types Supported

### 1. OAuth2 (`oauth2`)
Full OAuth 2.0 flow with:
- Client ID & Secret
- Redirect URI
- Authorization URL
- Token URL
- Scopes
- Access/Refresh tokens

**Examples:** QuickBooks, HubSpot, Gmail, Google Drive

### 2. API Key (`api_key`)
Simple API key in header or query.

**Example Config:**
```
Key: X-API-Key
Value: {api_key}
Placement: header
```

### 3. Bearer Token (`bearer_token`)
Token with "Bearer" prefix.

**Example Config:**
```
Key: Authorization
Value: Bearer {bearer_token}
Placement: header
```

### 4. Basic Auth (`basic_auth`)
HTTP Basic authentication.

**Example Config (Stripe):**
```
Key: api_key
Value: Basic {api_key}
Placement: header
```

**Example Config (Standard):**
```
Key: Authorization
Value: Basic {username}:{password}
Placement: header
```

### 5. Custom (`custom`)
For special cases like webhooks, multi-param auth, etc.

**Example Config (Slack webhook):**
```
Key: webhook_url
Value: {webhook_url}
Placement: url
```

**Example Config (Multi-param like Shopify):**
```
1. Key: X-Shopify-Access-Token | Value: {token} | Placement: header
2. Key: shop | Value: {shop_domain} | Placement: url
```

## Adding New Integrations

### 1. Create Integration Record
```ruby
Integration.create!(
  name: "My Service",
  slug: "my_service",
  auth_type: "api_key",  # or bearer_token, basic_auth, oauth2, custom
  api_base_url: "https://api.myservice.com",
  # ... other fields
)
```

### 2. Configure Authentication (Admin UI)
- Go to Admin → Integrations → My Service
- Click "Auth Config"
- Add auth parameters:
  - For API key: `X-API-Key` / `{api_key}` / `header`
  - For Bearer: `Authorization` / `Bearer {token}` / `header`
  - For Basic: `api_key` / `Basic {api_key}` / `header`
  - For OAuth: Fill in OAuth credentials

### 3. Test Connection
- Go to Scout → Integrations
- Click "Connect" on My Service
- Form automatically shows your configured fields!

## Production Deployment

See [`PRODUCTION_AUTH_MIGRATION.md`](./PRODUCTION_AUTH_MIGRATION.md) for detailed deployment steps.

**Quick checklist:**
1. ✅ Backup database
2. ✅ Deploy code
3. ✅ Run migrations: `rails db:migrate`
4. ✅ Run migration task: `rails integrations:migrate_auth_configs`
5. ✅ Configure OAuth integrations in admin UI
6. ✅ Test connections

## Troubleshooting

### Connection form shows "Authentication not configured"
**Solution:** Admin needs to configure the integration:
1. Go to Admin → Integrations → [Integration]
2. Click "Auth Config"
3. Set up authentication parameters

### OAuth integration shows "OAuth has not been configured yet"
**Solution:** Admin needs to add OAuth credentials:
1. Create OAuth app with provider
2. Go to Admin → Integrations → [Integration]
3. Click "Auth Config"
4. Enter Client ID, Client Secret, etc.

### Existing connections stopped working
**Solution:** Re-run migration task:
```bash
rails integrations:migrate_auth_configs
```

This ensures all integrations have database configs.

## Files Modified

### New Files
- `app/models/oauth_configuration.rb`
- `app/models/auth_config.rb`
- `app/controllers/admin/oauth_configurations_controller.rb`
- `app/views/admin/oauth_configurations/` (all views)
- `lib/tasks/migrate_auth_configs.rake`
- `docs/DATABASE_AUTH_SYSTEM.md` (this file)
- `docs/PRODUCTION_AUTH_MIGRATION.md`

### Modified Files
- `app/models/integration.rb` - Added `current_auth_params` method
- `app/controllers/integrations_controller.rb` - Dynamic credential building
- `app/controllers/scout_controller.rb` - Load auth_configs for canvas
- `app/views/integrations/connect.html.erb` - Dynamic form rendering
- `app/views/scout/canvas/_integration_connect.html.erb` - Dynamic form rendering
- `app/views/admin/integrations/show.html.erb` - Show auth config
- `app/views/admin/integrations/index.html.erb` - Auth Config button
- `config/routes.rb` - Nested oauth_configurations routes

### Removed
- All hardcoded auth logic from views
- Seed file dependencies for auth configuration
- Legacy `parse_legacy_auth_config` method (cleaned up)

## Future Enhancements

- [ ] **User-managed OAuth apps** - Let users register their own OAuth apps
- [ ] **OAuth token refresh** - Automatic token refresh handling
- [ ] **Credential encryption** - Encrypt sensitive fields at rest
- [ ] **Multi-environment configs** - Different configs for dev/staging/prod
- [ ] **API testing in admin** - Test API calls directly from admin UI
- [ ] **Audit logging** - Track who changed auth configs
- [ ] **Credential rotation** - Schedule credential updates

---

**🎉 System is now 100% database-driven and ready for production!**




