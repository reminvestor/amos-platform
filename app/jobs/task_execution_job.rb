class TaskExecutionJob < ApplicationJob
  include JobErrorHandling
  
  # V3: Simple queue assignment
  queue_as :default
  
  def perform(task_session_id)
    @task = TaskSession.find(task_session_id)
    Rails.logger.info "TaskExecutionJob: Starting task #{@task.id} (Type: #{@task.task_type}, Priority: #{@task.priority})"
    
    # Ensure task is not already completed or failed
    return if @task.completed? || @task.failed?
    
    # Check for failed dependencies
    if @task.has_failed_dependencies?
      handle_task_failure("One or more dependencies failed")
      return
    end
    
    # Check dependencies first
    return reschedule_if_dependencies_pending if dependencies_pending?
    
    # Mark task as started
    @task.update!(status: 'active', started_at: Time.current, progress: 10)
    broadcast_progress(10, "Task started")
    
    begin
      # Execute based on task type
      result = execute_task
      
      # Mark as completed
      @task.update!(
        status: 'completed',
        progress: 100,
        state: @task.state.merge(result: result),
        completed_at: Time.current
      )
      
      Rails.logger.info "TaskExecutionJob: Task #{@task.id} completed successfully"
      
      # Broadcast completion
      broadcast_completion(result)
      
      # Trigger dependent tasks
      trigger_dependent_tasks
      
    rescue => e
      handle_task_failure(e)
      # Don't re-raise - we've handled the failure
    end
  end
  
  private
  
  def dependencies_pending?
    @task.task_dependencies.joins(:depends_on_task).where.not(
      task_sessions: { status: 'completed' }
    ).exists?
  end
  
  def reschedule_if_dependencies_pending
    Rails.logger.info "Task #{@task.id} waiting for dependencies"
    
    # Check if any dependency has failed
    failed_deps = @task.task_dependencies.joins(:depends_on_task).where(
      task_sessions: { status: 'failed' }
    )
    
    if failed_deps.exists?
      @task.update!(
        status: 'failed',
        state: @task.state.merge(
          failure_reason: 'Dependency failed'
        )
      )
      return
    end
    
    # Reschedule for later
    self.class.set(wait: 1.second).perform_later(@task.id)
  end
  
  def execute_task
    # Get appropriate service based on task type
    service = service_for_task_type
    
    # Execute with progress tracking
    result = service.execute_with_progress do |progress, message|
      @task.update!(progress: progress)
      broadcast_progress(progress, message)
    end
    
    # Return the result
    result
  end
  
  def service_for_task_type
    # V3: All task types use V3 agent loop directly
    # InteractiveWorkflowTaskService is still available for structured workflows
    case @task.task_type
    when 'interactive_workflow'
      InteractiveWorkflowTaskService.new(@task) rescue nil
    else
      nil # Will be executed via V3 agent in execute_task
    end
  end
  
  def broadcast_progress(progress, message = nil)
    return unless @task.parent_conversation_id.present?
    
    Rails.logger.info "[TaskExecutionJob] Broadcasting progress for task #{@task.id}: #{progress}% - #{message}"
    
    # Always broadcast to Scout channel for UI updates
    ::ScoutChannel.broadcast_to(
      @task.parent_conversation_id,
      {
        type: 'task_progress',
        task_id: @task.id,
        task_type: @task.task_type,
        description: @task.metadata['description'],
        progress: progress,
        message: message,
        status: @task.status,
        timestamp: Time.current.iso8601
      }
    )
    
    # Additionally check for voice session
    voice_session = VoiceSession.find_by(session_id: @task.parent_conversation_id)
    
    if voice_session
      # Also broadcast to voice channel
      VoiceChannel.broadcast_to(
        voice_session,
        {
          type: 'task_progress',
          task_id: @task.id,
          task_type: @task.task_type,
          progress: progress,
          message: message,
          timestamp: Time.current.iso8601
        }
      )
    end
  end
  
  def broadcast_completion(result)
    return unless @task.parent_conversation_id.present?
    
    voice_session = VoiceSession.find_by(session_id: @task.parent_conversation_id)
    
    # For voice followup tasks, synthesize the response
    if @task.task_type == 'voice_followup' && voice_session
      VoiceChannel.broadcast_to(
        voice_session,
        {
          type: 'followup_response',
          content: result[:response],
          task_id: @task.id,
          should_synthesize: true,
          timestamp: Time.current.iso8601
        }
      )
    end
    
      # Broadcast task completed event
      ::ScoutChannel.broadcast_to(
        @task.parent_conversation_id,
        {
          type: 'task_completed',
          task_id: @task.id,
          task_type: @task.task_type,
          description: @task.metadata['description'],
          status: 'completed',
          progress: 100,
          result: result,
          timestamp: Time.current.iso8601
        }
      )
      
      # Also broadcast task result to main chat
      if result[:response].present?
        ::ScoutChannel.broadcast_to(
          @task.parent_conversation_id,
          {
            type: 'task_result',
            task_id: @task.id,
            description: @task.metadata['description'],
            content: result[:response],
            timestamp: Time.current.iso8601
          }
        )
      end
  end
  
  def trigger_dependent_tasks
    # Update dependencies pointing to this task as satisfied
    TaskDependency.where(depends_on_task_id: @task.id).update_all(status: 'satisfied')
    
    dependent_tasks = TaskSession.joins(:task_dependencies)
                                 .where(task_dependencies: { depends_on_task_id: @task.id })
                                 .where(status: 'active')
    
    dependent_tasks.each do |task|
      # Check if all blocking dependencies are now satisfied
      if task.task_dependencies.where(dependency_type: 'blocking')
                               .joins(:depends_on_task)
                               .where.not(task_sessions: { status: 'completed' })
                               .none?
        # Queue the dependent task
        TaskExecutionJob.perform_later(task.id)
      end
    end
  end
  
  def handle_task_failure(error)
    Rails.logger.error "Task #{@task.id} failed: #{error.message}"
    Rails.logger.error error.backtrace.first(10).join("\n")
    
    @task.update!(
      status: 'failed',
      state: @task.state.merge(
        error: error.message,
        error_class: error.class.name,
        failed_at: Time.current
      )
    )
    
    # Broadcast task failed event
    ::ScoutChannel.broadcast_to(
      @task.parent_conversation_id,
      {
        type: 'task_failed',
        task_id: @task.id,
        task_type: @task.task_type,
        description: @task.metadata['description'],
        status: 'failed',
        error: error.message,
        timestamp: Time.current.iso8601
      }
    )
    
    # Mark dependencies pointing to this task as failed
    TaskDependency.where(depends_on_task_id: @task.id).update_all(status: 'failed')
    
    # Cancel dependent tasks that have blocking dependencies on this task
    dependent_tasks = TaskSession.joins(:task_dependencies)
                                 .where(task_dependencies: { depends_on_task_id: @task.id, dependency_type: 'blocking' })
                                 .where(status: 'active')
    
    dependent_tasks.update_all(status: 'cancelled', error_message: "Dependency task #{@task.id} failed")
  end
  
  def worker_id
    "#{Socket.gethostname}-#{Process.pid}-#{Thread.current.object_id}"
  end
end
