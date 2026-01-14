# frozen_string_literal: true

module Modules
  # ModuleAgentGenerator
  #
  # Auto-creates a dedicated AI agent for each module.
  # This agent becomes the expert on that module's domain.
  #
  # The module agent:
  # - Has deep knowledge of the module's schema and purpose
  # - Has access to all module-specific tools
  # - Runs scheduled tasks for the module
  # - Responds to webhooks for the module
  # - Participates in Hub collaboration
  # - Learns from interactions and builds domain expertise
  #
  class ModuleAgentGenerator
    attr_reader :app_module, :user, :entity

    def initialize(app_module:, user:, entity:)
      @app_module = app_module
      @user = user
      @entity = entity
    end

    # Generate or update the module's dedicated agent
    def generate!
      Rails.logger.info "[ModuleAgentGenerator] Creating agent for module: #{app_module.name}"

      # Check if agent already exists (module has_many agent_plugins, use first as primary)
      existing_agent = app_module.agent_plugins.first
      return update_existing_agent(existing_agent) if existing_agent

      # Create new agent using AgentFactory
      factory = Factories::AgentFactory.new(user: user, entity: entity)
      
      result = factory.create(
        name: generate_agent_name,
        slug: generate_agent_slug,
        role: 'executor',
        description: generate_description,
        system_prompt: generate_system_prompt,
        tools: gather_module_tools,
        configuration: build_configuration,
        skip_test: true  # Skip test during creation - module is new
      )

      if result[:success]
        agent = result[:agent]
        
        # Link agent to module (agent belongs_to app_module)
        agent.update!(app_module: app_module)
        
        # Create knowledge base with module documentation
        seed_knowledge_base(agent)
        
        # Set up learning for this agent
        setup_learning(agent)
        
        Rails.logger.info "[ModuleAgentGenerator] ✅ Created agent '#{agent.name}' for module '#{app_module.name}'"
        
        { success: true, agent: agent }
      else
        Rails.logger.error "[ModuleAgentGenerator] Failed to create agent: #{result[:error]}"
        { success: false, error: result[:error] }
      end
    rescue => e
      Rails.logger.error "[ModuleAgentGenerator] Error: #{e.message}"
      { success: false, error: e.message }
    end

    private

    def generate_agent_name
      "#{app_module.name} Assistant"
    end

    def generate_agent_slug
      "#{app_module.slug}_assistant"
    end

    def generate_description
      base = "Expert AI assistant for the #{app_module.name} module. "
      base += app_module.description.presence || "Manages all aspects of #{app_module.name} data."
      base
    end

    def generate_system_prompt
      schema = app_module.metadata.dig('schema') || app_module.metadata.dig('schema_design', 'schema') || {}
      fields = schema['fields'] || []
      integrations = schema['integrations'] || []
      workflows = schema['workflows'] || []
      scheduled_tasks = schema['scheduled_tasks'] || []

      prompt = <<~PROMPT
        You are the **#{app_module.name} Assistant** - the dedicated AI expert for this module.

        ## 🎯 Your Identity

        You are a specialist who deeply understands the #{app_module.name} system. You:
        - Know every field, relationship, and workflow in this module
        - Can create, update, search, and analyze #{app_module.name} data
        - Run scheduled tasks and respond to events
        - Help users get the most out of their #{app_module.name}
        - Learn from every interaction to become more helpful

        ## 📊 Module Schema

        **#{app_module.name}** (#{app_module.description})

        ### Fields You Manage:
        #{format_fields_for_prompt(fields)}

        ### Status Workflow:
        #{format_status_workflow(fields)}

        ## 🔧 Your Tools

        You have access to these module-specific tools:
        #{format_tools_for_prompt}

        ## 🔌 Connected Integrations

        #{format_integrations_for_prompt(integrations)}

        ## ⚡ Automations

        **Scheduled Tasks:**
        #{format_scheduled_tasks_for_prompt(scheduled_tasks)}

        **Workflows:**
        #{format_workflows_for_prompt(workflows)}

        ## 💬 How to Help Users

        1. **Data Operations**
           - "Show me all [records]" → Use list tool
           - "Create a new [record]" → Use create tool, ask for required fields
           - "Update [record]" → Use update tool
           - "Delete [record]" → Use delete tool (with confirmation)

        2. **Analysis & Insights**
           - "How is my [module] performing?" → Analyze data trends
           - "Which [records] need attention?" → Filter and prioritize
           - "Generate a report on..." → Create summary analysis

        3. **Automations**
           - "Set up a daily report" → Create scheduled task
           - "Notify me when..." → Create workflow trigger
           - "Run the sync now" → Execute scheduled task manually

        4. **Troubleshooting**
           - If integration fails → Check connection, suggest re-auth
           - If data looks wrong → Validate and suggest fixes
           - If confused → Ask clarifying questions

        ## ⚠️ Important Rules

        1. **Stay in Your Domain** - You're the #{app_module.name} expert. For unrelated tasks, say "That's outside my expertise - Amos can help with that."
        
        2. **Confirm Destructive Actions** - Always confirm before deleting or bulk updating.
        
        3. **Use ask_user for Input** - When you need user input (preferences, parameters), use the `ask_user` tool instead of asking in text.
        
        4. **Learn and Remember** - Pay attention to user preferences and patterns. Use the knowledge base to remember important insights.

        5. **Collaborate** - If you need data from another module or system, use `ask_agent_for_help` to get assistance.

        ## 🧠 Your Knowledge

        Your knowledge base contains:
        - Module schema and documentation
        - Best practices for #{app_module.name} management
        - Learned patterns from past interactions
        - Integration documentation (if connected)

        Search your knowledge when uncertain. Save useful discoveries for future reference.
      PROMPT

      { 'prompt' => prompt.strip }
    end

    def format_fields_for_prompt(fields)
      return "- (No fields defined yet)" if fields.blank?

      fields.map do |f|
        name = f['name']
        type = f['field_type'] || f['type']
        required = f['required'] ? ' (required)' : ''
        options = f['options'].present? ? " [#{f['options'].join(', ')}]" : ''
        desc = f['description'].present? ? " - #{f['description']}" : ''
        
        "- **#{name.titleize}** (#{type})#{required}#{options}#{desc}"
      end.join("\n")
    end

    def format_status_workflow(fields)
      status_field = fields.find { |f| f['name'] == 'status' && f['options'].present? }
      return "- No status workflow defined" unless status_field

      statuses = status_field['options']
      "#{statuses.join(' → ')}"
    end

    def format_tools_for_prompt
      tools = gather_module_tools
      return "- (No tools assigned yet)" if tools.blank?

      tools.map { |t| "- `#{t}`: #{tool_description(t)}" }.join("\n")
    end

    def tool_description(tool_name)
      if tool_name.start_with?("create_")
        "Create a new #{app_module.name.singularize}"
      elsif tool_name.start_with?("list_")
        "List all #{app_module.name} records"
      elsif tool_name.start_with?("update_")
        "Update a #{app_module.name.singularize} record"
      elsif tool_name.start_with?("delete_")
        "Delete a #{app_module.name.singularize} record"
      else
        "Module-specific operation"
      end
    end

    def format_integrations_for_prompt(integrations)
      return "- No integrations connected" if integrations.blank?

      integrations.map do |i|
        "- **#{i['name']&.titleize || i['name']}**: #{i['description'] || 'Connected platform'}"
      end.join("\n")
    end

    def format_scheduled_tasks_for_prompt(tasks)
      return "- No scheduled tasks configured" if tasks.blank?

      tasks.map do |t|
        "- **#{t['name']}** (#{t['schedule']} at #{t['time']}): #{t['description'] || t['action']}"
      end.join("\n")
    end

    def format_workflows_for_prompt(workflows)
      return "- No automated workflows configured" if workflows.blank?

      workflows.map do |w|
        trigger_desc = case w['trigger']
        when 'status_change' then "When status changes#{w['from_status'] ? " from #{w['from_status']}" : ''}#{w['to_status'] ? " to #{w['to_status']}" : ''}"
        when 'record_created' then "When a new record is created"
        when 'scheduled_datetime' then "At the scheduled time"
        else w['trigger']
        end
        
        "- **#{w['name']}**: #{trigger_desc} → #{w['actions']&.join(', ') || 'execute actions'}"
      end.join("\n")
    end

    def gather_module_tools
      tools = []
      
      # Add module-specific CRUD tools
      tools << "create_#{app_module.slug}"
      tools << "list_#{app_module.slug.pluralize}"
      tools << "update_#{app_module.slug}"
      tools << "delete_#{app_module.slug}"
      
      # Add any custom tools for this module
      if app_module.tool_definitions.present?
        tools.concat(app_module.tool_definitions.pluck(:name))
      end
      
      # Add collaboration tools
      tools.concat(%w[ask_user ask_agent_for_help save_to_knowledge_base])
      
      # Add scratchpad tools for data handoff
      tools.concat(%w[save_to_scratchpad read_from_scratchpad list_scratchpad])
      
      # Add DM canvas tool for showing visualizations in direct messages
      tools << 'load_dm_canvas'
      
      tools.uniq
    end

    def build_configuration
      {
        'auto_created' => true,
        'module_id' => app_module.id,
        'module_slug' => app_module.slug,
        'temperature' => 0.4,  # Slightly lower for consistency
        'max_tokens' => 4000,
        'canvas_on_completion' => 'dynamic_canvas',
        'include_business_data' => true
      }
    end

    def update_existing_agent(agent)
      Rails.logger.info "[ModuleAgentGenerator] Updating existing agent for module: #{app_module.name}"
      
      # Update the system prompt with latest schema
      agent.update!(
        system_prompt: generate_system_prompt,
        description: generate_description
      )
      
      # Ensure all module tools are assigned
      gather_module_tools.each do |tool_name|
        agent.agent_tools.find_or_create_by!(tool_name: tool_name)
      end
      
      { success: true, agent: agent, updated: true }
    end

    def seed_knowledge_base(agent)
      return unless agent.respond_to?(:knowledge_base)
      
      # Add module documentation to knowledge base
      schema = app_module.metadata.dig('schema') || {}
      
      agent.add_to_knowledge(
        title: "#{app_module.name} Module Schema",
        content: <<~DOC,
          # #{app_module.name} Module Documentation
          
          ## Overview
          #{app_module.description}
          
          ## Data Schema
          #{schema.to_yaml}
          
          ## Created
          #{app_module.created_at}
          
          ## Author
          #{app_module.author_type}
        DOC
        source: 'module_generator',
        metadata: { module_id: app_module.id, type: 'schema_documentation' }
      )
      
      Rails.logger.info "[ModuleAgentGenerator] Seeded knowledge base for #{agent.name}"
    rescue => e
      Rails.logger.warn "[ModuleAgentGenerator] Could not seed knowledge base: #{e.message}"
    end

    def setup_learning(agent)
      # Initialize energy state for the agent
      agent.ensure_energy_state!
      
      # Initialize decision boundary
      agent.ensure_decision_boundary!
      
      Rails.logger.info "[ModuleAgentGenerator] Set up learning systems for #{agent.name}"
    rescue => e
      Rails.logger.warn "[ModuleAgentGenerator] Could not set up learning: #{e.message}"
    end
  end
end

