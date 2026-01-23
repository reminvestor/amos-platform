# frozen_string_literal: true

module Tools
  # Gets the status of an execution plan
  class GetPlanStatusTool < BaseTool
    def self.metadata
      {
        name: 'get_plan_status',
        description: <<~DESC.strip,
          Get the current status of an execution plan.
          
          Shows progress, current phase/step, any blockers, and next actions.
          Can also list all active plans for the user.
        DESC
        category: 'planning',
        input_schema: {
          type: 'object',
          properties: {
            plan_id: {
              type: 'integer',
              description: 'Specific plan ID to check (optional - lists all active plans if not provided)'
            },
            include_details: {
              type: 'boolean',
              description: 'Include full step details (default: false)'
            }
          },
          required: []
        }
      }
    end

    def self.read_only?
      true
    end

    def execute(args)
      log_execution(args)

      plan_id = get_arg(args, :plan_id)
      include_details = get_arg(args, :include_details, false)

      if plan_id
        plan = ExecutionPlan.find_by(id: plan_id, entity: entity)
        return error_response("Plan not found") unless plan

        success_response(
          plan: include_details ? plan.to_detailed : plan.to_summary
        )
      else
        # List all active plans
        active_plans = ExecutionPlan.where(entity: entity)
          .active
          .order(created_at: :desc)
          .limit(10)

        success_response(
          active_plans: active_plans.map(&:to_summary),
          count: active_plans.count,
          message: active_plans.any? ? 
            "#{active_plans.count} active plan(s)" : 
            "No active plans"
        )
      end
    end
  end
end





