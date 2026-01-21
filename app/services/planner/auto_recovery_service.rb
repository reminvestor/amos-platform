# frozen_string_literal: true

module Planner
  # AutoRecoveryService - Proactively recovers from step failures
  #
  # Strategies:
  # 1. Retry with exponential backoff
  # 2. Try alternative agent
  # 3. Simplify step (break into smaller steps)
  # 4. Escalate to user
  #
  class AutoRecoveryService
    MAX_RETRIES = 3
    RETRY_DELAYS = [30.seconds, 2.minutes, 10.minutes].freeze

    attr_reader :plan, :step_id, :error

    def initialize(plan:, step_id:, error:)
      @plan = plan
      @step_id = step_id
      @error = error
      @step = plan.find_step(step_id)
    end

    # Attempt automatic recovery
    def attempt_recovery
      return { success: false, reason: 'Step not found' } unless @step

      strategy = determine_best_strategy
      
      case strategy
      when :retry
        attempt_retry
      when :reassign
        attempt_reassign
      when :simplify
        attempt_simplify
      when :skip
        attempt_skip
      when :escalate
        escalate_to_user
      else
        { success: false, reason: 'No recovery strategy available' }
      end
    end

    # Determine the best recovery strategy
    def determine_best_strategy
      # Check retry eligibility
      if can_retry?
        return :retry if transient_error?
      end

      # Check if alternative agent available
      if alternative_agent_available?
        return :reassign
      end

      # Check if step can be skipped
      if step_can_be_skipped?
        return :skip
      end

      # Check if step can be simplified
      if step_can_be_simplified?
        return :simplify
      end

      # Fallback to escalation
      :escalate
    end

    private

    # ============================================
    # RETRY STRATEGY
    # ============================================

    def can_retry?
      current_retries = @step['retry_count'].to_i
      current_retries < MAX_RETRIES
    end

    def transient_error?
      transient_patterns = [
        /timeout/i,
        /rate limit/i,
        /temporary/i,
        /connection/i,
        /unavailable/i,
        /busy/i,
        /try again/i
      ]

      transient_patterns.any? { |pattern| @error.to_s.match?(pattern) }
    end

    def attempt_retry
      current_retries = @step['retry_count'].to_i
      delay = RETRY_DELAYS[current_retries] || RETRY_DELAYS.last

      # Update retry count
      update_step_retry_count(current_retries + 1)

      # Schedule retry job
      PlanStepRetryJob.set(wait: delay).perform_later(
        plan_id: plan.id,
        step_id: step_id,
        retry_number: current_retries + 1
      )

      # Log the recovery attempt
      plan.send(:log_event, 'auto_recovery', 
        "Scheduled retry #{current_retries + 1}/#{MAX_RETRIES} for '#{@step['name']}' in #{delay.to_i} seconds")

      {
        success: true,
        strategy: :retry,
        retry_number: current_retries + 1,
        scheduled_for: delay.from_now,
        message: "Will retry in #{delay.to_i} seconds"
      }
    end

    def update_step_retry_count(count)
      plan.send(:update_step, step_id, 'retry_count' => count)
    end

    # ============================================
    # REASSIGN STRATEGY
    # ============================================

    def alternative_agent_available?
      return false unless @step['agent']

      alternatives = find_alternative_agents
      alternatives.any? { |a| a[:agent_slug] != @step['agent'] && a[:score] > 50 }
    end

    def find_alternative_agents
      tools_needed = @step['tools_needed'] || []
      
      router = Agents::SmartRouterService.new(entity: plan.entity, user: plan.user)
      router.find_best_agent(
        task_description: @step['description'] || @step['name'],
        tools_needed: tools_needed,
        top_n: 5
      )
    end

    def attempt_reassign
      alternatives = find_alternative_agents
      new_agent = alternatives.find { |a| a[:agent_slug] != @step['agent'] }

      return { success: false, reason: 'No alternative agent found' } unless new_agent

      # Update step with new agent
      old_agent = @step['agent']
      plan.send(:update_step, step_id, 
        'agent' => new_agent[:agent_slug],
        'status' => 'pending',
        'error' => nil,
        'reassigned_from' => old_agent,
        'reassign_reason' => @error.to_s.truncate(200)
      )

      # Decrement failed count since we're recovering
      plan.decrement!(:failed_steps) if plan.failed_steps > 0

      # Log the recovery
      plan.send(:log_event, 'auto_recovery',
        "Reassigned '#{@step['name']}' from #{old_agent} to #{new_agent[:agent_slug]}")

      # Trigger re-execution
      PlanStepExecuteJob.perform_later(plan_id: plan.id, step_id: step_id)

      {
        success: true,
        strategy: :reassign,
        old_agent: old_agent,
        new_agent: new_agent[:agent_slug],
        confidence: new_agent[:score],
        message: "Reassigned to #{new_agent[:agent_name]}"
      }
    end

    # ============================================
    # SKIP STRATEGY
    # ============================================

    def step_can_be_skipped?
      # Check if any steps depend on this one
      dependent_steps = plan.all_steps.select do |s|
        (s['dependencies'] || []).include?(step_id)
      end

      # Can skip if no dependents or all dependents can handle missing data
      dependent_steps.empty? || dependent_steps.all? { |s| step_has_fallback?(s) }
    end

    def step_has_fallback?(step)
      # Steps with certain tools can handle missing inputs
      fallback_tools = %w[ask_user get_data]
      (step['tools_needed'] || []).any? { |t| fallback_tools.include?(t) }
    end

    def attempt_skip
      plan.skip_step!(step_id, reason: "Auto-skipped after failure: #{@error.to_s.truncate(100)}")

      plan.send(:log_event, 'auto_recovery',
        "Skipped '#{@step['name']}' - no critical dependents")

      {
        success: true,
        strategy: :skip,
        message: "Step skipped - will continue with remaining steps"
      }
    end

    # ============================================
    # SIMPLIFY STRATEGY
    # ============================================

    def step_can_be_simplified?
      # Complex steps with multiple tools can potentially be split
      (@step['tools_needed'] || []).length > 2 ||
        @step['description'].to_s.length > 200
    end

    def attempt_simplify
      # This would require LLM intervention to split the step
      # For now, just mark it for manual review
      plan.send(:log_event, 'auto_recovery',
        "Step '#{@step['name']}' marked for simplification - manual review needed")

      # Pause the plan and notify
      plan.pause!(reason: "Step '#{@step['name']}' needs to be simplified")

      {
        success: true,
        strategy: :simplify,
        message: "Plan paused - step needs to be broken into smaller steps"
      }
    end

    # ============================================
    # ESCALATE STRATEGY
    # ============================================

    def escalate_to_user
      # Create a Hub message asking for help
      bridge = Hub::PlanBridgeService.new(plan: plan)
      bridge.on_user_input_needed(
        @step,
        "The step '#{@step['name']}' has failed and automatic recovery was not possible.\n\n" \
        "Error: #{@error}\n\n" \
        "Options:\n" \
        "1. Retry the step manually\n" \
        "2. Skip this step\n" \
        "3. Cancel the plan\n\n" \
        "How would you like to proceed?"
      )

      # Pause the plan
      plan.pause!(reason: "Waiting for user decision on failed step '#{@step['name']}'")

      plan.send(:log_event, 'auto_recovery',
        "Escalated '#{@step['name']}' to user - awaiting decision")

      {
        success: true,
        strategy: :escalate,
        message: "Escalated to user - plan paused until resolved"
      }
    end
  end
end





