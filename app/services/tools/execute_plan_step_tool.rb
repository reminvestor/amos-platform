# frozen_string_literal: true

module Tools
  # Executes a step in an execution plan
  class ExecutePlanStepTool < BaseTool
    def self.metadata
      {
        name: 'execute_plan_step',
        description: <<~DESC.strip,
          Execute the next step in an execution plan, or a specific step by ID.
          
          This tool:
          1. Validates the step is ready (dependencies met)
          2. Uses handshake protocol to verify agent capability
          3. Delegates to the assigned agent
          4. Tracks progress and results
          
          If a step fails, returns recovery options.
        DESC
        category: 'planning',
        input_schema: {
          type: 'object',
          properties: {
            plan_id: {
              type: 'integer',
              description: 'The execution plan ID'
            },
            step_id: {
              type: 'string',
              description: 'Specific step ID to execute (optional - will execute next pending step if not provided)'
            },
            action: {
              type: 'string',
              enum: %w[execute skip retry],
              description: 'Action to take (default: execute)'
            }
          },
          required: ['plan_id']
        }
      }
    end

    def execute(args)
      log_execution(args)

      plan_id = get_arg(args, :plan_id)
      step_id = get_arg(args, :step_id)
      action = get_arg(args, :action, 'execute')

      if error = validate_required_args(args, [:plan_id])
        return error
      end

      plan = ExecutionPlan.find_by(id: plan_id, entity: entity)
      return error_response("Plan not found") unless plan

      # Check plan status
      unless %w[ready executing].include?(plan.status)
        return error_response(
          "Plan is not ready for execution",
          status: plan.status,
          action_needed: plan.status == 'paused' ? 'Resume plan first' : 'Plan must be in ready/executing status'
        )
      end

      # Start execution if not already started
      if plan.status == 'ready'
        plan.start_execution!
      end

      # Get the step to execute
      step = if step_id.present?
        plan.find_step(step_id)
      else
        plan.next_step
      end

      return success_response(
        plan_id: plan.id,
        status: 'completed',
        message: 'All steps completed!',
        summary: plan.to_summary
      ) unless step

      step_id = step['id']

      case action
      when 'skip'
        return skip_step(plan, step_id)
      when 'retry'
        return retry_step(plan, step_id)
      end

      # Check dependencies
      unless plan.step_ready?(step_id)
        blocking = step['dependencies'].reject { |d| plan.find_step(d)&.dig('status') == 'completed' }
        return error_response(
          "Step not ready - dependencies incomplete",
          step_id: step_id,
          blocking_steps: blocking
        )
      end

      # Execute the step
      execute_step(plan, step)
    end

    private

    def execute_step(plan, step)
      step_id = step['id']
      agent_slug = step['agent']

      # Mark step as started
      plan.mark_step_started!(step_id)

      # If no agent assigned, this is a manual/orchestrator step
      unless agent_slug
        return success_response(
          plan_id: plan.id,
          step_id: step_id,
          status: 'needs_orchestration',
          step_name: step['name'],
          description: step['description'],
          tools_needed: step['tools_needed'],
          message: "This step needs to be handled by the orchestrator (you)",
          requires_input: step['requires_input']
        )
      end

      # Find the agent
      agent = AgentPlugin.find_by(slug: agent_slug, status: 'active')
      
      unless agent
        plan.mark_step_failed!(step_id, error: "Agent '#{agent_slug}' not found")
        return handle_step_failure(plan, step_id, "Agent not found")
      end

      # Use handshake protocol
      proposal = AgentTaskProposal.create!(
        proposing_agent: nil,
        receiving_agent: agent,
        entity: entity,
        user: user,
        task_description: step['description'] || step['name'],
        task_type: infer_task_type(step),
        tools_needed: step['tools_needed'] || [],
        context: {
          plan_id: plan.id,
          step_id: step_id,
          plan_title: plan.title
        },
        status: 'proposed'
      )

      evaluation = proposal.evaluate_capability

      if evaluation[:accepted]
        proposal.accept!(confidence: evaluation[:confidence], details: evaluation[:details])
        
        # Build rich plan context for the agent
        plan_context = build_plan_context(plan, step)
        
        # Delegate to the agent with full context
        success_response(
          plan_id: plan.id,
          step_id: step_id,
          status: 'delegating',
          step_name: step['name'],
          agent: agent_slug,
          proposal_id: proposal.id,
          confidence: evaluation[:confidence],
          message: "Step delegated to #{agent.name}",
          next_action: "Call delegate_to_agent with proposal_id: #{proposal.id}",
          delegate_args: {
            agent_type: agent_slug,
            task_description: build_enriched_task_description(step, plan_context),
            proposal_id: proposal.id,
            context: {
              plan_id: plan.id,
              step_id: step_id,
              plan_context: plan_context
            }
          }
        )
      else
        proposal.reject!(
          reason: evaluation[:reason],
          missing_tools: evaluation[:missing_tools]
        )
        
        plan.mark_step_failed!(step_id, error: evaluation[:reason])
        handle_step_failure(plan, step_id, evaluation[:reason])
      end
    end

    def skip_step(plan, step_id)
      plan.skip_step!(step_id, reason: 'Skipped by orchestrator')
      
      success_response(
        plan_id: plan.id,
        step_id: step_id,
        status: 'skipped',
        message: 'Step skipped',
        next_step: plan.next_step&.dig('name')
      )
    end

    def retry_step(plan, step_id)
      step = plan.find_step(step_id)
      
      if step['status'] != 'failed'
        return error_response("Can only retry failed steps", current_status: step['status'])
      end

      # Reset step status
      plan.send(:update_step, step_id, 'status' => 'pending', 'error' => nil)
      plan.increment!(:retry_count)
      plan.decrement!(:failed_steps)

      # Try again
      execute_step(plan, step)
    end

    def handle_step_failure(plan, step_id, error)
      planner_service = PlannerService.new(entity: entity, user: user)
      recovery = planner_service.handle_step_failure(plan, step_id, error)

      error_response(
        "Step failed: #{error}",
        plan_id: plan.id,
        step_id: step_id,
        recovery_options: recovery[:options],
        recommendation: recovery[:recommendation],
        message: "Use execute_plan_step with action: '#{recovery[:recommendation][:action]}' to recover"
      )
    end

    def infer_task_type(step)
      tools = step['tools_needed'] || []
      
      if tools.any? { |t| t.include?('create') }
        'create_record'
      elsif tools.any? { |t| t.include?('update') || t.include?('module') }
        'update_schema'
      elsif tools.any? { |t| t.include?('get') || t.include?('query') }
        'query_data'
      elsif tools.any? { |t| t.include?('ask') }
        'research'
      else
        'custom'
      end
    end

    # Build rich plan context for the executing agent
    def build_plan_context(plan, current_step)
      # Get completed steps with their results
      completed_steps = plan.all_steps.select { |s| s['status'] == 'completed' }.map do |step|
        {
          name: step['name'],
          result: step['result'],
          agent: step['agent']
        }
      end

      # Get user decisions made during the plan
      user_decisions = plan.user_decisions || {}

      # Build context summary
      {
        plan_goal: plan.original_request,
        plan_title: plan.title,
        current_phase: plan.current_phase_data&.dig('name'),
        progress: "#{plan.completed_steps}/#{plan.total_steps} steps complete (#{plan.progress_percentage}%)",
        
        # What's been done
        completed_steps: completed_steps.map { |s| 
          result_summary = s[:result].is_a?(Hash) ? s[:result].to_json.truncate(200) : s[:result].to_s.truncate(200)
          "#{s[:name]}: #{result_summary}"
        },
        
        # Key results/artifacts from previous steps
        key_results: extract_key_results(completed_steps),
        
        # User decisions
        user_decisions: user_decisions,
        
        # What comes next
        remaining_steps: plan.all_steps.select { |s| s['status'] == 'pending' }.map { |s| s['name'] },
        
        # Dependencies for this step
        step_dependencies: (current_step['dependencies'] || []).map do |dep_id|
          dep_step = plan.find_step(dep_id)
          { name: dep_step&.dig('name'), result: dep_step&.dig('result') }
        end
      }
    end

    # Extract key results from completed steps
    def extract_key_results(completed_steps)
      results = {}
      
      completed_steps.each do |step|
        result = step[:result]
        next unless result.present?

        # Extract meaningful data based on step type
        if result.is_a?(Hash)
          # Look for common result patterns
          if result['module_id'] || result[:module_id]
            results[:created_modules] ||= []
            results[:created_modules] << result['module_id'] || result[:module_id]
          end
          
          if result['app_id'] || result[:app_id]
            results[:created_apps] ||= []
            results[:created_apps] << result['app_id'] || result[:app_id]
          end
          
          if result['blueprint'] || result[:blueprint]
            results[:blueprint] = result['blueprint'] || result[:blueprint]
          end
          
          if result['schema'] || result[:schema]
            results[:schema] = result['schema'] || result[:schema]
          end
          
          if result['user_requirements'] || result[:user_requirements]
            results[:user_requirements] = result['user_requirements'] || result[:user_requirements]
          end
        end
      end
      
      results
    end

    # Build an enriched task description with plan context
    def build_enriched_task_description(step, plan_context)
      parts = []
      
      # Core task
      parts << "TASK: #{step['description'] || step['name']}"
      
      # Plan context
      parts << "\n## PLAN CONTEXT"
      parts << "Overall Goal: #{plan_context[:plan_goal]}"
      parts << "Current Progress: #{plan_context[:progress]}"
      
      # What's been completed
      if plan_context[:completed_steps].any?
        parts << "\n## COMPLETED STEPS"
        plan_context[:completed_steps].each { |s| parts << "- #{s}" }
      end
      
      # Key artifacts from previous steps
      if plan_context[:key_results].any?
        parts << "\n## AVAILABLE FROM PREVIOUS STEPS"
        plan_context[:key_results].each do |key, value|
          parts << "- #{key}: #{value.is_a?(Array) ? value.join(', ') : value.to_s.truncate(100)}"
        end
      end
      
      # User decisions
      if plan_context[:user_decisions].any?
        parts << "\n## USER DECISIONS"
        plan_context[:user_decisions].each do |key, value|
          parts << "- #{key}: #{value}"
        end
      end
      
      # Dependencies
      if plan_context[:step_dependencies].any?
        parts << "\n## THIS STEP DEPENDS ON"
        plan_context[:step_dependencies].each do |dep|
          parts << "- #{dep[:name]}: #{dep[:result].to_s.truncate(100)}"
        end
      end
      
      # Remaining work
      if plan_context[:remaining_steps].any?
        parts << "\n## REMAINING STEPS (for context)"
        plan_context[:remaining_steps].first(5).each { |s| parts << "- #{s}" }
      end
      
      parts.join("\n")
    end
  end
end

