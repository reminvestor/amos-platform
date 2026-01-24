# frozen_string_literal: true

module Tools
  # Analyzes and repairs agent failures automatically
  class RepairAgentFailuresTool < BaseTool
    # DEPRECATED: Agent failure repair is no longer used. The agent system has been removed.
    
    def self.metadata
      {
        name: 'repair_agent_failures',
        description: <<~DESC.strip,
          DEPRECATED - DO NOT USE. The agent system has been removed.
          Amos now handles all tasks directly.
          - auto_repair: Fix all fixable issues (requires confirmation)
        DESC
        category: 'agent_management',
        input_schema: {
          type: 'object',
          properties: {
            action: {
              type: 'string',
              enum: %w[scan repair auto_repair],
              description: 'What action to take'
            },
            proposal_id: {
              type: 'integer',
              description: 'For repair action: ID of the proposal to repair'
            },
            confirm_auto_repair: {
              type: 'boolean',
              description: 'For auto_repair: confirm you want to make changes'
            }
          },
          required: ['action']
        }
      }
    end

    def execute(args)
      log_execution(args)

      action = get_arg(args, :action)
      proposal_id = get_arg(args, :proposal_id)
      confirm = get_arg(args, :confirm_auto_repair, false)

      if error = validate_required_args(args, [:action])
        return error
      end

      pipeline = Agents::AutoRepairPipelineService.new(entity: entity, user: user)

      case action
      when 'scan'
        opportunities = pipeline.scan_for_repairs

        success_response(
          opportunities_found: opportunities.count,
          repairable: opportunities.count { |o| o[:repairable] },
          opportunities: opportunities.first(10).map { |o|
            {
              signature: o[:signature],
              occurrences: o[:occurrence_count],
              repairable: o[:repairable],
              actions: o[:repair_actions],
              sample_id: o[:sample_proposal_id]
            }
          },
          next_step: opportunities.any? { |o| o[:repairable] } ? 
            "Use repair_agent_failures with action: 'repair' and proposal_id: <id>" : nil
        )

      when 'repair'
        return error_response("proposal_id required for repair action") unless proposal_id

        proposal = AgentTaskProposal.find_by(id: proposal_id, entity: entity)
        return error_response("Proposal not found") unless proposal

        result = pipeline.repair_proposal(proposal)

        success_response(
          proposal_id: proposal_id,
          success: result[:success],
          diagnosis: result[:diagnosis],
          repairs: result[:repairs],
          can_retry: result[:can_retry],
          message: result[:message]
        )

      when 'auto_repair'
        if confirm
          result = pipeline.auto_repair_all(dry_run: false)
          success_response(
            dry_run: false,
            opportunities_found: result[:opportunities_found],
            repairable: result[:repairable],
            results: result[:results],
            message: "Auto-repair completed"
          )
        else
          result = pipeline.auto_repair_all(dry_run: true)
          success_response(
            dry_run: true,
            opportunities_found: result[:opportunities_found],
            repairable: result[:repairable],
            would_repair: result[:results],
            message: "Dry run complete. Set confirm_auto_repair: true to apply changes."
          )
        end

      else
        error_response("Unknown action: #{action}")
      end
    rescue => e
      Rails.logger.error "[RepairAgentFailures] Error: #{e.message}"
      error_response("Failed to repair failures: #{e.message}")
    end
  end
end





