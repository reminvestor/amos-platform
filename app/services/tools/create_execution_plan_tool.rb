# frozen_string_literal: true

module Tools
  # Creates a structured execution plan for complex tasks
  class CreateExecutionPlanTool < BaseTool
    def self.metadata
      {
        name: 'create_execution_plan',
        description: <<~DESC.strip,
          Create a structured execution plan for a complex multi-step task.
          
          Use this when the user's request requires multiple phases, agents, or 
          significant coordination. The plan will break down the work into 
          manageable steps with dependencies and agent assignments.
          
          Returns the plan structure for review and execution.
        DESC
        category: 'planning',
        input_schema: {
          type: 'object',
          properties: {
            request: {
              type: 'string',
              description: 'The original user request to plan for'
            },
            title: {
              type: 'string',
              description: 'A clear title for this plan'
            },
            phases: {
              type: 'array',
              description: 'Array of phases with steps (optional - will auto-generate if not provided)',
              items: {
                type: 'object',
                properties: {
                  name: { type: 'string' },
                  description: { type: 'string' },
                  steps: {
                    type: 'array',
                    items: {
                      type: 'object',
                      properties: {
                        name: { type: 'string' },
                        description: { type: 'string' },
                        agent: { type: 'string' },
                        tools_needed: { type: 'array', items: { type: 'string' } },
                        dependencies: { type: 'array', items: { type: 'string' } },
                        estimated_minutes: { type: 'integer' }
                      }
                    }
                  }
                }
              }
            },
            requires_approval: {
              type: 'boolean',
              description: 'Whether to require user approval before execution (default: true for complex plans)'
            }
          },
          required: ['request']
        }
      }
    end

    def execute(args)
      log_execution(args)

      request = get_arg(args, :request)
      title = get_arg(args, :title)
      custom_phases = get_arg(args, :phases)
      requires_approval = get_arg(args, :requires_approval)

      if error = validate_required_args(args, [:request])
        return error
      end

      planner_service = PlannerService.new(entity: entity, user: user)

      begin
        # Check if planning is even needed
        complexity = planner_service.estimate_complexity(request)
        
        if complexity == :simple
          return success_response(
            needs_plan: false,
            complexity: complexity,
            message: "This request is simple enough to handle directly without a formal plan.",
            suggestion: "Proceed with direct execution"
          )
        end

        # Create the plan
        if custom_phases.present?
          # Use custom phases provided by the Planner agent
          plan = create_custom_plan(request, title, custom_phases, requires_approval, complexity)
        else
          # Generate skeleton plan
          plan = planner_service.generate_plan_skeleton(request)
        end

        # Update title if provided
        plan.update!(title: title) if title.present?
        plan.update!(requires_approval: requires_approval) if requires_approval != nil

        # Validate the plan
        validation = planner_service.validate_plan(plan)

        if validation[:valid]
          plan.mark_ready!
        end

        success_response(
          plan_id: plan.id,
          title: plan.title,
          status: plan.status,
          complexity: plan.complexity,
          needs_plan: true,
          requires_approval: plan.requires_approval,
          total_phases: plan.phases.count,
          total_steps: plan.total_steps,
          estimated_minutes: plan.estimated_duration_minutes,
          phases: plan.phases.map { |p|
            {
              name: p['name'],
              description: p['description'],
              steps_count: (p['steps'] || []).count
            }
          },
          validation: validation,
          next_action: plan.requires_approval ? 
            "Show plan to user for approval" : 
            "Execute plan with execute_plan_step"
        )
      rescue => e
        Rails.logger.error "[CreateExecutionPlan] Error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        error_response("Failed to create execution plan: #{e.message}")
      end
    end

    private

    def create_custom_plan(request, title, phases, requires_approval, complexity)
      # Convert phases to proper structure with IDs
      structured_phases = phases.each_with_index.map do |phase, p_idx|
        {
          'id' => "phase_#{p_idx + 1}",
          'name' => phase['name'] || phase[:name],
          'description' => phase['description'] || phase[:description],
          'status' => 'pending',
          'steps' => (phase['steps'] || phase[:steps] || []).each_with_index.map do |step, s_idx|
            {
              'id' => "step_#{p_idx + 1}_#{s_idx + 1}",
              'name' => step['name'] || step[:name],
              'description' => step['description'] || step[:description],
              'agent' => step['agent'] || step[:agent],
              'tools_needed' => step['tools_needed'] || step[:tools_needed] || [],
              'status' => 'pending',
              'dependencies' => step['dependencies'] || step[:dependencies] || [],
              'estimated_minutes' => step['estimated_minutes'] || step[:estimated_minutes] || 5
            }
          end
        }
      end

      total_steps = structured_phases.sum { |p| (p['steps'] || []).count }
      estimated_minutes = structured_phases.sum { |p| 
        (p['steps'] || []).sum { |s| s['estimated_minutes'] || 5 }
      }

      ExecutionPlan.create!(
        entity: entity,
        user: user,
        title: title || "Plan: #{request.truncate(50)}",
        original_request: request,
        complexity: complexity.to_s,
        status: 'planning',
        requires_approval: requires_approval.nil? ? true : requires_approval,
        phases: structured_phases,
        total_steps: total_steps,
        estimated_duration_minutes: estimated_minutes
      )
    end
  end
end





