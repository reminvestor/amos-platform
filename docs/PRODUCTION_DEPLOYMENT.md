# Production Deployment Guide - OAuth Configuration System

## Overview
This deployment adds a new OAuth configuration system that stores all OAuth credentials in the database instead of ENV variables.

## What's Being Deployed

### New Features
- ✅ **OAuth Configuration Management** - Admin UI to configure OAuth apps
- ✅ **Platform-wide OAuth credentials** - No more per-entity configs
- ✅ **Unified OAuth flow** - All OAuth integrations use `oauth2` type
- ✅ **Database-stored credentials** - No ENV variables needed

### Database Changes
The following migrations will run automatically:
1. `20251024033552_create_oauth_configurations.rb` - Creates `oauth_configurations` table
2. `20251024044000_add_auth_urls_to_oauth_configurations.rb` - Adds `authorize_url` and `token_url` columns
3. `20251024044008_remove_entity_from_oauth_configurations.rb` - Removes entity association (platform-wide configs)
4. `20251024161418_rename_oauth2_custom_to_oauth2.rb` - Changes `oauth2_custom` → `oauth2`

## Deployment Steps

### 1. Standard Deployment
```bash
git push origin main
# CodePipeline will automatically:
# - Build new Docker image
# - Run migrations
# - Deploy to ECS
```

### 2. Post-Deployment Tasks

#### A. Configure OAuth Apps (Required for OAuth Integrations)

After deployment, you'll need to configure OAuth credentials for any OAuth integrations:

1. **Go to Admin Panel**: `https://app.agentmarketing.com/admin`
2. **Navigate to Integrations**: Click "Integrations" in sidebar
3. **Configure each OAuth integration**:

**QuickBooks** (if already configured):
- Click "OAuth Config" button
- Should already have configuration
- Verify credentials are correct

**Gmail, Google Drive, Google Sheets, HubSpot** (need configuration):
- Click "OAuth Config" button on each
- Fill in:
  - Authorize URL (pre-filled)
  - Token URL (pre-filled)
  - Client ID (from OAuth app)
  - Client Secret (from OAuth app)
  - Redirect URI (pre-filled)
  - Scopes (pre-filled)
- Click "Create OAuth Configuration"

#### B. No Rake Task Needed!

The migrations handle everything:
- ✅ Creates `oauth_configurations` table
- ✅ Updates integration `auth_type` values
- ✅ Removes entity_id from oauth_configurations
- ✅ Adds unique constraint on integration_id

## What Happens to Existing Integrations

### OAuth Integrations (Gmail, HubSpot, Google Drive, etc.)
- **Before**: Would look for ENV variables (didn't exist)
- **After**: Look for database OAuth configurations
- **Action Required**: Configure OAuth credentials in admin panel

### Stripe (Basic Auth)
- **Status**: ✅ No changes needed
- **Still works**: Users enter API key directly
- **No admin configuration needed**

### QuickBooks (OAuth)
- **Status**: ✅ Already configured
- **Should continue working**: Existing OAuth config preserved

## Rollback Plan

If something goes wrong, you can rollback:

```bash
# Rollback the deployment
aws ecs update-service --cluster agent-marketing-cluster \
  --service agent-marketing-service \
  --task-definition agent-marketing:PREVIOUS_VERSION

# Rollback migrations (if needed)
rails db:rollback STEP=4
```

## Verification Steps

After deployment, verify:

1. **Check migrations ran**:
```bash
# SSH into ECS task via Session Manager
rails runner "puts OauthConfiguration.table_exists? ? '✅ Table exists' : '❌ Table missing'"
```

2. **Check integration types**:
```bash
rails runner "
Integration.where(auth_type: 'oauth2').each do |i|
  puts \"#{i.name} - oauth2\"
end
"
```

3. **Test OAuth flow**:
- Go to app as regular user
- Try connecting an OAuth integration
- Should redirect to OAuth provider (if configured)
- Or show "not configured" message (if not configured yet)

## ENV Variables to Remove (Optional Cleanup)

These ENV variables are no longer needed and can be removed:
- `QUICKBOOKS_CLIENT_ID`
- `QUICKBOOKS_CLIENT_SECRET`
- `HUBSPOT_CLIENT_ID`
- `HUBSPOT_CLIENT_SECRET`
- Any other OAuth-related ENV variables

**Note**: Keep Stripe ENV variables if you have them, as Stripe uses `basic_auth`, not OAuth.

## Support

If you encounter issues:

1. **Check ECS logs**:
```bash
aws logs tail /ecs/agent-marketing --follow
```

2. **Check migration status**:
```bash
rails db:migrate:status
```

3. **Check for errors in admin panel**:
- Navigate to `/admin/integrations`
- Look for any error messages

## Summary

✅ **Automated**: Migrations run automatically
✅ **Safe**: Existing Stripe integration unaffected
✅ **Action Required**: Configure OAuth apps in admin panel post-deployment
✅ **Rollback Ready**: Can revert if issues occur

The deployment should be smooth. The main post-deployment task is configuring OAuth credentials for any OAuth integrations you want to use.




