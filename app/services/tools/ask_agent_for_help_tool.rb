# frozen_string_literal: true

module Tools
  class AskAgentForHelpTool < BaseTool
    tool_name 'ask_agent_for_help'
    description <<~DESC
      Ask another agent for help with a subtask or for advice. Use this when you are uncertain
      about how to proceed, when the task requires expertise you don't have, or when you want
      a review of your work. This costs energy based on the type of help requested.

      Request types:
      - advice: Quick guidance or suggestions (2 energy)
      - review: Have another agent review your work (2 energy)
      - subtask: Delegate a specific subtask to another agent (10 energy)
      - full_delegation: Hand off the entire task to another agent (15 energy)
    DESC

    parameter :request_type, type: 'string', description: 'Type of help needed: advice, review, subtask, or full_delegation', required: true
    parameter :description, type: 'string', description: 'Detailed description of what you need help with', required: true
    parameter :helper_agent_slug, type: 'string', description: 'Optional: Specific agent to ask (leave empty to auto-select best helper)', required: false
    parameter :urgency, type: 'string', description: 'Urgency level: low, medium, high, critical', required: false
    parameter :context, type: 'object', description: 'Additional context to share with the helper', required: false

    def call(params)
      request_type = params[:request_type] || params['request_type']
      description = params[:description] || params['description']
      helper_slug = params[:helper_agent_slug] || params['helper_agent_slug']
      urgency = params[:urgency] || params['urgency'] || 'medium'
      additional_context = params[:context] || params['context'] || {}

      # Validate request type
      valid_types = %w[advice review subtask full_delegation]
      unless valid_types.include?(request_type)
        return { success: false, error: "Invalid request_type. Must be one of: #{valid_types.join(', ')}" }
      end

      # Get the requesting agent
      requesting_agent = @context[:agent_plugin]
      unless requesting_agent
        return { success: false, error: 'No agent context available' }
      end

      # Initialize energy tracker
      energy_tracker = Collaboration::EnergyTracker.new(requesting_agent)

      # Check if agent has enough energy
      unless requesting_agent.energy_state&.can_ask_for_help?
        return {
          success: false,
          error: 'Insufficient energy to ask for help',
          current_energy: requesting_agent.current_energy
        }
      end

      # Find helper agent
      helper_agent = if helper_slug.present?
        AgentPlugin.available.find_by(slug: helper_slug, entity: requesting_agent.entity)
      else
        # Auto-select best helper
        best = energy_tracker.find_best_helper(description)
        best&.dig(:agent)
      end

      unless helper_agent
        return { success: false, error: 'No suitable helper agent found' }
      end

      # Check collaboration depth
      parent_request = find_parent_request
      if parent_request && parent_request.would_exceed_depth?
        return {
          success: false,
          error: 'Maximum collaboration depth reached. Cannot delegate further.',
          depth: parent_request.depth
        }
      end

      # Create collaboration request
      request = AgentCollaborationRequest.create!(
        requesting_agent: requesting_agent,
        helper_agent: helper_agent,
        entity: requesting_agent.entity,
        agent_plugin_execution: @context[:execution],
        parent_request: parent_request,
        request_type: request_type,
        description: description,
        context: additional_context.merge(
          'original_task' => @context[:execution]&.input&.dig('task_description')
        ),
        urgency: urgency,
        required_capabilities: extract_required_capabilities(description)
      )

      # Check for cycles
      if request.creates_cycle?
        request.destroy
        return { success: false, error: 'Request would create a delegation cycle' }
      end

      # Spend energy
      unless energy_tracker.on_collaboration_requested(request)
        request.destroy
        return { success: false, error: 'Failed to spend energy for collaboration' }
      end

      # Execute the helper synchronously for now
      # In the future, this could be async with callbacks
      result = execute_helper(request, helper_agent, description)

      # Complete the request
      request.complete!(
        response: result,
        quality_rating: estimate_quality(result),
        was_helpful: result[:success]
      )

      # Track completion
      energy_tracker.on_collaboration_completed(request)

      {
        success: true,
        request_id: request.id,
        helper_agent: helper_agent.name,
        request_type: request_type,
        response: result[:response],
        energy_spent: request.energy_cost,
        helper_energy_earned: request.energy_reward
      }
    rescue => e
      Rails.logger.error "[AskAgentForHelpTool] Error: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      { success: false, error: e.message }
    end

    private

    def find_parent_request
      return nil unless @context[:execution]

      AgentCollaborationRequest
        .where(agent_plugin_execution: @context[:execution])
        .order(created_at: :desc)
        .first
    end

    def extract_required_capabilities(description)
      # Simple keyword extraction for capabilities
      capabilities = []

      keywords = {
        'analysis' => %w[analyze analysis data metrics],
        'creation' => %w[create generate build make],
        'research' => %w[research find search investigate],
        'integration' => %w[integrate api connect sync],
        'communication' => %w[email send message notify]
      }

      desc_lower = description.downcase

      keywords.each do |cap, words|
        if words.any? { |w| desc_lower.include?(w) }
          capabilities << cap
        end
      end

      capabilities
    end

    def execute_helper(request, helper_agent, description)
      # Build context for helper
      helper_context = {
        entity: helper_agent.entity,
        user: @context[:user],
        collaboration_request: request,
        requesting_agent: request.requesting_agent.name
      }

      # Create a mini-execution for the helper
      helper_execution = AgentPluginExecution.create!(
        agent_plugin: helper_agent,
        user: @context[:user],
        entity: helper_agent.entity,
        status: 'running',
        input: {
          'task_description' => description,
          'collaboration_context' => request.context
        }
      )

      begin
        # Instantiate and run helper
        agent_instance = helper_agent.instantiate(
          entity: helper_agent.entity,
          user: @context[:user],
          execution: helper_execution
        )

        result = agent_instance.run(description, helper_context)

        helper_execution.mark_completed!(output: result)

        { success: true, response: result }
      rescue => e
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

