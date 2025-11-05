# Production Deployment Checklist - Database-Driven Auth System

## ✅ Pre-Deployment Checklist

### 1. **Backup Database**
```bash
# On production server
pg_dump your_production_db > backup_auth_migration_$(date +%Y%m%d_%H%M%S).sql
```

### 2. **Check Current State**
```bash
# On production, check if migrations already exist
RAILS_ENV=production rails runner "
  puts 'Current state:'
  puts '  OauthConfiguration table exists: ' + ActiveRecord::Base.connection.table_exists?('oauth_configurations').to_s
  puts '  AuthConfig table exists: ' + ActiveRecord::Base.connection.table_exists?('auth_configs').to_s
  puts '  Integration has oauth_configurations association: ' + Integration.reflect_on_association(:oauth_configurations).present?.to_s
"
```

---

## 🚀 Deployment Steps

### Step 1: Deploy Code
```bash
git pull origin main
bundle install
```

### Step 2: Run Migrations (6 total)
```bash
RAILS_ENV=production rails db:migrate
```

**Migrations that will run:**
1. ✅ `20251024033552_create_oauth_configurations.rb` - Creates oauth_configurations table
2. ✅ `20251024044000_add_auth_urls_to_oauth_configurations.rb` - Adds authorize_url, token_url
3. ✅ `20251024044008_remove_entity_from_oauth_configurations.rb` - Makes configs platform-wide
4. ✅ `20251024161418_rename_oauth2_custom_to_oauth2.rb` - Consolidates OAuth types
5. ✅ `20251024163938_create_auth_configs.rb` - Creates auth_configs table
6. ✅ `20251024170748_make_oauth_config_fields_nullable.rb` - Makes OAuth fields optional

### Step 3: Migrate Existing Auth Configs
```bash
RAILS_ENV=production rails integrations:migrate_auth_configs
```

**Expected output:**
```
🔄 Migrating auth configurations to database...

📦 Processing Stripe (basic_auth)...
  ✅ Created: api_key (Bearer token header)

📦 Processing Shopify (api_key)...
  ✅ Created: api_key (header: X-API-Key)

📦 Processing Slack (custom)...
  ✅ Created: webhook_url (URL)

✅ Migration complete!

📊 Summary:
  Total integrations: X
  With auth configs: X
  Auth config fields: X
```

### Step 4: Fix Stripe Config (if needed)
```bash
# Update Stripe to use Bearer auth (correct for Stripe API)
RAILS_ENV=production rails runner "
  stripe = Integration.find_by(slug: 'stripe')
  if stripe
    oauth_config = OauthConfiguration.find_by(integration: stripe)
    if oauth_config
      auth_config = oauth_config.auth_configs.first
      auth_config.update!(
        auth_key: 'Authorization',
        auth_value: 'Bearer {api_key}',
        auth_placement: 'header'
      )
      puts '✅ Stripe auth config updated to Bearer token'
    end
  end
"
```

### Step 5: Restart Application
```bash
# Restart your app server (Puma, Passenger, etc.)
sudo systemctl restart your-app-service
# OR
passenger-config restart-app /path/to/app
```

---

## 🧪 Post-Deployment Verification

### 1. **Verify Migrations**
```bash
RAILS_ENV=production rails runner "
  puts '✅ Verifying database state...'
  puts ''
  puts 'Tables exist:'
  puts '  oauth_configurations: ' + ActiveRecord::Base.connection.table_exists?('oauth_configurations').to_s
  puts '  auth_configs: ' + ActiveRecord::Base.connection.table_exists?('auth_configs').to_s
  puts ''
  puts 'Counts:'
  puts '  OauthConfigurations: ' + OauthConfiguration.count.to_s
  puts '  AuthConfigs: ' + AuthConfig.count.to_s
  puts '  Integrations: ' + Integration.count.to_s
  puts ''
  puts 'Association check:'
  puts '  Integration has oauth_configurations: ' + Integration.reflect_on_association(:oauth_configurations).present?.to_s
"
```

### 2. **Verify Stripe Config**
```bash
RAILS_ENV=production rails runner "
  stripe = Integration.find_by(slug: 'stripe')
  if stripe
    oauth_config = OauthConfiguration.find_by(integration: stripe)
    if oauth_config && oauth_config.auth_configs.any?
      ac = oauth_config.auth_configs.first
      puts '✅ Stripe Auth Config:'
      puts \"  Key: #{ac.auth_key}\"
      puts \"  Value: #{ac.auth_value}\"
      puts \"  Placement: #{ac.auth_placement}\"
      puts ''
      puts 'Expected:'
      puts '  Key: Authorization'
      puts '  Value: Bearer {api_key}'
      puts '  Placement: header'
    else
      puts '❌ Stripe has no auth config!'
    end
  else
    puts '❌ Stripe integration not found!'
  end
"
```

### 3. **Test Stripe Connection (Optional)**
```bash
# Only if you have a test Stripe connection
RAILS_ENV=production rails runner "
  conn = Connection.joins(:integration).where(integrations: {slug: 'stripe'}).first
  if conn
    result = conn.test_connection!
    puts 'Stripe test: ' + (result[:success] ? '✅ PASSED' : '❌ FAILED')
    puts 'Message: ' + (result[:message] || result[:error] || 'N/A')
  else
    puts 'No Stripe connections to test'
  end
"
```

### 4. **Check Admin UI**
- ✅ Go to `/admin/integrations`
- ✅ Click on Stripe → Should show "Auth Config" button
- ✅ Click "Auth Config" → Should show existing config
- ✅ Verify: `Authorization` / `Bearer {api_key}` / `header`

### 5. **Test User Connection Flow**
- ✅ Go to `/social_media_accounts` or Scout → Integrations
- ✅ Click "Connect" on Stripe
- ✅ Should show "Api Key" field (not "username" or "password")
- ✅ Enter test API key and verify connection works

---

## 🔥 Rollback Plan (if needed)

### If Something Goes Wrong:

1. **Restore Database Backup**
```bash
psql your_production_db < backup_auth_migration_YYYYMMDD_HHMMSS.sql
```

2. **Revert Code**
```bash
git revert HEAD
git push origin main
# Deploy previous version
```

3. **Remove Auth Configs (if migrations succeeded but rake task failed)**
```bash
RAILS_ENV=production rails runner "
  # Delete only non-OAuth auth configs
  OauthConfiguration.joins(:integration)
    .where.not(integrations: {auth_type: 'oauth2'})
    .destroy_all
  puts '✅ Removed non-OAuth auth configs'
"
```

---

## 📋 What Changed in Production

### New Database Tables
- `oauth_configurations` - Stores auth config per integration
- `auth_configs` - Stores individual auth parameters

### Modified Models
- ✅ `Integration` - Added `has_many :oauth_configurations`
- ✅ `OauthConfiguration` - New model with auth_configs association
- ✅ `AuthConfig` - New model for flexible auth params
- ✅ `IntegrationCredential` - Updated `build_auth_header` to use auth_configs

### New Admin Features
- ✅ Configure any integration's auth from UI
- ✅ Dynamic forms for non-OAuth integrations
- ✅ Add/remove auth parameters on the fly

### User-Facing Changes
- ✅ Connection forms now dynamic (read from database)
- ✅ Shows only configured fields
- ✅ Works in both advanced mode and Scout canvas

---

## ⚠️ Known Issues & Solutions

### Issue: "Authentication not configured" when connecting
**Solution:** Run the migration task:
```bash
RAILS_ENV=production rails integrations:migrate_auth_configs
```

### Issue: Stripe connection fails with 401
**Solution:** Update Stripe auth config to use Bearer token:
```bash
RAILS_ENV=production rails runner "
  stripe = Integration.find_by(slug: 'stripe')
  oauth_config = OauthConfiguration.find_by(integration: stripe)
  auth_config = oauth_config.auth_configs.first
  auth_config.update!(auth_key: 'Authorization', auth_value: 'Bearer {api_key}')
"
```

### Issue: Scout canvas shows old fallback forms
**Solution:** 
1. Restart Rails server
2. Clear browser cache (Cmd+Shift+R / Ctrl+F5)
3. Verify `Integration` model has `has_many :oauth_configurations`

---

## 🎯 Success Criteria

✅ All migrations ran successfully  
✅ No database errors in logs  
✅ Migration task completed without errors  
✅ Stripe auth config shows: `Authorization` / `Bearer {api_key}` / `header`  
✅ Admin can view/edit auth configs in UI  
✅ Users can connect to Stripe in advanced mode  
✅ Users can connect to Stripe in Scout canvas  
✅ Test connection to Stripe succeeds  
✅ Existing connections still work  

---

## 📞 Support

If you encounter issues:
1. Check Rails logs: `tail -f log/production.log`
2. Check database state with verification commands above
3. Review migration output for errors
4. Contact dev team with error messages

---

## ⏱️ Estimated Deployment Time

- **Migrations**: 30 seconds
- **Rake task**: 1-2 minutes
- **Verification**: 2-3 minutes
- **Total**: ~5 minutes

**Downtime**: None (migrations are non-breaking)


