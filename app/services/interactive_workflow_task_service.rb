class InteractiveWorkflowTaskService
  def initialize(task)
    @task = task
    @user = task.user
    @entity = @user.entity
    @session_id = task.parent_conversation_id
    @workflow_type = task.metadata['workflow_type']
  end
  
  def execute_with_progress
    Rails.logger.info "[InteractiveWorkflowTaskService] Starting interactive workflow: #{@workflow_type} for task #{@task.id}"
    Rails.logger.info "[InteractiveWorkflowTaskService] Using session_id: #{@session_id} from parent_conversation_id: #{@task.parent_conversation_id}"
    
    # Check if we have a pre-created workflow spec
    workflow_spec = @task.metadata['workflow_spec']
    task_session_id = @task.metadata['task_session_id']
    
    if workflow_spec && task_session_id
      Rails.logger.info "[InteractiveWorkflowTaskService] Using pre-created workflow spec for task session #{task_session_id}"
      
      # Load the existing task session that contains the workflow
      existing_task_session = TaskSession.find(task_session_id)
      
      # Use WorkflowEngine directly to execute the workflow
      workflow_engine = WorkflowEngine.new(existing_task_session)
      
      # Set up progress callback
      workflow_engine.set_progress_callback do |event, data|
        handle_progress_event(event, data)
      end
      
      # Execute the workflow
      workflow = workflow_spec['workflow']
      is_v2 = workflow['template_version'] == 2 || workflow['phases'].present?
      
      if is_v2
        Rails.logger.info "🚀 Executing V2 phase-based workflow"
        workflow_result = workflow_engine.execute_v2_workflow(workflow, {})
      else
        Rails.logger.info "🚀 Executing V1 step-based workflow"
        workflow_result = workflow_engine.start_workflow(workflow, {})
      end
      
      # Update task based on workflow result
      handle_workflow_result(workflow_result)
      
      return {
        success: workflow_result[:success],
        response: workflow_result[:message],
        canvas_type: workflow_result[:canvas_type],
        canvas_data: workflow_result[:canvas_data],
        workflow_state: workflow_result[:workflow_state]
      }
    end
    
    # Fallback to original behavior if no pre-created workflow
    Rails.logger.info "[InteractiveWorkflowTaskService] No pre-created workflow, using standard process"
    
    # Load conversation history from parent conversation
    conversation_history = load_conversation_history
    
    # V3: Use agent loop directly
    initial_message = case @workflow_type
      when 'landing_page_creation_v2', 'landing_page_wizard'
        "create a landing page"
      when 'campaign_wizard'
        "create an email campaign"
      when 'email_template_wizard'
        "create an email template"
      else
        @task.metadata['description'] || @workflow_type
      end

    agent = V3::AgentLoop.new(
      user: @user,
      entity: @entity,
      session_id: @session_id
    )

    result = agent.process_message_streaming(initial_message, ->(_) {}, conversation_history)
    
    # If workflow needs input, mark task as awaiting input
    if result[:canvas_type] == 'workflow_plan_approval' || workflow_awaiting_input?(result)
      @task.update!(
        status: 'paused',
        state: @task.state.merge(
          workflow_state: result[:workflow_state] || {},
          awaiting_type: result[:canvas_type],
          last_message: result[:message]
        )
      )
      
      # Broadcast that we need user input
      broadcast_needs_input(result[:message])
    end
    
    # Return the result for the task execution job
    {
      success: result[:success],
      response: result[:message],
      canvas_type: result[:canvas_type],
      canvas_data: result[:canvas_data],
      workflow_state: result[:workflow_state]
    }
  end
  
  # Continue workflow with user input
  def continue_with_input(user_input)
    Rails.logger.info "[InteractiveWorkflowTaskService] Continuing workflow with input for task #{@task.id}"
    
    # Load conversation history
    conversation_history = load_conversation_history
    
    # V3: Use agent loop to continue workflow
    agent = V3::AgentLoop.new(
      user: @user,
      entity: @entity,
      session_id: @session_id
    )

    message = user_input.is_a?(String) ? user_input : "Continue with inputs: #{user_input.to_json}"
    result = agent.process_message_streaming(message, ->(_) {}, conversation_history)
    
    # Update task state
    if workflow_awaiting_input?(result)
      @task.update!(
        status: 'paused',
        state: @task.state.merge(
          workflow_state: result[:workflow_state] || {},
          last_message: result[:message]
        )
      )
    else
      # Workflow completed
      @task.update!(
        status: 'completed',
        progress: 100,
        state: @task.state.merge(
          workflow_state: result[:workflow_state] || {},
          result: result
        ),
        completed_at: Time.current
      )
    end
    
    result
  end
  
  private
  
  def load_conversation_history
    # Load the last 20 messages from the parent conversation
    ScoutMessage.where(session_id: @session_id)
                .order(created_at: :desc)
                .limit(20)
                .reverse
                .map { |msg| { role: msg.role, content: msg.content } }
  end
  
  def handle_progress_event(event, data)
    # Convert workflow engine events to progress data format
    case event
    when 'phase_progress'
      handle_progress({
        type: 'phase_progress',
        progress: data[:progress] || 50,
        message: data[:message]
      })
    when 'phase_complete'
      handle_progress({
        type: 'phase_complete',
        progress: 100,
        message: data[:message] || "Phase completed"
      })
    when 'intermediate_message'
      handle_progress({
        type: 'intermediate_message',
        content: data[:content],
        role: data[:role] || 'assistant',
        awaiting_input: data[:awaiting_input]
      })
    when 'workflow_paused'
      handle_progress({
        type: 'content_chunk',
        content: data[:message],
        awaiting_input: true
      })
    else
      Rails.logger.info "[InteractiveWorkflowTaskService] Unhandled workflow event: #{event}"
    end
  end
  
  def handle_workflow_result(workflow_result)
    case workflow_result[:status]
    when 'completed'
      @task.update!(
        status: 'completed',
        progress: 100,
        completed_at: Time.current,
        state: @task.state.merge(workflow_state: workflow_result[:workflow_state] || {})
      )
    when 'paused', 'awaiting_input'
      @task.update!(
        status: 'paused',
        state: @task.state.merge(
          workflow_state: workflow_result[:workflow_state] || {},
          awaiting_type: workflow_result[:canvas_type],
          last_message: workflow_result[:message]
        )
      )
      broadcast_needs_input(workflow_result[:message])
    when 'failed'
      @task.update!(
        status: 'failed',
        error_message: workflow_result[:error] || "Workflow execution failed"
      )
    end
  end
  
  def handle_progress(progress_data)
    # Broadcast progress updates via ScoutChannel
    case progress_data
    when String
      broadcast_progress(50, progress_data)
    when Hash
      case progress_data[:type]
      when 'phase_progress', 'phase_start'
        broadcast_progress(progress_data[:progress] || 50, progress_data[:message])
      when 'step_completed'
        broadcast_progress(progress_data[:progress] || 75, "✅ #{progress_data[:message]}")
      when 'content_chunk', 'intermediate_message'
        # Stream content to chat
        content = progress_data[:content] || progress_data[:message]
        if content
          Rails.logger.info "[InteractiveWorkflowTaskService] Broadcasting content_chunk: #{content[0..100]}..."
          ::ScoutChannel.broadcast_to(
            @session_id,
            {
              type: 'task_content',
              task_id: @task.id,
              content: content,
              role: progress_data[:role] || 'assistant',
              timestamp: Time.current.iso8601
            }
          )
        end
        
        # If this is awaiting input, also broadcast the needs_input message
        if progress_data[:awaiting_input]
          Rails.logger.info "[InteractiveWorkflowTaskService] Also broadcasting task_needs_input"
          broadcast_needs_input(content)
        end
      end
    end
  end
  
  def broadcast_progress(progress, message)
    ScoutChannel.broadcast_to(
      @session_id,
      {
        type: 'task_progress',
        task_id: @task.id,
        task_type: @task.task_type,
        description: @task.metadata['description'],
        status: @task.status,
        progress: progress,
        message: message,
        timestamp: Time.current.iso8601
      }
    )
  end
  
  def broadcast_needs_input(message)
    ScoutChannel.broadcast_to(
      @session_id,
      {
        type: 'task_needs_input',
        task_id: @task.id,
        description: @task.metadata['description'],
        message: message,
        workflow_type: @workflow_type,
        timestamp: Time.current.iso8601
      }
    )
  end
  
  def workflow_awaiting_input?(result)
    # Check various indicators that workflow needs input
    return true if result[:canvas_type] == 'workflow_plan_approval'
    return true if result[:canvas_type] == 'workflow_input'
    return true if result[:workflow_state] && result[:workflow_state]['awaiting_input']
    return true if result[:awaiting_input]
    false
  end
end
