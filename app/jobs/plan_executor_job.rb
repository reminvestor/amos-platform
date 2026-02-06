# frozen_string_literal: true

# PlanExecutorJob - Autonomously executes steps in an ExecutionPlan
#
# This job is queued when a plan is ready for execution and processes
# steps one at a time, respecting dependencies and handling failures.
#
class PlanExecutorJob < ApplicationJob
  queue_as :default

  # Retry with exponential backoff for transient failures
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(plan_id, options = {})
    @plan = ExecutionPlan.find_by(id: plan_id)
    return unless @plan

    @options = options.symbolize_keys
    @max_steps = @options[:max_steps] || 50  # Safety limit
    @steps_executed = 0

    Rails.logger.info "[PlanExecutor] Starting autonomous execution of plan ##{plan_id}: #{@plan.title}"

    # Ensure plan is in executable state
    unless %w[ready executing].include?(@plan.status)
      Rails.logger.info "[PlanExecutor] Plan ##{plan_id} not executable (status: #{@plan.status})"
      return
    end

    # Start execution if not already started
    @plan.start_execution! if @plan.status == 'ready'

    # Execute steps until done, blocked, or limit reached
    execute_pending_steps
  end

  private

  def execute_pending_steps
    loop do
      break if @steps_executed >= @max_steps
      break unless %w[executing].include?(@plan.reload.status)

      # Get next executable step
      step = @plan.next_step
      
      unless step
        # No more steps - check if all complete
        if @plan.all_steps_completed?
          @plan.complete!
          Rails.logger.info "[PlanExecutor] Plan ##{@plan.id} completed successfully!"
        else
          Rails.logger.info "[PlanExecutor] Plan ##{@plan.id} - no executable steps (may be blocked or all done)"
        end
        break
      end

      # Execute the step
      result = execute_step(step)
      @steps_executed += 1

      # Handle the result
      case result[:status]
      when 'completed'
        Rails.logger.info "[PlanExecutor] Step '#{step['name']}' completed"
        # Continue to next step
      when 'delegating', 'delegated'
        Rails.logger.info "[PlanExecutor] Step '#{step['name']}' delegated to agent"
        # Agent will handle it - we need to wait for callback
        # Schedule a follow-up check
        PlanExecutorJob.set(wait: 30.seconds).perform_later(@plan.id, check_pending: true)
        break
      when 'failed'
        Rails.logger.error "[PlanExecutor] Step '#{step['name']}' failed: #{result[:error]}"
        handle_step_failure(step, result)
        break if @plan.status == 'paused' || @plan.status == 'failed'
      when 'needs_orchestration'
        Rails.logger.info "[PlanExecutor] Step '#{step['name']}' needs orchestration"
        # This step requires the main AI to handle it
        handle_orchestration_step(step)
      else
        Rails.logger.warn "[PlanExecutor] Unknown step status: #{result[:status]}"
        break
      end
    end
  end

  def execute_step(step)
    step_id = step['id']
    agent_slug = step['agent']

    # Mark step as started
    @plan.mark_step_started!(step_id)

    # If no agent assigned, this needs orchestration
    unless agent_slug
      return { status: 'needs_orchestration', step: step }
    end

    # Find the agent - first try exact slug, then use Smart Router to find best match
    agent = AgentPlugin.find_by(slug: agent_slug, status: 'active')
    tools_needed = step['tools_needed'] || []
    
    # Check if agent has the required tools (or use Smart Router if not)
    if agent
      agent_tools = agent.agent_tools.pluck(:tool_name)
      if agent_tools.empty? || (tools_needed.present? && (tools_needed - agent_tools).any?)
        Rails.logger.info "[PlanExecutor] Agent '#{agent_slug}' missing tools, using Smart Router"
        agent = nil  # Force Smart Router lookup
      end
    end
    
    unless agent
      # Agent not found or lacks tools - use RAG search for best match
      task_desc = step['description'] || step['name']
      Rails.logger.info "[PlanExecutor] Using RAG search to find agent for step '#{step['name']}'"
      
      rag_results = AgentPlugin.search_by_similarity(task_desc, limit: 5, entity: @plan.entity)
      
      # Find first result with actual tools
      rag_results.each do |candidate|
        candidate_tools = candidate.agent_tools.pluck(:tool_name)
        if candidate_tools.any?
          agent = candidate
          Rails.logger.info "[PlanExecutor] RAG found agent: #{agent.slug} with #{candidate_tools.size} tools"
          break
        end
      end
      
      # Fallback to Smart Router if RAG fails
      unless agent
        Rails.logger.info "[PlanExecutor] RAG failed, trying Smart Router..."
        router = Agents::SmartRouterService.new(entity: @plan.entity, user: @plan.user)
        results = router.find_best_agent(
          task_description: task_desc,
          tools_needed: tools_needed
        )
        
        if results.any?
          agent = AgentPlugin.find_by(slug: results.first[:agent_slug], status: 'active')
          Rails.logger.info "[PlanExecutor] Smart Router found agent: #{agent&.slug}"
        end
      end
    end
    
    unless agent
      @plan.mark_step_failed!(step_id, error: "Agent '#{agent_slug}' not found")
      return { status: 'failed', error: "Agent not found" }
    end

    # Create proposal using handshake protocol
    proposal = AgentTaskProposal.create!(
      proposing_agent: nil,
      receiving_agent: agent,
      entity: @plan.entity,
      user: @plan.user,
      task_description: step['description'] || step['name'],
      task_type: infer_task_type(step),
      tools_needed: step['tools_needed'] || [],
      context: {
        plan_id: @plan.id,
        step_id: step_id,
        plan_title: @plan.title,
        autonomous: true
      },
      status: 'proposed'
    )

    evaluation = proposal.evaluate_capability

    if evaluation[:accepted]
      proposal.accept!(confidence: evaluation[:confidence], details: evaluation[:details])
      
      # Actually delegate to the agent
      delegate_result = delegate_to_agent(agent, step, proposal)
      
      if delegate_result[:success]
        { status: 'delegated', execution_id: delegate_result[:execution_id] }
      else
        @plan.mark_step_failed!(step_id, error: delegate_result[:error])
        { status: 'failed', error: delegate_result[:error] }
      end
    else
      proposal.reject!(
        reason: evaluation[:reason],
        missing_tools: evaluation[:missing_tools] || []
      )
      
      @plan.mark_step_failed!(step_id, error: evaluation[:reason])
      { status: 'failed', error: evaluation[:reason] }
    end
  end

  def delegate_to_agent(agent, step, proposal)
    # Build enriched task description
    task_description = build_task_description(step)

    # Generate a session_id for this execution - CRITICAL for tool calling to work!
    # Without session_id, agents may hallucinate tool calls instead of using native Bedrock tools
    session_id = "plan_#{@plan.id}_step_#{step['id']}_#{SecureRandom.hex(4)}"

    # Create the execution - use 'running' status (pending is not valid)
    execution = AgentPluginExecution.create!(
      agent_plugin: agent,
      user: @plan.user,
      status: 'running',
      started_at: Time.current,
      input_context: {
        task: task_description,
        entity_id: @plan.entity.id,  # Pass entity for agent context
        plan_id: @plan.id,
        step_id: step['id'],
        proposal_id: proposal.id,
        session_id: session_id  # CRITICAL: session_id enables proper tool execution
      }
    )

    Rails.logger.info "[PlanExecutor] Delegating step '#{step['name']}' to #{agent.slug} with session_id: #{session_id}"

    # Queue the agent execution job with required parameters
    AgentPluginExecutionJob.perform_later(
      execution.id,
      task_description,
      {
        plan_id: @plan.id,
        step_id: step['id'],
        proposal_id: proposal.id,
        entity_id: @plan.entity.id,
        session_id: session_id  # CRITICAL: Pass session_id to job context
      }
    )

    { success: true, execution_id: execution.id }
  rescue => e
    Rails.logger.error "[PlanExecutor] Delegation failed: #{e.message}"
    { success: false, error: e.message }
  end

  def build_task_description(step)
    parts = []
    
    # Check if this is an autonomous execution (no user present to answer questions)
    # This is determined by:
    # 1. Plan metadata setting (explicit)
    # 2. Whether the plan was auto-executed without user approval
    # 3. Option passed to the job
    is_autonomous = autonomous_execution?
    
    if is_autonomous
      # Autonomous mode: Agent should not ask questions
      parts << "## AUTONOMOUS EXECUTION MODE"
      parts << "⚠️ IMPORTANT: This is an autonomous plan execution. You MUST:"
      parts << "- Make reasonable decisions without asking questions"
      parts << "- Use default/sensible values when specifics aren't provided"
      parts << "- DO NOT use ask_user tool - there is no user to respond"
      parts << "- Proceed with your best judgment based on context"
      parts << ""
    else
      # Interactive mode: Agent can ask clarifying questions
      parts << "## INTERACTIVE EXECUTION MODE"
      parts << "You may ask the user clarifying questions if needed to deliver the best result."
      parts << "Use the ask_user tool if you need more information."
      parts << ""
    end
    
    parts << "## TASK"
    parts << (step['description'] || step['name'])
    
    parts << "\n## CONTEXT"
    parts << "Plan: #{@plan.title}"
    parts << "Goal: #{@plan.original_request}"
    
    # Add completed step results
    completed = @plan.all_steps.select { |s| s['status'] == 'completed' }
    if completed.any?
      parts << "\n## COMPLETED STEPS"
      completed.each do |s|
        result_summary = s['result'].to_s.truncate(200)
        parts << "- #{s['name']}: #{result_summary}"
      end
    end
    
    parts.join("\n")
  end

  def autonomous_execution?
    # Check explicit autonomous flags ONLY
    # These are set intentionally by benchmarks or scheduled tasks
    return true if @options[:autonomous] == true
    return true if @plan.user_decisions&.dig('autonomous') == true
    return true if @plan.user_decisions&.dig('execution_mode') == 'autonomous'
    
    # Default: interactive mode (user is present, can ask questions)
    # Note: We removed the requires_approval fallback because it was triggering
    # autonomous mode for normal user requests. If a request needs to be autonomous,
    # it should explicitly set autonomous=true in user_decisions.
    false
  end

  def handle_step_failure(step, result)
    # Check retry count
    if (@plan.retry_count || 0) < 3
      Rails.logger.info "[PlanExecutor] Retrying failed step..."
      @plan.increment!(:retry_count)
      
      # Reset step and retry
      @plan.send(:update_step, step['id'], 'status' => 'pending', 'error' => nil)
      @plan.decrement!(:failed_steps) if @plan.failed_steps > 0
      
      # Continue execution
    else
      Rails.logger.error "[PlanExecutor] Max retries reached, pausing plan"
      @plan.pause!(reason: "Step '#{step['name']}' failed after 3 retries: #{result[:error]}")
    end
  end

  def handle_orchestration_step(step)
    # These steps need the main AI to handle them
    # For now, we'll try to execute them using Scout
    
    # Create a work item for the orchestrator to handle
    work_item = AgentWorkItem.create!(
      entity: @plan.entity,
      user: @plan.user,
      work_type: 'task_completed',  # Valid work_type
      priority: 'high',
      title: "Execute plan step: #{step['name']}",
      summary: step['description'],
      requires_action: true,
      action_type: 'execute',
      metadata: {
        plan_id: @plan.id,
        step_id: step['id'],
        step_description: step['description'],
        tools_needed: step['tools_needed']
      }
    )

    Rails.logger.info "[PlanExecutor] Created work item ##{work_item.id} for orchestration step"
    
    # For autonomous execution, try to use Scout directly
    execute_via_scout(step)
  end

  def execute_via_scout(step)
    session_id = "plan_#{@plan.id}_step_#{step['id']}_#{Time.current.to_i}"

    prompt = "You are executing step '#{step['name']}' of a plan.\n\n"
    prompt += "Plan goal: #{@plan.original_request}\n\n"
    prompt += "Step to execute: #{step['description'] || step['name']}\n\n"
    prompt += "Please complete this step now."

    begin
      agent = V3::AgentLoop.new(
        user: @plan.user,
        entity: @plan.entity,
        session_id: session_id,
        model: ENV.fetch("BEDROCK_DEFAULT_MODEL", "anthropic.claude-sonnet-4-v1")
      )

      result = agent.process_message_streaming(prompt, ->(_) {}, [])

      response_content = result.dig(:final_response, :message) || ""
      @plan.mark_step_completed!(step['id'], result: { response: response_content.truncate(500) })
    rescue => e
      Rails.logger.error "[PlanExecutor] V3 execution failed: #{e.message}"
      @plan.mark_step_failed!(step['id'], error: e.message)
    end
  end

  def infer_task_type(step)
    tools = step['tools_needed'] || []
    
    if tools.any? { |t| t.include?('create') || t.include?('generate') }
      'create_record'
    elsif tools.any? { |t| t.include?('update') || t.include?('module') }
      'update_schema'
    elsif tools.any? { |t| t.include?('get') || t.include?('query') }
      'query_data'
    else
      'custom'
    end
  end
end

