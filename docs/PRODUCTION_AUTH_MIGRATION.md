# Production Auth Configuration Migration Guide

## Overview

This guide walks through migrating all integration authentication configurations from seed-based hardcoded values to database-driven records.

## What Changed

**Before:**
- Auth configs were hardcoded in `db/seeds/integrations.rb`
- Required code changes to update auth fields
- Inflexible and hard to maintain

**After:**
- Auth configs stored in `oauth_configurations` and `auth_configs` tables
- Fully manageable from admin UI
- Dynamic forms that adapt to database configuration
- Supports OAuth2, API Key, Bearer Token, Basic Auth, and Custom auth types

## Database Changes

### New Tables
1. **`oauth_configurations`** - Stores auth configuration for each integration
2. **`auth_configs`** - Stores individual auth parameters (key, value, placement)

### Migrations to Run
```bash
rails db:migrate
```

**Migrations included:**
- `20251024033552_create_oauth_configurations.rb` - Creates oauth_configurations table
- `20251024044000_add_auth_urls_to_oauth_configurations.rb` - Adds authorize_url, token_url
- `20251024044008_remove_entity_from_oauth_configurations.rb` - Makes configs platform-wide
- `20251024161418_rename_oauth2_custom_to_oauth2.rb` - Consolidates OAuth types
- `20251024163938_create_auth_configs.rb` - Creates flexible auth_configs table
- `20251024170748_make_oauth_config_fields_nullable.rb` - Makes OAuth fields optional for non-OAuth integrations

## Production Deployment Steps

### 1. Backup Database
```bash
# Create a backup before making changes
pg_dump your_production_db > backup_before_auth_migration_$(date +%Y%m%d).sql
```

### 2. Deploy Code
```bash
git pull origin main
bundle install
```

### 3. Run Migrations
```bash
RAILS_ENV=production rails db:migrate
```

### 4. Migrate Existing Configurations
```bash
# This will convert all seed-based configs to database records
RAILS_ENV=production rails integrations:migrate_auth_configs
```

**Expected Output:**
```
🔄 Migrating auth configurations to database...

📦 Processing Stripe (basic_auth)...
  ✅ Created: api_key (Basic auth header)

📦 Processing Shopify (api_key)...
  ✅ Created: api_key (header: X-API-Key)

📦 Processing Slack (custom)...
  ✅ Created: webhook_url (URL)

✅ Migration complete!

📊 Summary:
  Total integrations: 8
  With auth configs: 4
  Auth config fields: 3
```

### 5. Verify OAuth Integrations
For OAuth integrations (QuickBooks, HubSpot, Gmail, etc.), you'll need to configure them in the admin panel:

1. Go to Admin → Integrations
2. Click "Auth Config" for each OAuth integration
3. Fill in:
   - **Client ID** (from OAuth provider)
   - **Client Secret** (from OAuth provider)
   - **Redirect URI** (pre-filled, register this with provider)
   - **Authorize URL** (pre-filled from seeds)
   - **Token URL** (pre-filled from seeds)
   - **Scopes** (pre-filled from seeds)
4. Save configuration

### 6. Test Connections

#### Test Non-OAuth Integration (e.g., Stripe)
1. Go to Scout → Integrations
2. Click "Connect" on Stripe
3. You should see:
   - **Connection Name** field
   - **Api Key** field (dynamically from database)
   - Helper text: "Will be sent as: `Basic [your value]` via Header"
4. Enter test API key
5. Verify connection succeeds

#### Test OAuth Integration (e.g., QuickBooks)
1. Ensure Auth Config is set up in admin panel
2. Go to Scout → Integrations
3. Click "Connect" on QuickBooks
4. Should redirect to QuickBooks OAuth screen
5. Authorize and verify callback succeeds

### 7. Update Existing Connections (if needed)

If you have existing connections and they're not working:

```bash
# Re-test all existing connections
RAILS_ENV=production rails runner "
  Connection.includes(:integration).find_each do |conn|
    result = conn.test_connection!
    puts \"#{conn.integration.name}: #{result[:success] ? '✅' : '❌ ' + result[:error]}\"
  end
"
```

## Admin UI Changes

### Integration List (`/admin/integrations`)
- All integrations now have "Auth Config" button
- Works for OAuth and non-OAuth integrations

### Integration Show Page (`/admin/integrations/:id`)
- Shows current auth configuration
- Displays auth parameters for non-OAuth integrations
- "Configure Authentication" or "Edit Auth Config" button

### Auth Config Form
- **OAuth Integrations**: Shows Client ID, Secret, URLs, Scopes
- **Non-OAuth Integrations**: Dynamic form with key/value/placement fields
- Supports multiple auth parameters per integration
- Add/remove parameters on the fly

## User-Facing Changes

### Advanced Mode (`/integrations/connect/:slug`)
- Dynamically renders fields from database
- Shows field name, placement, and format
- No more hardcoded forms

### Scout Canvas Mode
- Connect canvas now reads from database
- Shows same dynamic fields as advanced mode
- Consistent experience across all interfaces

## Rolling Back (if needed)

If you need to rollback the auth configurations:

```bash
# This will delete all non-OAuth auth configs
RAILS_ENV=production rails integrations:rollback_auth_configs
```

⚠️ **Warning:** This will delete database auth configs. You'll fallback to seed-based configs (if they still exist in your code).

## Common Issues & Solutions

### Issue: "No authentication configuration yet"
**Solution:** Run the migration task:
```bash
rails integrations:migrate_auth_configs
```

### Issue: OAuth integration shows "OAuth has not been configured yet"
**Solution:** Go to Admin → Integrations → [Integration] → Auth Config and fill in OAuth credentials.

### Issue: Connection form shows old fields
**Solution:**
1. Clear Rails cache: `rails cache:clear`
2. Restart server
3. Hard refresh browser (Cmd+Shift+R / Ctrl+F5)

### Issue: Existing Stripe connections stopped working
**Solution:**
1. Verify Stripe has auth_config in database:
   ```bash
   rails runner "
     stripe = Integration.find_by(slug: 'stripe')
     puts stripe.current_auth_params.inspect
   "
   ```
2. Should show: `[{:key=>"api_key", :value=>"Basic {api_key}", :placement=>"header"}]`
3. If empty, run migration task again

## Verification Checklist

- [ ] All migrations completed successfully
- [ ] Migration task ran without errors
- [ ] Non-OAuth integrations show auth configs in admin panel
- [ ] OAuth integrations have credentials configured in admin panel
- [ ] Stripe connection form shows single "Api Key" field
- [ ] Scout canvas connection form shows database-driven fields
- [ ] Advanced mode connection form shows database-driven fields
- [ ] Test connections work for both OAuth and non-OAuth integrations
- [ ] Existing connections still function

## Support

If you encounter issues:
1. Check logs: `tail -f log/production.log`
2. Verify database records exist: `rails console` → `OauthConfiguration.count`, `AuthConfig.count`
3. Re-run migration task if needed
4. Contact dev team with error messages

## Files Changed

### Models
- `app/models/oauth_configuration.rb` (new)
- `app/models/auth_config.rb` (new)
- `app/models/integration.rb` (updated)
- `app/models/entity.rb` (updated)

### Controllers
- `app/controllers/admin/oauth_configurations_controller.rb` (new)
- `app/controllers/integrations_controller.rb` (updated)
- `app/controllers/scout_controller.rb` (updated)

### Views
- `app/views/admin/oauth_configurations/` (new)
- `app/views/admin/integrations/show.html.erb` (updated)
- `app/views/integrations/connect.html.erb` (updated)
- `app/views/scout/canvas/_integration_connect.html.erb` (updated)

### Routes
- `config/routes.rb` (updated - nested oauth_configurations)

### Tasks
- `lib/tasks/migrate_auth_configs.rake` (new)

## Timeline

**Estimated deployment time:** 10-15 minutes

1. Backup database: 2 min
2. Deploy code: 2 min
3. Run migrations: 1 min
4. Run migration task: 1 min
5. Configure OAuth integrations: 5-10 min (per integration)
6. Test connections: 2 min

Total: ~15 minutes + OAuth configuration time


