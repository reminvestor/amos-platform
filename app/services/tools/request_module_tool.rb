# frozen_string_literal: true

# RequestModuleTool
#
# Tool for Amos (Scout) to request a new module from the Platform Factory.
# This is the entry point for users asking for custom functionality.
#
# KEY ARCHITECTURE:
# This tool delegates to the Planner system rather than directly calling
# PlatformFactoryJob. This ensures complex module creation goes through
# proper planning, step-by-step execution, and error handling.
#
class Tools::RequestModuleTool < Tools::BaseTool
  def self.metadata
    {
      name: 'request_module',
      description: 'Request the Platform Factory to build a new custom module. Use this when users ask for functionality that doesn\'t exist yet, like "I need inventory tracking" or "Build me a project management system". This delegates to the Planner for structured execution.',
      category: 'platform_factory',
      input_schema: {
        type: 'object',
        properties: {
          module_name: {
            type: 'string',
            description: 'Name for the module (e.g., "Inventory Management", "Project Tracker")'
          },
          requirements: {
            type: 'string',
            description: 'Detailed requirements for what the module should do'
          },
          features: {
            type: 'array',
            items: { type: 'string' },
            description: 'List of specific features needed'
          },
          integrations: {
            type: 'array',
            items: { type: 'string' },
            description: 'External services to integrate with (optional)'
          },
          ui_modes: {
            type: 'array',
            items: { type: 'string', enum: %w[simple advanced] },
            description: 'Which UI modes to support'
          },
          auto_execute: {
            type: 'boolean',
            description: 'Start building immediately without approval (default: true)'
          }
        },
        required: %w[module_name requirements]
      }
    }
  end

  def execute(args)
    log_execution(args)

    module_name = get_arg(args, :module_name)
    requirements = get_arg(args, :requirements)
    features = get_arg(args, :features, [])
    integrations = get_arg(args, :integrations, [])
    ui_modes = get_arg(args, :ui_modes, ['simple'])
    # Default to false - user requests should be interactive, not autonomous
    # Only benchmarks should set auto_execute: true
    auto_execute = get_arg(args, :auto_execute, false)

    return error_response('Module name is required') if module_name.blank?
    return error_response('Requirements are required') if requirements.blank?

    # Build the full request string for the planner
    full_request = build_request_string(module_name, requirements, features, integrations)

    # Delegate to the Planner system
    # This creates an ExecutionPlan that will be executed step-by-step
    planner_result = delegate_to_planner(full_request, auto_execute)

    if planner_result[:success]
      success_response(
        plan_id: planner_result[:plan_id],
        plan_title: planner_result[:title],
        status: planner_result[:status],
        complexity: planner_result[:complexity],
        requires_approval: planner_result[:requires_approval],
        prompt_user: planner_result[:prompt_user],
        suggested_canvas: planner_result[:suggested_canvas],
        user_action_required: planner_result[:user_action_required],
        message: build_success_message(module_name, planner_result),
        estimated_time: "#{planner_result.dig(:plan_summary, :estimated_minutes) || 5} minutes",
        next_step: build_next_step_message(planner_result)
      )
    else
      error_response("Failed to create module plan: #{planner_result[:error]}")
    end
  end

  private

  def build_request_string(module_name, requirements, features, integrations)
    parts = ["Build a #{module_name} module."]
    parts << "Requirements: #{requirements}"
    parts << "Features needed: #{features.join(', ')}" if features.any?
    parts << "Integrate with: #{integrations.join(', ')}" if integrations.any?
    parts.join("\n")
  end

  def delegate_to_planner(request, auto_execute)
    # Use the existing delegate_to_planner tool
    planner_tool = Tools::DelegateToPlannerTool.new(
      user: user,
      entity: entity,
      context: context
    )

    result = planner_tool.execute(
      request: request,
      analysis: {
        'complexity' => 'complex',
        'reason' => 'Building a custom module requires multiple phases: design, code generation, deployment, and validation',
        'key_components' => ['data_models', 'user_interfaces', 'ai_tools'],
        'agents_likely_needed' => ['platform_factory']
      },
      auto_execute: auto_execute
    )

    # The result from delegate_to_planner is already a hash with plan details
    result
  end

  def build_success_message(module_name, planner_result)
    if planner_result[:status] == 'executing'
      "🚀 Building '#{module_name}'! The Platform Factory is now working on your module."
    elsif planner_result[:status] == 'ready'
      "📋 Plan created for '#{module_name}'. Ready to start building."
    else
      "📝 Created execution plan for '#{module_name}'."
    end
  end

  def build_next_step_message(planner_result)
    if planner_result[:status] == 'executing'
      "I'll notify you when it's ready. You can check progress by asking 'What's the status of my module?'"
    elsif planner_result[:requires_approval]
      "Review the plan and say 'approve' to start building, or ask me to modify it."
    else
      "Building will start automatically. I'll let you know when it's ready!"
    end
  end
end
