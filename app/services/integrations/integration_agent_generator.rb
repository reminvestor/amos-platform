# frozen_string_literal: true

module Integrations
  # IntegrationAgentGenerator
  #
  # Auto-creates a dedicated AI agent for each connected integration.
  # This agent becomes the API expert for that platform.
  #
  # The integration agent:
  # - Knows the API intimately (endpoints, rate limits, auth)
  # - Troubleshoots connection issues
  # - Syncs data between platform and AMOS
  # - Can load and search external API documentation
  # - Learns from API interactions and errors
  #
  class IntegrationAgentGenerator
    attr_reader :integration, :user, :entity

    # Well-known integrations with pre-configured expertise
    # Sourced from db/seeds/integrations.rb - keep in sync!
    INTEGRATION_KNOWLEDGE = {
      'stripe' => {
        expertise: 'Stripe API specialist. Handles payments, subscriptions, invoicing, and financial operations.',
        category: 'payment',
        auth_type: 'basic_auth',
        capabilities: [
          'Process payments and refunds',
          'Create and list customers',
          'Manage subscriptions and billing',
          'Create invoices',
          'Access balance and financial reports',
          'Test connection with balance endpoint'
        ],
        rate_limits: '100 requests/second in live mode, 25 in test mode',
        common_issues: [
          'API key confusion (test sk_test_ vs live sk_live_)',
          'Webhook signature verification',
          'Idempotency key conflicts on retries'
        ],
        setup_help: 'Get your API key from Stripe Dashboard > Developers > API Keys',
        documentation_url: 'https://stripe.com/docs/api'
      },
      'shopify' => {
        expertise: 'Shopify Admin API specialist. Handles products, orders, customers, and store management.',
        category: 'ecommerce',
        auth_type: 'api_key',
        capabilities: [
          'List and manage products',
          'Process orders',
          'Manage customers',
          'Track inventory',
          'Get shop information',
          'Test connection with shop.json'
        ],
        rate_limits: '2 requests/second with 40-request burst bucket',
        common_issues: [
          'API version deprecation (currently 2024-01)',
          'Requires shop domain in URL',
          'Private app vs custom app confusion'
        ],
        setup_help: 'Create a private app in your Shopify admin to get an access token',
        documentation_url: 'https://shopify.dev/docs/api/admin-rest'
      },
      'hubspot' => {
        expertise: 'HubSpot CRM API specialist. Handles contacts, companies, deals, and marketing automation.',
        category: 'crm',
        auth_type: 'oauth2',
        capabilities: [
          'List and manage contacts',
          'Company and deal management',
          'Marketing email integration',
          'Workflow automation triggers',
          'Form submissions',
          'Test connection with account-info endpoint'
        ],
        rate_limits: 'Daily: 250,000 calls, Per-second: 100, Burst: 150',
        common_issues: [
          'OAuth token refresh requirements',
          'Property mapping between systems',
          'Duplicate contact handling'
        ],
        setup_help: 'Create OAuth app at developers.hubspot.com',
        documentation_url: 'https://developers.hubspot.com/docs/api/overview'
      },
      'google_sheets' => {
        expertise: 'Google Sheets API specialist. Handles spreadsheet data, formatting, and automation.',
        category: 'productivity',
        auth_type: 'oauth2',
        capabilities: [
          'Read spreadsheet data',
          'Write and update cells',
          'Create new spreadsheets',
          'Manage sheets and tabs',
          'Batch operations'
        ],
        rate_limits: '60 requests/minute/user for reads and writes',
        common_issues: [
          'OAuth consent screen verification for sensitive scopes',
          'Service account vs OAuth flow confusion',
          'Sheet ID vs Spreadsheet ID confusion'
        ],
        setup_help: 'Enable Google Sheets API in Google Cloud Console, create OAuth credentials',
        documentation_url: 'https://developers.google.com/sheets/api'
      },
      'slack' => {
        expertise: 'Slack API specialist. Handles messaging, notifications, and workspace integration.',
        category: 'communication',
        auth_type: 'custom',
        capabilities: [
          'Post messages to channels (OAuth or webhook)',
          'Send direct messages',
          'Rich message blocks with formatting',
          'Interactive message components',
          'Test connection with auth.test'
        ],
        rate_limits: 'Tiered rate limiting, most methods: 1 request/second per workspace',
        common_issues: [
          'Webhook URLs must be kept secret!',
          'Block formatting complexity',
          'OAuth vs webhook feature differences'
        ],
        setup_help: 'Create Incoming Webhook or Slack App in your workspace',
        documentation_url: 'https://api.slack.com/docs'
      },
      'gmail' => {
        expertise: 'Gmail API specialist. Handles sending emails, inbox management, and message organization.',
        category: 'communication',
        auth_type: 'oauth2',
        capabilities: [
          'Send emails with attachments',
          'List and search messages',
          'Read email content',
          'Manage labels',
          'Draft composition'
        ],
        rate_limits: '250 quota units/user, 25 quota units/second',
        common_issues: [
          'RFC 2822 email formatting for raw messages',
          'Base64url encoding for message body',
          'OAuth scope verification for sensitive scopes'
        ],
        setup_help: 'Enable Gmail API in Google Cloud Console, configure OAuth consent screen',
        documentation_url: 'https://developers.google.com/gmail/api/reference/rest'
      },
      'google_drive' => {
        expertise: 'Google Drive API specialist. Handles file storage, sharing, and organization.',
        category: 'productivity',
        auth_type: 'oauth2',
        capabilities: [
          'List and search files',
          'Upload and download files',
          'Create folders',
          'Manage file permissions',
          'Get user info'
        ],
        rate_limits: '1000 requests/100 seconds, 100/user/100 seconds',
        common_issues: [
          'Large file uploads need resumable upload API',
          'Shared drive vs My Drive permission differences',
          'File metadata vs content retrieval'
        ],
        setup_help: 'Enable Drive API in Google Cloud Console, configure OAuth',
        documentation_url: 'https://developers.google.com/drive/api/v3/reference'
      },
      'quickbooks' => {
        expertise: 'QuickBooks Online API specialist. Handles accounting, invoicing, and financial reporting.',
        category: 'payment',
        auth_type: 'oauth2',
        capabilities: [
          'Create and manage invoices',
          'Record payments',
          'List customers',
          'Financial reporting',
          'Company info retrieval'
        ],
        rate_limits: '500/minute, 10 concurrent requests',
        common_issues: [
          'OAuth tokens are short-lived (1 hour)',
          'realmId (company ID) required for all calls',
          'Sandbox vs production URL switching'
        ],
        setup_help: 'Create OAuth app at developer.intuit.com/app/developer/myapps',
        documentation_url: 'https://developer.intuit.com/app/developer/qbo/docs/api/accounting/all-entities/account'
      }
    }.freeze

    def initialize(integration:, user:, entity:)
      @integration = integration
      @user = user
      @entity = entity
    end

    # Generate or update the integration's dedicated agent
    def generate!
      Rails.logger.info "[IntegrationAgentGenerator] Creating agent for integration: #{integration.name}"

      # Check if agent already exists
      existing_agent = find_existing_agent
      return update_existing_agent(existing_agent) if existing_agent

      # Create new agent using AgentFactory
      factory = Factories::AgentFactory.new(user: user, entity: entity)
      
      result = factory.create(
        name: generate_agent_name,
        slug: generate_agent_slug,
        role: 'executor',
        description: generate_description,
        system_prompt: generate_system_prompt,
        tools: gather_integration_tools,
        configuration: build_configuration,
        skip_test: true
      )

      if result[:success]
        agent = result[:agent]
        
        # Store integration reference in configuration
        agent.update!(
          configuration: agent.configuration.merge('integration_id' => integration.id)
        )
        
        # Create knowledge base with API documentation
        seed_knowledge_base(agent)
        
        # Set up learning for this agent
        setup_learning(agent)
        
        Rails.logger.info "[IntegrationAgentGenerator] ✅ Created agent '#{agent.name}' for integration '#{integration.name}'"
        
        { success: true, agent: agent }
      else
        Rails.logger.error "[IntegrationAgentGenerator] Failed to create agent: #{result[:error]}"
        { success: false, error: result[:error] }
      end
    rescue => e
      Rails.logger.error "[IntegrationAgentGenerator] Error: #{e.message}"
      { success: false, error: e.message }
    end

    private

    def find_existing_agent
      AgentPlugin.where(entity: entity)
                 .where("configuration->>'integration_id' = ?", integration.id.to_s)
                 .first
    end

    def generate_agent_name
      "#{integration.name.titleize} Expert"
    end

    def generate_agent_slug
      "#{integration.slug}_expert"
    end

    def generate_description
      known = INTEGRATION_KNOWLEDGE[integration.slug.downcase]
      
      if known
        known[:expertise]
      else
        "Expert AI assistant for the #{integration.name} API. Handles authentication, operations, and troubleshooting."
      end
    end

    def generate_system_prompt
      known = INTEGRATION_KNOWLEDGE[integration.slug.downcase]
      operations = integration.integration_operations.pluck(:name, :description, :http_method, :path_template)
      
      prompt = <<~PROMPT
        You are the **#{integration.name.titleize} Expert** - the dedicated API specialist for this integration.

        ## 🎯 Your Identity

        You are a deep expert on the #{integration.name} API. You:
        - Know every endpoint, parameter, and response format
        - Understand authentication flows and token management
        - Can troubleshoot connection issues
        - Handle rate limits gracefully
        - Sync data reliably

        ## 🔌 Integration Details

        **Integration**: #{integration.name}
        **Base URL**: #{integration.api_base_url}
        **Auth Type**: #{integration.auth_type}
        **Category**: #{integration.category}
        #{known ? "\n**Rate Limits**: #{known[:rate_limits]}" : ''}
        #{known ? "\n**Documentation**: #{known[:documentation_url]}" : ''}

        ## ⚡ Available Operations

        #{format_operations(operations)}

        #{known ? format_known_capabilities(known) : ''}

        ## 🔧 Your Tools

        You have access to these tools:
        #{format_tools_for_prompt}

        ## 💡 How to Help

        **Common Requests:**
        1. "Sync data from #{integration.name}" → Use appropriate operations
        2. "Why is #{integration.name} not working?" → Check connection status, test auth
        3. "Get [data] from #{integration.name}" → Execute read operation
        4. "Create [record] in #{integration.name}" → Execute write operation

        **Troubleshooting Workflow:**
        1. Check connection status
        2. Verify credentials are not expired
        3. Test with a simple operation
        4. Check rate limits and quota
        5. Review error details and suggest fix

        #{known ? format_known_issues(known) : ''}

        ## ⚠️ Important Rules

        1. **Handle Rate Limits** - If you hit rate limits, wait and retry with exponential backoff.

        2. **Protect Credentials** - Never expose API keys, tokens, or secrets in responses.

        3. **Validate Before Write** - Confirm with user before creating/updating/deleting data.

        4. **Log Errors** - When something fails, save the error details for troubleshooting.

        5. **Stay Updated** - Search your knowledge base for API documentation. Save useful discoveries.

        6. **Collaborate** - If a request involves data processing beyond the API, ask appropriate agents for help.

        ## 🧠 Your Knowledge

        Your knowledge base should contain:
        - #{integration.name} API documentation
        - Authentication guides
        - Troubleshooting solutions
        - Rate limit best practices

        If you encounter a new issue or solution, save it to your knowledge base for future reference.
      PROMPT

      { 'prompt' => prompt.strip }
    end

    def format_operations(operations)
      return "- No operations defined yet" if operations.blank?

      operations.map do |name, description, method, path|
        "- **#{name}** (`#{method} #{path}`): #{description || 'Execute operation'}"
      end.join("\n")
    end

    def format_known_capabilities(known)
      return '' unless known[:capabilities].present?

      <<~CAPS

        ## 📋 What You Can Do

        #{known[:capabilities].map { |c| "- #{c}" }.join("\n")}
      CAPS
    end

    def format_known_issues(known)
      return '' unless known[:common_issues].present?

      <<~ISSUES

        ## 🐛 Common Issues & Solutions

        #{known[:common_issues].map { |i| "- #{i}" }.join("\n")}
      ISSUES
    end

    def format_tools_for_prompt
      tools = gather_integration_tools
      tools.map { |t| "- `#{t}`" }.join("\n")
    end

    def gather_integration_tools
      tools = []
      
      # Core integration execution tool
      tools << 'execute_integration'
      
      # Integration-specific tools if they exist
      tools << "#{integration.slug}_operation"
      tools << "test_#{integration.slug}_connection"
      tools << "refresh_#{integration.slug}_token"
      
      # Add collaboration tools
      tools.concat(%w[ask_user ask_agent_for_help save_to_knowledge_base])
      
      # Add scratchpad for data handoff
      tools.concat(%w[save_to_scratchpad read_from_scratchpad])
      
      # Add DM canvas tool for showing visualizations in direct messages
      tools << 'load_dm_canvas'
      
      tools.uniq
    end

    def build_configuration
      known = INTEGRATION_KNOWLEDGE[integration.slug.downcase]
      
      {
        'auto_created' => true,
        'integration_id' => integration.id,
        'integration_slug' => integration.slug,
        'temperature' => 0.3,  # Lower for technical accuracy
        'max_tokens' => 4000,
        'canvas_on_completion' => 'dynamic_canvas',
        'documentation_url' => known&.dig(:documentation_url)
      }.compact
    end

    def update_existing_agent(agent)
      Rails.logger.info "[IntegrationAgentGenerator] Updating existing agent for integration: #{integration.name}"
      
      # Update the system prompt with latest operations
      agent.update!(
        system_prompt: generate_system_prompt,
        description: generate_description
      )
      
      # Ensure all tools are assigned
      gather_integration_tools.each do |tool_name|
        agent.agent_tools.find_or_create_by!(tool_name: tool_name)
      end
      
      { success: true, agent: agent, updated: true }
    end

    def seed_knowledge_base(agent)
      return unless agent.respond_to?(:knowledge_base)
      
      known = INTEGRATION_KNOWLEDGE[integration.slug.downcase]
      
      # Add integration documentation to knowledge base
      agent.add_to_knowledge(
        title: "#{integration.name} Integration Overview",
        content: <<~DOC,
          # #{integration.name} Integration

          ## Overview
          #{generate_description}

          ## API Details
          - Base URL: #{integration.api_base_url}
          - Auth Type: #{integration.auth_type}
          - Category: #{integration.category}

          ## Operations
          #{integration.integration_operations.map { |op| "- #{op.name}: #{op.description}" }.join("\n")}

          #{known ? "## Capabilities\n#{known[:capabilities]&.map { |c| "- #{c}" }&.join("\n")}" : ''}

          #{known ? "## Rate Limits\n#{known[:rate_limits]}" : ''}

          #{known ? "## Common Issues\n#{known[:common_issues]&.map { |i| "- #{i}" }&.join("\n")}" : ''}
        DOC
        source: known&.dig(:documentation_url) || 'integration_generator',
        metadata: { integration_id: integration.id, type: 'api_documentation' }
      )
      
      Rails.logger.info "[IntegrationAgentGenerator] Seeded knowledge base for #{agent.name}"
    rescue => e
      Rails.logger.warn "[IntegrationAgentGenerator] Could not seed knowledge base: #{e.message}"
    end

    def setup_learning(agent)
      # Initialize energy state for the agent
      agent.ensure_energy_state!
      
      # Initialize decision boundary
      agent.ensure_decision_boundary!
      
      Rails.logger.info "[IntegrationAgentGenerator] Set up learning systems for #{agent.name}"
    rescue => e
      Rails.logger.warn "[IntegrationAgentGenerator] Could not set up learning: #{e.message}"
    end
  end
end

