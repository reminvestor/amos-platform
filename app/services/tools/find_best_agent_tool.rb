# frozen_string_literal: true

module Tools
  # Returns candidate agents for a task - the LLM decides which is best
  # Uses Smart Router (historical data) + RAG (semantic similarity) to find candidates
  class FindBestAgentTool < BaseTool
    # DEPRECATED: Agent discovery is no longer used. Amos handles all tasks directly.
    DEFAULT_CANDIDATES = 10

    def self.metadata
      {
        name: 'find_best_agent',
        description: <<~DESC.strip,
          DEPRECATED - DO NOT USE. Agents have been removed from the platform.
          Amos now handles all tasks directly. Use discover_tools to find capabilities.
          
          Key things to consider when choosing:
          - Does the task require CREATING something new or MODIFYING something existing?
          - Does the agent's description match the task intent?
          - Does the agent have the right tools/capabilities?
          
          **CRITICAL: The task_description MUST use the user's EXACT words.**
          Do NOT add details the user didn't say. If user says "an app module", 
          pass "an app module" - NOT "a productivity tracker" or any other invented details.
          
          After choosing, use propose_task_to_agent with your selected agent.
        DESC
        category: 'agent_management',
        input_schema: {
          type: 'object',
          properties: {
            task_description: {
              type: 'string',
              description: 'Detailed description of the task to be performed'
            },
            task_type: {
              type: 'string',
              enum: AgentTaskProposal::TASK_TYPES,
              description: 'Optional category of task for better matching'
            },
            tools_needed: {
              type: 'array',
              items: { type: 'string' },
              description: 'Optional list of tools the agent will need'
            },
            max_candidates: {
              type: 'integer',
              description: "Max candidates to return (default: #{DEFAULT_CANDIDATES})"
            }
          },
          required: ['task_description']
        }
      }
    end

    def self.read_only?
      true
    end

    def execute(args)
      log_execution(args)

      task_description = get_arg(args, :task_description)
      task_type = get_arg(args, :task_type)
      tools_needed = get_arg(args, :tools_needed, [])
      max_candidates = get_arg(args, :max_candidates, DEFAULT_CANDIDATES)

      if error = validate_required_args(args, [:task_description])
        return error
      end

      Rails.logger.info "🤖 Finding agent candidates for: #{task_description.truncate(60)}"

      candidates = []

      # Strategy 1: Smart Router (uses historical performance data)
      begin
        router = Agents::SmartRouterService.new(entity: entity, user: user)
        router_results = router.find_best_agent(
          task_description: task_description,
          task_type: task_type,
          tools_needed: tools_needed,
          top_n: max_candidates
        )

        router_results.each do |r|
          agent = AgentPlugin.find_by(slug: r[:agent_slug])
          next unless agent

          candidates << build_candidate(agent, {
            historical_score: r[:total_score],
            confidence: r[:confidence],
            recommendation: r[:recommendation],
            source: 'historical_performance'
          })
        end
      rescue => e
        Rails.logger.warn "[FindBestAgent] Smart Router error: #{e.message}"
      end

      # Strategy 2: RAG Vector Search (semantic similarity)
      begin
        rag_limit = [max_candidates, max_candidates - candidates.size + 5].max
        rag_results = AgentPlugin.search_by_similarity(task_description, limit: rag_limit, entity: entity)
        
        rag_results.each do |plugin|
          next if candidates.any? { |c| c[:slug] == plugin.slug }
          
          candidates << build_candidate(plugin, {
            source: 'semantic_match'
          })
        end
      rescue => e
        Rails.logger.warn "[FindBestAgent] RAG search error: #{e.message}"
      end

      if candidates.empty?
        return error_response(
          "No candidate agents found for this task. " \
          "You may need to create a new agent or handle this task directly."
        )
      end

      # Take top N candidates (Smart Router results first, then RAG)
      candidates = candidates.take(max_candidates)

      # Detect task intent to help LLM decide
      task_intent = detect_task_intent(task_description)

      success_response(
        task: task_description,
        detected_intent: task_intent,
        candidates: candidates,
        total_found: candidates.size,
        decision_guide: build_decision_guide(task_intent),
        note: "Review these #{candidates.size} agents and choose the one best suited for this task. " \
              "Pay attention to whether you need to CREATE something new vs MODIFY something existing."
      )
    rescue => e
      Rails.logger.error "[FindBestAgent] Error: #{e.message}"
      error_response("Failed to find agent candidates: #{e.message}")
    end

    private

    def build_candidate(agent, extra = {})
      agent_tools = agent.agent_tools.pluck(:tool_name)
      
      {
        slug: agent.slug,
        name: agent.name,
        role: agent.role,
        description: agent.description,
        tools: agent_tools,
        tool_count: agent_tools.size,
        status: agent.status,
        source: extra[:source] || 'unknown',
        historical_score: extra[:historical_score],
        confidence: extra[:confidence],
        recommendation: extra[:recommendation]
      }.compact
    end

    def detect_task_intent(task_description)
      task_lower = task_description.downcase
      
      if task_lower.match?(/\b(create|build|make|generate|new|design|scaffold)\b/)
        'CREATE_NEW'
      elsif task_lower.match?(/\b(fix|repair|debug|diagnose|troubleshoot)\b/)
        'FIX_EXISTING'
      elsif task_lower.match?(/\b(update|modify|change|edit|enhance|add.*to|extend)\b/)
        'MODIFY_EXISTING'
      elsif task_lower.match?(/\b(analyze|research|report|investigate|study)\b/)
        'ANALYZE'
      elsif task_lower.match?(/\b(delete|remove|destroy|drop)\b/)
        'DELETE'
      else
        'GENERAL'
      end
    end

    def build_decision_guide(intent)
      case intent
      when 'CREATE_NEW'
        "This looks like a CREATE task. Look for agents that BUILD or CREATE new things (e.g., 'Platform Factory' for modules, 'AI Landing Page Creator' for pages)."
      when 'FIX_EXISTING'
        "This looks like a FIX/REPAIR task. Look for agents that DIAGNOSE and REPAIR (e.g., 'Integration Repair Agent', 'Module Architect' for fixing modules)."
      when 'MODIFY_EXISTING'
        "This looks like a MODIFY task. Look for agents that UPDATE or ENHANCE existing items."
      when 'ANALYZE'
        "This looks like an ANALYSIS task. Look for research or analytics agents."
      when 'DELETE'
        "This looks like a DELETE task. Be careful - verify the agent can safely handle deletions."
      else
        "Review each agent's description to find the best match for this task."
      end
    end
  end
end
