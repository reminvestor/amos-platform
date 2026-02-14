class ObservabilityService
  include Singleton

  # Event types for tracking
  EVENT_TYPES = {
    # Workflow events
    workflow_started: "workflow.started",
    workflow_completed: "workflow.completed",
    workflow_failed: "workflow.failed",
    workflow_abandoned: "workflow.abandoned",

    # Step events
    step_started: "step.started",
    step_completed: "step.completed",
    step_failed: "step.failed",
    step_skipped: "step.skipped",

    # Tool events
    tool_called: "tool.called",
    tool_completed: "tool.completed",
    tool_failed: "tool.failed",
    tool_timeout: "tool.timeout",

    # User events
    user_input_requested: "user.input_requested",
    user_input_provided: "user.input_provided",
    user_abandoned_step: "user.abandoned_step",

    # Performance events
    ai_request_started: "ai.request_started",
    ai_request_completed: "ai.request_completed",
    ai_tokens_used: "ai.tokens_used",

    # Canvas events
    canvas_loaded: "canvas.loaded",
    canvas_error: "canvas.error"
  }.freeze

  def initialize
    @metrics_store = {}
    @events_buffer = []
    @buffer_size = 100
  end

  # Track a workflow event
  def track_workflow_event(event_type, task_session, data = {})
    track_event(
      EVENT_TYPES[event_type] || event_type,
      {
        task_session_id: task_session.id,
        user_id: task_session.user_id,
        session_type: task_session.session_type,
        workflow_type: task_session.workflow_spec&.dig("type")
      }.merge(data)
    )
  end

  # Track a step event
  def track_step_event(event_type, task_session, step_id, data = {})
    track_event(
      EVENT_TYPES[event_type] || event_type,
      {
        task_session_id: task_session.id,
        user_id: task_session.user_id,
        step_id: step_id,
        workflow_type: task_session.workflow_spec&.dig("type")
      }.merge(data)
    )
  end

  # Track a tool execution
  def track_tool_event(event_type, tool_name, data = {})
    track_event(
      EVENT_TYPES[event_type] || event_type,
      {
        tool_name: tool_name,
        duration_ms: data[:duration_ms],
        success: data[:success],
        error: data[:error],
        input_size: data[:input_size],
        output_size: data[:output_size]
      }.compact.merge(data)
    )
  end

  # Track AI service usage
  def track_ai_usage(provider, model, tokens_used, cost = nil, duration_ms = nil)
    track_event(
      EVENT_TYPES[:ai_tokens_used],
      {
        provider: provider,
        model: model,
        tokens_used: tokens_used,
        estimated_cost: cost,
        duration_ms: duration_ms
      }.compact
    )

    # Update running totals
    update_ai_metrics(provider, model, tokens_used, cost)
  end

  # Track canvas loading
  def track_canvas_event(canvas_type, user_id, success = true, error = nil, load_time_ms = nil)
    event_type = success ? EVENT_TYPES[:canvas_loaded] : EVENT_TYPES[:canvas_error]

    track_event(
      event_type,
      {
        canvas_type: canvas_type,
        user_id: user_id,
        load_time_ms: load_time_ms,
        error: error
      }.compact
    )
  end

  # Get workflow analytics
  def workflow_analytics(period = 30.days)
    start_time = period.ago

    # Get workflow completion rates
    workflows_started = TaskSession.where(created_at: start_time..Time.current)
    workflows_completed = workflows_started.where(status: "completed")
    workflows_failed = workflows_started.where(status: "failed")

    completion_rate = workflows_started.count > 0 ?
      (workflows_completed.count.to_f / workflows_started.count * 100).round(1) : 0.0

    # Get popular workflow types
    workflow_types = workflows_started.group("metadata->>'workflow_type'").count

    # Get average completion times
    avg_completion_time = workflows_completed.average(
      "EXTRACT(EPOCH FROM (updated_at - created_at))"
    )&.to_f&.round(2)

    {
      period: period,
      total_workflows: workflows_started.count,
      completed_workflows: workflows_completed.count,
      failed_workflows: workflows_failed.count,
      completion_rate: completion_rate,
      avg_completion_time_seconds: avg_completion_time,
      popular_workflow_types: workflow_types,
      daily_workflow_counts: workflows_started.group_by_day(:created_at).count
    }
  end

  # Get tool execution analytics
  def tool_analytics(period = 30.days)
    # This would query tool execution events from TaskEvent
    tool_events = TaskEvent.where(
      event_type: [ "tool_called", "tool_completed", "tool_failed" ],
      created_at: period.ago..Time.current
    )

    tool_calls = tool_events.where(event_type: "tool_called").count
    tool_successes = tool_events.where(event_type: "tool_completed").count
    tool_failures = tool_events.where(event_type: "tool_failed").count

    success_rate = tool_calls > 0 ?
      (tool_successes.to_f / tool_calls * 100).round(1) : 0.0

    # Get tool usage by type
    tool_usage = tool_events.where(event_type: "tool_called")
                           .group("payload->>'tool_name'")
                           .count

    {
      period: period,
      total_tool_calls: tool_calls,
      successful_calls: tool_successes,
      failed_calls: tool_failures,
      success_rate: success_rate,
      tool_usage_by_type: tool_usage,
      daily_tool_usage: tool_events.group_by_day(:created_at).count
    }
  end

  # Get user engagement analytics
  def user_analytics(period = 30.days)
    active_users = TaskSession.where(created_at: period.ago..Time.current)
                             .distinct
                             .count(:user_id)

    # Get session types distribution
    session_types = TaskSession.where(created_at: period.ago..Time.current)
                              .group(:session_type)
                              .count

    # Average session duration
    avg_session_duration = TaskSession.where(
      created_at: period.ago..Time.current,
      status: [ "completed", "failed" ]
    ).average("EXTRACT(EPOCH FROM (updated_at - created_at))")&.to_f&.round(2)

    {
      period: period,
      active_users: active_users,
      session_types_distribution: session_types,
      avg_session_duration_seconds: avg_session_duration,
      daily_active_users: TaskSession.where(created_at: period.ago..Time.current)
                                    .group_by_day(:created_at)
                                    .distinct
                                    .count(:user_id)
    }
  end

  # Get AI usage and cost metrics
  def ai_metrics(period = 30.days)
    # This would be populated by track_ai_usage calls
    @metrics_store[:ai_usage] ||= {
      total_tokens: 0,
      total_requests: 0,
      estimated_cost: 0.0,
      by_provider: {},
      by_model: {}
    }

    @metrics_store[:ai_usage]
  end

  # Get performance metrics
  def performance_metrics(period = 30.days)
    # Average step execution times
    step_events = TaskEvent.where(
      event_type: [ "step_started", "step_completed" ],
      created_at: period.ago..Time.current
    )

    # Calculate average step duration
    step_durations = []
    step_events.group(:task_session_id).each do |session_id, events|
      events.each_cons(2) do |start_event, end_event|
        if start_event.event_type == "step_started" && end_event.event_type == "step_completed"
          duration = end_event.created_at - start_event.created_at
          step_durations << duration
        end
      end
    end

    avg_step_duration = step_durations.any? ?
      (step_durations.sum / step_durations.length).round(2) : 0.0

    {
      period: period,
      avg_step_duration_seconds: avg_step_duration,
      total_steps_executed: step_events.where(event_type: "step_completed").count,
      performance_percentiles: calculate_percentiles(step_durations)
    }
  end

  # Get comprehensive dashboard data
  def dashboard_metrics(period = 30.days)
    {
      workflow_analytics: workflow_analytics(period),
      tool_analytics: tool_analytics(period),
      user_analytics: user_analytics(period),
      ai_metrics: ai_metrics(period),
      performance_metrics: performance_metrics(period),
      generated_at: Time.current
    }
  end

  # Health check for the observability system
  def health_check
    {
      status: "healthy",
      events_buffer_size: @events_buffer.length,
      metrics_store_keys: @metrics_store.keys,
      last_event_time: @events_buffer.last&.dig(:timestamp),
      uptime_seconds: Time.current - (Rails.application.initialized_at || Time.current)
    }
  end

  private

  def track_event(event_type, data)
    event = {
      event_type: event_type,
      data: data,
      timestamp: Time.current,
      session_id: data[:task_session_id] || data[:session_id]
    }

    # Add to buffer
    @events_buffer << event

    # Flush buffer if it's full
    if @events_buffer.length >= @buffer_size
      flush_events_buffer
    end

    # Log important events
    if should_log_event?(event_type)
      Rails.logger.info "📊 OBSERVABILITY: #{event_type} - #{data.inspect}"
    end

    event
  end

  def flush_events_buffer
    return if @events_buffer.empty?

    events_to_persist = @events_buffer.dup
    @events_buffer.clear

    Rails.logger.info "📊 OBSERVABILITY: Flushing #{events_to_persist.length} events to database"

    # Persist to database asynchronously
    PersistObservabilityEventsJob.perform_later(events_to_persist)
  rescue => e
    Rails.logger.error "📊 OBSERVABILITY: Flush failed: #{e.message}"
  end

  def should_log_event?(event_type)
    # Log important events for debugging
    important_events = [
      EVENT_TYPES[:workflow_started],
      EVENT_TYPES[:workflow_completed],
      EVENT_TYPES[:workflow_failed],
      EVENT_TYPES[:tool_failed],
      EVENT_TYPES[:ai_request_completed]
    ]

    important_events.include?(event_type)
  end

  def update_ai_metrics(provider, model, tokens_used, cost)
    @metrics_store[:ai_usage] ||= {
      total_tokens: 0,
      total_requests: 0,
      estimated_cost: 0.0,
      by_provider: {},
      by_model: {}
    }

    metrics = @metrics_store[:ai_usage]
    metrics[:total_tokens] += tokens_used
    metrics[:total_requests] += 1
    metrics[:estimated_cost] += cost if cost

    # By provider
    metrics[:by_provider][provider] ||= { tokens: 0, requests: 0, cost: 0.0 }
    metrics[:by_provider][provider][:tokens] += tokens_used
    metrics[:by_provider][provider][:requests] += 1
    metrics[:by_provider][provider][:cost] += cost if cost

    # By model
    metrics[:by_model][model] ||= { tokens: 0, requests: 0, cost: 0.0 }
    metrics[:by_model][model][:tokens] += tokens_used
    metrics[:by_model][model][:requests] += 1
    metrics[:by_model][model][:cost] += cost if cost
  end

  def calculate_percentiles(durations)
    return {} if durations.empty?

    sorted = durations.sort
    {
      p50: percentile(sorted, 50),
      p90: percentile(sorted, 90),
      p95: percentile(sorted, 95),
      p99: percentile(sorted, 99)
    }
  end

  def percentile(sorted_array, percentile)
    return 0 if sorted_array.empty?

    index = (percentile / 100.0 * (sorted_array.length - 1)).round
    sorted_array[index].round(2)
  end
end
