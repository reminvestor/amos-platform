# Example of how to add integrations purely through database records
# This demonstrates that everything needed for an integration can be stored in the DB

# Safety check: Skip seeding integrations if any already exist (preserves customizations)
# Set FORCE_SEED_INTEGRATIONS=true to override
if Integration.exists? && ENV['FORCE_SEED_INTEGRATIONS'] != 'true'
  puts "⏭️  Skipping integrations seed - integrations already exist in database"
  puts "   Set FORCE_SEED_INTEGRATIONS=true to force seeding"
  return
end

puts "🔌 Seeding integrations..."

# Stripe Integration
stripe = Integration.find_or_create_by!(slug: 'stripe') do |i|
  i.name = 'Stripe'
  i.category = 'payment'
  i.auth_type = 'basic_auth'
  i.api_base_url = 'https://api.stripe.com'
  i.allowed_hosts = [ 'api.stripe.com' ]
  i.documentation_url = 'https://stripe.com/docs/api'
  i.icon_url = 'https://cdn.brandfolder.io/KGT2DTA4/at/8gkvgs86vw4gv4x48878kh4/Stripe_icon_-_square.svg'
  i.description = 'Accept payments and manage subscriptions'
  i.is_active = true
  i.is_verified = true
  i.auth_config = {
    auth_method: 'basic',
    username_label: 'API Key',
    username_placeholder: 'sk_test_... or sk_live_...',
    username_help_text: 'Enter your Stripe secret key. No password needed - Stripe uses the API key as username in Basic Auth.',
    password_required: false,
    password_value: '',
    test_endpoint: '/v1/customers?limit=1',
    setup_instructions: 'Get your API key from the Stripe Dashboard under Developers > API Keys'
  }
  i.metadata = {
    api_version: '2020-08-27',
    rate_limits: {
      default: 100,
      per: 'second'
    }
  }
end

# Stripe - Test Connection
stripe.integration_operations.find_or_create_by!(
  operation_id: 'stripe.test_connection'
) do |op|
  op.name = 'Test Connection'
  op.description = 'Test if your Stripe API key is valid'
  op.http_method = 'GET'
  op.path_template = '/v1/balance'  # Simple endpoint that requires no params
  op.pagination_strategy = 'no_pagination'
  op.is_idempotent = true
  op.requires_confirmation = false
  op.request_schema = {
    type: 'object',
    properties: {}
  }
  op.documentation = 'Returns your Stripe account balance - used to verify API key is working'
end

# Stripe Operations - List Customers
stripe.integration_operations.find_or_create_by!(
  operation_id: 'stripe.list_customers'
) do |op|
  op.name = 'List Customers'
  op.description = 'Returns a list of your customers'
  op.http_method = 'GET'
  op.path_template = '/v1/customers'
  op.pagination_strategy = 'cursor'
  op.is_idempotent = true
  op.requires_confirmation = false
  op.max_limit = 100
  op.request_schema = {
    type: 'object',
    properties: {
      limit: {
        type: 'integer',
        description: 'Number of customers to return (1-100)',
        minimum: 1,
        maximum: 100,
        default: 10
      },
      starting_after: {
        type: 'string',
        description: 'Cursor for pagination'
      },
      created: {
        type: 'object',
        properties: {
          gt: { type: 'integer', description: 'Created after timestamp' },
          gte: { type: 'integer', description: 'Created after or at timestamp' },
          lt: { type: 'integer', description: 'Created before timestamp' },
          lte: { type: 'integer', description: 'Created before or at timestamp' }
        }
      },
      email: {
        type: 'string',
        description: 'Filter by email address'
      }
    }
  }
  op.response_schema = {
    type: 'object',
    properties: {
      object: { type: 'string', enum: [ 'list' ] },
      url: { type: 'string' },
      has_more: { type: 'boolean' },
      data: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            id: { type: 'string' },
            object: { type: 'string', enum: [ 'customer' ] },
            email: { type: 'string' },
            name: { type: 'string' },
            created: { type: 'integer' }
          }
        }
      }
    }
  }
  op.examples = {
    query_params: {
      limit: 10,
      created: { gte: 1640995200 }
    }
  }
end

# Stripe - Create Customer
stripe.integration_operations.find_or_create_by!(
  operation_id: 'stripe.create_customer'
) do |op|
  op.name = 'Create Customer'
  op.description = 'Creates a new customer object'
  op.http_method = 'POST'
  op.path_template = '/v1/customers'
  op.pagination_strategy = 'no_pagination'
  op.is_idempotent = false
  op.requires_confirmation = true
  op.request_schema = {
    type: 'object',
    properties: {
      email: {
        type: 'string',
        format: 'email',
        description: 'Customer email address'
      },
      name: {
        type: 'string',
        description: 'Customer full name'
      },
      description: {
        type: 'string',
        description: 'Arbitrary description'
      },
      phone: {
        type: 'string',
        description: 'Customer phone number'
      },
      metadata: {
        type: 'object',
        description: 'Set of key-value pairs',
        additionalProperties: { type: 'string' }
      }
    },
    required: [ 'email' ]
  }
  op.examples = {
    body: {
      email: 'customer@example.com',
      name: 'John Doe',
      metadata: {
        order_id: '12345'
      }
    }
  }
end

# Shopify Integration
shopify = Integration.find_or_create_by!(slug: 'shopify') do |i|
  i.name = 'Shopify'
  i.category = 'ecommerce'
  i.auth_type = 'api_key'
  i.api_base_url = 'https://{shop_domain}/admin/api/2024-01'
  i.allowed_hosts = [ '*.myshopify.com' ]
  i.documentation_url = 'https://shopify.dev/docs/api/admin-rest'
  i.icon_url = 'https://cdn.shopify.com/shopifycloud/brochure/assets/brand-assets/shopify-logo-primary-logo@2x-11ee0e2c8d0635c096c0c258e1f3c3e26d95bd4bdc1a08c75f00e12afa91e1a6.png'
  i.description = 'Manage your online store, products, and orders'
  i.is_active = true
  i.is_verified = true
  i.auth_config = {
    auth_method: 'header',
    auth_field_name: 'X-Shopify-Access-Token',
    requires_shop_domain: true,
    setup_instructions: 'Create a private app in your Shopify admin to get an access token'
  }
  i.metadata = {
    api_version: '2024-01',
    rate_limits: {
      default: 2,
      burst: 40,
      per: 'second'
    }
  }
end

# Shopify - Test Connection
shopify.integration_operations.find_or_create_by!(
  operation_id: 'shopify.test_connection'
) do |op|
  op.name = 'Test Connection'
  op.description = 'Test if your Shopify access token is valid'
  op.http_method = 'GET'
  op.path_template = '/shop.json'  # Returns basic shop info
  op.pagination_strategy = 'no_pagination'
  op.is_idempotent = true
  op.requires_confirmation = false
  op.request_schema = {
    type: 'object',
    properties: {}
  }
  op.documentation = 'Returns your shop information - used to verify access token is working'
end

# Shopify - List Products
shopify.integration_operations.find_or_create_by!(
  operation_id: 'shopify.list_products.v2024-01'
) do |op|
  op.name = 'List Products'
  op.description = 'Retrieves a list of products'
  op.http_method = 'GET'
  op.path_template = '/products.json'
  op.pagination_strategy = 'page'
  op.is_idempotent = true
  op.requires_confirmation = false
  op.max_limit = 250
  op.request_schema = {
    type: 'object',
    properties: {
      limit: {
        type: 'integer',
        description: 'Number of results (max 250)',
        minimum: 1,
        maximum: 250,
        default: 50
      },
      page: {
        type: 'integer',
        description: 'Page number',
        minimum: 1,
        default: 1
      },
      since_id: {
        type: 'integer',
        description: 'Show products after this ID'
      },
      product_type: {
        type: 'string',
        description: 'Filter by product type'
      },
      vendor: {
        type: 'string',
        description: 'Filter by vendor'
      },
      status: {
        type: 'string',
        enum: [ 'active', 'archived', 'draft' ],
        description: 'Filter by status'
      }
    }
  }
end

# HubSpot Integration (OAuth2 example)
hubspot = Integration.find_or_create_by!(slug: 'hubspot') do |i|
  i.name = 'HubSpot'
  i.category = 'crm'
  i.auth_type = 'oauth2'
  i.api_base_url = 'https://api.hubapi.com'
  i.allowed_hosts = [ 'api.hubapi.com' ]
  i.documentation_url = 'https://developers.hubspot.com/docs/api/overview'
  i.icon_url = 'https://www.hubspot.com/hubfs/HubSpot_Logos/HubSpot-Inversed-Favicon.png'
  i.description = 'CRM, marketing, and sales platform'
  i.is_active = true
  i.is_verified = true
  i.auth_config = {
    authorize_url: 'https://app.hubspot.com/oauth/authorize',
    token_url: 'https://api.hubapi.com/oauth/v1/token',
    scopes: [ 'crm.objects.contacts.read', 'crm.objects.contacts.write' ],
    client_id: ENV['HUBSPOT_CLIENT_ID'],
    client_secret: ENV['HUBSPOT_CLIENT_SECRET'],
    redirect_uri: 'https://app.agentmarketing.com/integrations/callback/hubspot'
  }
  i.metadata = {
    api_version: 'v3',
    rate_limits: {
      daily: 250000,
      per_second: 100,
      burst: 150
    }
  }
end

# HubSpot - Test Connection
hubspot.integration_operations.find_or_create_by!(
  operation_id: 'hubspot.test_connection.v3'
) do |op|
  op.name = 'Test Connection'
  op.description = 'Test if your HubSpot access token is valid'
  op.http_method = 'GET'
  op.path_template = '/account-info/v3/details'  # Returns basic account info
  op.pagination_strategy = 'no_pagination'
  op.is_idempotent = true
  op.requires_confirmation = false
  op.request_schema = {
    type: 'object',
    properties: {}
  }
  op.documentation = 'Returns your HubSpot account details - used to verify OAuth token is working'
end

# HubSpot - Get Contacts
hubspot.integration_operations.find_or_create_by!(
  operation_id: 'hubspot.list_contacts.v3'
) do |op|
  op.name = 'List Contacts'
  op.description = 'Read a page of contacts'
  op.http_method = 'GET'
  op.path_template = '/crm/v3/objects/contacts'
  op.pagination_strategy = 'cursor'
  op.is_idempotent = true
  op.requires_confirmation = false
  op.max_limit = 100
  op.request_schema = {
    type: 'object',
    properties: {
      limit: {
        type: 'integer',
        description: 'Maximum number of results',
        minimum: 1,
        maximum: 100
      },
      after: {
        type: 'string',
        description: 'Pagination cursor'
      },
      properties: {
        type: 'array',
        items: { type: 'string' },
        description: 'Properties to include in response'
      }
    }
  }
end

# Google Sheets Integration (Custom OAuth example)
google_sheets = Integration.find_or_create_by!(slug: 'google_sheets') do |i|
  i.name = 'Google Sheets'
  i.category = 'productivity'
  i.auth_type = 'custom'  # User-managed OAuth app
  i.api_base_url = 'https://sheets.googleapis.com/v4'
  i.allowed_hosts = [ 'sheets.googleapis.com' ]
  i.documentation_url = 'https://developers.google.com/sheets/api/reference/rest'
  i.icon_url = 'https://upload.wikimedia.org/wikipedia/commons/3/30/Google_Sheets_logo_%282014-2020%29.svg'
  i.description = 'Read and write Google Sheets spreadsheets'
  i.is_active = true
  i.is_verified = false  # Requires user to set up their own OAuth app
  i.auth_config = {
    requires_user_app: true,
    auth_provider: 'google',
    scopes: [ 'https://www.googleapis.com/auth/spreadsheets' ],
    setup_instructions: <<~INSTRUCTIONS
      1. Go to Google Cloud Console
      2. Create a new project or select existing
      3. Enable Google Sheets API
      4. Create OAuth 2.0 credentials
      5. Add redirect URI: https://app.agentmarketing.com/integrations/callback/google_sheets
      6. Copy Client ID and Client Secret
    INSTRUCTIONS
  }
end

# Google Sheets - Test Connection (for custom OAuth)
google_sheets.integration_operations.find_or_create_by!(
  operation_id: 'google_sheets.test_connection.v4'
) do |op|
  op.name = 'Test Connection'
  op.description = 'Test if your Google Sheets OAuth token is valid'
  op.http_method = 'GET'
  op.path_template = '/spreadsheets?pageSize=1'  # List one spreadsheet
  op.pagination_strategy = 'no_pagination'
  op.is_idempotent = true
  op.requires_confirmation = false
  op.request_schema = {
    type: 'object',
    properties: {}
  }
  op.documentation = 'Lists one spreadsheet - used to verify OAuth token is working'
end

# Slack Integration (Webhook example)
slack = Integration.find_or_create_by!(slug: 'slack') do |i|
  i.name = 'Slack'
  i.category = 'communication'
  i.auth_type = 'custom'
  i.api_base_url = 'https://slack.com/api'
  i.allowed_hosts = [ 'slack.com', 'hooks.slack.com' ]
  i.documentation_url = 'https://api.slack.com/docs'
  i.icon_url = 'https://a.slack-edge.com/80588/marketing/img/icons/icon_slack_hash_colored.png'
  i.description = 'Send messages and notifications to Slack'
  i.is_active = true
  i.is_verified = true
  i.auth_config = {
    auth_types: [ 'webhook', 'oauth2' ],
    webhook_instructions: 'Create an Incoming Webhook in your Slack workspace',
    oauth_scopes: [ 'chat:write', 'channels:read' ]
  }
end

# Slack - Test Connection (OAuth)
slack.integration_operations.find_or_create_by!(
  operation_id: 'slack.test_connection.v1'
) do |op|
  op.name = 'Test Connection'
  op.description = 'Test if your Slack OAuth token is valid'
  op.http_method = 'GET'
  op.path_template = '/api/auth.test'  # Returns auth info
  op.pagination_strategy = 'no_pagination'
  op.is_idempotent = true
  op.requires_confirmation = false
  op.request_schema = {
    type: 'object',
    properties: {}
  }
  op.documentation = 'Returns your Slack authentication info - used to verify OAuth token is working'
end

# Slack - Post Message (via webhook)
slack.integration_operations.find_or_create_by!(
  operation_id: 'slack.post_webhook_message.v1'
) do |op|
  op.name = 'Post Message (Webhook)'
  op.description = 'Post a message to Slack via webhook URL'
  op.http_method = 'POST'
  op.path_template = '/'  # Full URL provided by webhook
  op.is_idempotent = false
  op.requires_confirmation = false
  op.request_schema = {
    type: 'object',
    properties: {
      text: {
        type: 'string',
        description: 'Message text'
      },
      blocks: {
        type: 'array',
        description: 'Rich message blocks'
      },
      channel: {
        type: 'string',
        description: 'Override default channel'
      }
    },
    required: [ 'text' ]
  }
end

# Gmail Integration
gmail = Integration.find_or_create_by!(slug: 'gmail') do |i|
  i.name = 'Gmail'
  i.category = 'communication'
  i.auth_type = 'oauth2'
  i.api_base_url = 'https://gmail.googleapis.com/gmail/v1'
  i.allowed_hosts = [ 'gmail.googleapis.com', 'www.googleapis.com' ]
  i.documentation_url = 'https://developers.google.com/gmail/api/reference/rest'
  i.icon_url = 'https://ssl.gstatic.com/ui/v1/icons/mail/rfr/logo_gmail_lockup_default_2x_r2.png'
  i.description = 'Send emails, manage inbox, and organize messages'
  i.is_active = true
  i.is_verified = true
  i.auth_config = {
    authorize_url: 'https://accounts.google.com/o/oauth2/v2/auth',
    token_url: 'https://oauth2.googleapis.com/token',
    scopes: [
      'https://www.googleapis.com/auth/gmail.send',
      'https://www.googleapis.com/auth/gmail.readonly',
      'https://www.googleapis.com/auth/gmail.compose',
      'https://www.googleapis.com/auth/gmail.labels'
    ],
    client_id: ENV['GOOGLE_CLIENT_ID'],
    client_secret: ENV['GOOGLE_CLIENT_SECRET'],
    redirect_uri: 'https://app.agentmarketing.com/integrations/callback/gmail',
    access_type: 'offline',
    prompt: 'consent'
  }
  i.metadata = {
    rate_limits: {
      quota_units_per_user: 250,
      quota_units_per_second: 25
    }
  }
end

# Gmail - Test Connection
gmail.integration_operations.find_or_create_by!(
  operation_id: 'gmail.test_connection.v1'
) do |op|
  op.name = 'Test Connection'
  op.description = 'Test if your Gmail OAuth token is valid'
  op.http_method = 'GET'
  op.path_template = '/users/me/profile'  # Returns basic user profile
  op.pagination_strategy = 'no_pagination'
  op.is_idempotent = true
  op.requires_confirmation = false
  op.request_schema = {
    type: 'object',
    properties: {}
  }
  op.documentation = 'Returns your Gmail profile - used to verify OAuth token is working'
end

# Gmail Operations
gmail.integration_operations.find_or_create_by!(
  operation_id: 'gmail.send_email.v1'
) do |op|
  op.name = 'Send Email'
  op.description = 'Send an email message'
  op.http_method = 'POST'
  op.path_template = '/users/me/messages/send'
  op.is_idempotent = false
  op.requires_confirmation = true
  op.request_schema = {
    type: 'object',
    required: [ 'raw' ],
    properties: {
      raw: {
        type: 'string',
        description: 'Base64url encoded email message (RFC 2822 format)'
      }
    }
  }
  op.documentation = 'Email should be formatted with headers like To:, Subject:, etc.'
end

gmail.integration_operations.find_or_create_by!(
  operation_id: 'gmail.list_messages.v1'
) do |op|
  op.name = 'List Messages'
  op.description = 'List messages in the user\'s mailbox'
  op.http_method = 'GET'
  op.path_template = '/users/me/messages'
  op.pagination_strategy = 'token'
  op.is_idempotent = true
  op.requires_confirmation = false
  op.max_limit = 500
  op.request_schema = {
    type: 'object',
    properties: {
      q: {
        type: 'string',
        description: 'Query string (same as Gmail search box)'
      },
      maxResults: {
        type: 'integer',
        minimum: 1,
        maximum: 500,
        default: 100
      },
      pageToken: {
        type: 'string',
        description: 'Page token for pagination'
      },
      labelIds: {
        type: 'array',
        items: { type: 'string' },
        description: 'Filter by label IDs'
      }
    }
  }
end

gmail.integration_operations.find_or_create_by!(
  operation_id: 'gmail.get_message.v1'
) do |op|
  op.name = 'Get Message'
  op.description = 'Get a specific email message'
  op.http_method = 'GET'
  op.path_template = '/users/me/messages/{id}'
  op.is_idempotent = true
  op.requires_confirmation = false
  op.request_schema = {
    type: 'object',
    properties: {
      format: {
        type: 'string',
        enum: [ 'minimal', 'full', 'raw', 'metadata' ],
        default: 'full'
      }
    }
  }
end

# ================================
# Microsoft Outlook/365 Integration
# ================================
outlook = Integration.find_or_create_by!(slug: 'outlook') do |i|
  i.name = 'Microsoft Outlook'
  i.category = 'communication'
  i.auth_type = 'oauth2'
  i.api_base_url = 'https://graph.microsoft.com/v1.0'
  i.allowed_hosts = [ 'graph.microsoft.com', 'login.microsoftonline.com' ]
  i.documentation_url = 'https://learn.microsoft.com/en-us/graph/api/resources/mail-api-overview'
  i.icon_url = 'https://img-prod-cms-rt-microsoft-com.akamaized.net/cms/api/am/imageFileData/RE1Mu3b'
  i.description = 'Access Outlook mail, calendar, and contacts via Microsoft Graph API'
  i.is_active = true
  i.is_verified = true
  i.auth_config = {
    authorize_url: 'https://login.microsoftonline.com/common/oauth2/v2.0/authorize',
    token_url: 'https://login.microsoftonline.com/common/oauth2/v2.0/token',
    scopes: [
      'https://graph.microsoft.com/Mail.Read',
      'https://graph.microsoft.com/Mail.Send',
      'https://graph.microsoft.com/Mail.ReadWrite',
      'https://graph.microsoft.com/User.Read',
      'offline_access'
    ],
    client_id: ENV['OUTLOOK_CLIENT_ID'],
    client_secret: ENV['OUTLOOK_CLIENT_SECRET'],
    redirect_uri: 'https://app.agentmarketing.com/integrations/callback/outlook'
  }
  i.metadata = {
    rate_limits: {
      requests_per_minute: 10000
    },
    provider_type: 'microsoft'
  }
end

# Outlook - Test Connection
outlook.integration_operations.find_or_create_by!(
  operation_id: 'outlook.test_connection.v1'
) do |op|
  op.name = 'Test Connection'
  op.description = 'Test if your Microsoft OAuth token is valid'
  op.http_method = 'GET'
  op.path_template = '/me'
  op.pagination_strategy = 'no_pagination'
  op.is_idempotent = true
  op.requires_confirmation = false
  op.request_schema = { type: 'object', properties: {} }
  op.documentation = 'Returns your Microsoft profile - used to verify OAuth token is working'
end

# Outlook - List Messages
outlook.integration_operations.find_or_create_by!(
  operation_id: 'outlook.list_messages.v1'
) do |op|
  op.name = 'List Messages'
  op.description = 'List emails from your Outlook inbox'
  op.http_method = 'GET'
  op.path_template = '/me/messages'
  op.pagination_strategy = 'cursor'
  op.is_idempotent = true
  op.requires_confirmation = false
  op.request_schema = {
    type: 'object',
    properties: {
      '$top': { type: 'integer', description: 'Number of messages to return (max 50)', default: 25 },
      '$filter': { type: 'string', description: 'OData filter (e.g., "isRead eq false")' },
      '$select': { type: 'string', description: 'Fields to return (e.g., "subject,from,receivedDateTime")' },
      '$orderby': { type: 'string', description: 'Sort order (e.g., "receivedDateTime desc")', default: 'receivedDateTime desc' }
    }
  }
  op.documentation = 'Lists emails. Use $filter for queries like unread messages.'
end

# Outlook - Get Message
outlook.integration_operations.find_or_create_by!(
  operation_id: 'outlook.get_message.v1'
) do |op|
  op.name = 'Get Message'
  op.description = 'Get a specific email by ID'
  op.http_method = 'GET'
  op.path_template = '/me/messages/{id}'
  op.is_idempotent = true
  op.requires_confirmation = false
  op.request_schema = {
    type: 'object',
    properties: {
      '$select': { type: 'string', description: 'Fields to return' }
    }
  }
end

# Outlook - Send Email
outlook.integration_operations.find_or_create_by!(
  operation_id: 'outlook.send_email.v1'
) do |op|
  op.name = 'Send Email'
  op.description = 'Send an email via Outlook'
  op.http_method = 'POST'
  op.path_template = '/me/sendMail'
  op.is_idempotent = false
  op.requires_confirmation = true
  op.request_schema = {
    type: 'object',
    required: [ 'message' ],
    properties: {
      message: {
        type: 'object',
        required: [ 'subject', 'body', 'toRecipients' ],
        properties: {
          subject: { type: 'string' },
          body: {
            type: 'object',
            properties: {
              contentType: { type: 'string', enum: [ 'Text', 'HTML' ] },
              content: { type: 'string' }
            }
          },
          toRecipients: {
            type: 'array',
            items: {
              type: 'object',
              properties: {
                emailAddress: {
                  type: 'object',
                  properties: {
                    address: { type: 'string' }
                  }
                }
              }
            }
          }
        }
      },
      saveToSentItems: { type: 'boolean', default: true }
    }
  }
end

# Google Drive Integration
google_drive = Integration.find_or_create_by!(slug: 'google_drive') do |i|
  i.name = 'Google Drive'
  i.category = 'productivity'
  i.auth_type = 'oauth2'
  i.api_base_url = 'https://www.googleapis.com/drive/v3'
  i.allowed_hosts = [ 'www.googleapis.com', 'googleapis.com' ]
  i.documentation_url = 'https://developers.google.com/drive/api/v3/reference'
  i.icon_url = 'https://ssl.gstatic.com/images/branding/product/2x/drive_2020q4_48dp.png'
  i.description = 'Store, sync, and share files in the cloud'
  i.is_active = true
  i.is_verified = true
  i.auth_config = {
    authorize_url: 'https://accounts.google.com/o/oauth2/v2/auth',
    token_url: 'https://oauth2.googleapis.com/token',
    scopes: [
      'https://www.googleapis.com/auth/drive.file',
      'https://www.googleapis.com/auth/drive.readonly',
      'https://www.googleapis.com/auth/drive.metadata.readonly'
    ],
    client_id: ENV['GOOGLE_CLIENT_ID'],
    client_secret: ENV['GOOGLE_CLIENT_SECRET'],
    redirect_uri: 'https://app.agentmarketing.com/integrations/callback/google_drive',
    access_type: 'offline',
    prompt: 'consent'
  }
  i.metadata = {
    rate_limits: {
      queries_per_100_seconds: 1000,
      queries_per_100_seconds_per_user: 100
    }
  }
end

# Google Drive - Test Connection
google_drive.integration_operations.find_or_create_by!(
  operation_id: 'google_drive.test_connection.v3'
) do |op|
  op.name = 'Test Connection'
  op.description = 'Test if your Google Drive OAuth token is valid'
  op.http_method = 'GET'
  op.path_template = '/about?fields=user'  # Returns basic user info
  op.pagination_strategy = 'no_pagination'
  op.is_idempotent = true
  op.requires_confirmation = false
  op.request_schema = {
    type: 'object',
    properties: {}
  }
  op.documentation = 'Returns your Google Drive user info - used to verify OAuth token is working'
end

# Google Drive Operations
google_drive.integration_operations.find_or_create_by!(
  operation_id: 'google_drive.list_files.v3'
) do |op|
  op.name = 'List Files'
  op.description = 'List files and folders in Google Drive'
  op.http_method = 'GET'
  op.path_template = '/files'
  op.pagination_strategy = 'token'
  op.is_idempotent = true
  op.requires_confirmation = false
  op.max_limit = 1000
  op.request_schema = {
    type: 'object',
    properties: {
      q: {
        type: 'string',
        description: 'Query string for searching files'
      },
      pageSize: {
        type: 'integer',
        minimum: 1,
        maximum: 1000,
        default: 100
      },
      pageToken: {
        type: 'string',
        description: 'Page token for pagination'
      },
      orderBy: {
        type: 'string',
        description: 'Sort order (e.g., "modifiedTime desc")'
      },
      fields: {
        type: 'string',
        description: 'Fields to include in response'
      }
    }
  }
end

google_drive.integration_operations.find_or_create_by!(
  operation_id: 'google_drive.create_folder.v3'
) do |op|
  op.name = 'Create Folder'
  op.description = 'Create a new folder in Google Drive'
  op.http_method = 'POST'
  op.path_template = '/files'
  op.is_idempotent = false
  op.requires_confirmation = true
  op.request_schema = {
    type: 'object',
    required: [ 'name', 'mimeType' ],
    properties: {
      name: {
        type: 'string',
        description: 'Folder name'
      },
      mimeType: {
        type: 'string',
        enum: [ 'application/vnd.google-apps.folder' ],
        default: 'application/vnd.google-apps.folder'
      },
      parents: {
        type: 'array',
        items: { type: 'string' },
        description: 'Parent folder IDs'
      }
    }
  }
end

google_drive.integration_operations.find_or_create_by!(
  operation_id: 'google_drive.upload_file.v3'
) do |op|
  op.name = 'Upload File'
  op.description = 'Upload a file to Google Drive'
  op.http_method = 'POST'
  op.path_template = '/files'
  op.is_idempotent = false
  op.requires_confirmation = true
  op.request_schema = {
    type: 'object',
    required: [ 'name' ],
    properties: {
      name: {
        type: 'string',
        description: 'File name'
      },
      mimeType: {
        type: 'string',
        description: 'MIME type of the file'
      },
      parents: {
        type: 'array',
        items: { type: 'string' },
        description: 'Parent folder IDs'
      }
    }
  }
  op.documentation = 'This is a metadata-only operation. Actual file upload requires multipart request.'
end

# QuickBooks Integration
quickbooks = Integration.find_or_create_by!(slug: 'quickbooks') do |i|
  i.name = 'QuickBooks Online'
  i.category = 'accounting'
  i.auth_type = 'oauth2'
  i.api_base_url = 'https://sandbox-quickbooks.api.intuit.com/v3'  # Switch to production URL in prod
  i.allowed_hosts = [ 'sandbox-quickbooks.api.intuit.com', 'quickbooks.api.intuit.com' ]
  i.documentation_url = 'https://developer.intuit.com/app/developer/qbo/docs/api/accounting/all-entities/account'
  i.icon_url = 'https://quickbooks.intuit.com/etc/designs/qb-core/graphics/favicon.ico'
  i.description = 'Accounting software for invoicing, expenses, and financial reporting'
  i.is_active = true
  i.is_verified = true
  i.auth_config = {
    authorize_url: 'https://appcenter.intuit.com/connect/oauth2',
    token_url: 'https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer',
    scopes: [ 'com.intuit.quickbooks.accounting' ],
    use_basic_auth: true  # QuickBooks requires basic auth for token exchange
  }
  i.metadata = {
    api_version: 'v3',
    minor_version: '65',
    rate_limits: {
      per_minute: 500,
      concurrent_requests: 10
    },
    sandbox_url: 'https://sandbox-quickbooks.api.intuit.com/v3',
    production_url: 'https://quickbooks.api.intuit.com/v3'
  }
end

# QuickBooks - Test Connection
quickbooks.integration_operations.find_or_create_by!(
  operation_id: 'quickbooks.test_connection.v3'
) do |op|
  op.name = 'Test Connection'
  op.description = 'Test if your QuickBooks OAuth token is valid'
  op.http_method = 'GET'
  op.path_template = '/company/{companyId}/companyinfo/{companyId}'  # Returns company info
  op.pagination_strategy = 'no_pagination'
  op.is_idempotent = true
  op.requires_confirmation = false
  op.request_schema = {
    type: 'object',
    properties: {}
  }
  op.documentation = 'Returns your QuickBooks company info - used to verify OAuth token is working'
end

# QuickBooks Operations
quickbooks.integration_operations.find_or_create_by!(
  operation_id: 'quickbooks.create_invoice.v3'
) do |op|
  op.name = 'Create Invoice'
  op.description = 'Create a new invoice in QuickBooks'
  op.http_method = 'POST'
  op.path_template = '/company/{companyId}/invoice'
  op.is_idempotent = false
  op.requires_confirmation = true
  op.request_schema = {
    type: 'object',
    required: [ 'Line', 'CustomerRef' ],
    properties: {
      CustomerRef: {
        type: 'object',
        required: [ 'value' ],
        properties: {
          value: { type: 'string', description: 'Customer ID' }
        }
      },
      Line: {
        type: 'array',
        minItems: 1,
        items: {
          type: 'object',
          required: [ 'Amount', 'DetailType' ],
          properties: {
            Amount: { type: 'number' },
            Description: { type: 'string' },
            DetailType: { type: 'string', enum: [ 'SalesItemLineDetail' ] },
            SalesItemLineDetail: {
              type: 'object',
              properties: {
                ItemRef: {
                  type: 'object',
                  properties: {
                    value: { type: 'string' },
                    name: { type: 'string' }
                  }
                }
              }
            }
          }
        }
      },
      DueDate: {
        type: 'string',
        format: 'date',
        description: 'Invoice due date (YYYY-MM-DD)'
      },
      DocNumber: {
        type: 'string',
        description: 'Invoice number'
      }
    }
  }
end

quickbooks.integration_operations.find_or_create_by!(
  operation_id: 'quickbooks.list_customers.v3'
) do |op|
  op.name = 'List Customers'
  op.description = 'Retrieve a list of customers'
  op.http_method = 'GET'
  op.path_template = '/company/{companyId}/query'
  op.pagination_strategy = 'offset'
  op.is_idempotent = true
  op.requires_confirmation = false
  op.max_limit = 1000
  op.request_schema = {
    type: 'object',
    required: [ 'query' ],
    properties: {
      query: {
        type: 'string',
        description: 'SQL-like query (e.g., "SELECT * FROM Customer")',
        default: 'SELECT * FROM Customer'
      },
      startPosition: {
        type: 'integer',
        minimum: 1,
        default: 1
      },
      maxResults: {
        type: 'integer',
        minimum: 1,
        maximum: 1000,
        default: 100
      }
    }
  }
end

quickbooks.integration_operations.find_or_create_by!(
  operation_id: 'quickbooks.get_company_info.v3'
) do |op|
  op.name = 'Get Company Info'
  op.description = 'Retrieve company information'
  op.http_method = 'GET'
  op.path_template = '/company/{companyId}/companyinfo/{companyId}'
  op.is_idempotent = true
  op.requires_confirmation = false
end

quickbooks.integration_operations.find_or_create_by!(
  operation_id: 'quickbooks.create_payment.v3'
) do |op|
  op.name = 'Create Payment'
  op.description = 'Record a payment from a customer'
  op.http_method = 'POST'
  op.path_template = '/company/{companyId}/payment'
  op.is_idempotent = false
  op.requires_confirmation = true
  op.request_schema = {
    type: 'object',
    required: [ 'CustomerRef', 'TotalAmt' ],
    properties: {
      CustomerRef: {
        type: 'object',
        required: [ 'value' ],
        properties: {
          value: { type: 'string', description: 'Customer ID' }
        }
      },
      TotalAmt: {
        type: 'number',
        description: 'Total payment amount'
      },
      Line: {
        type: 'array',
        description: 'Invoice lines being paid',
        items: {
          type: 'object',
          properties: {
            Amount: { type: 'number' },
            LinkedTxn: {
              type: 'array',
              items: {
                type: 'object',
                properties: {
                  TxnId: { type: 'string' },
                  TxnType: { type: 'string', enum: [ 'Invoice' ] }
                }
              }
            }
          }
        }
      }
    }
  }
end

puts "✅ Seeded #{Integration.count} integrations with #{IntegrationOperation.count} operations"

# ================================
# OAuth Configurations
# ================================
puts "\n🔐 Configuring OAuth integrations..."

# Gmail OAuth Configuration
gmail = Integration.find_by(slug: 'gmail')
if gmail
  OauthConfiguration.find_or_create_by!(integration: gmail) do |config|
    config.client_id = ENV.fetch('GMAIL_CLIENT_ID', 'PLACEHOLDER_CLIENT_ID')
    config.client_secret = ENV.fetch('GMAIL_CLIENT_SECRET', 'PLACEHOLDER_CLIENT_SECRET')
    config.status = ENV['GMAIL_CLIENT_ID'].present? ? :active : :inactive
    config.authorize_url = 'https://accounts.google.com/o/oauth2/v2/auth'
    config.token_url = 'https://oauth2.googleapis.com/token'
    config.redirect_uri = "#{ENV.fetch('APP_URL', 'http://localhost:3000')}/oauth/callback"
    config.scopes = 'https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/gmail.send https://www.googleapis.com/auth/gmail.compose'
    config.metadata = {
      setup_instructions: 'Create OAuth credentials at https://console.cloud.google.com/',
      requires_client_credentials: true,
      access_type: 'offline',
      prompt: 'consent'
    }
  end
  puts "  ✓ Gmail OAuth configured (status: #{ENV['GMAIL_CLIENT_ID'].present? ? 'active' : 'inactive - needs credentials'})"
end

# Microsoft Outlook OAuth Configuration
outlook = Integration.find_by(slug: 'outlook')
if outlook
  OauthConfiguration.find_or_create_by!(integration: outlook) do |config|
    config.client_id = ENV.fetch('OUTLOOK_CLIENT_ID', 'PLACEHOLDER_CLIENT_ID')
    config.client_secret = ENV.fetch('OUTLOOK_CLIENT_SECRET', 'PLACEHOLDER_CLIENT_SECRET')
    config.status = ENV['OUTLOOK_CLIENT_ID'].present? ? :active : :inactive
    config.authorize_url = 'https://login.microsoftonline.com/common/oauth2/v2.0/authorize'
    config.token_url = 'https://login.microsoftonline.com/common/oauth2/v2.0/token'
    config.redirect_uri = "#{ENV.fetch('APP_URL', 'http://localhost:3000')}/oauth/callback"
    config.scopes = 'https://graph.microsoft.com/Mail.Read https://graph.microsoft.com/Mail.Send https://graph.microsoft.com/User.Read offline_access'
    config.metadata = {
      setup_instructions: 'Create an app registration at https://portal.azure.com/',
      requires_client_credentials: true
    }
  end
  puts "  ✓ Outlook OAuth configured (status: #{ENV['OUTLOOK_CLIENT_ID'].present? ? 'active' : 'inactive - needs credentials'})"
end

# QuickBooks OAuth Configuration
quickbooks = Integration.find_by(slug: 'quickbooks')
if quickbooks
  OauthConfiguration.find_or_create_by!(integration: quickbooks) do |config|
    config.client_id = 'PLACEHOLDER_CLIENT_ID'  # Admin will replace this
    config.client_secret = 'PLACEHOLDER_CLIENT_SECRET'  # Admin will replace this
    config.status = :inactive  # Admin needs to add real client_id and client_secret
    config.authorize_url = 'https://appcenter.intuit.com/connect/oauth2'
    config.token_url = 'https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer'
    config.redirect_uri = 'https://app.agentmarketing.com/integrations/callback/quickbooks'
    config.scopes = 'com.intuit.quickbooks.accounting'
    config.callback_params = ['realmId']  # Capture realmId from OAuth callback
    config.test_endpoint = 'company/{company_id}/companyinfo/{company_id}'  # No leading slash - URI.join handles it
    config.metadata = {
      setup_instructions: 'Create an OAuth app at https://developer.intuit.com/app/developer/myapps',
      requires_client_credentials: true
    }
  end
  puts "  ✓ QuickBooks OAuth configured (callback_params: realmId)"
end

puts "\n✅ OAuth configurations ready"
