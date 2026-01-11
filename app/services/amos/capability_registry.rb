# frozen_string_literal: true

module Amos
  # CapabilityRegistry - The central source of truth for what AMOS and the platform can do
  #
  # This registry tells AMOS:
  # 1. What he can do directly (with tools)
  # 2. What specialized agents can do
  # 3. What's not built yet (be honest!)
  # 4. How to route requests intelligently
  #
  class CapabilityRegistry
    attr_reader :entity

    def initialize(entity)
      @entity = entity
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # DIRECT CAPABILITIES (What AMOS does himself with tools)
    # ═══════════════════════════════════════════════════════════════════════════

    DIRECT_CAPABILITIES = {
      # Communication
      send_email: {
        name: 'Send Email',
        description: 'Compose and send emails to contacts',
        tool: 'send_email',
        category: :communication,
        examples: ['Send an email to John', 'Email the client about the proposal']
      },
      search_contacts: {
        name: 'Search Contacts',
        description: 'Find contacts by name, email, company, or other criteria',
        tool: 'search_contacts',
        category: :data,
        examples: ['Find contacts at Acme Corp', 'Look up John Smith']
      },
      create_contact: {
        name: 'Create Contact',
        description: 'Add a new contact to the CRM',
        tool: 'create_contact',
        category: :data,
        examples: ['Add a new contact', 'Create a contact for Jane Doe']
      },

      # Knowledge
      search_documents: {
        name: 'Search Documents',
        description: 'Search through uploaded documents and knowledge base',
        tool: 'search_documents',
        category: :knowledge,
        examples: ['Find documents about pricing', 'Search for the contract template']
      },
      answer_from_knowledge: {
        name: 'Answer from Knowledge',
        description: 'Answer questions using the knowledge base',
        tool: 'rag_search',
        category: :knowledge,
        examples: ['What is our refund policy?', 'How do I reset my password?']
      },

      # Support
      create_ticket: {
        name: 'Create Support Ticket',
        description: 'Report bugs, issues, or feature requests',
        tool: 'create_support_ticket',
        category: :support,
        examples: ['Report a bug', 'Something is not working', 'I found an issue']
      },
      check_ticket: {
        name: 'Check Ticket Status',
        description: 'Check status of existing support tickets',
        tool: 'check_ticket_status',
        category: :support,
        examples: ['What\'s the status of my ticket?', 'Check on AMOS-00001']
      },

      # Platform
      check_platform_health: {
        name: 'Platform Health',
        description: 'Check current platform health and status',
        tool: 'platform_status',
        category: :platform,
        examples: ['How is the platform doing?', 'Any issues right now?']
      },

      # Scheduling
      schedule_task: {
        name: 'Schedule Task',
        description: 'Schedule automated tasks to run later or on a recurring basis',
        tool: 'schedule_agent_task',
        category: :automation,
        examples: ['Remind me tomorrow', 'Schedule a weekly report']
      }
    }.freeze

    # ═══════════════════════════════════════════════════════════════════════════
    # AGENT CAPABILITIES (What specialized agents can do)
    # ═══════════════════════════════════════════════════════════════════════════

    AGENT_CAPABILITY_TEMPLATES = {
      # ═══════════════════════════════════════════════════════════════════
      # MODULE AGENTS - Auto-created for each custom module
      # These are dynamically added when modules are built
      # ═══════════════════════════════════════════════════════════════════
      module_assistant: {
        name: 'Module Assistant (Template)',
        description: 'Auto-created for each module built by Platform Factory',
        specializations: [
          'Module data CRUD operations',
          'Module-specific analysis',
          'Running scheduled tasks for the module',
          'Responding to module webhooks',
          'Domain expertise for the module'
        ],
        when_to_delegate: [
          'Work with [module_name] data',
          'Create a new [record type]',
          'Run the [module_name] report',
          'Analyze my [module_name]'
        ],
        category: :module,
        auto_created: true
      },
      
      # ═══════════════════════════════════════════════════════════════════
      # INTEGRATION AGENTS - Auto-created for connected integrations
      # These become API experts for each platform
      # ═══════════════════════════════════════════════════════════════════
      integration_expert: {
        name: 'Integration Expert (Template)',
        description: 'Auto-created when an integration is connected',
        specializations: [
          'API operations and endpoints',
          'Authentication and token management',
          'Rate limit handling',
          'Data synchronization',
          'Troubleshooting connection issues'
        ],
        when_to_delegate: [
          'Sync data from [platform]',
          'Why is [platform] not working',
          'Post to [platform]',
          'Get data from [platform]'
        ],
        category: :integration,
        auto_created: true
      },
      
      # ═══════════════════════════════════════════════════════════════════
      # SYSTEM AGENTS - Pre-built specialists
      # ═══════════════════════════════════════════════════════════════════
      marketing_agent: {
        name: 'Marketing Agent',
        specializations: [
          'Campaign creation and management',
          'Email marketing content',
          'Social media content',
          'Audience segmentation',
          'Marketing analytics'
        ],
        when_to_delegate: [
          'Create a marketing campaign',
          'Write marketing copy',
          'Analyze campaign performance',
          'Segment our audience'
        ],
        category: :marketing
      },
      sales_agent: {
        name: 'Sales Agent',
        specializations: [
          'Lead scoring and qualification',
          'Pipeline management',
          'Deal analysis',
          'Sales forecasting',
          'Outreach sequences'
        ],
        when_to_delegate: [
          'Score my leads',
          'Analyze the sales pipeline',
          'Create a follow-up sequence',
          'Forecast sales for next quarter'
        ],
        category: :sales
      },
      content_agent: {
        name: 'Content Agent',
        specializations: [
          'Blog posts and articles',
          'Website copy',
          'Product descriptions',
          'Case studies',
          'Long-form content'
        ],
        when_to_delegate: [
          'Write a blog post',
          'Create product descriptions',
          'Draft a case study',
          'Update our website copy'
        ],
        category: :content
      },
      data_analyst_agent: {
        name: 'Data Analyst Agent',
        specializations: [
          'Data analysis and insights',
          'Report generation',
          'Trend identification',
          'Performance metrics',
          'Data visualization'
        ],
        when_to_delegate: [
          'Analyze our data',
          'Create a report',
          'What are the trends?',
          'Show me performance metrics'
        ],
        category: :analytics
      },
      customer_success_agent: {
        name: 'Customer Success Agent',
        specializations: [
          'Customer health monitoring',
          'Churn prediction',
          'Onboarding assistance',
          'Renewal management',
          'Customer feedback analysis'
        ],
        when_to_delegate: [
          'Check on our at-risk customers',
          'Create an onboarding plan',
          'Analyze customer feedback',
          'Which customers might churn?'
        ],
        category: :customer_success
      },
      platform_factory: {
        name: 'Platform Factory',
        specializations: [
          'Custom module design',
          'Module creation and building',
          'Database schema design',
          'Canvas and UI generation',
          'Inventory management systems',
          'Project tracking systems',
          'CRM extensions',
          'Custom data tracking'
        ],
        when_to_delegate: [
          'Build a module',
          'Create a module',
          'Install a module',
          'Design a module',
          'I want to build',
          'I need a custom',
          'Create an inventory',
          'Build an inventory',
          'Track my inventory',
          'Project management',
          'Custom software',
          'Design software for me'
        ],
        category: :platform
      },
      module_architect: {
        name: 'Module Architect',
        specializations: [
          'Module fixes and repairs',
          'Schema updates',
          'Canvas fixes',
          'Adding fields to modules',
          'Module troubleshooting'
        ],
        when_to_delegate: [
          'Fix my module',
          'Update the module',
          'Add a field to',
          'The module is broken',
          'Canvas not working'
        ],
        category: :platform
      }
    }.freeze

    # ═══════════════════════════════════════════════════════════════════════════
    # NOT YET AVAILABLE (Be honest about limitations)
    # ═══════════════════════════════════════════════════════════════════════════

    NOT_YET_AVAILABLE = [
      {
        capability: 'Video generation',
        status: :not_planned,
        alternative: 'I can help you write video scripts or storyboards'
      },
      {
        capability: 'Real-time voice calls',
        status: :planned,
        alternative: 'I can help you prepare for calls or draft follow-up emails'
      },
      {
        capability: 'Direct database access',
        status: :not_available,
        alternative: 'I can search and retrieve data through our secure tools'
      },
      {
        capability: 'Payment processing',
        status: :not_available,
        alternative: 'I can help you create invoices or payment links'
      },
      {
        capability: 'Code deployment',
        status: :human_only,
        alternative: 'I can create a PR for review, but deployment requires human approval'
      },
      {
        capability: 'Deleting user data',
        status: :human_only,
        alternative: 'I can create a request for data deletion that requires admin approval'
      }
    ].freeze

    # ═══════════════════════════════════════════════════════════════════════════
    # QUERIES
    # ═══════════════════════════════════════════════════════════════════════════

    def direct_capabilities
      DIRECT_CAPABILITIES
    end

    def available_agents
      @available_agents ||= begin
        entity.agent_plugins.where(status: 'active').map do |agent|
          template = AGENT_CAPABILITY_TEMPLATES[agent.slug.to_sym] || {}
          
          # Determine agent type and category
          agent_type = determine_agent_type(agent)
          
          {
            id: agent.id,
            name: agent.name,
            slug: agent.slug,
            description: agent.description,
            specializations: template[:specializations] || infer_specializations(agent, agent_type),
            when_to_delegate: template[:when_to_delegate] || infer_delegation_triggers(agent, agent_type),
            category: template[:category] || agent_type,
            agent_type: agent_type,
            module_id: agent.app_module_id,
            integration_id: agent.configuration&.dig('integration_id')
          }
        end
      end
    end
    
    # Get all module agents
    def module_agents
      available_agents.select { |a| a[:agent_type] == :module }
    end
    
    # Get all integration agents
    def integration_agents
      available_agents.select { |a| a[:agent_type] == :integration }
    end
    
    # Get agent for a specific module
    def agent_for_module(app_module)
      module_id = app_module.is_a?(AppModule) ? app_module.id : app_module
      available_agents.find { |a| a[:module_id] == module_id }
    end
    
    # Get agent for a specific integration
    def agent_for_integration(integration)
      integration_id = integration.is_a?(Integration) ? integration.id : integration
      available_agents.find { |a| a[:integration_id]&.to_i == integration_id.to_i }
    end

    def agent_by_slug(slug)
      available_agents.find { |a| a[:slug] == slug.to_s }
    end

    def agent_for_task(task_description)
      # Find the best agent for a task based on specializations
      task_lower = task_description.downcase

      available_agents.max_by do |agent|
        relevance = 0

        # Check specializations
        agent[:specializations].each do |spec|
          relevance += 10 if task_lower.include?(spec.downcase.split.first)
        end

        # Check delegate examples
        agent[:when_to_delegate].each do |example|
          relevance += 20 if task_lower.include?(example.downcase.split.first(3).join(' '))
        end

        relevance
      end
    end

    def limitations
      NOT_YET_AVAILABLE
    end

    def can_do?(capability_name)
      DIRECT_CAPABILITIES.key?(capability_name.to_sym) ||
        available_agents.any? { |a| a[:specializations].any? { |s| s.downcase.include?(capability_name.downcase) } }
    end

    def limitation_for(capability_name)
      NOT_YET_AVAILABLE.find { |l| l[:capability].downcase.include?(capability_name.downcase) }
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # SUMMARY FOR SYSTEM PROMPT
    # ═══════════════════════════════════════════════════════════════════════════

    def summary_for_prompt
      {
        direct_tools: DIRECT_CAPABILITIES.keys.count,
        direct_capabilities: DIRECT_CAPABILITIES.map { |k, v| { name: v[:name], description: v[:description] } },
        available_agents: available_agents.map { |a| { name: a[:name], specializations: a[:specializations] } },
        agent_count: available_agents.count,
        known_limitations: NOT_YET_AVAILABLE.map { |l| l[:capability] }
      }
    end

    def capabilities_text
      text = "## Your Direct Capabilities (use tools)\n"
      DIRECT_CAPABILITIES.each do |key, cap|
        text += "- **#{cap[:name]}**: #{cap[:description]}\n"
      end

      text += "\n## Specialized Agents Available\n"
      available_agents.each do |agent|
        text += "- **#{agent[:name]}**: #{agent[:specializations].join(', ')}\n"
      end
      
      # Add module agents section
      if module_agents.any?
        text += "\n## Module Experts (Your Custom Apps)\n"
        module_agents.each do |agent|
          text += "- **#{agent[:name]}**: Expert on your #{agent[:name].gsub(' Assistant', '')} data\n"
        end
      end
      
      # Add integration agents section
      if integration_agents.any?
        text += "\n## Integration Experts (API Specialists)\n"
        integration_agents.each do |agent|
          text += "- **#{agent[:name]}**: API expert for #{agent[:name].gsub(' Expert', '')}\n"
        end
      end

      text += "\n## What You Cannot Do (be honest!)\n"
      NOT_YET_AVAILABLE.each do |limit|
        text += "- #{limit[:capability]} - Alternative: #{limit[:alternative]}\n"
      end

      text
    end
    
    private
    
    # Determine agent type based on associations and configuration
    def determine_agent_type(agent)
      if agent.app_module_id.present?
        :module
      elsif agent.configuration&.dig('integration_id').present?
        :integration
      elsif AGENT_CAPABILITY_TEMPLATES[agent.slug.to_sym].present?
        AGENT_CAPABILITY_TEMPLATES[agent.slug.to_sym][:category] || :system
      else
        :general
      end
    end
    
    # Infer specializations for dynamically created agents
    def infer_specializations(agent, agent_type)
      case agent_type
      when :module
        module_obj = agent.app_module
        module_name = module_obj&.name || agent.name.gsub(' Assistant', '')
        [
          "#{module_name} data management",
          "Creating and updating #{module_name.downcase} records",
          "#{module_name} reports and analysis",
          "#{module_name} scheduled tasks",
          "#{module_name} domain expertise"
        ]
      when :integration
        integration_name = agent.name.gsub(' Expert', '')
        [
          "#{integration_name} API operations",
          "#{integration_name} authentication",
          "#{integration_name} data sync",
          "#{integration_name} troubleshooting",
          "#{integration_name} rate limit handling"
        ]
      else
        [agent.description.presence || 'General assistance']
      end
    end
    
    # Infer when to delegate to this agent
    def infer_delegation_triggers(agent, agent_type)
      case agent_type
      when :module
        module_obj = agent.app_module
        module_name = module_obj&.name || agent.name.gsub(' Assistant', '')
        [
          "Work with #{module_name.downcase}",
          "Create a #{module_name.singularize.downcase}",
          "Show my #{module_name.downcase}",
          "#{module_name} report",
          "Analyze my #{module_name.downcase}"
        ]
      when :integration
        integration_name = agent.name.gsub(' Expert', '')
        [
          "Sync from #{integration_name}",
          "Post to #{integration_name}",
          "Get data from #{integration_name}",
          "#{integration_name} not working",
          "Connect to #{integration_name}"
        ]
      else
        []
      end
    end
  end
end

