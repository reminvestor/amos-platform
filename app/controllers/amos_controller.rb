# Web interface for Amos orchestrator
class AmosController < ApplicationController
  include ActionController::Live

  skip_before_action :authenticate_user!, only: [:callback]
  before_action :initialize_orchestrator, except: [:callback]
  skip_before_action :verify_authenticity_token, only: [:callback]
  skip_before_action :check_token_balance, only: [:callback]
  skip_before_action :check_onboarding_status, only: [:callback]
  
  # Main chat endpoint - replaces Scout's chat_stream
  def chat
    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['Cache-Control'] = 'no-cache'
    response.headers['X-Accel-Buffering'] = 'no'
    
    message = params[:message]
    attached_files = process_attached_files
    
    begin
      # Process through Amos
      @orchestrator.process_message(
        message, 
        source: :user,
        metadata: {
          attached_files: attached_files,
          canvas: params[:canvas]
        }
      )
      
      # Keep connection alive while jobs are running
      keep_alive_while_processing
      
    rescue => e
      Rails.logger.error "[Amos] Chat error: #{e.message}"
      stream_error(e.message)
    ensure
      response.stream.close
    end
  end
  
  # Callback endpoint for agents to report back
  def callback
    Rails.logger.info "[Amos] ===== CALLBACK ACTION STARTED ====="
    Rails.logger.info "[Amos] Params: #{params.inspect}"

    @session_id = params[:session_id]
    job_id = params[:job_id]
    data = params[:data] || {}

    Rails.logger.info "[Amos] Received callback for job #{job_id}: #{data[:type]}"
    
    # For input requests and content streams that need processing, respond immediately
    # and handle asynchronously to prevent timeout
    if data[:type] == 'input_request' || (data[:type] == 'content' && data[:content]&.match?(/\[AGENT:.*\]/))
      # Respond immediately
      render json: { success: true }
      
      # Process in background (using Rails after_action or a job)
      Thread.new do
        Rails.application.executor.wrap do
          case data[:type]
          when 'input_request'
            handle_input_request(job_id, data)
          when 'content'
            handle_content_stream(job_id, data)
          end
        end
      rescue => e
        Rails.logger.error "[Amos] Background processing error: #{e.message}"
      end
      
      return
    end
    
    # Handle other types synchronously
    case data[:type]
    when 'status_update'
      handle_status_update(job_id, data)
    when 'job_completed'
      handle_job_completion(job_id, data)
    when 'job_failed'
      handle_job_failure(job_id, data)
    else
      Rails.logger.warn "[Amos] Unknown callback type: #{data[:type]}"
    end
    
    render json: { success: true }
  rescue => e
    Rails.logger.error "[Amos] Callback error: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    render json: { success: false, error: e.message }, status: :internal_server_error
  end
  
  # Get status of all jobs
  def job_status
    statuses = @orchestrator.query_job_status
    render json: { jobs: statuses }
  end
  
  # Send input to a waiting job
  def send_input
    job_id = params[:job_id]
    user_input = params[:input]
    
    @orchestrator.process_message(
      user_input,
      source: :user,
      metadata: { job_id: job_id, is_continuation: true }
    )
    
    render json: { success: true }
  end
  
  private
  
  def initialize_orchestrator
    @session_id = session[:amos_session_id] ||= SecureRandom.uuid
    @orchestrator = Amos::Orchestrator.new(current_user, current_entity, @session_id)
  end
  
  def process_attached_files
    return [] unless params[:attached_files].present?
    
    files = []
    params[:attached_files].each do |file|
      if file.respond_to?(:tempfile)
        # Handle file upload
        asset = create_asset_from_upload(file)
        files << {
          type: 'upload',
          asset_id: asset.id,
          filename: file.original_filename,
          content_type: file.content_type,
          url: asset.respond_to?(:url) ? asset.url : nil
        }
      else
        # Handle existing asset reference
        files << JSON.parse(file).deep_symbolize_keys
      end
    end
    
    files
  end
  
  def create_asset_from_upload(file)
    if image_file?(file)
      ImageAsset.create!(
        entity: current_entity,
        user: current_user,
        file: file,
        filename: file.original_filename
      )
    else
      Asset.create!(
        entity: current_entity,
        user: current_user,
        file: file,
        original_filename: file.original_filename,
        file_type: file.content_type
      )
    end
  end
  
  def handle_status_update(job_id, data)
    # Get job details for task monitor
    job = Amos::JobRecord.find_by(job_id: job_id)
    
    # Also broadcast to ScoutChannel for task monitor
    if job
      ScoutChannel.broadcast_to(
        @session_id,
        {
          type: 'task_progress',
          task_id: "amos-#{job_id}",
          task_type: job.agent_type,
          description: job.input_data&.dig('task') || job.status_message || "#{job.agent_type.humanize} Job",
          status: data[:status],
          progress: data[:progress] || job.progress,
          message: data[:message]
        }
      )
    end
  end
  
  def handle_content_stream(job_id, data)
    # Check if this content has agent tags
    content = data[:content]
    
    if content && content.match?(/\[AGENT:.*\].*\[JOB_ID:.*\].*\[REQUEST_TYPE:.*\]/)
      # This is an agent message - route through orchestrator
      Rails.logger.info "[Amos] Forwarding agent content to orchestrator: #{content[0..100]}..."
      
      # Find the job to get user context
      if job = Amos::JobRecord.find_by(job_id: job_id)
        user_id = job.input_data['user_id'] || job.input_data.dig('context', 'user_id')
        entity_id = job.input_data['entity_id'] || job.input_data.dig('context', 'entity_id')
        
        if user = User.find_by(id: user_id)
          entity = Entity.find_by(id: entity_id) || user.entity
          orchestrator = Amos::Orchestrator.new(user, entity, @session_id)
          orchestrator.process_message(content, source: :agent, metadata: {
            job_id: job_id,
            callback_data: data
          })
        else
          Rails.logger.error "[Amos] Could not find user for job #{job_id} to route agent message"
        end
      else
        Rails.logger.error "[Amos] Could not find job #{job_id} to route agent message"
      end
    else
      # Regular content stream - broadcast directly
      clean_metadata = case data[:metadata]
                      when ActionController::Parameters
                        data[:metadata].permit!.to_h
                      when Hash
                        data[:metadata]
                      else
                        {}
                      end
      
      ScoutChannel.broadcast_to(
        @session_id,
        {
          type: 'assistant_message',
          job_id: job_id,
          content: content,
          metadata: clean_metadata
        }
      )
    end
    
    # Also save to conversation history if we can find the user
    if job = Amos::JobRecord.find_by(job_id: job_id)
      # Extract user_id and entity_id from the job's input_data
      if job.input_data
        user_id = job.input_data['user_id'] || job.input_data.dig('context', 'user_id')
        entity_id = job.input_data['entity_id'] || job.input_data.dig('context', 'entity_id')
        
        if user_id && entity_id
          # Convert metadata to regular hash if it's ActionController::Parameters
          clean_metadata = case data[:metadata]
                          when ActionController::Parameters
                            data[:metadata].permit!.to_h
                          when Hash
                            data[:metadata]
                          else
                            {}
                          end
          
          ScoutMessage.create!(
            user_id: user_id,
            entity_id: entity_id,
            session_id: @session_id,
            role: 'assistant',
            content: data[:content],
            metadata: { job_id: job_id }.merge(clean_metadata)
          )
        end
      end
    end
  end
  
  def handle_input_request(job_id, data)
    # Get the agent's formatted prompt (should include tags)
    prompt = data[:prompt] || "I need some additional information to continue"
    
    # Find the job to get user context
    job = Amos::JobRecord.find_by(job_id: job_id)
    if job && job.input_data
      # User and entity IDs are at the top level of input_data
      user_id = job.input_data['user_id'] || job.input_data.dig('context', 'user_id')
      entity_id = job.input_data['entity_id'] || job.input_data.dig('context', 'entity_id')
      
      Rails.logger.info "[Amos] Found user_id: #{user_id}, entity_id: #{entity_id} for job #{job_id}"
      
      if user = User.find_by(id: user_id)
        entity = Entity.find_by(id: entity_id) || user.entity
        
        # Create orchestrator for this request
        orchestrator = Amos::Orchestrator.new(user, entity, @session_id)
        
        # Forward to orchestrator as an agent message
        Rails.logger.info "[Amos] Forwarding agent input request to orchestrator: #{prompt}"
        orchestrator.process_message(prompt, source: :agent, metadata: {
          job_id: job_id,
          callback_data: data
        })
      else
        Rails.logger.error "[Amos] Could not find user for job #{job_id} (user_id: #{user_id})"
      end
    else
      Rails.logger.error "[Amos] Could not find job or input_data for #{job_id}"
    end
  end
  
  def handle_job_completion(job_id, data)
    # Find the job to get user context
    if job = Amos::JobRecord.find_by(job_id: job_id)
      if job.input_data && job.input_data['context']
        user_id = job.input_data['context']['user_id']
        entity_id = job.input_data['context']['entity_id']
        
        if user = User.find_by(id: user_id)
          entity = Entity.find_by(id: entity_id) || user.entity
          
          # Create orchestrator for this job
          orchestrator = Amos::Orchestrator.new(user, entity, @session_id)
          orchestrator.handle_job_completion(job_id, data[:result])
        else
          Rails.logger.error "[Amos] Could not find user for job #{job_id}"
        end
      end
      
      # Broadcast completion to task monitor
      ScoutChannel.broadcast_to(
        @session_id,
        {
          type: 'task_completed',
          task_id: "amos-#{job_id}",
          description: job.input_data&.dig('task') || "#{job.agent_type.humanize} Job",
          status: 'completed',
          progress: 100
        }
      )
      
      # If landing page was created successfully, load the editor
      if job.agent_type == 'landing_page_agent' && data[:result] && data[:result][:landing_page_id]
        # Add a small delay to ensure the success message appears first
        Thread.new do
          sleep 0.5
          ScoutChannel.broadcast_to(
            @session_id,
            {
              type: 'load_canvas',
              canvas: 'landing_page_editor',
              canvas_data: { landing_page_id: data[:result][:landing_page_id] }
            }
          )
        end
      end
    else
      Rails.logger.error "[Amos] Could not find job record for #{job_id}"
    end
  end
  
  def handle_job_failure(job_id, data)
    # Stream error to user via ScoutChannel
    ScoutChannel.broadcast_to(
      @session_id,
      {
        type: 'error',
        job_id: job_id,
        message: "Task failed: #{data[:error]}"
      }
    )
    
    # Send a user-friendly message
    ScoutChannel.broadcast_to(
      @session_id,
      {
        type: 'assistant_message',
        content: "I'm sorry, I encountered an error while creating your landing page. Please try again or let me know if you'd like to try something else.",
        metadata: { error: true, job_id: job_id }
      }
    )
    
    # Get job details for task monitor
    job = Amos::JobRecord.find_by(job_id: job_id)
    if job
      # Broadcast failure to task monitor
      ScoutChannel.broadcast_to(
        @session_id,
        {
          type: 'task_failed',
          task_id: "amos-#{job_id}",
          description: job.input_data&.dig('task') || "#{job.agent_type.humanize} Job",
          status: 'failed',
          error: data[:error]
        }
      )
    end
  end
  
  def keep_alive_while_processing
    # Send periodic heartbeats while jobs are active
    30.times do
      break unless @orchestrator.query_job_status.any? { |j| j[:status][:status] == 'running' }
      
      response.stream.write(":\n\n") # SSE comment for keep-alive
      sleep 1
    end
  end
  
  def stream_error(message)
    data = JSON.generate({ type: 'error', message: message })
    response.stream.write("data: #{data}\n\n")
  end
  
  def current_entity
    @current_entity ||= current_user.entity
  end
  
  def image_file?(file)
    %w[image/jpeg image/jpg image/png image/gif image/webp].include?(file.content_type)
  end
end
