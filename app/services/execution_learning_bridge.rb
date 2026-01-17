# frozen_string_literal: true

# ExecutionLearningBridge - Connects ExecutionGuard findings to the learning systems
#
# This bridge ensures that patterns detected by ExecutionGuard are:
# 1. Recorded in the Energy System for agent capability updates
# 2. Sent to SystemNotificationService for user visibility
# 3. Used to update decision boundaries in the collaboration system
#
# It replaces the need for Agent Lightning for these specific patterns,
# using the native energy/school/collaboration infrastructure instead.
#
class ExecutionLearningBridge
  attr_reader :entity, :user, :agent

  def initialize(entity:, user:, agent: nil)
    @entity = entity
    @user = user
    @agent = agent
    @notification_service = SystemNotificationService.new(entity: entity, user: user)
  end

  # ═══════════════════════════════════════════════════════════════
  # PATTERN RECORDING
  # ═══════════════════════════════════════════════════════════════

  # Record an unfulfilled intent pattern
  # Called when AI says "I'll do X" but doesn't call the tool
  def record_unfulfilled_intent(intents:, response:, context: {})
    Rails.logger.info "[ExecutionLearningBridge] Recording unfulfilled intent: #{intents.join(', ')}"
    
    # 1. Notify user
    @notification_service.notify_unfulfilled_intent(
      intents: intents,
      response_preview: response.to_s.truncate(300),
      context: context
    )
    
    # 2. Update agent capability belief if we have an agent
    if @agent&.respond_to?(:update_capability_belief!)
      @agent.update_capability_belief!(
        task_type: 'tool_execution',
        success: false,
        quality: 0.3  # Partial success - intent was there, execution wasn't
      )
    end
    
    # 3. Record in analytics
    record_pattern_analytics(
      pattern_type: 'unfulfilled_intent',
      intents: intents,
      response_preview: response.to_s.truncate(500),
      agent_slug: @agent&.slug
    )
    
    true
  end

  # Record an execution loop pattern
  # Called when the same tool is called repeatedly without progress
  def record_execution_loop(pattern:, tool_name:, retry_count:, context: {})
    Rails.logger.warn "[ExecutionLearningBridge] Recording execution loop: #{pattern} on #{tool_name}"
    
    # 1. Notify user
    @notification_service.notify_execution_loop(
      pattern: pattern,
      tool_name: tool_name,
      retry_count: retry_count,
      context: context
    )
    
    # 2. Update agent capability belief
    if @agent&.respond_to?(:update_capability_belief!)
      @agent.update_capability_belief!(
        task_type: 'loop_avoidance',
        success: false,
        quality: 0.0  # Complete failure - got stuck in loop
      )
      
      # Also penalize energy if energy state exists
      if @agent.energy_state
        penalty = Collaboration::DynamicEnergyPricer.new.failure_penalty(@agent, nil) * 0.5
        @agent.energy_state.penalize!(
          penalty,
          reason: 'execution_loop',
          context: { pattern: pattern, tool_name: tool_name }
        )
      end
    end
    
    # 3. Record in analytics
    record_pattern_analytics(
      pattern_type: 'execution_loop',
      pattern: pattern,
      tool_name: tool_name,
      retry_count: retry_count,
      agent_slug: @agent&.slug
    )
    
    true
  end

  # Record a stuck execution
  # Called when execution times out without completing
  def record_stuck_execution(execution_id:, duration_seconds:, unfulfilled_intents: [], context: {})
    Rails.logger.warn "[ExecutionLearningBridge] Recording stuck execution: #{execution_id} (#{duration_seconds}s)"
    
    agent_name = @agent&.name || context[:agent_name] || 'Unknown'
    
    # 1. Notify user
    @notification_service.notify_stuck_execution(
      execution_id: execution_id,
      agent_name: agent_name,
      duration_seconds: duration_seconds,
      unfulfilled_intents: unfulfilled_intents
    )
    
    # 2. Update agent stats
    if @agent&.respond_to?(:energy_state) && @agent.energy_state
      @agent.energy_state.update_stats!(success: false, quality: 0.0)
      
      # Check if agent should go to school
      if @agent.current_energy <= 0
        AgentSchoolEnrollmentJob.perform_later(@agent.id)
      end
    end
    
    # 3. Record in analytics
    record_pattern_analytics(
      pattern_type: 'stuck_execution',
      execution_id: execution_id,
      duration_seconds: duration_seconds,
      unfulfilled_intents: unfulfilled_intents,
      agent_slug: @agent&.slug
    )
    
    true
  end

  # Record a successful execution (for positive reinforcement)
  def record_successful_execution(execution_id:, tool_calls:, duration_seconds:, context: {})
    Rails.logger.debug "[ExecutionLearningBridge] Recording successful execution: #{execution_id}"
    
    # 1. Update agent capability belief
    if @agent&.respond_to?(:update_capability_belief!)
      tool_calls.each do |tool_call|
        tool_name = tool_call[:name] || tool_call['name']
        @agent.update_capability_belief!(
          task_type: "tool_#{tool_name}",
          success: true,
          quality: 0.9
        )
      end
    end
    
    # 2. Record in analytics (sampled to avoid overwhelming)
    if rand < 0.1  # 10% sampling for successes
      record_pattern_analytics(
        pattern_type: 'successful_execution',
        execution_id: execution_id,
        tool_count: tool_calls.size,
        duration_seconds: duration_seconds,
        agent_slug: @agent&.slug
      )
    end
    
    true
  end

  # Record a delegation failure
  def record_delegation_failure(from_agent:, to_agent:, task:, error:, context: {})
    Rails.logger.warn "[ExecutionLearningBridge] Recording delegation failure: #{from_agent} → #{to_agent}"
    
    # 1. Notify user
    @notification_service.notify_delegation_failure(
      from_agent: from_agent,
      to_agent: to_agent,
      task: task,
      error: error
    )
    
    # 2. Update routing preferences (if we track this)
    # This could inform the smart router to avoid this delegation path
    update_delegation_history(
      from_agent: from_agent,
      to_agent: to_agent,
      success: false,
      error: error.to_s
    )
    
    # 3. Record in analytics
    record_pattern_analytics(
      pattern_type: 'delegation_failure',
      from_agent: from_agent,
      to_agent: to_agent,
      task_preview: task.to_s.truncate(200),
      error: error.to_s.truncate(300)
    )
    
    true
  end

  # ═══════════════════════════════════════════════════════════════
  # BATCH LEARNING
  # ═══════════════════════════════════════════════════════════════

  # Analyze patterns from recent executions and update beliefs
  def analyze_recent_patterns(hours: 24)
    since = hours.hours.ago
    
    # Get recent system notifications for patterns
    notifications = SystemNotification.where(entity: entity)
                                      .where('created_at > ?', since)
                                      .where(category: %w[unfulfilled_intent execution_loop stuck_execution delegation_failure])
    
    patterns = {
      unfulfilled_intents: [],
      loops: [],
      stuck: [],
      delegation_failures: []
    }
    
    notifications.find_each do |notification|
      case notification.category
      when 'unfulfilled_intent'
        patterns[:unfulfilled_intents] << notification.metadata
      when 'execution_loop'
        patterns[:loops] << notification.metadata
      when 'stuck_execution'
        patterns[:stuck] << notification.metadata
      when 'delegation_failure'
        patterns[:delegation_failures] << notification.metadata
      end
    end
    
    # Analyze and summarize
    {
      total_patterns: notifications.count,
      by_category: patterns.transform_values(&:count),
      most_common_unfulfilled_intents: extract_common_intents(patterns[:unfulfilled_intents]),
      most_common_loop_tools: extract_common_tools(patterns[:loops]),
      delegation_success_rate: calculate_delegation_success_rate(patterns[:delegation_failures])
    }
  end

  private

  def record_pattern_analytics(data)
    # Use existing analytics infrastructure
    ObservabilityService.track_event(
      'execution_pattern',
      entity_id: @entity.id,
      user_id: @user&.id,
      **data.merge(timestamp: Time.current)
    )
  rescue => e
    Rails.logger.debug "[ExecutionLearningBridge] Analytics recording failed: #{e.message}"
  end

  def update_delegation_history(from_agent:, to_agent:, success:, error: nil)
    # Update delegation history for smart routing
    key = "delegation_history_#{@entity.id}"
    history = Rails.cache.fetch(key) { {} }
    
    pair_key = "#{from_agent}:#{to_agent}"
    history[pair_key] ||= { success: 0, failure: 0 }
    
    if success
      history[pair_key][:success] += 1
    else
      history[pair_key][:failure] += 1
    end
    
    Rails.cache.write(key, history, expires_in: 24.hours)
  end

  def extract_common_intents(intent_patterns)
    return {} if intent_patterns.empty?
    
    all_intents = intent_patterns.flat_map { |p| p['intents'] || [] }
    all_intents.tally.sort_by { |_, count| -count }.first(5).to_h
  end

  def extract_common_tools(loop_patterns)
    return {} if loop_patterns.empty?
    
    tools = loop_patterns.map { |p| p['tool_name'] }.compact
    tools.tally.sort_by { |_, count| -count }.first(5).to_h
  end

  def calculate_delegation_success_rate(failures)
    return 1.0 if failures.empty?
    
    # We don't have success data here, but we can estimate based on failure frequency
    # Lower is worse
    failure_count = failures.size
    estimated_total = failure_count * 10  # Assume 10% failure rate baseline
    
    ((estimated_total - failure_count).to_f / estimated_total).round(2)
  end
end

