# Manages job creation and lifecycle for Amos
module Amos
  class JobManager
    def initialize
      @jobs = {}
    end
    
    def create_job(job_spec)
      job_id = SecureRandom.uuid
      
      # Find the AgentPlugin for this agent type
      agent_slug = job_spec[:agent].to_s.gsub('_agent', '')
      agent_plugin = AgentPlugin.find_by(slug: agent_slug)
      
      unless agent_plugin
        Rails.logger.error "[JobManager] Agent plugin not found: #{agent_slug}"
        raise "Agent plugin not found: #{agent_slug}"
      end
      
      # Get user and entity from context
      context = job_spec[:context] || {}
      user = User.find_by(id: context[:user_id]) || User.find_by(id: context['user_id'])
      entity = Entity.find_by(id: context[:entity_id]) || Entity.find_by(id: context['entity_id'])
      
      unless user && entity
        Rails.logger.error "[JobManager] User or Entity not found in context"
        raise "User or Entity required for agent execution"
      end
      
      # Create AgentPluginExecution record (the standard way to run agents)
      # Note: AgentPluginExecution doesn't have entity - it gets it from user or input_context
      execution = AgentPluginExecution.create!(
        agent_plugin: agent_plugin,
        user: user,
        status: 'running',  # Set to running since we're about to execute
        input_context: {
          task: job_spec[:task],
          session_id: job_spec[:session_id],
          callback_url: job_spec[:callback_url],
          original_job_id: job_id,
          entity_id: entity.id  # Store entity_id in context for the job to use
        }
      )
      
      # Also create JobRecord for AMOS tracking
      job_record = JobRecord.create!(
        job_id: job_id,
        agent_type: job_spec[:agent],
        session_id: job_spec[:session_id],
        status: 'queued',
        input_data: job_spec.merge(execution_id: execution.id),
        created_at: Time.current
      )
      
      # Queue the AgentPluginExecutionJob (the standard agent execution mechanism)
      AgentPluginExecutionJob.perform_later(
        execution.id,
        job_spec[:task],
        {
          session_id: job_spec[:session_id],
          entity_id: entity.id,
          callback_url: job_spec[:callback_url]
        }
      )
      
      @jobs[job_id] = {
        record: job_record,
        execution: execution,
        status: 'queued',
        agent: job_spec[:agent]
      }
      
      Rails.logger.info "[JobManager] Created job #{job_id} for #{agent_plugin.name} (execution: #{execution.id})"
      
      job_id
    end
    
    def status(job_id)
      job = @jobs[job_id] || load_job(job_id)
      return { status: 'not_found', message: 'Job not found' } unless job
      
      # Get latest status from record
      record = job[:record].reload
      
      {
        status: record.status,
        message: record.status_message || default_status_message(record.status),
        progress: record.progress || 0,
        result: record.result_data
      }
    end
    
    def send_input(job_id, input)
      job = @jobs[job_id] || load_job(job_id)
      return false unless job
      
      # Send input to the running job via Redis or ActiveJob
      Rails.cache.write(
        "job_input_#{job_id}",
        { input: input, timestamp: Time.current },
        expires_in: 1.hour
      )
      
      # Notify the job that input is available
      ActionCable.server.broadcast(
        "job_channel_#{job_id}",
        { type: 'user_input', input: input }
      )
      
      true
    end
    
    def resume_job(job_id)
      job = @jobs[job_id] || load_job(job_id)
      return false unless job
      
      job[:record].update!(status: 'resuming')
      
      # Notify the job to resume
      ActionCable.server.broadcast(
        "job_channel_#{job_id}",
        { type: 'resume' }
      )
      
      true
    end
    
    def cancel_job(job_id)
      job = @jobs[job_id] || load_job(job_id)
      return false unless job
      
      job[:record].update!(
        status: 'cancelled',
        completed_at: Time.current
      )
      
      # Notify the job to stop
      ActionCable.server.broadcast(
        "job_channel_#{job_id}",
        { type: 'cancel' }
      )
      
      @jobs.delete(job_id)
      true
    end
    
    private
    
    
    def load_job(job_id)
      record = JobRecord.find_by(job_id: job_id)
      return nil unless record
      
      @jobs[job_id] = {
        record: record,
        status: record.status,
        agent: record.agent_type.to_sym
      }
    end
    
    def default_status_message(status)
      case status
      when 'queued' then 'Waiting to start...'
      when 'running' then 'Processing your request...'
      when 'waiting_for_input' then 'Waiting for your response...'
      when 'completed' then 'Task completed successfully!'
      when 'failed' then 'Task encountered an error.'
      when 'cancelled' then 'Task was cancelled.'
      else 'Unknown status'
      end
    end
  end
end

