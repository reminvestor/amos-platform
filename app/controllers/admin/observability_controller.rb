class Admin::ObservabilityController < Admin::BaseController
  def workflows
    @time_range = params[:time_range]&.to_i&.days || 7.days
    @status_filter = params[:status]

    # Get workflow executions
    @workflows = WorkflowExecution
                   .where("workflow_executions.created_at > ?", @time_range.ago)
                   .includes(:entity, :user)
                   .order(created_at: :desc)

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

    # Workflows by template
    @workflows_by_template = all_workflows
                               .where.not(workflow_template_id: nil)
                               .group(:workflow_template_id)
                               .count
                               .sort_by { |_, count| -count }
                               .first(10)

    # Workflows by entity
    @workflows_by_entity = all_workflows
                             .joins(:entity)
                             .group(Arel.sql("entities.name"))
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

    # Use actual WorkflowExecution data instead of ObservabilityEvent
    @workflows = WorkflowExecution
                   .where("workflow_executions.created_at > ?", @time_range.ago)
                   .includes(:entity, :user)

    # Calculate performance metrics from WorkflowExecution
    @total_workflows = @workflows.count
    @successful_workflows = @workflows.where(status: "completed").count
    @failed_workflows = @workflows.where(status: "failed").count
    @success_rate = @total_workflows > 0 ? ((@successful_workflows.to_f / @total_workflows) * 100).round(2) : 0

    # Average execution times from WorkflowExecution
    @avg_workflow_duration = calculate_avg_workflow_duration(@workflows)
    @avg_phase_duration = 0 # Will calculate from workflow_spec if available
    @avg_tool_duration = 0 # Will calculate from workflow_spec if available

    # Performance over time chart
    @performance_chart = generate_performance_chart

    # Error rate data (simple calculation for doughnut chart)
    @error_rate_chart = {
      data: [@successful_workflows, @failed_workflows],
      labels: ['Success', 'Errors']
    }

    # Slowest operations from WorkflowExecution
    @slowest_workflows = @workflows
                          .where(status: "completed")
                          .where.not(started_at: nil, completed_at: nil)
                          .sort_by { |w| w.completed_at - w.started_at }
                          .reverse
                          .first(10)
    
    @slowest_tools = [] # Will be empty until we track tool executions

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

    # Get errors from multiple sources
    # 1. Failed workflows
    @failed_workflows = WorkflowExecution
                          .where(status: "failed")
                          .where("workflow_executions.created_at > ?", @time_range.ago)
                          .includes(:entity, :user)
                          .order(created_at: :desc)
    
    # 2. Failed integration calls
    @failed_integrations = IntegrationLog
                             .failed
                             .where("integration_logs.created_at > ?", @time_range.ago)
                             .includes(:connection, :user)
                             .order(created_at: :desc)

    # Calculate error metrics
    @total_errors = @failed_workflows.count + @failed_integrations.count
    @workflow_errors = @failed_workflows.count
    @integration_errors = @failed_integrations.count
    
    # Group errors by type
    @errors_by_type = {
      "Workflow Failures" => @workflow_errors,
      "Integration Failures" => @integration_errors
    }.select { |_, count| count > 0 }

    # Recent errors (combine both sources)
    @recent_errors = (@failed_workflows.to_a + @failed_integrations.to_a)
                       .sort_by(&:created_at)
                       .reverse
                       .first(50)

    # Error trend chart
    @error_trend_chart = generate_error_trend_chart_from_real_data

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

    # Use actual ScoutMessage data for AI usage
    @ai_messages = ScoutMessage
                     .where("created_at > ?", @time_range.ago)
                     .where(role: 'assistant') # AI responses
                     .includes(:entity, :user)
                     .order(created_at: :desc)

    # Calculate aggregated stats from AI usage logs (time-range specific)
    @total_requests = @ai_messages.count
    @total_tokens = AiUsageLog.total_tokens_in_range(@time_range)
    
    # Calculate total cost including AI + Voice costs
    ai_cost = AiUsageLog.total_cost_in_range(@time_range)
    tts_cost = TtsUsageLog.where("created_at > ?", @time_range.ago).sum(:cost_cents) / 100.0
    @total_cost = (ai_cost + tts_cost).round(2)
    
    @average_latency = AiUsageLog.average_duration_in_range(@time_range)
    
    # Voice usage stats
    @tts_requests = TtsUsageLog.where("created_at > ?", @time_range.ago).count
    @tts_characters = TtsUsageLog.where("created_at > ?", @time_range.ago).sum(:character_count)

    # Usage by entity
    @usage_by_entity = calculate_usage_by_entity

    # Usage by model
    @usage_by_model = calculate_usage_by_model

    # Token usage over time
    @token_usage_chart = generate_token_usage_chart

    # Cost over time
    @cost_chart = generate_cost_chart

    # Top entities by usage from scout messages
    @top_entities = Entity
                      .joins("LEFT JOIN scout_messages ON scout_messages.entity_id = entities.id")
                      .where("scout_messages.created_at > ?", @time_range.ago)
                      .where("scout_messages.role = ?", "assistant")
                      .group(Arel.sql("entities.id, entities.name"))
                      .select(Arel.sql("entities.*, COUNT(scout_messages.id) as request_count"))
                      .order(Arel.sql("request_count DESC"))
                      .limit(10)

    # Recent AI messages
    @recent_requests = @ai_messages.limit(50)

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
                          .pluck(Arel.sql("(metadata->>'duration')::float"))

    return 0 if latencies.empty?
    (latencies.sum / latencies.size).round(2)
  end

  def calculate_usage_by_entity
    ScoutMessage
      .joins(:entity)
      .where(role: 'assistant')
      .where("scout_messages.created_at > ?", @time_range.ago)
      .group(Arel.sql("entities.name"))
      .count
  end

  def calculate_usage_by_model
    AiUsageLog
      .within(@time_range)
      .group(:model)
      .sum(:total_tokens)
  end
  
  def calculate_total_tokens_from_messages
    @ai_messages.sum do |msg|
      (msg.metadata&.dig('input_tokens').to_i + msg.metadata&.dig('output_tokens').to_i)
    end
  end
  
  def calculate_total_cost_from_messages
    @ai_messages.sum do |msg|
      msg.metadata&.dig('cost')&.to_f || 0
    end.round(2)
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

    # Use AI usage logs for accurate token tracking
    usage_logs = AiUsageLog.within(@time_range).to_a
    data_by_time = usage_logs.group_by { |log| log.created_at.send("beginning_of_#{@group_by}") }

    {
      labels: time_groups.reverse.map { |t| format_time_label(t) },
      datasets: [
        {
          label: "Input Tokens",
          data: time_groups.reverse.map do |time|
            logs = data_by_time[time] || []
            logs.sum(&:input_tokens)
          end,
          backgroundColor: "rgba(59, 130, 246, 0.5)"
        },
        {
          label: "Output Tokens",
          data: time_groups.reverse.map do |time|
            logs = data_by_time[time] || []
            logs.sum(&:output_tokens)
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

    # Get both AI and TTS usage logs for cost tracking
    ai_logs = AiUsageLog.within(@time_range).to_a
    tts_logs = TtsUsageLog.where("created_at > ?", @time_range.ago).to_a
    
    ai_data_by_time = ai_logs.group_by { |log| log.created_at.send("beginning_of_#{@group_by}") }
    tts_data_by_time = tts_logs.group_by { |log| log.created_at.send("beginning_of_#{@group_by}") }

    {
      labels: time_groups.reverse.map { |t| format_time_label(t) },
      datasets: [
        {
          label: "AI Cost ($)",
          data: time_groups.reverse.map do |time|
            logs = ai_data_by_time[time] || []
            cost = logs.sum { |log| log.cost_cents / 100.0 }
            cost.round(2)
          end,
          borderColor: "rgb(59, 130, 246)",
          backgroundColor: "rgba(59, 130, 246, 0.1)",
          fill: true
        },
        {
          label: "Voice Cost ($)",
          data: time_groups.reverse.map do |time|
            logs = tts_data_by_time[time] || []
            cost = logs.sum { |log| (log.cost_cents || 0) / 100.0 }
            cost.round(2)
          end,
          borderColor: "rgb(16, 185, 129)",
          backgroundColor: "rgba(16, 185, 129, 0.1)",
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
  def calculate_avg_workflow_duration(workflows)
    completed = workflows.where(status: "completed").where.not(started_at: nil, completed_at: nil)
    
    return 0 if completed.empty?
    
    durations = completed.map do |w|
      ((w.completed_at - w.started_at) * 1000).round # Convert to milliseconds
    end
    
    (durations.sum.to_f / durations.size).round(2)
  end
  
  def calculate_avg_duration(event_type)
    durations = @performance_events
                  .where(event_type: event_type)
                  .where.not("metadata->>'duration' IS NULL")
                  .pluck(Arel.sql("(metadata->>'duration')::float"))

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

    # Use WorkflowExecution instead of ObservabilityEvent
    data_by_time = @workflows.group_by { |w| w.created_at.beginning_of_day }

    {
      labels: time_groups.reverse.map { |t| t.strftime("%b %-d") },
      data: time_groups.reverse.map do |time|
        workflows = data_by_time[time] || []
        if workflows.any?
          # Calculate average duration for workflows completed that day
          completed = workflows.select { |w| w.status == "completed" && w.started_at && w.completed_at }
          if completed.any?
            durations = completed.map { |w| ((w.completed_at - w.started_at) * 1000).round }
            (durations.sum.to_f / durations.size).round(2)
          else
            0
          end
        else
          0
        end
      end
    }
  end

  # Error tracking helpers
  def calculate_error_rate
    # Calculate error rate from workflows
    total_workflows = WorkflowExecution.where("workflow_executions.created_at > ?", @time_range.ago).count
    return 0 if total_workflows == 0
    ((@workflow_errors.to_f / total_workflows) * 100).round(2)
  end

  def generate_error_trend_chart_from_real_data
    time_groups = (@time_range.to_i / 1.day.to_i).times.map { |d| d.days.ago.beginning_of_day }

    # Combine workflow and integration errors by day
    workflow_data = @failed_workflows.group_by { |w| w.created_at.beginning_of_day }
    integration_data = @failed_integrations.group_by { |i| i.created_at.beginning_of_day }

    {
      labels: time_groups.reverse.map { |t| t.strftime("%b %-d") },
      data: time_groups.reverse.map do |time|
        workflow_count = (workflow_data[time] || []).count
        integration_count = (integration_data[time] || []).count
        workflow_count + integration_count
      end
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
