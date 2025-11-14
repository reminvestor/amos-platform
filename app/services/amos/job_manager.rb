# Manages job creation and lifecycle for Amos
module Amos
  class JobManager
    def initialize
      @jobs = {}
    end
    
    def create_job(job_spec)
      job_id = SecureRandom.uuid
      
      # Create the appropriate job based on agent type
      job_class = agent_to_job_class(job_spec[:agent])
      
      # Create job record in database
      job_record = JobRecord.create!(
        job_id: job_id,
        agent_type: job_spec[:agent],
        session_id: job_spec[:session_id],
        status: 'queued',
        input_data: job_spec,
        created_at: Time.current
      )
      
      # Queue the actual background job
      job_class.perform_later(
        job_id: job_id,
        task: job_spec[:task],
        context: job_spec[:context],
        callback_url: job_spec[:callback_url]
      )
      
      @jobs[job_id] = {
        record: job_record,
        status: 'queued',
        agent: job_spec[:agent]
      }
      
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
    
    def agent_to_job_class(agent_type)
      case agent_type
      when :landing_page_agent
        AgentJobs::LandingPageAgentJob
      when :email_agent
        AgentJobs::EmailAgentJob
      when :integration_agent
        AgentJobs::IntegrationAgentJob
      when :data_agent
        AgentJobs::DataAgentJob
      when :analytics_agent
        AgentJobs::AnalyticsAgentJob
      else
        AgentJobs::GeneralAgentJob
      end
    end
    
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

