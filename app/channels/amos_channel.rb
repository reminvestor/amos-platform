# ActionCable channel for Amos real-time communication
class AmosChannel < ApplicationCable::Channel
  def subscribed
    session_id = params[:session_id]
    stream_from "amos_channel_#{session_id}"
    
    Rails.logger.info "[AmosChannel] Client subscribed to session: #{session_id}"
  end
  
  def unsubscribed
    Rails.logger.info "[AmosChannel] Client unsubscribed"
  end
  
  # Handle incoming messages from client
  def receive(data)
    case data['type']
    when 'user_input'
      # Forward user input to waiting job
      handle_user_input(data)
    when 'cancel_job'
      # Cancel a running job
      handle_job_cancellation(data)
    when 'heartbeat'
      # Client keepalive
      transmit({ type: 'heartbeat_ack', timestamp: Time.current.iso8601 })
    end
  end
  
  # Broadcast to a specific session
  def self.broadcast_to(session_id, data)
    ActionCable.server.broadcast("amos_channel_#{session_id}", data)
    
    Rails.logger.info "[AmosChannel] Broadcasting to #{session_id}: #{data[:type]}"
  end
  
  private
  
  def handle_user_input(data)
    job_id = data['job_id']
    input = data['input']
    
    # Store input for job to pick up
    Rails.cache.write(
      "job_input_#{job_id}",
      { input: input, timestamp: Time.current },
      expires_in: 1.hour
    )
    
    # Notify the job
    ActionCable.server.broadcast(
      "job_channel_#{job_id}",
      { type: 'user_input', input: input }
    )
    
    transmit({ type: 'input_received', job_id: job_id })
  end
  
  def handle_job_cancellation(data)
    job_id = data['job_id']
    
    # Update job status
    job = Amos::JobRecord.find_by(job_id: job_id)
    if job && job.status.in?(['queued', 'running', 'waiting_for_input'])
      job.update!(
        status: 'cancelled',
        completed_at: Time.current
      )
      
      # Notify the job to stop
      ActionCable.server.broadcast(
        "job_channel_#{job_id}",
        { type: 'cancel' }
      )
      
      transmit({ 
        type: 'job_cancelled', 
        job_id: job_id,
        message: 'Job has been cancelled.'
      })
    else
      transmit({ 
        type: 'error', 
        message: 'Job not found or already completed.'
      })
    end
  end
end

