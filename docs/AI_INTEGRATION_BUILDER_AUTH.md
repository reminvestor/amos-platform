# AI Integration Builder - Database-Driven Auth System

## Overview

The AI Integration Builder workflow (`integration_builder_v2.yml`) has been updated to work with the new 100% database-driven authentication system.

## How It Works Now

### Phase 1-4: Research & Knowledge Building
*(Unchanged - AI researches API, gathers docs, builds RAG store)*

### Phase 5: Generate Scaffold ✅ **UPDATED**

When AI creates the integration using `generate_integration_scaffold`:

1. **Creates `Integration` record** in database
   - Sets `auth_type` (oauth2, api_key, bearer_token, basic_auth)
   - Marks as custom in metadata with `owner_entity_id`
   
2. **For OAuth integrations**:
   - Also creates `OauthConfiguration` with `status: inactive`
   - Marks as `pending_setup` in metadata
   
3. **Creates `Connection`** for user's entity
   
4. **Creates `IntegrationCredential`** with empty credentials (pending)

5. **AI tells user** what to do next based on auth type

### User Next Steps (Before Testing)

#### For OAuth Integrations:
AI will instruct user:
```
I've created your integration! Before testing, you'll need to:
a) Register an OAuth app with [App Name]
b) Go to Admin → Integrations → [App Name] → Auth Config
c) Enter Client ID, Client Secret, Redirect URI, and OAuth URLs
d) Then click Connect to authorize access
```

#### For Non-OAuth Integrations (API Key, Bearer, Basic Auth):
AI will instruct user:
```
I've created your integration! Before testing, you'll need to:
a) Go to Admin → Integrations → [App Name] → Auth Config
b) Configure the authentication parameters:
   - For API Key: Set header name and value template
   - For Bearer Token: Configure Authorization header
   - For Basic Auth: Configure username/password fields
c) Then click Connect and enter your credentials
```

### Phase 6-9: Testing & Completion
*(Workflow continues as normal once auth is configured)*

## Example User Flow

### Scenario: User wants to integrate with "Acme CRM"

**User**: "I want to integrate with Acme CRM to sync contacts"

**AI (Phase 1-2)**: Researches Acme CRM API, finds it uses OAuth 2.0

**AI (Phase 3-4)**: Gathers user feedback, builds RAG knowledge base

**AI (Phase 5)**: 
- Creates integration with `auth_type: oauth2`
- Creates `OauthConfiguration` (inactive)
- Creates connection and credential records
- Tells user:
  > "I've created your Acme CRM integration! Before we can test it, you'll need to:
  > 1. Go to Acme CRM developer portal and register an OAuth app
  > 2. Get your Client ID and Client Secret
  > 3. Visit Admin → Integrations → Acme CRM → Auth Config
  > 4. Enter your OAuth credentials and configure the redirect URI
  > 5. Then click Connect to authorize

**User**: Configures OAuth in admin panel

**AI (Phase 6)**: User tests connection, AI verifies it works

**AI (Phase 7-8)**: Builds out remaining endpoints

**AI (Phase 9)**: Validates complete integration

## Key Changes from Previous Version

### Before (Old System)
- ❌ Generated code files for auth
- ❌ Hardcoded auth configs in seed files
- ❌ No admin UI for auth configuration
- ❌ Required code changes to update auth

### After (New System)
- ✅ 100% database-driven (no code generation)
- ✅ Creates `OauthConfiguration` for OAuth integrations
- ✅ Admin can configure auth via UI
- ✅ Dynamic forms based on `auth_configs`
- ✅ User-specific integrations tracked in metadata

## What Gets Created

### For OAuth Integration:
```ruby
Integration
├─ name: "Acme CRM"
├─ slug: "acme_crm"
├─ auth_type: "oauth2"
├─ metadata: { owner_entity_id: 1, custom: true, ... }

OauthConfiguration
├─ integration_id: ...
├─ status: "inactive"
├─ client_id: nil  (user fills this)
├─ client_secret: nil  (user fills this)
├─ metadata: { pending_setup: true, ... }

Connection
├─ integration_id: ...
├─ entity_id: 1
├─ status: "disconnected"
├─ metadata: { setup_required: true, ... }

IntegrationCredential
├─ connection_id: ...
├─ credentials: {}  (empty until OAuth flow)
├─ status: "expired"
├─ auth_method: "bearer"
```

### For API Key Integration:
```ruby
Integration
├─ name: "Simple API"
├─ auth_type: "api_key"
├─ metadata: { owner_entity_id: 1, custom: true, ... }

# NO OauthConfiguration created (not needed for non-OAuth)

Connection
├─ integration_id: ...
├─ entity_id: 1
├─ status: "disconnected"

IntegrationCredential
├─ connection_id: ...
├─ credentials: {}  (empty until user connects)
├─ status: "expired"
├─ auth_method: "header"
```

## Admin Configuration Flow

### OAuth Integration:
1. User (or admin) goes to `/admin/integrations/acme_crm`
2. Clicks "Auth Config" button
3. Fills in form:
   - Client ID: `abc123...`
   - Client Secret: `xyz789...`
   - Redirect URI: `https://app.example.com/integrations/callback/acme_crm`
   - Authorize URL: `https://acme.com/oauth/authorize`
   - Token URL: `https://acme.com/oauth/token`
   - Scopes: `contacts.read, contacts.write`
4. Saves → `OauthConfiguration` status changes to `active`
5. User clicks "Connect" → OAuth flow → Tokens stored

### Non-OAuth Integration:
1. User (or admin) goes to `/admin/integrations/simple_api`
2. Clicks "Auth Config" button
3. Adds auth parameters:
   - **Parameter 1**: 
     - Key: `X-API-Key`
     - Value: `{api_key}`
     - Placement: `header`
4. Saves → Creates `AuthConfig` records
5. User clicks "Connect" → Form shows "Api Key" field → User enters key → Stored

## Benefits

✅ **Flexible**: Works for ANY auth type (OAuth, API Key, Bearer, Basic, Custom)  
✅ **Secure**: No code generation, all in database  
✅ **User-friendly**: Clear instructions at each step  
✅ **Maintainable**: Change auth config via UI, no code changes  
✅ **Scalable**: Users can create unlimited integrations  
✅ **Tracked**: Owner entity stored in metadata  

## Production Deployment

When deploying to production, the workflow automatically works with the new system:

1. ✅ Migrations create `oauth_configurations` and `auth_configs` tables
2. ✅ `generate_integration_scaffold` tool updated to create `OauthConfiguration`
3. ✅ Workflow instructions updated to guide users through admin config
4. ✅ Admin UI ready for configuring auth for any integration type

No additional setup needed! 🎉

## Testing the Workflow

### Test OAuth Integration:
```
User: "I want to integrate with GitHub's API to manage repositories"

AI will:
1. Research GitHub API → finds OAuth 2.0
2. Build RAG store with GitHub docs
3. Create integration with auth_type: oauth2
4. Create OauthConfiguration (inactive)
5. Tell user to register OAuth app and configure in admin
6. Wait for user to complete auth setup
7. Test connection
8. Build endpoints (repos, issues, pull requests, etc.)
```

### Test API Key Integration:
```
User: "I want to integrate with SendGrid to send emails"

AI will:
1. Research SendGrid API → finds API Key auth
2. Build RAG store
3. Create integration with auth_type: api_key
4. Tell user to configure auth params in admin (X-API-Key header)
5. User adds auth config → form asks for api_key
6. Test connection
7. Build endpoints (send_email, etc.)
```

## Troubleshooting

### Issue: "No authentication configuration yet"
**Cause**: User hasn't configured auth in admin panel  
**Fix**: Direct user to Admin → Integrations → [App] → Auth Config

### Issue: OAuth callback fails
**Cause**: Redirect URI mismatch or missing OAuth config  
**Fix**: Verify `OauthConfiguration` exists and Client ID/Secret are set

### Issue: API calls return 401 Unauthorized
**Cause**: No `auth_configs` set up for non-OAuth, or credentials not entered  
**Fix**: Admin needs to configure auth params, then user needs to connect

---

**System Status**: ✅ Fully updated and production-ready!


