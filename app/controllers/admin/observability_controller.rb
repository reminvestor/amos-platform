class Admin::ObservabilityController < Admin::BaseController
  def workflows
    @time_range = params[:time_range]&.to_i&.days || 7.days
    @status_filter = params[:status]

    # Get workflow executions
    @workflows = WorkflowExecution
                   .where("workflow_executions.created_at > ?", @time_range.ago)
                   .includes(:entity, :user)
                   .order("workflow_executions.created_at DESC")

    # Apply status filter if provided
    @workflows = @workflows.where(status: @status_filter) if @status_filter.present?

    # Paginate results
    @workflows = @workflows.limit(100)

    # Calculate workflow stats
    all_workflows = WorkflowExecution.where("workflow_executions.created_at > ?", @time_range.ago)
    @total_workflows = all_workflows.count
    @completed_workflows = all_workflows.where(status: "completed").count
    @failed_workflows = all_workflows.where(status: "failed").count
    @in_progress_workflows = all_workflows.where(status: "in_progress").count
    @success_rate = @total_workflows > 0 ? ((@completed_workflows.to_f / @total_workflows) * 100).round(2) : 0

    # Workflows by template (workflow_template_id is a string containing the template name)
    @workflows_by_template = all_workflows
                               .group(:workflow_template_id)
                               .count
                               .reject { |name, _| name.nil? || name.blank? }
                               .sort_by { |_, count| -count }
                               .first(10)

    # Workflows by entity
    @workflows_by_entity = all_workflows
                             .joins(:entity)
                             .group("entities.name")
                             .count
                             .sort_by { |_, count| -count }
                             .first(10)

    # Average execution time
    @avg_execution_time = calculate_avg_workflow_time(all_workflows)

    # Workflow trend chart
    @workflow_trend_chart = generate_workflow_trend_chart(all_workflows)

    respond_to do |format|
      format.html
      format.json do
        render json: {
          total: @total_workflows,
          completed: @completed_workflows,
          failed: @failed_workflows,
          in_progress: @in_progress_workflows,
          success_rate: @success_rate,
          workflows: @workflows.as_json(include: [:entity, :user])
        }
      end
    end
  end

  def performance
    @time_range = params[:time_range]&.to_i&.days || 7.days

    # Get performance events
    @performance_events = ObservabilityEvent
                            .where(event_type: ["workflow_execution", "phase_execution", "tool_execution"])
                            .where("created_at > ?", @time_range.ago)
                            .order(created_at: :desc)

    # Calculate performance metrics
    @total_workflows = @performance_events.where(event_type: "workflow_execution").count
    @successful_workflows = @performance_events.where(event_type: "workflow_execution")
                                                .where("metadata->>'status' = ?", "completed").count
    @failed_workflows = @performance_events.where(event_type: "workflow_execution")
                                            .where("metadata->>'status' IN (?)", ["failed", "error"]).count
    @success_rate = @total_workflows > 0 ? ((@successful_workflows.to_f / @total_workflows) * 100).round(2) : 0

    # Average execution times
    @avg_workflow_duration = calculate_avg_duration("workflow_execution")
    @avg_phase_duration = calculate_avg_duration("phase_execution")
    @avg_tool_duration = calculate_avg_duration("tool_execution")

    # Performance over time chart
    @performance_chart = generate_performance_chart

    # Error rate chart
    @error_rate_chart = generate_error_rate_chart

    # Slowest operations
    @slowest_workflows = find_slowest_operations("workflow_execution", 10)
    @slowest_tools = find_slowest_operations("tool_execution", 10)

    respond_to do |format|
      format.html
      format.json do
        render json: {
          total_workflows: @total_workflows,
          successful_workflows: @successful_workflows,
          failed_workflows: @failed_workflows,
          success_rate: @success_rate,
          avg_workflow_duration: @avg_workflow_duration,
          avg_phase_duration: @avg_phase_duration,
          avg_tool_duration: @avg_tool_duration
        }
      end
    end
  end

  def errors
    @time_range = params[:time_range]&.to_i&.days || 7.days

    # Get error events
    @error_events = ObservabilityEvent
                      .where(event_type: ["error", "exception", "workflow_error"])
                      .or(ObservabilityEvent.where("metadata->>'status' IN (?)", ["failed", "error"]))
                      .where("created_at > ?", @time_range.ago)
                      .order(created_at: :desc)

    # Calculate error metrics
    @total_errors = @error_events.count
    @error_rate = calculate_error_rate
    @errors_by_type = @error_events.group_by { |e| e.metadata&.dig("error_type") || "Unknown" }
                                    .transform_values(&:count)
                                    .sort_by { |_, count| -count }

    # Recent errors
    @recent_errors = @error_events.includes(:entity, :user).limit(50)

    # Error trend chart
    @error_trend_chart = generate_error_trend_chart

    respond_to do |format|
      format.html
      format.json do
        render json: {
          total_errors: @total_errors,
          error_rate: @error_rate,
          errors_by_type: @errors_by_type,
          recent_errors: @recent_errors.as_json(include: [:entity, :user])
        }
      end
    end
  end

  def ai_usage
    @time_range = params[:time_range]&.to_i&.days || 7.days
    @group_by = params[:group_by] || "day"

    # Get AI usage data from ObservabilityEvent
    @ai_events = ObservabilityEvent
                   .where(event_type: ["ai_request", "ai_response", "tool_call"])
                   .where("created_at > ?", @time_range.ago)
                   .order(created_at: :desc)

    # Calculate aggregated stats
    @total_requests = @ai_events.where(event_type: "ai_request").count
    @total_tokens = calculate_total_tokens
    @total_cost = calculate_total_cost
    @average_latency = calculate_average_latency

    # Usage by entity
    @usage_by_entity = calculate_usage_by_entity

    # Usage by model
    @usage_by_model = calculate_usage_by_model

    # Token usage over time
    @token_usage_chart = generate_token_usage_chart

    # Cost over time
    @cost_chart = generate_cost_chart

    # Top entities by usage
    @top_entities = Entity
                      .joins("LEFT JOIN observability_events ON observability_events.entity_id = entities.id")
                      .where("observability_events.created_at > ?", @time_range.ago)
                      .where("observability_events.event_type = ?", "ai_request")
                      .group("entities.id", "entities.name")
                      .select("entities.*, COUNT(observability_events.id) as request_count")
                      .order("request_count DESC")
                      .limit(10)

    # Recent requests
    @recent_requests = @ai_events
                         .where(event_type: "ai_request")
                         .includes(:entity, :user)
                         .limit(50)

    respond_to do |format|
      format.html
      format.json do
        render json: {
          total_requests: @total_requests,
          total_tokens: @total_tokens,
          total_cost: @total_cost,
          average_latency: @average_latency,
          usage_by_entity: @usage_by_entity,
          usage_by_model: @usage_by_model,
          token_usage_chart: @token_usage_chart,
          cost_chart: @cost_chart
        }
      end
    end
  end

  private

  def calculate_total_tokens
    # Sum input and output tokens from metadata
    @ai_events.where(event_type: "ai_response").sum do |event|
      metadata = event.metadata || {}
      (metadata["input_tokens"] || 0) + (metadata["output_tokens"] || 0)
    end
  end

  def calculate_total_cost
    # Calculate cost based on token usage and model rates
    total_cost = 0.0

    @ai_events.where(event_type: "ai_response").each do |event|
      metadata = event.metadata || {}
      input_tokens = metadata["input_tokens"] || 0
      output_tokens = metadata["output_tokens"] || 0
      model = metadata["model"] || "claude-sonnet-4.5"

      # Model pricing (per 1M tokens)
      pricing = get_model_pricing(model)

      total_cost += (input_tokens / 1_000_000.0 * pricing[:input]) +
                    (output_tokens / 1_000_000.0 * pricing[:output])
    end

    total_cost.round(2)
  end

  def calculate_average_latency
    latencies = @ai_events.where(event_type: "ai_response")
                          .where.not("metadata->>'duration' IS NULL")
                          .pluck("(metadata->>'duration')::float")

    return 0 if latencies.empty?
    (latencies.sum / latencies.size).round(2)
  end

  def calculate_usage_by_entity
    result = ObservabilityEvent
               .joins(:entity)
               .where(event_type: "ai_request")
               .where("observability_events.created_at > ?", @time_range.ago)
               .group("entities.name")
               .count

    result.is_a?(Hash) ? result : {}
  end

  def calculate_usage_by_model
    result = @ai_events
               .where(event_type: "ai_response")
               .where.not("metadata->>'model' IS NULL")
               .group("metadata->>'model'")
               .count

    result.is_a?(Hash) ? result : {}
  end

  def generate_token_usage_chart
    time_groups = case @group_by
    when "hour"
      24.times.map { |h| h.hours.ago.beginning_of_hour }
    when "day"
      (@time_range.to_i / 1.day.to_i).times.map { |d| d.days.ago.beginning_of_day }
    else
      7.times.map { |d| d.days.ago.beginning_of_day }
    end

    data_by_time = @ai_events
                     .where(event_type: "ai_response")
                     .where("created_at > ?", @time_range.ago)
                     .group_by { |e| e.created_at.send("beginning_of_#{@group_by}") }

    {
      labels: time_groups.reverse.map { |t| format_time_label(t) },
      datasets: [
        {
          label: "Input Tokens",
          data: time_groups.reverse.map do |time|
            events = data_by_time[time] || []
            events.sum { |e| (e.metadata || {})["input_tokens"] || 0 }
          end,
          backgroundColor: "rgba(59, 130, 246, 0.5)"
        },
        {
          label: "Output Tokens",
          data: time_groups.reverse.map do |time|
            events = data_by_time[time] || []
            events.sum { |e| (e.metadata || {})["output_tokens"] || 0 }
          end,
          backgroundColor: "rgba(16, 185, 129, 0.5)"
        }
      ]
    }
  end

  def generate_cost_chart
    time_groups = case @group_by
    when "hour"
      24.times.map { |h| h.hours.ago.beginning_of_hour }
    when "day"
      (@time_range.to_i / 1.day.to_i).times.map { |d| d.days.ago.beginning_of_day }
    else
      7.times.map { |d| d.days.ago.beginning_of_day }
    end

    data_by_time = @ai_events
                     .where(event_type: "ai_response")
                     .where("created_at > ?", @time_range.ago)
                     .group_by { |e| e.created_at.send("beginning_of_#{@group_by}") }

    {
      labels: time_groups.reverse.map { |t| format_time_label(t) },
      datasets: [
        {
          label: "Cost ($)",
          data: time_groups.reverse.map do |time|
            events = data_by_time[time] || []
            cost = events.sum do |e|
              metadata = e.metadata || {}
              input_tokens = metadata["input_tokens"] || 0
              output_tokens = metadata["output_tokens"] || 0
              model = metadata["model"] || "claude-sonnet-4.5"
              pricing = get_model_pricing(model)

              (input_tokens / 1_000_000.0 * pricing[:input]) +
                (output_tokens / 1_000_000.0 * pricing[:output])
            end
            cost.round(2)
          end,
          borderColor: "rgb(239, 68, 68)",
          backgroundColor: "rgba(239, 68, 68, 0.1)",
          fill: true
        }
      ]
    }
  end

  def format_time_label(time)
    case @group_by
    when "hour"
      time.strftime("%-l %p")
    when "day"
      time.strftime("%b %-d")
    else
      time.strftime("%b %-d")
    end
  end

  def get_model_pricing(model)
    # Pricing per 1M tokens (as of 2025)
    case model
    when /claude-3-opus/
      { input: 15.00, output: 75.00 }
    when /claude-3-sonnet/, /claude-sonnet/
      { input: 3.00, output: 15.00 }
    when /claude-3-haiku/, /claude-haiku/
      { input: 0.25, output: 1.25 }
    when /claude-sonnet-4/
      { input: 3.00, output: 15.00 }
    when /gpt-4/
      { input: 30.00, output: 60.00 }
    when /gpt-3.5/
      { input: 0.50, output: 1.50 }
    else
      { input: 3.00, output: 15.00 } # Default to Claude Sonnet pricing
    end
  end

  # Performance tracking helpers
  def calculate_avg_duration(event_type)
    durations = @performance_events
                  .where(event_type: event_type)
                  .where.not("metadata->>'duration' IS NULL")
                  .pluck("(metadata->>'duration')::float")

    return 0 if durations.empty?
    (durations.sum / durations.size).round(2)
  end

  def find_slowest_operations(event_type, limit)
    @performance_events
      .where(event_type: event_type)
      .where.not("metadata->>'duration' IS NULL")
      .sort_by { |e| (e.metadata&.dig("duration") || 0).to_f }
      .reverse
      .first(limit)
  end

  def generate_performance_chart
    time_groups = (@time_range.to_i / 1.day.to_i).times.map { |d| d.days.ago.beginning_of_day }

    data_by_time = @performance_events
                     .where(event_type: "workflow_execution")
                     .where("created_at > ?", @time_range.ago)
                     .group_by { |e| e.created_at.beginning_of_day }

    {
      labels: time_groups.reverse.map { |t| t.strftime("%b %-d") },
      datasets: [
        {
          label: "Successful",
          data: time_groups.reverse.map do |time|
            events = data_by_time[time] || []
            events.count { |e| e.metadata&.dig("status") == "completed" }
          end,
          backgroundColor: "rgba(16, 185, 129, 0.5)"
        },
        {
          label: "Failed",
          data: time_groups.reverse.map do |time|
            events = data_by_time[time] || []
            events.count { |e| ["failed", "error"].include?(e.metadata&.dig("status")) }
          end,
          backgroundColor: "rgba(239, 68, 68, 0.5)"
        }
      ]
    }
  end

  # Error tracking helpers
  def calculate_error_rate
    total_events = ObservabilityEvent.where("created_at > ?", @time_range.ago).count
    return 0 if total_events == 0
    ((@total_errors.to_f / total_events) * 100).round(2)
  end

  def generate_error_trend_chart
    time_groups = (@time_range.to_i / 1.day.to_i).times.map { |d| d.days.ago.beginning_of_day }

    data_by_time = @error_events
                     .where("created_at > ?", @time_range.ago)
                     .group_by { |e| e.created_at.beginning_of_day }

    {
      labels: time_groups.reverse.map { |t| t.strftime("%b %-d") },
      datasets: [
        {
          label: "Errors",
          data: time_groups.reverse.map do |time|
            events = data_by_time[time] || []
            events.count
          end,
          borderColor: "rgb(239, 68, 68)",
          backgroundColor: "rgba(239, 68, 68, 0.1)",
          fill: true
        }
      ]
    }
  end

  # Workflow tracking helpers
  def calculate_avg_workflow_time(workflows)
    completed = workflows.where(status: "completed")
    return 0 if completed.empty?

    total_time = completed.sum do |wf|
      if wf.updated_at && wf.created_at
        (wf.updated_at - wf.created_at).to_f
      else
        0
      end
    end

    (total_time / completed.count).round(2)
  end

  def generate_workflow_trend_chart(workflows)
    time_groups = (@time_range.to_i / 1.day.to_i).times.map { |d| d.days.ago.beginning_of_day }

    data_by_time = workflows.group_by { |wf| wf.created_at.beginning_of_day }

    {
      labels: time_groups.reverse.map { |t| t.strftime("%b %-d") },
      datasets: [
        {
          label: "Completed",
          data: time_groups.reverse.map do |time|
            wfs = data_by_time[time] || []
            wfs.count { |wf| wf.status == "completed" }
          end,
          backgroundColor: "rgba(16, 185, 129, 0.5)"
        },
        {
          label: "Failed",
          data: time_groups.reverse.map do |time|
            wfs = data_by_time[time] || []
            wfs.count { |wf| wf.status == "failed" }
          end,
          backgroundColor: "rgba(239, 68, 68, 0.5)"
        },
        {
          label: "In Progress",
          data: time_groups.reverse.map do |time|
            wfs = data_by_time[time] || []
            wfs.count { |wf| wf.status == "in_progress" }
          end,
          backgroundColor: "rgba(59, 130, 246, 0.5)"
        }
      ]
    }
  end
end
