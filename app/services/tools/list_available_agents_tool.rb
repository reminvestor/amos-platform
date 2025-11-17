module Tools
  class ListAvailableAgentsTool < BaseTool
    def self.metadata
      {
        name: 'list_available_agents',
        description: 'Search for specialized agents that can help with a specific task. Provides relevant agents based on the task description.',
        category: 'system',
        input_schema: {
          type: 'object',
          properties: {
            task_description: {
              type: 'string',
              description: 'A detailed description of the task you need help with. This is used to find the most relevant agents.'
            },
            include_capabilities: {
              type: 'boolean',
              description: 'Include detailed capability descriptions for each agent',
              default: true
            },
            max_results: {
              type: 'integer',
              description: 'Maximum number of agents to return (default: 5)',
              default: 5
            }
          },
          required: ['task_description']
        },
        output_schema: {
          type: 'object',
          properties: {
            agents: {
              type: 'array',
              description: 'List of available agents with their capabilities'
            }
          }
        }
      }
    end
    
    def execute(args = {})
      task_description = args[:task_description]
      max_results = args[:max_results] || 5
      include_capabilities = args[:include_capabilities] != false
      
      Rails.logger.info "🤖 [ListAvailableAgentsTool] Searching for agents to help with: #{task_description}"
      
      # TODO: In production, this will query a RAG system with vector embeddings
      # For now, we'll use keyword matching and predefined agents
      
      # Define available agents and their capabilities
      # In the future, these will be stored in a vector database
      agents = [
        {
          name: 'landing_page_agent',
          display_name: 'Landing Page Creator',
          description: 'Creates beautiful, conversion-optimized landing pages with AI-generated content',
          capabilities: ['Creates landing pages', 'Generates persuasive copy', 'Applies brand styling', 'SEO optimization'],
          trigger_phrases: ['landing page', 'sales page', 'marketing page', 'website'],
          complexity: 'moderate',
          ready_indicators: ['I want to create', 'Build me a', 'I need a landing page']
        },
        {
          name: 'email_agent',
          display_name: 'Email Campaign Manager',
          description: 'Designs and sends email campaigns, manages templates, and handles email automation',
          capabilities: ['Creates email campaigns', 'Designs templates', 'Manages subscribers', 'Schedules sends', 'A/B testing'],
          trigger_phrases: ['email campaign', 'newsletter', 'email blast', 'marketing email'],
          complexity: 'moderate',
          ready_indicators: ['Send an email', 'Create a campaign', 'Email my customers']
        },
        {
          name: 'integration_agent',
          display_name: 'Integration Specialist',
          description: 'Connects external services like Stripe, Zapier, and other APIs to automate workflows',
          capabilities: ['Connects Stripe', 'Sets up Zapier', 'Configures webhooks', 'Syncs data between services'],
          trigger_phrases: ['connect', 'integrate', 'sync', 'automation', 'webhook'],
          complexity: 'complex',
          ready_indicators: ['Connect my Stripe', 'Set up integration', 'Sync data from']
        },
        {
          name: 'data_agent',
          display_name: 'Data Manager',
          description: 'Imports, exports, cleans, and manages customer data and contacts',
          capabilities: ['Imports contacts', 'Exports data', 'Deduplicates records', 'Data cleaning', 'Bulk operations'],
          trigger_phrases: ['import contacts', 'clean data', 'deduplicate', 'export', 'bulk update'],
          complexity: 'moderate',
          ready_indicators: ['Import my contacts', 'Clean up duplicates', 'Export data']
        },
        {
          name: 'analytics_agent',
          display_name: 'Analytics Expert',
          description: 'Generates comprehensive reports, analyzes performance, and provides business insights',
          capabilities: ['Performance reports', 'Revenue analysis', 'Funnel analysis', 'Cohort analysis', 'Custom dashboards'],
          trigger_phrases: ['analytics', 'report', 'performance', 'metrics', 'insights'],
          complexity: 'complex',
          ready_indicators: ['Generate a report', 'Analyze my revenue', 'Show me insights']
        },
        {
          name: 'workflow_agent',
          display_name: 'Workflow Automation Builder',
          description: 'Creates automated workflows and multi-step processes',
          capabilities: ['Workflow design', 'Process automation', 'Trigger setup', 'Multi-step sequences'],
          trigger_phrases: ['workflow', 'automation', 'process', 'sequence'],
          complexity: 'complex',
          ready_indicators: ['Automate my process', 'Create a workflow', 'Set up automation']
        }
      ]
      
      # Add custom agents if any exist
      # TODO: Re-enable when CustomAgentDefinition.active scope is fixed
      # if defined?(CustomAgentDefinition)
      #   custom_agents = CustomAgentDefinition.active.where(entity: @entity).map do |agent_def|
      #     {
      #       name: "custom_#{agent_def.id}",
      #       display_name: agent_def.name,
      #       description: agent_def.definition['description'],
      #       capabilities: agent_def.definition['capabilities'] || [],
      #       trigger_phrases: agent_def.definition['trigger_phrases'] || [],
      #       complexity: 'custom',
      #       custom: true
      #     }
      #   end
      #   agents.concat(custom_agents)
      # end
      
      # Rank agents by relevance to the task
      # In production, this will be replaced by vector similarity search
      ranked_agents = rank_agents_by_relevance(agents, task_description)
      
      # Take only the top N most relevant agents
      relevant_agents = ranked_agents.take(max_results)
      
      # Format based on include_capabilities parameter
      if !include_capabilities
        relevant_agents = relevant_agents.map { |a| a.slice(:name, :display_name, :relevance_score) }
      end
      
      success_response(
        agents: relevant_agents,
        total_found: ranked_agents.size,
        returned: relevant_agents.size,
        task_context: task_description,
        message: "Found #{relevant_agents.size} relevant agents for your task"
      )
    rescue => e
      error_response(e.message)
    end
    
    private
    
    def rank_agents_by_relevance(agents, task_description)
      return agents if task_description.blank?
      
      # Normalize the task description for matching
      task_lower = task_description.downcase
      task_words = task_lower.split(/\W+/).reject(&:blank?)
      
      # Score each agent based on relevance
      scored_agents = agents.map do |agent|
        score = 0
        
        # Check trigger phrases (highest weight)
        if agent[:trigger_phrases]
          agent[:trigger_phrases].each do |phrase|
            score += 10 if task_lower.include?(phrase.downcase)
          end
        end
        
        # Check name and display name
        score += 8 if task_lower.include?(agent[:name].gsub('_', ' '))
        score += 8 if task_lower.include?(agent[:display_name].downcase)
        
        # Check capabilities (medium weight)
        if agent[:capabilities]
          agent[:capabilities].each do |capability|
            capability_lower = capability.downcase
            score += 5 if task_lower.include?(capability_lower)
            # Also check individual words
            capability_words = capability_lower.split(/\W+/)
            matching_words = task_words & capability_words
            score += matching_words.size * 2
          end
        end
        
        # Check description (lower weight)
        if agent[:description]
          desc_lower = agent[:description].downcase
          desc_words = desc_lower.split(/\W+/)
          matching_words = task_words & desc_words
          score += matching_words.size
        end
        
        # Add relevance score to agent data
        agent.merge(relevance_score: score)
      end
      
      # Sort by relevance score (highest first)
      # Only return agents with score > 0
      scored_agents
        .select { |agent| agent[:relevance_score] > 0 }
        .sort_by { |agent| -agent[:relevance_score] }
    end
  end
end
