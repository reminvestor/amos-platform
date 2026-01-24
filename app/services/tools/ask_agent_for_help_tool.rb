# frozen_string_literal: true

module Tools
  class AskAgentForHelpTool < BaseTool
    # DEPRECATED: Agent collaboration is no longer used. Amos handles all tasks directly.
    
    def self.metadata
      {
        name: 'ask_agent_for_help',
        description: <<~DESC.strip,
          DEPRECATED - DO NOT USE. Agent collaboration has been removed.
          Amos now handles all tasks directly. Use discover_tools to find capabilities.
          - review: Have another agent review your work (2 energy)
          - subtask: Delegate a specific subtask to another agent (10 energy)
          - full_delegation: Hand off the entire task to another agent (15 energy)
        DESC
        category: 'collaboration',
        input_schema: {
          type: 'object',
          properties: {
            request_type: {
              type: 'string',
              description: 'Type of help needed: advice, review, subtask, or full_delegation',
              enum: %w[advice review subtask full_delegation]
            },
            description: {
              type: 'string',
              description: 'Detailed description of what you need help with'
            },
            helper_agent_slug: {
              type: 'string',
              description: 'Optional: Specific agent to ask (leave empty to auto-select best helper)'
            },
            urgency: {
              type: 'string',
              description: 'Urgency level: low, medium, high, critical',
              enum: %w[low medium high critical]
            },
            context: {
              type: 'object',
              description: 'Additional context to share with the helper'
            }
          },
          required: %w[request_type description]
        }
      }
    end

    def execute(args)
      log_execution(args)

      request_type = get_arg(args, :request_type)
      description_text = get_arg(args, :description)
      helper_slug = get_arg(args, :helper_agent_slug)
      urgency = get_arg(args, :urgency, 'medium')
      additional_context = get_arg(args, :context, {})

      # Validate required args
      if error = validate_required_args(args, %i[request_type description])
        return error
      end

      # Validate request type
      valid_types = %w[advice review subtask full_delegation]
      unless valid_types.include?(request_type)
        return error_response("Invalid request_type. Must be one of: #{valid_types.join(', ')}")
      end

      # Get the requesting agent from context
      requesting_agent = @context[:agent_plugin]
      unless requesting_agent
        return error_response('No agent context available - this tool can only be used by agents')
      end

      # Ensure energy state exists
      begin
        requesting_agent.ensure_energy_state!
      rescue => e
        Rails.logger.warn "[AskAgentForHelpTool] Could not create energy state: #{e.message}"
      end

      # Check if agent has enough energy (if energy system is enabled)
      if requesting_agent.energy_state && !requesting_agent.energy_state.can_ask_for_help?
        return error_response(
          'Insufficient energy to ask for help',
          current_energy: requesting_agent.current_energy
        )
      end

      # Find helper agent
      helper_agent = find_helper_agent(helper_slug, requesting_agent, description_text)
      unless helper_agent
        return error_response('No suitable helper agent found. Try specifying a different agent or task.')
      end

      # Check collaboration depth to prevent infinite loops
      parent_request = find_parent_request
      if parent_request && parent_request.depth >= AgentCollaborationRequest::MAX_DEPTH
        return error_response(
          'Maximum collaboration depth reached. Cannot delegate further.',
          depth: parent_request.depth,
          max_depth: AgentCollaborationRequest::MAX_DEPTH
        )
      end

      # Create collaboration request
      request = create_collaboration_request(
        requesting_agent: requesting_agent,
        helper_agent: helper_agent,
        parent_request: parent_request,
        request_type: request_type,
        description: description_text,
        urgency: urgency,
        additional_context: additional_context
      )

      return error_response(request[:error]) if request[:error]

      collaboration_request = request[:request]

      # Check for cycles
      if collaboration_request.creates_cycle?
        collaboration_request.destroy
        return error_response('Request would create a delegation cycle')
      end

      # Spend energy (if energy system is enabled)
      if requesting_agent.energy_state
        begin
          requesting_agent.energy_state.spend!(
            collaboration_request.energy_cost,
            reason: "collaboration_#{request_type}",
            request: collaboration_request
          )
        rescue InsufficientEnergyError => e
          collaboration_request.destroy
          return error_response("Insufficient energy: #{e.message}")
        rescue => e
          Rails.logger.warn "[AskAgentForHelpTool] Energy spend failed: #{e.message}"
          # Continue anyway - energy tracking is optional
        end
      end

      # Execute the helper synchronously
      result = execute_helper_agent(collaboration_request, helper_agent, description_text)

      # Mark request as completed
      begin
        # Need to go through the lifecycle: accept -> start -> complete
        collaboration_request.update!(
          status: 'accepted',
          accepted_at: Time.current
        )
        collaboration_request.update!(status: 'in_progress')
        collaboration_request.complete!(
          response: result,
          quality_rating: estimate_quality(result),
          was_helpful: result[:success]
        )
      rescue => e
        Rails.logger.warn "[AskAgentForHelpTool] Could not complete request lifecycle: #{e.message}"
        # Still return the result even if tracking fails
      end

      success_response(
        request_id: collaboration_request.id,
        helper_agent: helper_agent.name,
        request_type: request_type,
        response: result[:response] || result[:output],
        success: result[:success],
        energy_spent: collaboration_request.energy_cost,
        helper_energy_earned: collaboration_request.energy_reward
      )
    rescue => e
      Rails.logger.error "[AskAgentForHelpTool] Error: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      error_response("Collaboration failed: #{e.message}")
    end

    private

    def find_helper_agent(helper_slug, requesting_agent, task_description)
      if helper_slug.present?
        # Find specific agent by slug
        AgentPlugin.available
          .where(slug: helper_slug)
          .where(entity: [requesting_agent.entity, nil])
          .first
      else
        # Auto-select best helper based on task
        find_best_helper(requesting_agent, task_description)
      end
    end

    def find_best_helper(requesting_agent, task_description)
      # Get available agents (excluding self)
      candidates = AgentPlugin.available
        .where(entity: [requesting_agent.entity, nil])
        .where.not(id: requesting_agent.id)
        .limit(20)

      return nil if candidates.empty?

      task_lower = task_description.to_s.downcase

      # Score each candidate based on semantic relevance + operational factors
      scored = candidates.map do |agent|
        score = 0.0

        # 1. Semantic matching on description (most important)
        agent_desc = (agent.description.to_s + " " + agent.name.to_s).downcase
        agent_slug = agent.slug.to_s.downcase
        
        # Keyword matching from task to agent description/name/slug
        task_words = task_lower.split(/\W+/).select { |w| w.length > 3 }
        matches = task_words.count { |word| agent_desc.include?(word) || agent_slug.include?(word) }
        score += (matches * 0.15).clamp(0, 0.6)

        # 2. Check capabilities match
        if agent.respond_to?(:agent_capabilities)
          cap_names = agent.agent_capabilities.pluck(:capability_name).join(' ').downcase
          cap_matches = task_words.count { |word| cap_names.include?(word) }
          score += (cap_matches * 0.1).clamp(0, 0.3)
        end

        # 3. Operational factors (secondary)
        if agent.energy_state
          # Prefer agents with higher energy
          score += (agent.current_energy / 200.0).clamp(0, 0.1)
          # Prefer agents with good success rate
          score += (agent.energy_state.success_rate * 0.1) if agent.energy_state.respond_to?(:success_rate)
        end

        # 4. Prefer agents that explicitly can help others
        score += 0.05 if agent.respond_to?(:can_help_others?) && agent.can_help_others?

        { agent: agent, score: score }
      end

      # Return the best match if score is meaningful
      best = scored.max_by { |s| s[:score] }
      
      Rails.logger.info "[AskAgentForHelpTool] Best helper match: #{best[:agent].name} (score: #{best[:score].round(2)})" if best
      
      # Only return if there's some relevance
      best[:score] > 0.1 ? best[:agent] : scored.sample&.dig(:agent)
    end

    def find_parent_request
      return nil unless @context[:execution]

      AgentCollaborationRequest
        .where(agent_plugin_execution: @context[:execution])
        .order(created_at: :desc)
        .first
    end

    def create_collaboration_request(requesting_agent:, helper_agent:, parent_request:, request_type:, description:, urgency:, additional_context:)
      request = AgentCollaborationRequest.new(
        requesting_agent: requesting_agent,
        helper_agent: helper_agent,
        entity: requesting_agent.entity,
        agent_plugin_execution: @context[:execution],
        parent_request: parent_request,
        request_type: request_type,
        description: description,
        context: (additional_context || {}).merge(
          'original_task' => @context[:execution]&.input&.dig('task_description')
        ),
        urgency: urgency,
        status: 'pending',
        required_capabilities: extract_required_capabilities(description)
      )

      if request.save
        { request: request }
      else
        { error: "Failed to create collaboration request: #{request.errors.full_messages.join(', ')}" }
      end
    end

    def extract_required_capabilities(description)
      capabilities = []
      desc_lower = description.to_s.downcase

      keywords = {
        'analysis' => %w[analyze analysis data metrics],
        'creation' => %w[create generate build make],
        'research' => %w[research find search investigate],
        'integration' => %w[integrate api connect sync],
        'communication' => %w[email send message notify]
      }

      keywords.each do |cap, words|
        if words.any? { |w| desc_lower.include?(w) }
          capabilities << cap
        end
      end

      capabilities
    end

    def execute_helper_agent(request, helper_agent, description)
      # Create a mini-execution for the helper
      helper_execution = AgentPluginExecution.create!(
        agent_plugin: helper_agent,
        user: @context[:user],
        entity: helper_agent.entity || @context[:entity],
        status: 'running',
        input: {
          'task_description' => description,
          'collaboration_context' => request.context,
          'requesting_agent' => request.requesting_agent.name
        }
      )

      begin
        # Instantiate and run helper
        agent_instance = helper_agent.instantiate(
          entity: helper_agent.entity || @context[:entity],
          user: @context[:user],
          execution: helper_execution
        )

        result = agent_instance.run(description, {
          entity: helper_agent.entity || @context[:entity],
          user: @context[:user],
          collaboration_request: request
        })

        helper_execution.mark_completed!(output: result)

        { success: true, response: result, output: result }
      rescue => e
        Rails.logger.error "[AskAgentForHelpTool] Helper execution failed: #{e.message}"
        helper_execution.mark_failed!(e.message)
        { success: false, response: nil, error: e.message }
      end
    end

    def estimate_quality(result)
      return 1.0 if result[:success] == false
      return 5.0 if result[:response].present? && result[:response].to_s.length > 200
      3.0
    end
  end
end
