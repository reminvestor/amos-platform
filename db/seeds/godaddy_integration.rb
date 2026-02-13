# GoDaddy Integration - DNS management for custom domains
#
# Allows users to automatically configure CNAME records for their
# landing pages, websites, and apps, as well as email verification records.

puts "🌐 Seeding GoDaddy integration..."

godaddy = Integration.find_or_create_by!(slug: 'godaddy') do |i|
  i.name = 'GoDaddy'
  i.category = 'custom'
  i.auth_type = 'api_key'
  i.api_base_url = 'https://api.godaddy.com'
  i.allowed_hosts = ['api.godaddy.com', 'api.ote-godaddy.com']
  i.documentation_url = 'https://developer.godaddy.com/doc'
  i.icon_url = 'https://www.godaddy.com/favicon.ico'
  i.description = 'Manage DNS records for custom domains. Auto-configure CNAME records for landing pages and email sending.'
  i.is_active = true
  i.is_verified = true
  i.auth_config = {
    auth_method: 'sso-key',
    api_key_label: 'API Key',
    api_key_placeholder: 'Your GoDaddy API Key',
    api_secret_label: 'API Secret',
    api_secret_placeholder: 'Your GoDaddy API Secret',
    header_name: 'Authorization',
    header_template: 'sso-key {api_key}:{api_secret}',
    test_endpoint: '/v1/domains',
    setup_instructions: <<~INSTRUCTIONS.strip
      1. Go to https://developer.godaddy.com/keys
      2. Create a new API Key (Production or OTE for testing)
      3. Copy your API Key and Secret
      4. The Authorization header will be: sso-key API_KEY:API_SECRET
    INSTRUCTIONS
  }
  i.metadata = {
    rate_limits: {
      default: 60,
      per: 'minute'
    },
    supports_ote: true,
    ote_base_url: 'https://api.ote-godaddy.com'
  }
end

# =========================================
# GoDaddy Operations
# =========================================

# List Domains
godaddy.integration_operations.find_or_create_by!(
  operation_id: 'godaddy.list_domains'
) do |op|
  op.name = 'List Domains'
  op.description = 'Returns all domains owned by the authenticated user'
  op.http_method = 'GET'
  op.path_template = '/v1/domains'
  op.pagination_strategy = 'offset'
  op.is_idempotent = true
  op.requires_confirmation = false
  op.request_schema = {
    type: 'object',
    properties: {
      statuses: {
        type: 'array',
        items: { type: 'string' },
        description: 'Filter by domain status (ACTIVE, CANCELLED, PENDING_TRANSFER, etc.)'
      },
      limit: {
        type: 'integer',
        description: 'Maximum number of domains to return',
        default: 100
      },
      marker: {
        type: 'string',
        description: 'Marker for pagination'
      }
    }
  }
  op.response_schema = {
    type: 'array',
    items: {
      type: 'object',
      properties: {
        domain: { type: 'string', description: 'Domain name' },
        status: { type: 'string', description: 'Domain status' },
        expires: { type: 'string', format: 'date-time' },
        expirationProtected: { type: 'boolean' },
        holdRegistrar: { type: 'boolean' },
        locked: { type: 'boolean' },
        privacy: { type: 'boolean' },
        renewAuto: { type: 'boolean' },
        renewable: { type: 'boolean' },
        transferProtected: { type: 'boolean' }
      }
    }
  }
  op.documentation = 'Lists all domains in your GoDaddy account. Use this to find domains available for custom domain setup.'
end

# Get Domain Details
godaddy.integration_operations.find_or_create_by!(
  operation_id: 'godaddy.get_domain'
) do |op|
  op.name = 'Get Domain Details'
  op.description = 'Returns detailed information about a specific domain'
  op.http_method = 'GET'
  op.path_template = '/v1/domains/{domain}'
  op.pagination_strategy = 'no_pagination'
  op.is_idempotent = true
  op.requires_confirmation = false
  op.request_schema = {
    type: 'object',
    properties: {
      domain: {
        type: 'string',
        description: 'Domain name to retrieve',
        required: true
      }
    },
    required: ['domain']
  }
  op.documentation = 'Get detailed information about a specific domain including DNS settings.'
end

# Get DNS Records
godaddy.integration_operations.find_or_create_by!(
  operation_id: 'godaddy.get_dns_records'
) do |op|
  op.name = 'Get DNS Records'
  op.description = 'Returns all DNS records for a domain'
  op.http_method = 'GET'
  op.path_template = '/v1/domains/{domain}/records'
  op.pagination_strategy = 'no_pagination'
  op.is_idempotent = true
  op.requires_confirmation = false
  op.request_schema = {
    type: 'object',
    properties: {
      domain: {
        type: 'string',
        description: 'Domain name',
        required: true
      },
      type: {
        type: 'string',
        description: 'Filter by record type (A, AAAA, CNAME, MX, TXT, etc.)'
      },
      name: {
        type: 'string',
        description: 'Filter by record name'
      }
    },
    required: ['domain']
  }
  op.response_schema = {
    type: 'array',
    items: {
      type: 'object',
      properties: {
        type: { type: 'string', description: 'Record type (A, AAAA, CNAME, MX, TXT, etc.)' },
        name: { type: 'string', description: 'Record name' },
        data: { type: 'string', description: 'Record value' },
        ttl: { type: 'integer', description: 'Time to live in seconds' },
        priority: { type: 'integer', description: 'Priority (for MX records)' }
      }
    }
  }
  op.documentation = 'Get all DNS records for a domain. Useful for checking existing configuration.'
end

# Add DNS Record
godaddy.integration_operations.find_or_create_by!(
  operation_id: 'godaddy.add_dns_record'
) do |op|
  op.name = 'Add DNS Record'
  op.description = 'Adds a new DNS record to a domain'
  op.http_method = 'PATCH'
  op.path_template = '/v1/domains/{domain}/records'
  op.pagination_strategy = 'no_pagination'
  op.is_idempotent = false
  op.requires_confirmation = true
  op.request_schema = {
    type: 'object',
    properties: {
      domain: {
        type: 'string',
        description: 'Domain name',
        required: true
      },
      records: {
        type: 'array',
        description: 'Array of DNS records to add',
        items: {
          type: 'object',
          properties: {
            type: {
              type: 'string',
              enum: ['A', 'AAAA', 'CNAME', 'MX', 'TXT', 'NS', 'SRV', 'CAA'],
              description: 'Record type'
            },
            name: {
              type: 'string',
              description: 'Record name (use @ for root domain)'
            },
            data: {
              type: 'string',
              description: 'Record value'
            },
            ttl: {
              type: 'integer',
              description: 'Time to live in seconds',
              default: 3600
            },
            priority: {
              type: 'integer',
              description: 'Priority (required for MX records)'
            }
          },
          required: ['type', 'name', 'data']
        }
      }
    },
    required: ['domain', 'records']
  }
  op.examples = {
    add_cname: {
      domain: 'example.com',
      records: [
        { type: 'CNAME', name: '@', data: 'abc123.custom.amoslabs.co', ttl: 3600 }
      ]
    },
    add_txt_for_email: {
      domain: 'example.com',
      records: [
        { type: 'TXT', name: '_dmarc', data: 'v=DMARC1; p=none;', ttl: 3600 }
      ]
    }
  }
  op.documentation = 'Add DNS records for custom domain configuration. Used for CNAME, DKIM, SPF, and DMARC records.'
end

# Replace DNS Records (for a specific type)
godaddy.integration_operations.find_or_create_by!(
  operation_id: 'godaddy.replace_dns_records'
) do |op|
  op.name = 'Replace DNS Records'
  op.description = 'Replaces all DNS records of a specific type for a domain'
  op.http_method = 'PUT'
  op.path_template = '/v1/domains/{domain}/records/{type}'
  op.pagination_strategy = 'no_pagination'
  op.is_idempotent = true
  op.requires_confirmation = true
  op.request_schema = {
    type: 'object',
    properties: {
      domain: {
        type: 'string',
        description: 'Domain name',
        required: true
      },
      type: {
        type: 'string',
        enum: ['A', 'AAAA', 'CNAME', 'MX', 'TXT', 'NS', 'SRV', 'CAA'],
        description: 'Record type to replace',
        required: true
      },
      records: {
        type: 'array',
        description: 'Array of replacement records',
        items: {
          type: 'object',
          properties: {
            name: { type: 'string', description: 'Record name' },
            data: { type: 'string', description: 'Record value' },
            ttl: { type: 'integer', default: 3600 },
            priority: { type: 'integer' }
          },
          required: ['name', 'data']
        }
      }
    },
    required: ['domain', 'type', 'records']
  }
  op.documentation = 'Replace all records of a specific type. Use with caution as it overwrites existing records.'
end

# Delete DNS Record
godaddy.integration_operations.find_or_create_by!(
  operation_id: 'godaddy.delete_dns_record'
) do |op|
  op.name = 'Delete DNS Record'
  op.description = 'Deletes a specific DNS record from a domain'
  op.http_method = 'DELETE'
  op.path_template = '/v1/domains/{domain}/records/{type}/{name}'
  op.pagination_strategy = 'no_pagination'
  op.is_idempotent = true
  op.requires_confirmation = true
  op.request_schema = {
    type: 'object',
    properties: {
      domain: {
        type: 'string',
        description: 'Domain name',
        required: true
      },
      type: {
        type: 'string',
        enum: ['A', 'AAAA', 'CNAME', 'MX', 'TXT', 'NS', 'SRV', 'CAA'],
        description: 'Record type',
        required: true
      },
      name: {
        type: 'string',
        description: 'Record name (use @ for root domain)',
        required: true
      }
    },
    required: ['domain', 'type', 'name']
  }
  op.documentation = 'Delete a specific DNS record. Use to clean up old configurations.'
end

# Verify Domain Ownership
godaddy.integration_operations.find_or_create_by!(
  operation_id: 'godaddy.verify_domain_ownership'
) do |op|
  op.name = 'Verify Domain Ownership'
  op.description = 'Check if you own a specific domain'
  op.http_method = 'GET'
  op.path_template = '/v1/domains/{domain}'
  op.pagination_strategy = 'no_pagination'
  op.is_idempotent = true
  op.requires_confirmation = false
  op.request_schema = {
    type: 'object',
    properties: {
      domain: {
        type: 'string',
        description: 'Domain name to verify',
        required: true
      }
    },
    required: ['domain']
  }
  op.documentation = 'Verify that you have control over a domain before setting up custom domain features.'
end

# =========================================
# GoDaddy OAuth Configuration + Auth Config
# (Required for IntegrationCredential#build_auth_header to work)
# =========================================

godaddy_oauth = OauthConfiguration.find_or_create_by!(integration: godaddy) do |config|
  config.status = :active
  config.test_endpoint = '/v1/domains'
end

# Ensure test_endpoint is set even if record already existed
godaddy_oauth.update!(test_endpoint: '/v1/domains') if godaddy_oauth.test_endpoint.blank?

# Auth header: Authorization: sso-key {api_key}:{api_secret}
godaddy_oauth.auth_configs.find_or_create_by!(auth_key: 'Authorization') do |ac|
  ac.auth_value = 'sso-key {api_key}:{api_secret}'
  ac.auth_placement = 'header'
  ac.position = 1
end

puts "  ✅ GoDaddy integration seeded with #{godaddy.integration_operations.count} operations and auth config"
