# frozen_string_literal: true

module Agents
  # Auto-Repair Pipeline: Analyzes failed proposals and attempts to fix capability gaps
  # Can: create missing tools, update agent configurations, suggest training
  class AutoRepairPipelineService
    attr_reader :entity, :user

    def initialize(entity:, user: nil)
      @entity = entity
      @user = user
    end

    # Analyze a specific failed proposal and attempt repair
    def repair_proposal(proposal)
      return { success: false, error: 'Proposal not failed/rejected' } unless proposal.rejected? || proposal.failed?

      diagnosis = diagnose_failure(proposal)
      
      return { success: false, diagnosis: diagnosis, repairs: [] } unless diagnosis[:repairable]

      repairs = attempt_repairs(proposal, diagnosis)

      {
        success: repairs.any? { |r| r[:success] },
        diagnosis: diagnosis,
        repairs: repairs,
        can_retry: repairs.all? { |r| r[:success] },
        message: build_repair_summary(repairs)
      }
    end

    # Scan for repair opportunities across recent failures
    def scan_for_repairs(limit: 50)
      failed_proposals = AgentTaskProposal.where(entity: entity)
        .where(status: %w[rejected failed])
        .where('created_at > ?', 7.days.ago)
        .order(created_at: :desc)
        .limit(limit)

      opportunities = failed_proposals.group_by { |p| failure_signature(p) }

      opportunities.map do |signature, proposals|
        sample = proposals.first
        diagnosis = diagnose_failure(sample)
        
        {
          signature: signature,
          occurrence_count: proposals.count,
          diagnosis: diagnosis,
          repairable: diagnosis[:repairable],
          repair_actions: diagnosis[:repairable] ? suggest_repair_actions(diagnosis) : [],
          sample_proposal_id: sample.id
        }
      end.sort_by { |o| -o[:occurrence_count] }
    end

    # Auto-repair all fixable issues
    def auto_repair_all(dry_run: true)
      opportunities = scan_for_repairs

      results = opportunities.select { |o| o[:repairable] }.map do |opportunity|
        proposal = AgentTaskProposal.find(opportunity[:sample_proposal_id])
        
        if dry_run
          {
            proposal_id: proposal.id,
            would_repair: true,
            actions: opportunity[:repair_actions]
          }
        else
          repair_proposal(proposal)
        end
      end

      {
        dry_run: dry_run,
        opportunities_found: opportunities.count,
        repairable: opportunities.count { |o| o[:repairable] },
        results: results
      }
    end

    # Create a missing tool based on what agents need
    def create_missing_tool(tool_name:, based_on_proposals: [])
      # Analyze proposals to understand what the tool should do
      tool_spec = infer_tool_specification(tool_name, based_on_proposals)
      
      return { success: false, error: 'Could not infer tool specification' } unless tool_spec

      # Delegate to Tool Builder agent
      {
        success: true,
        action: 'delegate_to_tool_builder',
        tool_spec: tool_spec,
        message: "Tool '#{tool_name}' specification ready for Tool Builder"
      }
    end

    private

    def diagnose_failure(proposal)
      diagnosis = {
        proposal_id: proposal.id,
        agent: proposal.receiving_agent&.slug,
        task_type: proposal.task_type,
        failure_type: determine_failure_type(proposal),
        issues: [],
        repairable: false
      }

      # Check for missing tools
      if proposal.missing_tools.present?
        proposal.missing_tools.each do |tool|
          diagnosis[:issues] << {
            type: 'missing_tool',
            tool_name: tool,
            repairable: tool_can_be_created?(tool),
            repair_action: 'create_tool'
          }
        end
      end

      # Check for missing capabilities
      if proposal.missing_capabilities.present?
        proposal.missing_capabilities.each do |cap|
          diagnosis[:issues] << {
            type: 'missing_capability',
            capability: cap,
            repairable: capability_can_be_added?(cap),
            repair_action: 'add_capability'
          }
        end
      end

      # Check for agent not found
      if proposal.rejection_reason&.include?('not found')
        diagnosis[:issues] << {
          type: 'agent_not_found',
          repairable: false,
          repair_action: 'create_agent'
        }
      end

      # Check for wrong agent type
      if proposal.failure_reason&.include?('cannot') || proposal.rejection_reason&.include?('Cannot')
        diagnosis[:issues] << {
          type: 'wrong_agent',
          repairable: true,
          repair_action: 'route_to_different_agent'
        }
      end

      diagnosis[:repairable] = diagnosis[:issues].any? { |i| i[:repairable] }
      diagnosis
    end

    def determine_failure_type(proposal)
      if proposal.missing_tools.present?
        'missing_tools'
      elsif proposal.missing_capabilities.present?
        'missing_capabilities'
      elsif proposal.rejection_reason.present?
        'rejected'
      elsif proposal.failure_reason.present?
        'execution_failed'
      else
        'unknown'
      end
    end

    def failure_signature(proposal)
      [
        proposal.receiving_agent&.slug,
        proposal.task_type,
        (proposal.missing_tools || []).sort.join(','),
        (proposal.missing_capabilities || []).sort.join(',')
      ].join('|')
    end

    def tool_can_be_created?(tool_name)
      # Check if we have a Tool Builder agent
      tool_builder = AgentPlugin.find_by(slug: 'tool_builder', status: 'active')
      return false unless tool_builder

      # Check if this is a known pattern we can auto-generate
      known_patterns = %w[
        update_ create_ get_ list_ delete_ search_ query_
        sync_ export_ import_ analyze_ validate_
      ]

      known_patterns.any? { |pattern| tool_name.start_with?(pattern) }
    end

    def capability_can_be_added?(capability)
      # Capabilities that can be added by updating agent configuration
      addable_capabilities = %w[
        update_records create_records query_data
        fix_modules fix_canvases web_research
        code_execution data_analysis
      ]

      addable_capabilities.include?(capability)
    end

    def suggest_repair_actions(diagnosis)
      diagnosis[:issues].select { |i| i[:repairable] }.map do |issue|
        case issue[:repair_action]
        when 'create_tool'
          {
            action: 'create_tool',
            tool_name: issue[:tool_name],
            method: 'delegate_to_tool_builder',
            description: "Create tool '#{issue[:tool_name]}' using Tool Builder"
          }
        when 'add_capability'
          {
            action: 'add_capability',
            capability: issue[:capability],
            method: 'update_agent_config',
            description: "Add '#{issue[:capability]}' capability to agent"
          }
        when 'route_to_different_agent'
          {
            action: 'reroute',
            method: 'use_smart_router',
            description: 'Find a more suitable agent using Smart Router'
          }
        end
      end.compact
    end

    def attempt_repairs(proposal, diagnosis)
      repairs = []

      diagnosis[:issues].select { |i| i[:repairable] }.each do |issue|
        repair = attempt_single_repair(proposal, issue)
        repairs << repair
      end

      repairs
    end

    def attempt_single_repair(proposal, issue)
      case issue[:repair_action]
      when 'create_tool'
        attempt_tool_creation(issue[:tool_name], proposal)
      when 'add_capability'
        attempt_capability_addition(proposal.receiving_agent, issue[:capability])
      when 'route_to_different_agent'
        attempt_rerouting(proposal)
      else
        { success: false, error: "Unknown repair action: #{issue[:repair_action]}" }
      end
    end

    def attempt_tool_creation(tool_name, proposal)
      # Check if Tool Builder exists
      tool_builder = AgentPlugin.find_by(slug: 'tool_builder', status: 'active')
      
      unless tool_builder
        return { 
          success: false, 
          action: 'create_tool',
          tool_name: tool_name,
          error: 'Tool Builder agent not available'
        }
      end

      # Create a proposal to the Tool Builder
      tool_spec = infer_tool_specification(tool_name, [proposal])

      {
        success: true,
        action: 'create_tool',
        tool_name: tool_name,
        status: 'queued',
        tool_spec: tool_spec,
        message: "Tool creation request queued for Tool Builder",
        next_step: "Use delegate_to_agent with agent_type: 'tool_builder' and task: 'Create tool #{tool_name}'"
      }
    end

    def attempt_capability_addition(agent, capability)
      return { success: false, error: 'Agent not found' } unless agent

      # Add capability to agent's configuration
      current_caps = agent.capabilities_definition&.dig('capabilities') || []
      
      if current_caps.include?(capability)
        return { success: true, action: 'add_capability', status: 'already_exists' }
      end

      new_caps = current_caps + [capability]
      agent.update!(
        capabilities_definition: (agent.capabilities_definition || {}).merge('capabilities' => new_caps)
      )

      {
        success: true,
        action: 'add_capability',
        capability: capability,
        agent: agent.slug,
        message: "Added '#{capability}' to #{agent.name}"
      }
    end

    def attempt_rerouting(proposal)
      router = SmartRouterService.new(entity: entity, user: user)
      
      alternatives = router.find_best_agent(
        task_description: proposal.task_description,
        task_type: proposal.task_type,
        tools_needed: proposal.tools_needed || []
      )

      if alternatives.any? && alternatives.first[:total_score] >= 60
        best = alternatives.first
        {
          success: true,
          action: 'reroute',
          original_agent: proposal.receiving_agent&.slug,
          recommended_agent: best[:agent_slug],
          confidence: best[:total_score],
          message: "Recommend routing to #{best[:agent_name]} (score: #{best[:total_score]})"
        }
      else
        {
          success: false,
          action: 'reroute',
          error: 'No suitable alternative agent found'
        }
      end
    end

    def infer_tool_specification(tool_name, proposals)
      # Analyze the context of proposals to infer what the tool should do
      contexts = proposals.map { |p| p.context || {} }
      task_descriptions = proposals.map(&:task_description)
      object_types = proposals.flat_map { |p| p.object_types || [] }.uniq

      # Infer tool type from name
      if tool_name.start_with?('update_')
        {
          name: tool_name,
          type: 'data_mutation',
          description: "Update #{tool_name.sub('update_', '')} records",
          inferred_from: task_descriptions.first(3),
          object_types: object_types,
          suggested_parameters: ['id', 'data']
        }
      elsif tool_name.start_with?('get_') || tool_name.start_with?('list_')
        {
          name: tool_name,
          type: 'data_query',
          description: "Retrieve #{tool_name.sub(/^(get_|list_)/, '')} data",
          inferred_from: task_descriptions.first(3),
          object_types: object_types,
          suggested_parameters: ['filters', 'limit']
        }
      elsif tool_name.start_with?('create_')
        {
          name: tool_name,
          type: 'data_creation',
          description: "Create new #{tool_name.sub('create_', '')} records",
          inferred_from: task_descriptions.first(3),
          object_types: object_types,
          suggested_parameters: ['data']
        }
      else
        {
          name: tool_name,
          type: 'custom',
          description: "Tool inferred from failed proposals",
          inferred_from: task_descriptions.first(3),
          object_types: object_types,
          suggested_parameters: []
        }
      end
    end

    def build_repair_summary(repairs)
      successful = repairs.select { |r| r[:success] }
      failed = repairs.reject { |r| r[:success] }

      parts = []
      parts << "#{successful.count} repair(s) successful" if successful.any?
      parts << "#{failed.count} repair(s) failed" if failed.any?
      
      parts.join(', ')
    end
  end
end





