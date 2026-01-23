# frozen_string_literal: true

module Tools
  # Allows modification of execution plans
  class ModifyPlanTool < BaseTool
    def self.metadata
      {
        name: 'modify_plan',
        description: <<~DESC.strip,
          Modify an existing execution plan based on user feedback.
          
          Supports:
          - Adding review checkpoints after steps
          - Skipping phases
          - Reordering steps
          - Adding new steps
          - Removing steps
          - Changing agent assignments
          - Updating step descriptions
        DESC
        category: 'planning',
        input_schema: {
          type: 'object',
          properties: {
            plan_id: {
              type: 'integer',
              description: 'The plan to modify'
            },
            action: {
              type: 'string',
              enum: %w[add_checkpoint skip_phase add_step remove_step update_step reassign_agent reorder],
              description: 'The modification action'
            },
            target: {
              type: 'string',
              description: 'Phase name, step ID, or position depending on action'
            },
            details: {
              type: 'object',
              description: 'Additional details for the modification',
              properties: {
                step_name: { type: 'string' },
                step_description: { type: 'string' },
                agent: { type: 'string' },
                tools_needed: { type: 'array', items: { type: 'string' } },
                after_step: { type: 'string' },
                before_step: { type: 'string' },
                new_position: { type: 'integer' }
              }
            }
          },
          required: ['plan_id', 'action']
        }
      }
    end

    def execute(args)
      log_execution(args)

      plan_id = get_arg(args, :plan_id)
      action = get_arg(args, :action)
      target = get_arg(args, :target)
      details = get_arg(args, :details, {})

      if error = validate_required_args(args, [:plan_id, :action])
        return error
      end

      plan = ExecutionPlan.find_by(id: plan_id, entity: entity)
      return error_response("Plan not found") unless plan

      # Can only modify plans that aren't completed/failed
      unless plan.status.in?(%w[planning ready paused])
        return error_response(
          "Cannot modify plan in #{plan.status} status",
          suggestion: "Pause the plan first if it's executing"
        )
      end

      case action
      when 'add_checkpoint'
        add_review_checkpoint(plan, target, details)
      when 'skip_phase'
        skip_phase(plan, target)
      when 'add_step'
        add_step(plan, target, details)
      when 'remove_step'
        remove_step(plan, target)
      when 'update_step'
        update_step(plan, target, details)
      when 'reassign_agent'
        reassign_agent(plan, target, details)
      when 'reorder'
        reorder_step(plan, target, details)
      else
        error_response("Unknown action: #{action}")
      end
    end

    private

    def add_review_checkpoint(plan, after_step_id, details)
      step = plan.find_step(after_step_id)
      return error_response("Step not found: #{after_step_id}") unless step

      # Find the phase containing this step
      phase_idx, step_idx = find_step_position(plan, after_step_id)
      return error_response("Could not locate step in phases") unless phase_idx

      # Create checkpoint step
      checkpoint = {
        'id' => "#{after_step_id}_checkpoint",
        'name' => details['checkpoint_name'] || "Review: #{step['name']}",
        'description' => details['checkpoint_description'] || "Review the results before continuing",
        'agent' => nil,
        'tools_needed' => ['ask_user'],
        'status' => 'pending',
        'dependencies' => [after_step_id],
        'requires_input' => true,
        'estimated_minutes' => 5
      }

      # Update dependencies of steps that depended on the original step
      updated_phases = plan.phases.deep_dup
      updated_phases.each do |phase|
        (phase['steps'] || []).each do |s|
          if (s['dependencies'] || []).include?(after_step_id)
            s['dependencies'] = s['dependencies'] - [after_step_id] + [checkpoint['id']]
          end
        end
      end

      # Insert checkpoint after the target step
      updated_phases[phase_idx]['steps'].insert(step_idx + 1, checkpoint)

      plan.update!(
        phases: updated_phases,
        total_steps: plan.total_steps + 1
      )
      plan.send(:log_event, 'plan_modified', "Added review checkpoint after '#{step['name']}'")

      success_response(
        action: 'add_checkpoint',
        checkpoint_id: checkpoint['id'],
        after: step['name'],
        message: "Added review checkpoint after '#{step['name']}'"
      )
    end

    def skip_phase(plan, phase_name)
      phase_idx = plan.phases.find_index { |p| p['name'] == phase_name }
      return error_response("Phase not found: #{phase_name}") unless phase_idx

      updated_phases = plan.phases.deep_dup
      phase = updated_phases[phase_idx]
      step_count = (phase['steps'] || []).count

      # Mark all steps as skipped
      (phase['steps'] || []).each do |step|
        step['status'] = 'skipped'
        step['skip_reason'] = 'Phase skipped by user'
      end

      phase['status'] = 'skipped'

      plan.update!(phases: updated_phases)
      plan.send(:log_event, 'plan_modified', "Skipped phase '#{phase_name}' (#{step_count} steps)")

      success_response(
        action: 'skip_phase',
        phase: phase_name,
        steps_skipped: step_count,
        message: "Skipped phase '#{phase_name}'"
      )
    end

    def add_step(plan, phase_name, details)
      return error_response("Step name required") unless details['step_name']

      phase_idx = plan.phases.find_index { |p| p['name'] == phase_name }
      return error_response("Phase not found: #{phase_name}") unless phase_idx

      updated_phases = plan.phases.deep_dup

      new_step = {
        'id' => "step_custom_#{SecureRandom.hex(4)}",
        'name' => details['step_name'],
        'description' => details['step_description'] || details['step_name'],
        'agent' => details['agent'],
        'tools_needed' => details['tools_needed'] || [],
        'status' => 'pending',
        'dependencies' => [],
        'estimated_minutes' => details['estimated_minutes'] || 5
      }

      # Handle positioning
      if details['after_step']
        _, step_idx = find_step_position(plan, details['after_step'])
        if step_idx
          new_step['dependencies'] = [details['after_step']]
          updated_phases[phase_idx]['steps'].insert(step_idx + 1, new_step)
        else
          updated_phases[phase_idx]['steps'] << new_step
        end
      else
        updated_phases[phase_idx]['steps'] << new_step
      end

      plan.update!(
        phases: updated_phases,
        total_steps: plan.total_steps + 1
      )
      plan.send(:log_event, 'plan_modified', "Added step '#{new_step['name']}' to phase '#{phase_name}'")

      success_response(
        action: 'add_step',
        step_id: new_step['id'],
        phase: phase_name,
        message: "Added step '#{new_step['name']}'"
      )
    end

    def remove_step(plan, step_id)
      step = plan.find_step(step_id)
      return error_response("Step not found: #{step_id}") unless step

      # Check for dependents
      dependents = plan.all_steps.select { |s| (s['dependencies'] || []).include?(step_id) }
      if dependents.any?
        return error_response(
          "Cannot remove step - other steps depend on it",
          dependents: dependents.map { |s| s['name'] }
        )
      end

      updated_phases = plan.phases.deep_dup
      updated_phases.each do |phase|
        phase['steps']&.reject! { |s| s['id'] == step_id }
      end

      plan.update!(
        phases: updated_phases,
        total_steps: [plan.total_steps - 1, 0].max
      )
      plan.send(:log_event, 'plan_modified', "Removed step '#{step['name']}'")

      success_response(
        action: 'remove_step',
        step_id: step_id,
        step_name: step['name'],
        message: "Removed step '#{step['name']}'"
      )
    end

    def update_step(plan, step_id, details)
      step = plan.find_step(step_id)
      return error_response("Step not found: #{step_id}") unless step

      updates = {}
      updates['name'] = details['step_name'] if details['step_name']
      updates['description'] = details['step_description'] if details['step_description']
      updates['estimated_minutes'] = details['estimated_minutes'] if details['estimated_minutes']
      updates['tools_needed'] = details['tools_needed'] if details['tools_needed']

      return error_response("No updates provided") if updates.empty?

      plan.send(:update_step, step_id, updates)
      plan.send(:log_event, 'plan_modified', "Updated step '#{step['name']}': #{updates.keys.join(', ')}")

      success_response(
        action: 'update_step',
        step_id: step_id,
        updates: updates,
        message: "Updated step '#{step['name']}'"
      )
    end

    def reassign_agent(plan, step_id, details)
      step = plan.find_step(step_id)
      return error_response("Step not found: #{step_id}") unless step
      return error_response("New agent required") unless details['agent']

      old_agent = step['agent']
      plan.send(:update_step, step_id, 'agent' => details['agent'])
      plan.send(:log_event, 'plan_modified', 
        "Reassigned step '#{step['name']}' from #{old_agent || 'none'} to #{details['agent']}")

      success_response(
        action: 'reassign_agent',
        step_id: step_id,
        old_agent: old_agent,
        new_agent: details['agent'],
        message: "Reassigned '#{step['name']}' to #{details['agent']}"
      )
    end

    def reorder_step(plan, step_id, details)
      # This is more complex - would need to update dependencies
      # For now, just update the position in the array
      return error_response("Reordering not yet implemented - use add/remove steps")
    end

    def find_step_position(plan, step_id)
      plan.phases.each_with_index do |phase, p_idx|
        (phase['steps'] || []).each_with_index do |step, s_idx|
          return [p_idx, s_idx] if step['id'] == step_id
        end
      end
      nil
    end
  end
end





