# Base class for all specialized agent jobs
module AgentJobs
  class BaseAgentJob < ApplicationJob
    queue_as :agents
    
    def perform(job_id:, task:, context:, callback_url:)
      @job_id = job_id
      @task = task
      @context = context
      @callback_url = callback_url
      @job_record = Amos::JobRecord.find_by!(job_id: job_id)
      
      Rails.logger.info "[#{self.class.name}] Starting job #{job_id}"
      
      # Update status
      update_status('running', 'Starting task...')
      
      # Set up communication channel
      setup_communication_channel
      
      begin
        # Execute the agent's specific logic
        result = execute_agent_task
        
        # Mark complete and callback
        complete_job(result)
      rescue => e
        # Handle failures
        fail_job(e)
      end
    end
    
    protected
    
    # Override in subclasses
    def execute_agent_task
      raise NotImplementedError, "Subclasses must implement execute_agent_task"
    end
    
    def update_status(status, message = nil, progress: nil)
      @job_record.update!(
        status: status,
        status_message: message,
        progress: progress,
        updated_at: Time.current
      )
      
      # Stream update to Amos
      stream_to_amos({
        type: 'status_update',
        status: status,
        message: message,
        progress: progress
      })
    end
    
    def stream_content(content, metadata: {})
      # Stream content back to Amos in real-time
      formatted_content = format_agent_message(content, 'update')
      stream_to_amos({
        type: 'content',
        content: formatted_content,
        metadata: metadata
      })
    end
    
    def request_user_input(prompt, options: nil)
      update_status('waiting_for_input', prompt)
      
      # Format the prompt with agent communication tags
      formatted_prompt = format_agent_message(prompt, 'question')
      
      stream_to_amos({
        type: 'input_request',
        prompt: formatted_prompt,
        options: options
      })
      
      # Wait for input
      wait_for_user_input
    end
    
    private
    
    def setup_communication_channel
      # Subscribe to job-specific channel for bidirectional communication
      @channel = "job_channel_#{@job_id}"
      
      # This would set up actual subscription
      Rails.logger.info "[#{self.class.name}] Listening on channel: #{@channel}"
    end
    
    def wait_for_user_input(timeout: 5.minutes)
      start_time = Time.current
      
      loop do
        # Check for input in cache
        input_data = Rails.cache.read("job_input_#{@job_id}")
        
        if input_data
          Rails.cache.delete("job_input_#{@job_id}")
          return input_data[:input]
        end
        
        # Check timeout
        if Time.current - start_time > timeout
          raise "Timeout waiting for user input"
        end
        
        # Small delay to prevent hammering
        sleep 0.5
      end
    end
    
    def stream_to_amos(data)
      # Send real-time updates to Amos
      payload = {
        job_id: @job_id,
        timestamp: Time.current.iso8601,
        data: data
      }
      
      # For status updates, use ActionCable directly to avoid deadlocks
      if data[:type] == 'status_update' && @context[:session_id]
        # Broadcast directly via ActionCable for immediate status updates
        begin
          ScoutChannel.broadcast_to(
            @context[:session_id],
            {
              type: 'task_progress',
              task_id: "amos-#{@job_id}",
              task_type: self.class.name.demodulize.underscore.gsub('_job', ''),
              description: @task,
              status: data[:status],
              progress: data[:progress] || 0,
              message: data[:message]
            }
          )
          Rails.logger.info "[#{self.class.name}] Broadcasted status update via ActionCable"
        rescue => e
          Rails.logger.error "[#{self.class.name}] Failed to broadcast via ActionCable: #{e.message}"
        end
      end
      
      # For other types or if ActionCable fails, use HTTP callback
      if @callback_url && data[:type] != 'status_update'
        begin
          HTTParty.post(@callback_url, 
            body: payload.to_json,
            headers: { 'Content-Type' => 'application/json' },
            timeout: 5  # 5 second timeout
          )
        rescue => e
          Rails.logger.error "[#{self.class.name}] Failed to stream to Amos: #{e.message}"
        end
      end
    end
    
    def complete_job(result)
      @job_record.update!(
        status: 'completed',
        result_data: result,
        progress: 100,
        completed_at: Time.current
      )
      
      # Notify Scout of completion with proper tags
      completion_message = format_agent_message("Task completed successfully!", 'completion')
      stream_to_amos({
        type: 'job_completed',
        content: completion_message,
        result: result
      })
      
      Rails.logger.info "[#{self.class.name}] Job #{@job_id} completed successfully"
    end
    
    def fail_job(error)
      @job_record.update!(
        status: 'failed',
        error_data: {
          message: error.message,
          backtrace: error.backtrace.first(10)
        },
        completed_at: Time.current
      )
      
      # Notify Scout of failure with proper tags
      failure_message = format_agent_message("Task failed: #{error.message}", 'completion')
      stream_to_amos({
        type: 'job_failed',
        content: failure_message,
        error: error.message
      })
      
      Rails.logger.error "[#{self.class.name}] Job #{@job_id} failed: #{error.message}"
    end
    
    def format_agent_message(content, request_type)
      # Format messages with standardized tags for Scout to recognize
      agent_name = self.class.name.demodulize.underscore.gsub('_job', '')
      status = case @job_record&.status
               when 'running' then 'processing'
               when 'waiting_for_input' then 'needs_input'
               else 'gathering_info'
               end
      
      # Build the tagged message
      "[AGENT: #{agent_name}][JOB_ID: #{@job_id}][STATUS: #{status}][REQUEST_TYPE: #{request_type}] #{content}"
    end
    
    def get_current_job_status
      @job_record&.status || 'initializing'
    end
  end
end


