# Universal OAuth Parameter & Endpoint Management System

## 🎯 Overview

This system provides a **universal, database-driven approach** for handling OAuth callback parameters and dynamic endpoint URL construction. It eliminates hardcoded integration-specific logic and works for ANY OAuth integration.

## 🚀 Key Features

### 1. **OAuth Callback Parameter Capture**
- Admin configures which parameters to capture from OAuth callback URLs
- Parameters are automatically stored in credentials
- Examples: `realmId` (QuickBooks), `instance_url` (Salesforce), `organization_id` (Emburse)

### 2. **Two-Tier URL Parameter System**

#### **Tier 1: Auto-Injected Credentials (from OAuth callback)**
- Captured during OAuth authorization
- Stored in `IntegrationCredential.credentials`
- Automatically replaced in ALL API calls
- Examples: `{company_id}`, `{realm_id}`, `{instance_url}`

#### **Tier 2: User-Provided Parameters**
- Provided by user when calling an operation
- Required each time the operation is executed
- Examples: `{customer_id}`, `{invoice_id}`, `{limit}`

### 3. **Configurable Test Endpoints**
- Simple GET endpoint for connection testing
- Uses credential-based parameter replacement
- No user input required
- Example: `/v3/company/{company_id}/companyinfo/{company_id}`

## 📊 Database Schema

### New Fields on `oauth_configurations`

```ruby
callback_params  # jsonb, default: [], null: false
                 # Array of parameter names to capture from OAuth callback
                 # Example: ["realmId", "instance_url"]

test_endpoint    # text, nullable
                 # Simple GET endpoint for testing connection
                 # Example: "/v3/company/{company_id}/companyinfo/{company_id}"
```

## 🔄 How It Works

### OAuth Authorization Flow

```
1. User clicks "Connect to QuickBooks"
   ↓
2. Redirected to QuickBooks OAuth authorize URL
   ↓
3. User authorizes app
   ↓
4. Callback: /integrations/callback/quickbooks?code=ABC&realmId=123456789
   ↓
5. OauthController checks oauth_configuration.callback_params → ["realmId"]
   ↓
6. Stores in credentials:
   {
     access_token: "...",
     refresh_token: "...",
     realmId: "123456789",      # Original param
     realm_id: "123456789",     # Alias
     company_id: "123456789"    # Alias for compatibility
   }
   ↓
7. Test connection uses /v3/company/{company_id}/companyinfo/{company_id}
   → Becomes: /v3/company/123456789/companyinfo/123456789
```

### API Call Flow

```
User: "Get QuickBooks customers"
  ↓
IntegrationApiService#execute_operation
  ↓
IntegrationOperation#build_path(params, credentials)
  ↓
Path template: "/company/{company_id}/query"
  ↓
Step 1: Replace from credentials
  {company_id: "123456789"} → "/company/123456789/query"
  ↓
Step 2: Replace from user params
  {query: "SELECT * FROM Customer"} → Query string
  ↓
Final URL: https://api.intuit.com/v3/company/123456789/query?query=SELECT%20*%20FROM%20Customer
```

## 🛠️ Configuration Guide

### For QuickBooks

#### 1. Migration
```bash
rails db:migrate  # Adds callback_params and test_endpoint columns
```

#### 2. Seed Data
```bash
rails db:seed  # Creates OAuth configuration
```

Or manually in console:
```ruby
quickbooks = Integration.find_by(slug: 'quickbooks')

OauthConfiguration.find_or_create_by!(integration: quickbooks) do |config|
  config.status = :inactive
  config.authorize_url = 'https://appcenter.intuit.com/connect/oauth2'
  config.token_url = 'https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer'
  config.redirect_uri = 'https://app.agentmarketing.com/integrations/callback/quickbooks'
  config.scopes = 'com.intuit.quickbooks.accounting'
  config.callback_params = ['realmId']
  config.test_endpoint = '/v3/company/{company_id}/companyinfo/{company_id}'
end
```

#### 3. Admin Configuration
1. Go to **Admin → Integrations → QuickBooks**
2. Click **"Auth Config"**
3. Fill in:
   - **Client ID**: (from Intuit Developer)
   - **Client Secret**: (from Intuit Developer)
   - **Callback Params**: `realmId` (already pre-filled from seed)
   - **Test Endpoint**: `/v3/company/{company_id}/companyinfo/{company_id}` (pre-filled)
4. Set status to **Active**
5. Save

#### 4. User Connection
1. User clicks **Connect to QuickBooks**
2. Authorizes app
3. Callback captures `realmId` automatically
4. Connection tested with simple GET request (no params needed!)

### For Other Integrations

#### Salesforce Example
```ruby
salesforce = Integration.find_by(slug: 'salesforce')

OauthConfiguration.create!(
  integration: salesforce,
  authorize_url: 'https://login.salesforce.com/services/oauth2/authorize',
  token_url: 'https://login.salesforce.com/services/oauth2/token',
  redirect_uri: 'https://app.agentmarketing.com/integrations/callback/salesforce',
  scopes: 'api refresh_token',
  callback_params: ['instance_url'],  # Salesforce returns instance_url
  test_endpoint: '/services/data/v57.0/sobjects'  # Simple test endpoint
)
```

#### Emburse Example
```ruby
emburse = Integration.find_by(slug: 'emburse')

OauthConfiguration.create!(
  integration: emburse,
  authorize_url: 'https://app.emburse.com/oauth/authorize',
  token_url: 'https://app.emburse.com/oauth/token',
  redirect_uri: 'https://app.agentmarketing.com/integrations/callback/emburse',
  scopes: 'expenses:read expenses:write',
  callback_params: ['organization_id'],  # Emburse returns organization_id
  test_endpoint: '/api/v1/organizations/{organization_id}/profile'
)
```

## 🧪 Testing

### Test QuickBooks Connection

```ruby
# 1. Create QuickBooks integration (from seeds)
quickbooks = Integration.find_by(slug: 'quickbooks')

# 2. Configure OAuth (admin panel or console)
oauth_config = OauthConfiguration.find_by(integration: quickbooks)
oauth_config.update!(
  client_id: 'YOUR_CLIENT_ID',
  client_secret: 'YOUR_CLIENT_SECRET',
  callback_params: ['realmId'],
  test_endpoint: '/v3/company/{company_id}/companyinfo/{company_id}',
  status: :active
)

# 3. Simulate OAuth callback (would normally come from QuickBooks)
user = User.first
entity = user.entities.first

connection = entity.connections.create!(
  integration: quickbooks,
  name: 'Test QuickBooks',
  status: :connected
)

credential = connection.integration_credentials.create!(
  name: 'OAuth Token',
  credentials: {
    access_token: 'test_access_token',
    refresh_token: 'test_refresh_token',
    realmId: '123456789',       # Captured from callback
    realm_id: '123456789',      # Alias
    company_id: '123456789'     # Alias
  },
  auth_method: 'bearer',
  status: :active
)

# 4. Test connection (should use test_endpoint with {company_id} replaced)
api_service = IntegrationApiService.new(connection)
result = api_service.test_connection

puts "Test Result: #{result[:success] ? 'SUCCESS' : 'FAILED'}"
puts "Endpoint Called: /v3/company/123456789/companyinfo/123456789"
puts "Error: #{result[:error]}" if result[:error]
```

### Test API Call with URL Parameters

```ruby
# Operation that uses {company_id} in path
operation = quickbooks.integration_operations.find_by(
  operation_id: 'quickbooks.list_customers.v3'
)

# Execute operation (company_id automatically injected from credentials)
api_service = IntegrationApiService.new(connection)
response = api_service.execute_operation(
  operation,
  params: {
    query: 'SELECT * FROM Customer'
  }
)

# URL built: /v3/company/123456789/query?query=SELECT%20*%20FROM%20Customer
puts "Success!" if response.success?
```

## 📝 Code Changes Summary

### 1. Migration
**File**: `db/migrate/20251024200008_add_oauth_callback_params_to_oauth_configurations.rb`
- Added `callback_params` (jsonb)
- Added `test_endpoint` (text)
- Added GIN index on `callback_params`

### 2. Model Changes
**File**: `app/models/oauth_configuration.rb`
- Added `callback_param_names` method
- Auto-initialize `callback_params` to `[]`
- Pre-fill `test_endpoint` from integration defaults

### 3. Controller Changes
**File**: `app/controllers/integrations/oauth_controller.rb`
- Dynamically capture callback params based on `oauth_configuration.callback_params`
- Store params with original name and common aliases
- Removed hardcoded QuickBooks logic

**File**: `app/controllers/admin/oauth_configurations_controller.rb`
- Added `callback_params` and `test_endpoint` to permitted params
- Convert comma-separated string to array

### 4. Service Changes
**File**: `app/services/integration_api_service.rb`
- Added `test_with_endpoint` method for configured test endpoints
- Replace placeholders in test endpoint with credentials
- Pass credentials to `build_path` for auto-injection

**File**: `app/models/integration_operation.rb`
- Updated `build_path` to accept `credentials` parameter
- Replace placeholders from credentials FIRST (Tier 1)
- Then replace from user params (Tier 2)

### 5. View Changes
**Files**: 
- `app/views/admin/oauth_configurations/new.html.erb`
- `app/views/admin/oauth_configurations/edit.html.erb`

- Added "OAuth Callback Parameters to Capture" field
- Added "Test Connection Endpoint" field
- Added helpful examples and documentation

### 6. Seeds
**File**: `db/seeds/integrations.rb`
- Added QuickBooks `OauthConfiguration` with:
  - `callback_params: ['realmId']`
  - `test_endpoint: '/v3/company/{company_id}/companyinfo/{company_id}'`

## 🎯 Benefits

✅ **Universal**: Works for ANY OAuth integration  
✅ **No Hardcoding**: All integration-specific logic is in database  
✅ **Flexible**: Admin can configure via UI  
✅ **Automatic**: Parameters auto-injected in ALL API calls  
✅ **Testable**: Simple test endpoints with no user input  
✅ **Maintainable**: Add new integrations without code changes  
✅ **Scalable**: Supports multiple callback params per integration  

## 🚀 Production Deployment

### Step 1: Run Migration
```bash
# On production server
rails db:migrate
```

### Step 2: Run Seeds
```bash
# This creates OAuth configurations for integrations
rails db:seed
```

### Step 3: Configure OAuth Apps
For each integration (QuickBooks, Salesforce, etc.):
1. Create OAuth app with provider
2. Get `client_id` and `client_secret`
3. Register callback URL: `https://app.agentmarketing.com/integrations/callback/{slug}`
4. Go to Admin → Integrations → {Integration} → Auth Config
5. Enter credentials and set status to Active

### Step 4: Test Connections
1. As a user, click "Connect" on integration
2. Authorize app
3. Verify connection test passes
4. Try executing operations

## 📚 Examples for Common Integrations

### QuickBooks
```ruby
callback_params: ['realmId']
test_endpoint: '/v3/company/{company_id}/companyinfo/{company_id}'
operations use: /v3/company/{company_id}/* paths
```

### Salesforce
```ruby
callback_params: ['instance_url']
test_endpoint: '/services/data/v57.0/sobjects'
operations use: {instance_url}/services/data/v57.0/* paths
```

### NetSuite
```ruby
callback_params: ['accountId']
test_endpoint: '/services/rest/record/v1/account/{accountId}/metadata'
operations use: /services/rest/record/v1/account/{accountId}/* paths
```

### Shopify
```ruby
callback_params: ['shop']  # shop domain
test_endpoint: '/admin/api/2024-01/shop.json'
operations use: /admin/api/2024-01/* paths
```

## 🐛 Troubleshooting

### "Missing required path parameters: company_id"
**Cause**: `company_id` not in credentials  
**Fix**: Ensure `callback_params` includes the OAuth param (e.g., `realmId`) and that the callback successfully captured it

### "No test operation defined for this integration"
**Cause**: No `test_endpoint` configured  
**Fix**: Add `test_endpoint` in Admin → Auth Config

### "Authentication not configured"
**Cause**: No `OauthConfiguration` for integration  
**Fix**: Run seeds or create configuration manually

### OAuth callback params not captured
**Cause**: `callback_params` array is empty or has wrong param name  
**Fix**: Check `oauth_configuration.callback_params` matches what the OAuth provider returns

## 🎉 Success!

You now have a **fully universal OAuth parameter system** that:
- Captures ANY callback parameter
- Auto-injects into API calls
- Works for ANY integration
- Requires ZERO code changes for new integrations

Just configure in the admin panel and go! 🚀

