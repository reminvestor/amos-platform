# AgentPluginExecutor - Wrapper that adapts database-backed agent plugins
# to work with the existing workflow phase executor interface.
#
# This class bridges the gap between:
# - Custom agent plugins (database-defined, user-created)
# - Built-in phase executors (GatherContextExecutor, GoalExecutor, etc.)
#
# It provides a consistent interface that the WorkflowEngine can use
# regardless of whether an agent is built-in or custom.
#
module Agents
  class AgentPluginExecutor
  attr_reader :agent_plugin, :agent_service, :phase_config, :context, :execution_record

  def initialize(agent_plugin, agent_service, phase_config, context)
    @agent_plugin = agent_plugin
    @agent_service = agent_service
    @phase_config = phase_config
    @context = context
    @execution_record = nil
  end

  # Main execution method - called by WorkflowEngine
  def execute
    Rails.logger.info "🤖 Executing agent plugin: #{agent_plugin.name}"

    # Create execution tracking record
    @execution_record = agent_service.create_execution_record(agent_plugin, execution_context)

    begin
      # Instantiate the actual agent
      agent_instance = agent_plugin.instantiate(execution_context)

      # Execute based on agent's role and phase type
      result = execute_agent_for_phase(agent_instance)

      # Mark execution as successful
      agent_service.complete_execution(execution_record, result)

      # Return in expected format
      {
        success: true,
        status: "completed",
        result: result,
        agent_plugin_id: agent_plugin.id,
        execution_id: execution_record.id
      }
    rescue => e
      Rails.logger.error "Agent plugin execution failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      # Mark execution as failed
      agent_service.fail_execution(execution_record, e.message) if execution_record

      {
        success: false,
        status: "failed",
        error: e.message,
        agent_plugin_id: agent_plugin.id
      }
    end
  end

  private

  def execute_agent_for_phase(agent_instance)
    phase_type = phase_config[:type] || phase_config["type"]

    case phase_type.to_s
    when "gather_context"
      execute_gather_context_phase(agent_instance)
    when "execute_goal"
      execute_goal_phase(agent_instance)
    when "validate_result"
      execute_validation_phase(agent_instance)
    else
      # Generic execution - let the agent handle it
      execute_generic_phase(agent_instance)
    end
  end

  def execute_gather_context_phase(agent_instance)
    # For gather_context, we need to collect information
    sources = phase_config[:sources] || phase_config["sources"] || []
    questions = phase_config[:questions] || phase_config["questions"] || []

    collected_data = {}

    # Gather from each source
    sources.each do |source|
      begin
        data = gather_from_source(agent_instance, source)
        collected_data[source] = data if data
      rescue => e
        Rails.logger.warn "Failed to gather from #{source}: #{e.message}"
      end
    end

    # Ask questions if needed
    if questions.any?
      answers = ask_questions(agent_instance, questions)
      collected_data[:user_answers] = answers if answers
    end

    collected_data
  end

  def execute_goal_phase(agent_instance)
    # For execute_goal, we execute tools to achieve the goal
    goal = phase_config[:goal] || phase_config["goal"]
    approach = phase_config[:approach] || phase_config["approach"] || "adaptive"

    if approach == "structured"
      execute_structured_goal(agent_instance, goal)
    else
      execute_adaptive_goal(agent_instance, goal)
    end
  end

  def execute_validation_phase(agent_instance)
    # For validation, check the results of previous phases
    criteria = phase_config[:criteria] || phase_config["criteria"] || []
    auto_fix = phase_config[:auto_fix] || phase_config["auto_fix"] || false

    validation_result = {
      valid: true,
      issues: [],
      fixes_applied: []
    }

    # Validate each criterion
    criteria.each do |criterion|
      result = validate_criterion(agent_instance, criterion)

      unless result[:valid]
        validation_result[:valid] = false
        validation_result[:issues] << result[:issue]

        # Try to auto-fix if enabled
        if auto_fix && result[:fixable]
          fix_result = apply_fix(agent_instance, result[:issue])
          validation_result[:fixes_applied] << fix_result if fix_result[:success]
        end
      end
    end

    validation_result
  end

  def execute_generic_phase(agent_instance)
    # For custom phases, execute the agent's run method directly
    # This gives maximum flexibility for custom agent plugins

    # Get agent's system prompt and configuration
    prompt = build_agent_prompt

    # Execute the agent
    if agent_instance.respond_to?(:run)
      agent_instance.run(prompt)
    elsif agent_instance.respond_to?(:execute)
      agent_instance.execute(execution_context)
    else
      # Fallback: use the agent's think-act-learn cycle
      run_autonomous_cycle(agent_instance)
    end
  end

  # Helper methods for gather_context

  def gather_from_source(agent_instance, source)
    case source.to_s
    when "conversation_history"
      gather_conversation_history
    when "uploaded_files"
      gather_uploaded_files
    when "workflow_context"
      gather_workflow_context
    when "entity_profile"
      gather_entity_profile
    else
      # Custom source - delegate to agent
      agent_instance.gather_data(source) if agent_instance.respond_to?(:gather_data)
    end
  end

  def ask_questions(agent_instance, questions)
    # For now, return nil - questions would be handled via user interaction
    # This would integrate with the conversational flow
    nil
  end

  # Helper methods for execute_goal

  def execute_structured_goal(agent_instance, goal)
    # Structured approach: Direct mapping to tool calls
    tool_calls = phase_config[:tool_calls] || phase_config["tool_calls"] || []

    results = {}
    tool_calls.each do |tool_call|
      tool_name = tool_call[:tool] || tool_call["tool"]
      args = tool_call[:args] || tool_call["args"] || {}

      result = execute_tool(tool_name, args)
      results[tool_name] = result
    end

    results
  end

  def execute_adaptive_goal(agent_instance, goal)
    # Adaptive approach: AI determines tool sequence
    # This would use the agent's autonomous decision-making

    if agent_instance.respond_to?(:achieve_goal)
      agent_instance.achieve_goal(goal, execution_context)
    else
      # Fallback to basic execution
      { goal: goal, approach: "adaptive", status: "delegated_to_agent" }
    end
  end

  # Helper methods for validation

  def validate_criterion(agent_instance, criterion)
    # Validate a single criterion
    # This would be customized based on the criterion type

    {
      valid: true,  # Simplified for now
      issue: nil,
      fixable: false
    }
  end

  def apply_fix(agent_instance, issue)
    # Apply a fix for an issue
    { success: false, message: "Auto-fix not implemented yet" }
  end

  # Context and utility methods

  def execution_context
    @context.merge(
      agent_plugin: agent_plugin,
      phase_config: phase_config,
      workflow_execution: @context[:workflow_execution],
      task_session: @context[:task_session]
    )
  end

  def build_agent_prompt
    system_prompt = agent_plugin.system_prompt["prompt"] || ""
    phase_instructions = phase_config[:instructions] || phase_config["instructions"] || ""

    "#{system_prompt}\n\n#{phase_instructions}"
  end

  def run_autonomous_cycle(agent_instance)
    # Run agent's autonomous perceive-think-act-learn cycle
    max_iterations = 3

    max_iterations.times do |i|
      perception = agent_instance.perceive rescue nil
      thought = agent_instance.think(perception) rescue nil
      action = agent_instance.act(thought) rescue nil
      agent_instance.learn(action) rescue nil

      # Check if goal is achieved
      break if action&.dig(:status) == "goal_achieved"
    end

    { iterations: max_iterations, status: "completed" }
  rescue => e
    { error: e.message, status: "failed" }
  end

  def execute_tool(tool_name, args)
    # Execute a tool through the ToolCatalog
    Tools::ToolCatalog.instance.execute_tool(
      tool_name,
      args,
      execution_context
    )
  rescue => e
    Rails.logger.error "Tool execution failed: #{tool_name} - #{e.message}"
    { success: false, error: e.message }
  end

  def gather_conversation_history
    # Gather conversation history from the task session
    @context[:task_session]&.conversation_history || []
  end

  def gather_uploaded_files
    # Gather files uploaded by the user
    @context[:task_session]&.uploaded_files || []
  end

  def gather_workflow_context
    # Gather persisted workflow context
    workflow_execution = @context[:workflow_execution]
    return {} unless workflow_execution

    WorkflowContext.where(workflow_execution: workflow_execution).pluck(:key, :value).to_h
  end

  def gather_entity_profile
    # Gather entity's business profile
    entity = @context[:entity]
    return {} unless entity

    {
      name: entity.name,
      business_profile: entity.business_profile&.attributes || {},
      settings: entity.settings || {}
    }
  end
end
end
