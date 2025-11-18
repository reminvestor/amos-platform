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
    # Redirect to Agent Lightning Model Performance page
    # AI Usage metrics are now consolidated under Agent Lightning
    redirect_to models_performance_admin_agent_lightning_index_path,
                notice: "AI Usage metrics have been moved to Agent Lightning Model Performance"
  end

  private

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
