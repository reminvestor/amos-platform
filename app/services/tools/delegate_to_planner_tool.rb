module Tools
  class DelegateToPlannerTool < BaseTool
    def self.metadata
      {
        name: 'delegate_to_planner',
        description: 'Delegate a complex multi-step request to the Planner Agent for workflow creation and automatic execution. The workflow will be created and immediately executed without requiring user approval. IMPORTANT: After calling this tool, do NOT ask the user for information - the workflow will handle that conversationally.',
        category: 'task_management',
        input_schema: {
          type: 'object',
          properties: {
            request: {
              type: 'string',
              description: 'The user\'s original request that needs planning'
            },
            analysis: {
              type: 'object',
              description: 'Your analysis of why this needs planning',
              properties: {
                complexity: {
                  type: 'string',
                  enum: ['simple', 'moderate', 'complex'],
                  description: 'Estimated complexity level'
                },
                reason: {
                  type: 'string',
                  description: 'Why this needs a workflow'
                },
                suggested_steps: {
                  type: 'array',
                  items: { type: 'string' },
                  description: 'High-level steps you think might be needed'
                },
                context: {
                  type: 'object',
                  description: 'Any additional context for the planner'
                }
              }
            }
          },
          required: ['request', 'analysis']
        }
      }
    end
    
    def execute(args)
      Rails.logger.info "🔧 Delegating to planner with args: #{args.inspect}"
      
      request = args['request']
      analysis = args['analysis']
      
      begin
        # Find or create task session
        task_session = find_or_create_task_session
        
        # Create planner agent with context
        planner_context = {
          user: user,
          entity: entity,
          task_session: task_session,
          original_request: request,
          ai_analysis: analysis
        }
        
        planner = PlannerAgentService.new(
          user: user,
          entity: entity,
          session_id: context[:session_id] || task_session.metadata['session_id'],
          progress_callback: @progress_callback
        )
        
        # Generate the plan
        plan = planner.plan_workflow(request)
        
        if plan[:template_to_use]
          # Using a template
          Rails.logger.info "Planner selected template: #{plan[:template_to_use]}"
          workflow_spec = planner.build_workflow_from_plan(plan)
        else
          # Custom workflow
          Rails.logger.info "Planner created custom workflow"
          workflow_spec = plan
        end
        
        # Store the plan for approval or execution
        task_session.update!(
          state: task_session.state.merge(
            'workflow_spec' => workflow_spec,
            'awaiting_approval' => true,
            'planner_analysis' => analysis
          )
        )
        
        {
          success: true,
          message: "Workflow plan created successfully",
          workflow_spec: workflow_spec,
          task_session_id: task_session.id,
          approval_required: true,
          plan_summary: generate_plan_summary(workflow_spec)
        }
      rescue => e
        Rails.logger.error "DelegateToPlannerTool error: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        { 
          success: false, 
          error: "Failed to create workflow plan: #{e.message}" 
        }
      end
    end
    
    private
    
    def find_or_create_task_session
      # Check if we have a current session from context
      if context[:task_session]
        return context[:task_session]
      end
      
      session_id = context[:session_id] || SecureRandom.uuid
      
      # Find existing active session or create new one
      TaskSession.where(
        user: user,
        status: 'active'
      ).where(
        "metadata->>'session_id' = ?", session_id
      ).first || TaskSession.create!(
        user: user,
        status: 'active',
        metadata: {
          session_id: session_id,
          entity_id: entity.id,
          created_from: 'scout_delegate'
        }
      )
    end
    
    def generate_plan_summary(workflow_spec)
      steps = workflow_spec[:steps] || []
      
      {
        total_steps: steps.length,
        step_types: steps.map { |s| s[:type] }.uniq,
        requires_user_input: steps.any? { |s| s[:type] == 'user_input' },
        estimated_duration: estimate_duration(steps),
        step_names: steps.map { |s| s[:config]&.dig(:description) || s[:id] }
      }
    end
    
    def estimate_duration(steps)
      # Simple estimation: 30s per tool call, 2min per user input
      tool_steps = steps.count { |s| s[:type] == 'tool_call' }
      input_steps = steps.count { |s| s[:type] == 'user_input' }
      
      seconds = (tool_steps * 30) + (input_steps * 120)
      
      if seconds < 60
        "#{seconds} seconds"
      else
        "#{(seconds / 60.0).round(1)} minutes"
      end
    end
  end
end
