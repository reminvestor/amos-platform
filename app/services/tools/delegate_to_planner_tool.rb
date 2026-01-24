# frozen_string_literal: true

module Tools
  # Delegates complex requests to the Planner for structured execution
  class DelegateToPlannerTool < BaseTool
    # DEPRECATED: Planner delegation is no longer used. Amos handles planning directly.
    
    def self.metadata
      {
        name: 'delegate_to_planner',
        description: <<~DESC.strip,
          DEPRECATED - Use create_execution_plan instead for complex multi-step tasks.
          Amos now handles planning directly without delegation.
          - Progress tracking
          
          The Planner will break down the request into phases and steps, assign agents,
          and create an execution plan that can be tracked and managed.
          
          After calling this, show the plan to the user and ask for approval if needed.
        DESC
        category: 'planning',
        input_schema: {
          type: 'object',
          properties: {
            request: {
              type: 'string',
              description: "The user's original request that needs planning"
            },
            analysis: {
              type: 'object',
              description: 'Your analysis of why this needs planning',
              properties: {
                complexity: {
                  type: 'string',
                  enum: %w[simple medium complex epic],
                  description: 'Estimated complexity level'
                },
                reason: {
                  type: 'string',
                  description: 'Why this needs a structured plan'
                },
                key_components: {
                  type: 'array',
                  items: { type: 'string' },
                  description: 'Main components/modules that will need to be built'
                },
                agents_likely_needed: {
                  type: 'array',
                  items: { type: 'string' },
                  description: 'Agents that will probably be involved'
                }
              }
            },
            auto_execute: {
              type: 'boolean',
              description: 'Start execution immediately after plan creation (default: true for autonomous operation)'
            }
          },
          required: ['request']
        }
      }
    end

    def execute(args)
      log_execution(args)

      request = get_arg(args, :request)
      analysis = get_arg(args, :analysis, {})
      # Default to false - interactive mode for user requests
      # Only benchmarks/scheduled tasks should explicitly set auto_execute: true
      auto_execute = get_arg(args, :auto_execute, false)

      if error = validate_required_args(args, [:request])
        return error
      end

      begin
        planner_service = PlannerService.new(entity: entity, user: user)

        # Check complexity - trust the AI's analysis if provided
        complexity = analysis['complexity']&.to_sym || planner_service.estimate_complexity(request)

        # For simple requests, suggest direct execution (unless auto_execute is requested)
        unless auto_execute || %i[complex epic].include?(complexity) || planner_service.should_plan?(request)
          return success_response(
            needs_plan: false,
            complexity: complexity,
            message: "This request can be handled directly without a formal plan.",
            suggestion: "Use the appropriate tools or delegate to a specialist agent."
          )
        end

        # Create the execution plan
        plan = planner_service.generate_plan_skeleton(request)

        # Store analysis context and execution mode in user_decisions (JSON field)
        current_decisions = plan.user_decisions || {}
        current_decisions['autonomous'] = auto_execute
        current_decisions['execution_mode'] = auto_execute ? 'autonomous' : 'interactive'
        current_decisions['analysis'] = analysis
        
        # Append to execution log
        current_log = plan.execution_log || []
        current_log << {
          timestamp: Time.current.iso8601,
          event: 'plan_created',
          message: "Created by Amos with analysis: #{analysis.to_json}"
        }
        
        plan.update!(
          summary: analysis['reason'],
          user_decisions: current_decisions,
          execution_log: current_log
        )

        # Validate the plan
        validation = planner_service.validate_plan(plan)
        Rails.logger.info "[DelegateToPlanner] Plan ##{plan.id} validation: valid=#{validation[:valid]}, can_execute=#{validation[:can_execute]}, auto_execute=#{auto_execute}"

        # If valid, mark ready. Auto_execute bypasses approval requirement for automation
        if validation[:valid] || validation[:can_execute]
          if auto_execute
            Rails.logger.info "[DelegateToPlanner] 🚀 Auto-executing plan ##{plan.id}..."
            # Auto-execute bypasses approval requirement - assumes the caller knows what they're doing
            plan.update!(requires_approval: false) if plan.requires_approval
            plan.mark_ready!(auto_execute: true)  # This queues PlanExecutorJob
            Rails.logger.info "[DelegateToPlanner] Plan ##{plan.id} marked ready with auto_execute"
          else
            Rails.logger.info "[DelegateToPlanner] Marking plan ##{plan.id} ready (no auto-execute)"
            plan.mark_ready!(auto_execute: false)  # Just mark ready, don't auto-execute
          end
        else
          Rails.logger.warn "[DelegateToPlanner] Plan ##{plan.id} NOT ready - validation issues: #{validation[:issues].inspect}"
        end

        # Build response with plan details
        response = success_response(
          plan_id: plan.id,
          title: plan.title,
          status: plan.status,
          complexity: plan.complexity,
          requires_approval: plan.requires_approval,
          validation: validation,
          plan_summary: {
            total_phases: plan.phases.count,
            total_steps: plan.total_steps,
            estimated_minutes: plan.estimated_duration_minutes,
            phases: plan.phases.map { |p|
              {
                name: p['name'],
                description: p['description'],
                steps: (p['steps'] || []).map { |s| s['name'] }
              }
            }
          },
          next_actions: build_next_actions(plan, validation),
          message: build_message(plan, validation)
        )
        
        # In interactive mode, suggest loading the plan canvas for user review
        if !auto_execute && plan.requires_approval
          response[:suggested_canvas] = {
            type: 'execution_plan',
            data: { plan_id: plan.id }
          }
          response[:user_action_required] = true
          response[:prompt_user] = "I've created a plan for your #{plan.title.split(':').first}. " \
            "Would you like to review the #{plan.total_steps} steps before I start building?"
        end
        
        response
      rescue => e
        Rails.logger.error "[DelegateToPlanner] Error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        error_response("Failed to create execution plan: #{e.message}")
      end
    end

    private

    def build_next_actions(plan, validation)
      actions = []

      if plan.requires_approval
        actions << {
          action: 'show_plan',
          description: 'Show the plan to the user for approval',
          tool: 'load_canvas',
          args: { type: 'execution_plan', plan_id: plan.id }
        }
      end

      unless validation[:valid]
        actions << {
          action: 'fix_validation_issues',
          description: 'Assign agents to unassigned steps',
          issues: validation[:issues]
        }
      end

      if plan.status == 'ready' && !plan.requires_approval
        actions << {
          action: 'start_execution',
          description: 'Begin executing the plan',
          tool: 'execute_plan_step',
          args: { plan_id: plan.id }
        }
      end

      actions
    end

    def build_message(plan, validation)
      if validation[:valid] && plan.requires_approval
        "Created a #{plan.complexity} plan with #{plan.total_steps} steps across #{plan.phases.count} phases. " \
        "This plan requires user approval before execution."
      elsif plan.status == 'executing'
        "Created a #{plan.complexity} plan with #{plan.total_steps} steps. " \
        "**Execution has started automatically.** The plan will run in the background - " \
        "do NOT manually call execute_plan_step. Check progress with get_plan_status."
      elsif validation[:valid]
        "Created a #{plan.complexity} plan with #{plan.total_steps} steps. Ready to execute."
      else
        "Created plan but #{validation[:issues].count} issue(s) need attention before execution."
      end
    end
  end
end
