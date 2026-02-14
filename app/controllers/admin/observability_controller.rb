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

    # Template analytics (detailed stats by template)
    @template_stats = compute_template_stats(@time_range)

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

    # Get error events for error rate chart
    @error_events = ObservabilityEvent
                      .where(event_type: ["error", "exception", "workflow_error"])
                      .or(ObservabilityEvent.where("metadata->>'status' IN (?)", ["failed", "error"]))
                      .where("created_at > ?", @time_range.ago)
                      .order(created_at: :desc)

    # Error rate chart
    @error_rate_chart = generate_error_trend_chart

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
    @time_range = (params[:time_range]&.to_i || 7).days
    @group_by = params[:group_by] || "day"

    # Get usage logs in range
    logs = AiUsageLog.where(created_at: @time_range.ago..)

    # Main stats
    @total_requests = logs.count
    @total_tokens = logs.sum(:total_tokens)
    @total_cost = logs.sum(:cost_cents) / 100.0
    @average_latency = (logs.where.not(duration_ms: nil).average(:duration_ms)&.to_f || 0) / 1000.0

    # Token breakdown for display
    @input_tokens = logs.sum(:input_tokens)
    @output_tokens = logs.sum(:output_tokens)
    @cache_read_tokens = logs.sum("COALESCE((metadata->>'cache_read')::int, 0)")
    @cache_write_tokens = logs.sum("COALESCE((metadata->>'cache_creation')::int, 0)")

    # Usage by entity with cost breakdown
    @usage_by_entity = logs
      .joins(:entity)
      .group("entities.id", "entities.name")
      .select("entities.id as entity_id,
               entities.name as entity_name,
               COUNT(*) as request_count,
               SUM(ai_usage_logs.input_tokens) as input_tokens,
               SUM(ai_usage_logs.output_tokens) as output_tokens,
               SUM(ai_usage_logs.total_tokens) as total_tokens,
               SUM(ai_usage_logs.cost_cents) / 100.0 as cost")
      .order("cost DESC")

    # Usage by model with full breakdown
    @usage_by_model = logs
      .group(:model)
      .select("model,
               COUNT(*) as request_count,
               SUM(input_tokens) as input_tokens,
               SUM(output_tokens) as output_tokens,
               SUM(total_tokens) as total_tokens,
               SUM(cost_cents) / 100.0 as cost")
      .order("cost DESC")

    # Top entities
    cutoff_time = @time_range.ago.utc.strftime("%Y-%m-%d %H:%M:%S")
    @top_entities = Entity
      .joins("LEFT JOIN ai_usage_logs ON ai_usage_logs.entity_id = entities.id AND ai_usage_logs.created_at > '#{cutoff_time}'")
      .select("entities.*, COUNT(ai_usage_logs.id) as request_count")
      .group("entities.id")
      .order("request_count DESC")
      .limit(10)

    # Recent requests (from AiUsageLog)
    @recent_requests = logs
      .includes(:entity, :user)
      .order(created_at: :desc)
      .limit(50)
      .map { |log| OpenStruct.new(
        created_at: log.created_at,
        entity: log.entity,
        user: log.user,
        event_type: log.request_type,
        metadata: { "model" => log.model, "tokens" => log.total_tokens, "cost" => "$#{(log.cost_cents / 100.0).round(4)}" }
      )}

    # Charts
    @token_usage_chart = generate_token_chart(logs)
    @cost_chart = generate_cost_chart(logs)
  end

  def ai_usage_by_entity
    @entity = Entity.find(params[:entity_id])
    @time_range = (params[:time_range]&.to_i || 7).days

    # Get usage logs for this entity
    logs = AiUsageLog.where(entity: @entity, created_at: @time_range.ago..)

    # Main stats for this entity
    @total_requests = logs.count
    @total_tokens = logs.sum(:total_tokens)
    @total_cost = logs.sum(:cost_cents) / 100.0
    @average_latency = (logs.where.not(duration_ms: nil).average(:duration_ms)&.to_f || 0) / 1000.0

    # Token breakdown
    @input_tokens = logs.sum(:input_tokens)
    @output_tokens = logs.sum(:output_tokens)

    # Usage by model for this entity
    @usage_by_model = logs
      .group(:model)
      .select("model,
               COUNT(*) as request_count,
               SUM(input_tokens) as input_tokens,
               SUM(output_tokens) as output_tokens,
               SUM(total_tokens) as total_tokens,
               SUM(cost_cents) / 100.0 as cost")
      .order("cost DESC")

    # Usage by user within this entity
    @usage_by_user = logs
      .joins(:user)
      .group("users.id", "users.email")
      .select("users.id as user_id,
               users.email as user_email,
               COUNT(*) as request_count,
               SUM(ai_usage_logs.input_tokens) as input_tokens,
               SUM(ai_usage_logs.output_tokens) as output_tokens,
               SUM(ai_usage_logs.total_tokens) as total_tokens,
               SUM(ai_usage_logs.cost_cents) / 100.0 as cost")
      .order("cost DESC")

    # Recent requests for this entity
    @recent_requests = logs
      .includes(:user)
      .order(created_at: :desc)
      .limit(25)

    # Charts for this entity
    @token_usage_chart = generate_token_chart(logs)
    @cost_chart = generate_cost_chart(logs)
  end

  private

  # AI Usage chart helpers
  def generate_token_chart(logs)
    days = [(@time_range.to_i / 1.day.to_i), 7].max.clamp(1, 30)

    # Aggregate by day in database
    input_by_day = logs.group("DATE(created_at)").sum(:input_tokens)
    output_by_day = logs.group("DATE(created_at)").sum(:output_tokens)

    labels = days.times.map { |d| d.days.ago.to_date }.reverse

    {
      labels: labels.map { |d| d.strftime("%b %-d") },
      datasets: [
        {
          label: "Input Tokens",
          data: labels.map { |d| input_by_day[d] || 0 },
          backgroundColor: "rgba(59, 130, 246, 0.7)"
        },
        {
          label: "Output Tokens",
          data: labels.map { |d| output_by_day[d] || 0 },
          backgroundColor: "rgba(16, 185, 129, 0.7)"
        }
      ]
    }
  end

  def generate_cost_chart(logs)
    days = [(@time_range.to_i / 1.day.to_i), 7].max.clamp(1, 30)

    # Aggregate by day in database
    cost_by_day = logs.group("DATE(created_at)").sum(:cost_cents)

    labels = days.times.map { |d| d.days.ago.to_date }.reverse

    {
      labels: labels.map { |d| d.strftime("%b %-d") },
      datasets: [
        {
          label: "Cost ($)",
          data: labels.map { |d| ((cost_by_day[d] || 0) / 100.0).round(4) },
          borderColor: "rgb(239, 68, 68)",
          backgroundColor: "rgba(239, 68, 68, 0.1)",
          fill: true
        }
      ]
    }
  end

  # AI Usage helpers (for MetricsController compatibility)
  def timeframe_start(timeframe)
    case timeframe
    when "1h" then 1.hour.ago
    when "24h" then 24.hours.ago
    when "7d" then 7.days.ago
    when "30d" then 30.days.ago
    else 24.hours.ago
    end
  end

  def calculate_ai_calls(timeframe)
    AiUsageLog.where(created_at: timeframe_start(timeframe)..).count
  end

  def calculate_tokens(timeframe)
    logs = AiUsageLog.where(created_at: timeframe_start(timeframe)..)
    {
      input: logs.sum(:input_tokens),
      output: logs.sum(:output_tokens),
      total: logs.sum(:total_tokens),
      cache_read: logs.sum("COALESCE((metadata->>'cache_read')::int, 0)"),
      cache_write: logs.sum("COALESCE((metadata->>'cache_creation')::int, 0)")
    }
  end

  def calculate_cost(timeframe)
    cost_cents = AiUsageLog.where(created_at: timeframe_start(timeframe)..).sum(:cost_cents)
    (cost_cents / 100.0).round(4)
  end

  def calculate_avg_response_time(timeframe)
    AiUsageLog.where(created_at: timeframe_start(timeframe)..)
              .where.not(duration_ms: nil)
              .average(:duration_ms)&.round(0) || 0
  end

  def calculate_usage_by_user(timeframe)
    AiUsageLog.where(created_at: timeframe_start(timeframe)..)
              .joins(:user)
              .group("users.email")
              .select("users.email as email,
                       SUM(ai_usage_logs.total_tokens) as total_tokens,
                       SUM(ai_usage_logs.cost_cents) / 100.0 as cost,
                       COUNT(*) as call_count")
              .order("total_tokens DESC")
              .limit(10)
  end

  def calculate_usage_by_model(timeframe)
    AiUsageLog.where(created_at: timeframe_start(timeframe)..)
              .group(:model)
              .select("model,
                       SUM(input_tokens) as input_tokens,
                       SUM(output_tokens) as output_tokens,
                       SUM(total_tokens) as total_tokens,
                       SUM(cost_cents) / 100.0 as cost,
                       COUNT(*) as call_count")
              .order("total_tokens DESC")
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
      .to_a
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

  def compute_template_stats(time_range)
    executions = WorkflowExecution
      .where.not(workflow_template_id: [nil, ""])
      .where("workflow_executions.created_at > ?", time_range.ago)

    # Group by template and compute aggregates
    grouped = executions.group(:workflow_template_id).select(
      "workflow_template_id",
      "COUNT(*) as total_runs",
      "COUNT(CASE WHEN status = 'completed' THEN 1 END) as successful_runs",
      "COUNT(DISTINCT entity_id) as unique_entities"
    )

    # Calculate average duration separately (only for completed executions with timestamps)
    avg_durations = executions
      .where(status: "completed")
      .where.not(started_at: nil, completed_at: nil)
      .group(:workflow_template_id)
      .pluck(
        :workflow_template_id,
        Arel.sql("AVG(EXTRACT(EPOCH FROM (completed_at - started_at)))")
      ).to_h

    # Look up template metadata from DB and file-based templates
    template_slugs = grouped.map(&:workflow_template_id)

    # Try to find categories from WorkflowTemplate DB records
    db_templates = WorkflowTemplate.where(slug: template_slugs).or(
      WorkflowTemplate.where(name: template_slugs)
    ).index_by { |t| t.slug.presence || t.name }

    # Also check file-based templates for category info
    file_templates = WorkflowTemplateLoader.list_all_templates.index_by { |t| t[:slug] }

    grouped.map do |stat|
      template_id = stat.workflow_template_id
      db_template = db_templates[template_id]
      file_template = file_templates[template_id]

      category = db_template&.category || file_template&.dig(:category) || "uncategorized"
      display_name = db_template&.name || file_template&.dig(:name) || template_id.to_s.titleize

      total = stat.total_runs.to_i
      successful = stat.successful_runs.to_i
      success_rate = total > 0 ? (successful.to_f / total * 100).round(1) : 0.0

      {
        name: display_name,
        template_id: template_id,
        category: category.to_s.titleize,
        total_runs: total,
        success_rate: success_rate,
        avg_duration: format_duration(avg_durations[template_id]),
        unique_entities: stat.unique_entities.to_i
      }
    end.compact.sort_by { |s| -s[:total_runs] }
  end

  def format_duration(seconds)
    return "N/A" unless seconds
    seconds = seconds.to_f
    if seconds < 60
      "#{seconds.round(1)}s"
    elsif seconds < 3600
      "#{(seconds / 60).round(1)}m"
    else
      "#{(seconds / 3600).round(1)}h"
    end
  end
end
