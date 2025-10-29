module Scout
  class TaskProgressLoader
    def initialize(user:, session_id:)
      @user = user
      @session_id = session_id
    end

    # Load task progress data from various sources
    def load_task_data(data = {})
      # Handle nil data
      data = {} if data.nil?

      # Handle both symbol and string keys
      data = data.with_indifferent_access if data.is_a?(Hash)

      # If we have progress data from workflow, use it
      if data[:progress] && !data[:tasks]
        data = convert_workflow_progress_to_tasks(data)
      end

      # If no data provided, try to load from TaskSession
      # Skip loading if we have workflow approval data
      if (data.empty? || data[:tasks].nil?) && !is_workflow_approval?(data)
        data = load_from_task_session(data)
      else
        Rails.logger.info "📋 Using provided task data: #{data[:tasks]&.size} tasks"
      end

      data
    end

    # Determine if this is a workflow approval
    def is_workflow_approval?(data)
      return false if data.nil?
      !!(data[:awaiting_approval] || data["awaiting_approval"])
    end

    private

    attr_reader :user, :session_id

    # Convert workflow progress to task list format
    def convert_workflow_progress_to_tasks(data)
      Rails.logger.info "📋 Converting workflow progress to task list format"

      # Use the task_session_id if provided
      if data[:task_session_id]
        task_session = TaskSession.find_by(id: data[:task_session_id])
        if task_session
          workflow_engine = WorkflowEngine.new(task_session)
          workflow = workflow_engine.instance_variable_get(:@workflow)

          return {
            tasks: workflow.steps.map do |step|
              {
                id: step.id,
                description: step.config[:description] || step.id.to_s.humanize,
                status: step.status,
                details: step.error,
                completed_at: step.completed_at,
                failed_at: step.status == "failed" ? step.completed_at : nil
              }
            end,
            title: task_session.workflow_name || "Workflow Progress",
            created_at: task_session.created_at
          }
        end
      end

      data
    end

    # Load task data from TaskSession
    def load_from_task_session(data)
      # If we have a specific task_session_id, load that regardless of status
      task_session = if data[:task_session_id] || data["task_session_id"]
        task_session_id = data[:task_session_id] || data["task_session_id"]
        TaskSession.where(user: user, id: task_session_id).first
      else
        # Try to find active task session
        TaskSession.active
                   .where(user: user)
                   .where("metadata->>'session_id' = ?", session_id)
                   .first
      end

      if task_session
        # Check if we have a task list in state
        if task_session.state&.dig("task_list")
          task_list = task_session.state["task_list"].with_indifferent_access
          Rails.logger.info "📋 Loaded task list from TaskSession state: #{task_list[:tasks]&.size} tasks"
          return task_list
        elsif task_session.workflow_spec
          # Convert workflow to task list format for display with proper state restoration
          return convert_workflow_to_task_list(task_session)
        else
          Rails.logger.info "📋 TaskSession found but no task list or workflow"
          return { tasks: [] }
        end
      else
        Rails.logger.info "📋 No active task session found for session: #{session_id}"
        return { tasks: [] }
      end
    end

    # Convert workflow to task list format
    def convert_workflow_to_task_list(task_session)
      workflow_engine = WorkflowEngine.new(task_session)
      workflow_progress = workflow_engine.progress

      # Get workflow instance to access steps
      workflow = workflow_engine.instance_variable_get(:@workflow)

      # Try to get workflow execution for accurate step statuses
      workflow_execution = task_session.workflow_execution

      tasks = workflow.steps.map do |step|
        step_name = step.name || step.config[:name] || step.description
        step_details = step.config[:description] || step.description

        # Get status from workflow execution if available
        step_status = step.status
        completed_at = step.completed_at

        if workflow_execution
          step_exec = workflow_execution.workflow_step_executions.find_by(step_id: step.id)
          if step_exec
            step_status = step_exec.status
            completed_at = step_exec.completed_at
          end
        end

        Rails.logger.info "📋 Step mapping: id=#{step.id}, name=#{step_name}, details=#{step_details}, status=#{step_status}"

        {
          id: step.id,
          description: step_name,
          details: step_details,
          status: step_status,
          completed_at: completed_at,
          failed_at: step_status == "failed" ? completed_at : nil
        }
      end

      Rails.logger.info "📋 Loaded task list from TaskSession workflow: #{tasks.size} tasks"

      {
        tasks: tasks,
        workflow_status: workflow_progress[:status],
        progress: workflow_progress
      }
    end
  end
end
