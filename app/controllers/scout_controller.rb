class ScoutController < ApplicationController
  include ActionController::Live  # Enable real-time streaming
  include ActionView::Helpers::NumberHelper  # For number formatting
  include ActionView::Helpers::DateHelper  # For time_ago_in_words
  include Scout::Streaming  # Streaming helpers
  include Scout::StreamingKeepalive  # Keep-alive for long operations

  skip_before_action :verify_authenticity_token, only: [:chat_stream, :chat]
  before_action :authenticate_user_or_api!
  before_action :ensure_entity_exists
  before_action :ensure_onboarded, unless: :api_request?

  layout "scout"

  def index
    # Ensure session belongs to current user - reset if it belongs to someone else
    ensure_user_owns_session!
    
    @session_id = session[:scout_session_id] ||= SecureRandom.uuid
    @conversation_history = persisted_history_last_k(10)
    @show_parallel_tasks = true
    
    # Set current space for view rendering
    # Map old space slugs to new ones for users who haven't switched yet
    active_space = current_user.active_space
    active_space = 'operations' if active_space.in?(['work', 'team'])  # Legacy mapping
    
    @current_space = SpaceDefinition.find_by(slug: active_space) || 
                     SpaceDefinition.find_by(slug: 'operations')
    
    # THREE MODE ARCHITECTURE:
    # - Personal: No sidebar, just chat + canvas
    # - Operations: Collaboration sidebar (agents, team, channels)
    # - Design: Collaboration sidebar (design agents, current projects)
    @in_personal_mode = @current_space&.slug == 'personal'
    @show_collab_sidebar = @current_space&.slug.in?(['operations', 'design'])
    
    # Legacy compatibility
    @in_team_space = @show_collab_sidebar
    
    # Load Hub/Collaboration data when sidebar is shown
    if @show_collab_sidebar
      load_hub_data
    end

    # Load available RAG stores for the entity
    @rag_stores = RagLoaderService.load_for_entity(current_entity)

    # Check if user recently created a landing page (within last 5 minutes)
    # This helps users who missed the streaming response know their page was created
    recent_landing_page = current_entity.landing_pages.where(created_at: 5.minutes.ago..Time.current).first
    if recent_landing_page
      flash.now[:success] = "🎉 Your landing page '#{recent_landing_page.title}' was created successfully! You can access it from the Landing Pages section."
    end

    # If this is a fresh start, add Scout's welcome message
    # Stay in conversation mode - don't auto-load any canvas
    if @conversation_history.empty?
      create_welcome_message
      @conversation_history = persisted_history_last_k(10)
      # No auto-load canvas - user stays in chat mode until they choose a canvas
    end

    # Business context for display
    @business_profile = current_user.business_profile
    @entity = current_entity
    
    # Check if we should auto-load dashboard (e.g., just completed onboarding)
    @load_dashboard_on_entry = session.delete(:load_dashboard_on_entry)
    
    # Check cookie for theme preference (set during onboarding)
    @initial_theme = cookies[:amos_theme_preference] || 'light'

    # Load pending agent questions for the question queue
    begin
      @pending_questions = AgentInputRequest
        .joins(agent_plugin_execution: :agent_plugin)
        .where(agent_plugin_executions: { 
          user: current_user,
          status: 'waiting_for_input'
        })
        .active
        .by_priority
        .limit(20)
      
      @pending_questions_count = @pending_questions.count
    rescue => e
      Rails.logger.error "❌ Error loading pending questions: #{e.message}"
      @pending_questions = []
      @pending_questions_count = 0
    end

    # Handle auto-load parameters (supports both 'load' and 'canvas' params)
    @auto_load_canvas = params[:load] || params[:canvas] if params[:load].present? || params[:canvas].present?
    
    # Handle flash messages passed as URL params (from OAuth callbacks)
    flash.now[:notice] = params[:notice] if params[:notice].present?
    flash.now[:alert] = params[:alert] if params[:alert].present?
  end

  def chat
    @session_id = session[:scout_session_id] ||= SecureRandom.uuid
    user_message = params[:message]&.strip
    current_canvas = params[:current_canvas]

    Rails.logger.info "Scout chat - Session: #{@session_id}, User: #{current_user.id}, Message: #{user_message}"
    Rails.logger.info "Current canvas context: #{current_canvas.inspect}" if current_canvas

    if user_message.blank?
      render json: { error: "Message cannot be empty" }, status: 400
      return
    end

    begin
      # Save user message
      save_scout_message("user", user_message)
      Rails.logger.info "Scout: Saved user message"

      # Use the new V2 tools service with main_chat agent loadout
      # Pass entity to load DB-driven tool configuration
      main_chat_loadout = AgentLoadout.new(agent_role: "main_chat", entity: current_entity)
      
      # Parse fresh_start_at from session (filter memory to only after Fresh Start)
      fresh_start_time = session[:scout_fresh_start_at].present? ? 
        (Time.parse(session[:scout_fresh_start_at]) rescue nil) : nil
      
      generic_tools_service = ScoutGenericToolsServiceV2.new(
        current_user,
        current_entity,
        session[:scout_session_id],
        agent_loadout: main_chat_loadout,
        fresh_start_at: fresh_start_time
      )

      # Apply model mode from user preference (auto, fast, balanced, powerful)
      model_mode = params[:model_mode]&.to_sym || session[:model_mode]&.to_sym || :auto
      generic_tools_service.set_model_mode(model_mode)
      
      # Pass session context for tools that need it (e.g., read_viewed_page)
      generic_tools_service.set_context({
        current_viewed_url: session[:current_viewed_url],
        current_viewed_at: session[:current_viewed_at],
        proxy_base_url: session[:proxy_base_url],
        proxy_session_id: session[:proxy_session_id]
      })

      # Use last 20 messages for active context window (keeping token usage manageable)
      conversation_history = persisted_history_last_k(20)
      # Note: V2 uses streaming by default, but this endpoint returns JSON
      # We'll need to update this to use process_message_with_tools_streaming properly
      # For now, let's create a simple wrapper
      result = nil
      generic_tools_service.process_message_with_tools_streaming(
        user_message,
        ->(update) {
          # Collect the final response
          if update.is_a?(Hash) && update[:final_response]
            result = update
          end
        },
        conversation_history,
        current_canvas
      )

      # Extract response from result
      response = if result
        {
          message: result[:final_response][:message],
          tools_used: result[:tools_used] || [],
          success_count: result[:tools_used]&.length || 0,
          error_count: 0,
          canvas_type: result[:canvas_type] || "conversation",
          canvas_data: result[:canvas_data] || {}
        }
      else
        {
          message: "I couldn't process that request.",
          tools_used: [],
          success_count: 0,
          error_count: 1,
          canvas_type: "conversation",
          canvas_data: {}
        }
      end

      Rails.logger.info "Scout: Got response - tools_used: #{response[:tools_used]}, success_count: #{response[:success_count]}"

      # Extract source information from tools_used (specifically read_document calls)
      sources = extract_response_sources(response[:tools_used])
      Rails.logger.info "📚 Extracted sources: #{sources.inspect}" if sources.any?

      # Save Scout's response
      save_scout_message("assistant", response[:message])

      # Return structured response
      render json: {
        message: response[:message],
        tools_used: response[:tools_used],
        tools_list: response[:tools_list],
        success_count: response[:success_count],
        error_count: response[:error_count],
        sources: sources,
        canvas: response[:canvas]
      }

    rescue AmosErrors::BedrockThrottlingError, AmosErrors::BedrockUnavailableError, AmosErrors::BedrockTimeoutError => e
      Rails.logger.error "Scout Bedrock error: #{e.class.name} - #{e.message}"
      save_scout_message("assistant", e.user_message)

      render json: {
        message: e.user_message,
        error: true,
        retry_after: e.retry_after,
        error_type: e.class.name.demodulize
      }, status: 503
    rescue AmosErrors::BedrockError => e
      Rails.logger.error "Scout Bedrock error: #{e.message}"
      save_scout_message("assistant", e.user_message)

      render json: {
        message: e.user_message,
        error: true,
        retry_after: e.retry_after
      }, status: 503
    rescue AmosErrors::IntegrationError => e
      Rails.logger.error "Scout integration error: #{e.integration_name} - #{e.message}"
      save_scout_message("assistant", e.user_message)

      render json: {
        message: e.user_message,
        error: true,
        integration: e.integration_name
      }, status: 422
    rescue StandardError => e
      Rails.logger.error "Scout chat error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      # Fallback response
      fallback_message = "I apologize, but I'm experiencing some technical difficulties. Please try again, or contact support if the issue persists."
      save_scout_message("assistant", fallback_message)

      render json: {
        message: fallback_message,
        error: true,
        tools_used: false
      }, status: 500
    end
  end

  def chat_interactive
    @session_id = session[:scout_session_id] ||= SecureRandom.uuid
    user_message = params[:message]&.strip
    current_canvas = params[:current_canvas]
    context = params[:context]
    file_urls = params[:file_urls] || []

    Rails.logger.info "Scout interactive chat - Session: #{@session_id}, User: #{current_user.id}, Message: #{user_message}"
    Rails.logger.info "Chat context: #{context.inspect}" if context
    Rails.logger.info "File URLs: #{file_urls.inspect}" if file_urls.any?

    if user_message.blank?
      render json: { error: "Message cannot be empty" }, status: 400
      return
    end

    begin
      # Build enhanced message if files are attached
      enhanced_message = user_message
      metadata = {}

      if file_urls.any?
        Rails.logger.info "🔍 Scout file_urls: #{file_urls.inspect}"
        # Include asset_id so AMOS can use read_document tool
        file_details = file_urls.map do |f|
          # Support both asset_id and document_id for backward compatibility
          id = f['asset_id'] || f['document_id']
          asset_type = f['asset_type'] || 'image' # Default to image for backward compatibility
          "📎 #{f['filename']} (asset_id: #{id}, asset_type: #{asset_type}, type: #{f['content_type']})"
        end.join(", ")

        enhanced_message = "#{user_message}\n\n[Attached Files: #{file_details}]\n\nIMPORTANT: Use the read_document tool with the asset_id AND asset_type to extract content from these files before responding."
        metadata[:file_urls] = file_urls
      end

      # Save user message with file info
      save_scout_message("user", enhanced_message, metadata: metadata)

      # Capture workflow messages during progress
      workflow_message = nil

      # Set up progress callback for real-time updates
      interactive_service.on_progress do |progress_data|
        Rails.logger.info "Workflow progress: #{progress_data.inspect}"

        # Capture workflow questions/messages for awaiting_input state
        if progress_data.is_a?(Hash)
          if progress_data[:type] == "content_chunk" && progress_data[:awaiting_input]
            workflow_message = progress_data[:message]
          elsif progress_data[:type] == "phase_progress" && progress_data[:message]
            workflow_message ||= progress_data[:message]
          end
        end
      end

      # Process the message with 20-message active window
      result = interactive_service.process_message(user_message, persisted_history_last_k(20), current_canvas)

      # If workflow is awaiting input and we captured a message, use that
      if result[:awaiting_input] && workflow_message
        result[:message] = workflow_message
      end

      # Save assistant response if present
      if result[:message]
        save_scout_message("assistant", result[:message])
      end

      # Return structured response
      render json: {
        success: result[:success],
        message: result[:message],
        canvas: result[:canvas],
        canvas_data: result[:canvas_data],
        mode: result[:mode],
        awaiting_input: result[:awaiting_input],
        workflow_completed: result[:workflow_completed],
        step_completed: result[:step_completed]
      }

    rescue => e
      Rails.logger.error "Scout interactive chat error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      render json: {
        success: false,
        message: "I encountered an error processing your request. Please try again.",
        error: e.message,
        canvas: "conversation"
      }, status: 500
    end
  end

  # Approve or reject a workflow
  def approve_workflow
    task_session_id = params[:task_session_id]
    approved = params[:approved]

    begin
      task_session = TaskSession.find(task_session_id)

      if approved
        # Start the workflow
        interactive_service = InteractiveTaskService.new(current_user, current_entity, session[:scout_session_id])
        result = interactive_service.handle_plan_approval(
          task_session.state["workflow_spec"],
          approved: true
        )

        render json: { success: true, message: "Workflow approved and started" }
      else
        # Cancel the workflow
        task_session.update!(
          status: "cancelled",
          state: task_session.state.merge("cancelled_at" => Time.current)
        )

        render json: { success: true, message: "Workflow cancelled" }
      end
    rescue ActiveRecord::RecordNotFound
      render json: { success: false, error: "Task session not found" }, status: 404
    rescue => e
      Rails.logger.error "Workflow approval error: #{e.message}"
      render json: { success: false, error: e.message }, status: 500
    end
  end

  def approve_plan
    plan_id = params[:plan_id]
    auto_execute = params[:auto_execute] == true || params[:auto_execute] == 'true'

    begin
      plan = ExecutionPlan.find_by!(id: plan_id, entity: current_entity)

      # Approve the plan
      plan.update!(
        approved: true,
        approved_at: Time.current,
        status: 'ready'
      )

      # Add to execution log
      plan.add_log_entry('plan_approved', 'Plan approved by user')

      if auto_execute
        # Start execution immediately
        plan.update!(status: 'executing', started_at: Time.current)
        plan.add_log_entry('execution_started', 'Execution started after approval')
        
        # Queue the executor job
        PlanExecutorJob.perform_later(plan.id, { start_execution: true })
        
        render json: { 
          success: true, 
          message: "Plan approved and execution started",
          plan_id: plan.id,
          status: 'executing'
        }
      else
        render json: { 
          success: true, 
          message: "Plan approved. Ready to execute.",
          plan_id: plan.id,
          status: 'ready'
        }
      end
    rescue ActiveRecord::RecordNotFound
      render json: { success: false, error: "Plan not found" }, status: 404
    rescue => e
      Rails.logger.error "Plan approval error: #{e.message}"
      render json: { success: false, error: e.message }, status: 500
    end
  end

  # Set thinking depth mode (auto, quick, standard, deep)
  # Also supports legacy modes (fast, balanced, powerful) for backwards compatibility
  def set_model_mode
    mode = params[:mode]&.to_sym
    
    # Map legacy modes to new thinking depth modes
    mode = case mode
           when :fast, :quick then :light
           when :balanced, :standard then :medium
           when :powerful, :maximum then :deep
           else mode
           end
    
    valid_modes = %i[auto light medium deep]

    unless valid_modes.include?(mode)
      render json: { success: false, error: "Invalid mode. Valid: #{valid_modes.join(', ')}" }, status: 400
      return
    end

    # Store in session
    session[:model_mode] = mode

    # Get thinking depth info for the selected mode
    depth_service = ThinkingDepthService.new
    depth_info = depth_service.config_for(mode == :auto ? :medium : mode)

    render json: {
      success: true,
      mode: mode,
      description: depth_info[:description],
      thinking_depth: mode == :auto ? 'auto-selected' : mode.to_s
    }
  end

  # Get current thinking depth mode and available levels
  def get_model_mode
    current_mode = session[:model_mode]&.to_sym || :auto
    
    # Map legacy modes to new thinking depth modes
    current_mode = case current_mode
                   when :fast then :quick
                   when :balanced then :standard
                   when :powerful then :deep
                   else current_mode
                   end
    
    depth_service = ThinkingDepthService.new

    render json: {
      success: true,
      current_mode: current_mode,
      available_tiers: depth_service.available_depths.map { |d|
        {
          key: d[:key],
          level: d[:level],
          description: d[:description],
          auto_eligible: d[:auto_eligible]
        }
      }
    }
  end

  # Handle file uploads from chat
  def upload_files
    Rails.logger.info "Scout upload_files called"
    Rails.logger.info "Params: #{params.inspect}"
    Rails.logger.info "Files param: #{params[:files].inspect}"
    
    uploaded_urls = []
    storage_type = params[:storage_type] || 'long-term'
    Rails.logger.info "Storage type: #{storage_type}"

    if params[:files].present?
      params[:files].each do |index, file|
        Rails.logger.info "Processing file #{index}: #{file.inspect}"
        
        if file.is_a?(ActionDispatch::Http::UploadedFile)
          Rails.logger.info "File: #{file.original_filename}, Type: #{file.content_type}, Size: #{file.size}"
          
          # Route based on file type and storage preference
          if storage_type == 'short-term'
            # Temporary upload - store with a short expiry
            Rails.logger.info "Handling as temporary upload"
            uploaded_urls << handle_temporary_upload(file)
          else
            # Long-term storage - route to appropriate system
            if image_file?(file)
              Rails.logger.info "Handling as image upload"
              uploaded_urls << handle_image_upload(file)
            else
              Rails.logger.info "Handling as document upload"
              uploaded_urls << handle_document_upload(file)
            end
          end
        else
          Rails.logger.error "File is not an UploadedFile: #{file.class.name}"
        end
      end
    else
      Rails.logger.warn "No files present in params"
    end

    Rails.logger.info "Upload complete, URLs: #{uploaded_urls.inspect}"
    render json: { success: true, urls: uploaded_urls }
  rescue => e
    Rails.logger.error "File upload error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    render json: { success: false, error: e.message, details: e.backtrace.first(5) }, status: 500
  end

  def continue_workflow
    @session_id = session[:scout_session_id] ||= SecureRandom.uuid

    # Convert ActionController::Parameters to regular hash
    user_inputs = if params[:inputs].is_a?(ActionController::Parameters)
      params[:inputs].to_unsafe_h
    else
      params[:inputs] || {}
    end

    Rails.logger.info "Scout continue workflow - Session: #{@session_id}, Inputs: #{user_inputs.keys}"

    begin
      # Initialize interactive task service
      interactive_service = InteractiveTaskService.new(current_user, current_entity, @session_id)

      # Continue the workflow
      result = interactive_service.continue_workflow(user_inputs)

      # Save any assistant response
      if result[:message]
        save_scout_message("assistant", result[:message])
      end

      render json: {
        success: result[:success],
        message: result[:message],
        canvas: result[:canvas],
        canvas_data: result[:canvas_data],
        workflow_completed: result[:workflow_completed],
        step_completed: result[:step_completed]
      }

    rescue => e
      Rails.logger.error "Scout continue workflow error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      render json: {
        success: false,
        message: "I encountered an error continuing the workflow. Please try again.",
        error: e.message,
        canvas: "conversation"
      }, status: 500
    end
  end

  def chat_stream
    # For API requests, use provided session_id or generate UUID per user
    # For web requests, use Rails session
    if api_request?
      @session_id = params[:session_id] || "mobile_#{current_user.id}_#{Date.current.strftime('%Y%m%d')}"
    else
      @session_id = session[:scout_session_id] ||= SecureRandom.uuid
    end
    user_message = params[:message]&.strip
    current_canvas = params[:current_canvas]
    context = params[:context]
    file_urls = params[:file_urls] || []
    selected_model = params[:model] # Get the selected model from frontend

    Rails.logger.info "Scout streaming chat - Session: #{@session_id}, User: #{current_user.id}, Message: #{user_message}"
    Rails.logger.info "Selected model: #{selected_model}" if selected_model
    Rails.logger.info "Current canvas context: #{current_canvas.inspect}" if current_canvas
    
    # Log specific landing page details if on landing page editor
    if current_canvas && current_canvas["type"] == "landing_page_editor"
      landing_page_id = current_canvas["data"] && current_canvas["data"]["landing_page_id"]
      Rails.logger.info "🎯 Landing Page Editor Canvas - ID: #{landing_page_id}"
      Rails.logger.info "🎯 Canvas Data Details: #{current_canvas["data"].inspect}"
    end
    
    Rails.logger.info "Chat context: #{context.inspect}" if context
    Rails.logger.info "File URLs: #{file_urls.inspect}" if file_urls.any?

    if user_message.blank?
      render json: { error: "Message cannot be empty" }, status: 400
      return
    end

    # Set streaming headers
    response.headers["Content-Type"] = "text/event-stream; charset=utf-8"
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
    response.headers["Connection"] = "keep-alive"
    response.headers["X-Accel-Buffering"] = "no" # Prevent nginx buffering
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["X-Content-Type-Options"] = "nosniff"
    # Don't set Transfer-Encoding manually - Rails handles this automatically with ActionController::Live

    # Force the headers to be sent immediately
    response.status = 200

    begin
      # Start keep-alive thread to prevent timeout during long operations
      start_keepalive_thread
      
      # ===== NEW AMOS INTEGRATION =====
      # Initialize Amos orchestrator
      @orchestrator = initialize_amos_orchestrator
      
      # Set up real-time streaming from Amos
      setup_amos_streaming
      
      # Process message through Amos
      process_through_amos(user_message, file_urls, current_canvas, selected_model)
      
      # ===== END AMOS INTEGRATION =====
      
      return # Early return - Amos handles everything

      # Build enhanced message if files are attached
      enhanced_message = user_message
      metadata = {}

      if file_urls.any?
        Rails.logger.info "🔍 Scout file_urls: #{file_urls.inspect}"
        # Include asset_id so AMOS can use read_document tool
        file_details = file_urls.map do |f|
          # Support both asset_id and document_id for backward compatibility
          id = f['asset_id'] || f['document_id']
          asset_type = f['asset_type'] || 'image' # Default to image for backward compatibility
          "📎 #{f['filename']} (asset_id: #{id}, asset_type: #{asset_type}, type: #{f['content_type']})"
        end.join(", ")

        enhanced_message = "#{user_message}\n\n[Attached Files: #{file_details}]\n\nIMPORTANT: Use the read_document tool with the asset_id AND asset_type to extract content from these files before responding."
        metadata[:file_urls] = file_urls
      end

      # Save user message with file info
      save_scout_message("user", enhanced_message, metadata: metadata)
      stream_update("📚 Loading conversation history...")

      # Get conversation history (last 20 messages for active window)
      conversation_history = persisted_history_last_k(20)
      stream_update("📚 Loading conversation history (#{conversation_history.length} messages)")

      # Track sources used in tool responses
      sources_used = {}
      interactive_service = nil  # Will be initialized based on processing type

      # Define progress callback that will be used if we create InteractiveTaskService
      progress_callback = lambda do |progress_data|
        # Handle both string and hash formats
        if progress_data.is_a?(String)
          # Simple string message
          stream_update(progress_data)
        elsif progress_data.is_a?(Hash)
          # Structured progress data
          case progress_data[:type]
          when "content_chunk"
            # Stream content chunks directly
            stream_content_chunk(progress_data[:content])
          when "intermediate_message", "save_message"
            # Save and stream intermediate messages
            if progress_data[:content]
              save_scout_message(progress_data[:role] || "assistant", progress_data[:content])
              stream_content_chunk(progress_data[:content])
            end
          when 'phase_progress', 'phase_start'
            # Show workflow phase progress as VISIBLE messages (not transient)
            phase_message = "🔄 #{progress_data[:message]}"
            Rails.logger.info "Phase progress: #{phase_message}"
            save_scout_message('assistant', phase_message)
            stream_update({
              type: 'intermediate_message',
              content: phase_message,
              role: 'assistant'
            })
          when 'phase_complete'
            # Show phase completion as VISIBLE messages
            complete_message = "✅ #{progress_data[:message]}"
            Rails.logger.info "Phase complete: #{complete_message}"
            save_scout_message('assistant', complete_message)
            stream_update({
              type: 'intermediate_message',
              content: complete_message,
              role: 'assistant'
            })
          when 'tool_start'
            # Show tool start as VISIBLE message with thinking indicator
            tool_name = progress_data[:tool_name] || progress_data[:name]
            tool_message = "🔧 #{get_friendly_tool_name(tool_name)}..."
            Rails.logger.info "Tool start: #{tool_message}"
            save_scout_message('assistant', tool_message)
            stream_update({
              type: 'intermediate_message',
              content: tool_message,
              role: 'assistant'
            })
          when 'tool_complete'
            # Tool complete - just log, don't spam chat
            tool_name = progress_data[:tool_name] || progress_data[:name]
            Rails.logger.info "Tool complete: #{tool_name}"

            # Track source if provided in tool response
            if progress_data[:source]
              source_type = progress_data[:source]
              sources_used[source_type] ||= 0
              sources_used[source_type] += 1
              Rails.logger.info "📊 Source tracked: #{source_type} (total: #{sources_used[source_type]})"
            end
            # Don't show tool complete messages - too noisy
          when 'progress'
            # Progress updates from long-running tools with percentage
            Rails.logger.info "📊 Tool progress: #{progress_data[:tool]} - #{progress_data[:message]} (#{progress_data[:percentage]}%)"
            stream_update({
              type: "progress",
              tool: progress_data[:tool],
              message: progress_data[:message],
              percentage: progress_data[:percentage],
              timestamp: progress_data[:timestamp] || Time.current.to_f
            })
          when 'planner_progress'
            # Stream planner reasoning as transient messages
            Rails.logger.info "Planner: #{progress_data[:message]}"
            stream_transient_update("🧠 #{progress_data[:message]}")
          when "load_canvas"
            # Stream canvas loading
            stream_update(progress_data)
          when "canvas_update"
            # Stream canvas update
            stream_update(progress_data)
          when "workflow_approval_needed"
            # Handle workflow approval request
            task_session_id = progress_data[:task_session_id]
            workflow_spec = progress_data[:workflow_spec]

            # Stream the message and approval UI
            stream_content_chunk(progress_data[:message] || "I've created a workflow plan for your request. Please review:")

            # Load the approval canvas
            stream_update({
              type: "load_canvas",
              canvas: "task_progress",
              canvas_data: {
                task_session_id: task_session_id,
                awaiting_approval: true,
                workflow_spec: workflow_spec
              }
            })
          when :step_completed, "step_completed"
            # Stream step completion and trigger canvas refresh
            stream_update({
              type: "step_completed",
              step_id: progress_data[:step_id],
              step_name: progress_data[:step_name],
              message: "✅ Completed: #{progress_data[:step_name] || progress_data[:step_id]}"
            })
            # Also send a canvas update to refresh the task list
            stream_update({
              type: "canvas_update",
              canvas_type: "task_progress",
              canvas_data: {
                task_session_id: interactive_service.instance_variable_get(:@task_session)&.id
              }
            })
          when :step_failed, "step_failed"
            # Stream step failure and trigger canvas refresh
            stream_update({
              type: "step_failed",
              step_id: progress_data[:step_id],
              step_name: progress_data[:step_name],
              error: progress_data[:error],
              message: "❌ Failed: #{progress_data[:step_name] || progress_data[:step_id]}"
            })
            # Also send a canvas update to refresh the task list
            stream_update({
              type: "canvas_update",
              canvas_type: "task_progress",
              canvas_data: {
                task_session_id: interactive_service.instance_variable_get(:@task_session)&.id
              }
            })
          when "tool_start", "tool_complete"
            # Save and stream tool updates as content
            tool_name = progress_data[:tool_name] || progress_data[:name]
            tool_message = if progress_data[:type] == "tool_start"
              "🔧 Using tool: #{tool_name}"
            else
              "✅ Tool completed: #{tool_name}"
            end
            save_scout_message("assistant", tool_message)
            # Stream as intermediate message so it appears in chat
            stream_update({
              type: "intermediate_message",
              content: tool_message,
              role: "assistant"
            })
          when "canvas_update"
            # CRITICAL: Stream canvas updates for freeform_canvas and others
            # The frontend expects type: "canvas_update" with canvas_type and canvas_data
            Rails.logger.info "🎨 Streaming canvas_update: #{progress_data[:canvas_type]}"
            stream_update({
              type: "canvas_update",
              canvas_type: progress_data[:canvas_type],
              canvas_data: progress_data[:canvas_data] || {}
            })
          else
            # Default progress message
            stream_update("🔄 #{progress_data[:message] || progress_data.to_s}")
          end
        else
          # Fallback for other types
          stream_update("🔄 #{progress_data}")
        end
      end

      # Check if we should use context (keeping legacy support for now)
      if false  # Disabled context setting for now
        # No context loading needed for InteractiveTaskService
      end

      # Check if this is a plan approval response
      if current_canvas&.dig("data", "awaiting_approval") && is_approval_response?(user_message)
        stream_update("📋 Processing your plan feedback...")
        approval_action = extract_approval_action(user_message)
        
        # Initialize service for plan approval if not already done
        interactive_service ||= InteractiveTaskService.new(current_user, current_entity, session[:scout_session_id], model: selected_model)
        interactive_service.on_progress(&progress_callback)
        
        result = interactive_service.handle_plan_approval(approval_action, user_message)
      else
        # Check if we should use parallel processing
        if should_use_parallel_processing?(user_message, file_urls)
          stream_update("🚀 **Activating parallel processing** to handle your multi-part request efficiently...")
          
          # Use ParallelTaskOrchestrator instead
          orchestrator = ParallelTaskOrchestrator.new(current_user, current_entity, @session_id)
          
          # Create tasks from the request
          tasks = orchestrator.process_request(user_message, {
            voice_mode: false,
            current_canvas: current_canvas,
            recent_history: conversation_history,
            file_urls: file_urls
          })
          
          # Stream the parallel execution start
          stream_update({
            type: 'parallel_execution_start',
            execution_id: SecureRandom.uuid,
            task_count: tasks.length,
            tasks: tasks.map { |t| 
              {
                id: t.id,
                type: t.task_type,
                description: t.metadata['description']
              }
            }
          })
          
          # Load the parallel tasks canvas
          stream_update({
            type: 'load_canvas',
            canvas: 'parallel_tasks',
            canvas_data: {
              session_id: @session_id,
              tasks: tasks.map { |t| 
                {
                  id: t.id,
                  type: t.task_type,
                  description: t.metadata['description'],
                  status: t.status,
                  progress: t.progress || 0,
                  dependencies: t.task_dependencies.map { |d|
                    {
                      id: d.id,
                      depends_on_task_id: d.depends_on_task_id,
                      relationship_type: d.relationship_type,
                      dependency_type: d.dependency_type,
                      status: d.status
                    }
                  }
                }
              }
            }
          })
          
          # Don't claim success yet - tasks are just queued
          result = { 
            success: true, 
            message: "I'm processing #{tasks.length} tasks in parallel. You can continue chatting or work on other things while I handle these in the background. Check the parallel tasks panel for real-time progress.",
            mode: "parallel",
            message_already_saved: false,
            canvas_type: 'parallel_tasks',
            canvas_data: {
              session_id: @session_id,
              tasks: tasks.map { |t| 
                {
                  id: t.id,
                  type: t.task_type,
                  description: t.metadata['description'],
                  status: t.status,
                  progress: t.progress || 0,
                  dependencies: t.task_dependencies.map { |d|
                    {
                      id: d.id,
                      depends_on_task_id: d.depends_on_task_id,
                      relationship_type: d.relationship_type,
                      dependency_type: d.dependency_type,
                      status: d.status
                    }
                  }
                }
              }
            }
          }
          
          # Immediately enable chat for continued conversation
          stream_update({
            type: 'enable_chat',
            message: 'Feel free to ask other questions while I work on these tasks!'
          })
        else
          # Process message using InteractiveTaskService
          stream_update("🧠 Analyzing your request...")
          stream_update("📋 Detecting task mode and preparing workflow...")
          
          # Initialize InteractiveTaskService for sequential processing
          interactive_service = InteractiveTaskService.new(current_user, current_entity, session[:scout_session_id], model: selected_model)
          interactive_service.on_progress(&progress_callback)
          
          # Add file URLs to context if present
          if file_urls.any?
            interactive_service.set_context(attached_files: file_urls)
          end

          result = interactive_service.process_message(user_message, conversation_history, current_canvas)
        end
      end

      # Handle the response from InteractiveTaskService
      if result[:success]
        # Save assistant response (only if not already streamed)
        if result[:mode] != "autonomous" && result[:message] && !result[:message_already_saved]
          save_scout_message("assistant", result[:message])
          stream_content_chunk(result[:message])
        end

        # Handle canvas loading (if not already done during streaming)
        canvas = result[:canvas_type] || result[:canvas]
        if canvas && canvas != "conversation" && result[:mode] != "autonomous" && result[:mode] != "parallel"
          stream_update({
            type: "load_canvas",
            canvas: canvas,
            canvas_data: result[:canvas_data] || {}
          })
        end

        # Return the response
        final_response = {
          message: result[:message],
          message_already_saved: result[:message_already_saved] || false,
          canvas_type: result[:canvas_type] || result[:canvas] || "conversation",
          canvas_data: result[:canvas_data] || {},
          tools_used: result[:tools_used] || [],
          success_count: (result[:tools_used].is_a?(Array) ? result[:tools_used].count : 0),
          error_count: 0
        }

        # Add source attribution from tools_used (e.g., read_document)
        extracted_sources = extract_response_sources(final_response[:tools_used])
        if extracted_sources.any?
          final_response[:sources] = extracted_sources
          Rails.logger.info "📚 Extracted sources from tools: #{final_response[:sources]}"
        elsif sources_used.any?
          # Fallback to event-tracked sources if no tools sources found
          final_response[:sources] = sources_used.map { |source, count| { type: source, count: count } }
          Rails.logger.info "📊 Response included sources from events: #{final_response[:sources]}"
        end

        # Check if workflow approval is needed
        if result[:workflow_approval_needed]
          final_response[:workflow_approval] = {
            task_session_id: result[:task_session_id],
            workflow_spec: result[:workflow_spec]
          }
        end
        
        # Check if parallel tasks were created (workflow executed as parallel task)
        if result[:parallel_tasks]
          Rails.logger.info "🚀 Workflow queued as parallel task"
          
          # Stream the parallel execution start
          stream_update({
            type: 'parallel_execution_start',
            execution_id: SecureRandom.uuid,
            task_count: result[:parallel_tasks].length,
            tasks: result[:parallel_tasks].map { |t| 
              {
                id: t.id,
                type: t.task_type,
                description: t.metadata['description']
              }
            }
          })
          
          # Load the parallel tasks canvas
          stream_update({
            type: 'load_canvas',
            canvas: 'parallel_tasks',
            canvas_data: {
              session_id: @session_id,
              tasks: result[:parallel_tasks]
            }
          })
          
          # Enable the chat for continued conversation
          stream_update({
            type: 'enable_chat'
          })
          
          # Monitor the parallel tasks
          monitor_parallel_tasks(result[:parallel_tasks])
        end
      else
        # Handle error case
        error_message = result[:error] || "An error occurred while processing your request."
        stream_update("❌ Error: #{error_message}")
        stream_content_chunk(error_message)

        final_response = {
          message: error_message,
          canvas_type: "conversation",
          canvas_data: {},
          tools_used: [],
          success_count: 0,
          error_count: 1
        }

        # Add source attribution even in error case
        if sources_used.any?
          final_response[:sources] = sources_used.map { |source, count| { type: source, count: count } }
        end
      end

      # Stream final response and close
      stream_final_response(final_response)

    rescue AmosErrors::BedrockThrottlingError, AmosErrors::BedrockUnavailableError => e
      Rails.logger.error "Scout streaming Bedrock error: #{e.class.name} - #{e.message}"
      stream_event("error", {
        message: e.user_message,
        retry_after: e.retry_after,
        error_type: e.class.name.demodulize
      })
    rescue AmosErrors::BedrockTimeoutError => e
      Rails.logger.error "Scout streaming timeout: #{e.message}"
      stream_event("error", {
        message: e.user_message,
        retry_after: e.retry_after
      })
    rescue AmosErrors::IntegrationError => e
      Rails.logger.error "Scout streaming integration error: #{e.integration_name} - #{e.message}"
      stream_event("error", {
        message: e.user_message,
        integration: e.integration_name,
        action: "Please check your #{e.integration_name} connection in Settings > Integrations."
      })
    rescue IOError, Errno::EPIPE, Errno::ECONNRESET => e
      # Client disconnected - this is normal, not an error
      Rails.logger.info "Client disconnected during chat stream: #{e.message}"

      # Check if a landing page was created successfully before disconnection
      # This helps users know their request completed even if streaming failed
      if @workflow_engine&.workflow_execution&.status == "completed"
        Rails.logger.info "Workflow completed successfully before client disconnect"
        
        # Store a notification for the user about the successful completion
        # This will be shown when they next access the interface
        if @workflow_engine.workflow_execution.workflow_spec&.dig('name')&.downcase&.include?('landing page')
          Rails.logger.info "Landing page workflow completed successfully"
          # The landing page was created - user can access it through the normal interface
        end
      end
    rescue StandardError => e
      Rails.logger.error "Scout streaming chat error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      fallback_message = case e.message
      when /timeout/i
        "I'm taking longer than expected to respond. Please try again in a moment."
      when /network/i, /connection/i
        "I'm having trouble connecting right now. Please try again."
      else
        "I encountered an unexpected error. Please try rephrasing your request."
      end

      stream_update("❌ Error occurred")
      stream_final_response({
        message: fallback_message,
        error: true,
        tools_used: false
      })
    ensure
      # Stop keep-alive thread
      stop_keepalive_thread
      
      response.stream.close
    end
  end

  # Template/Canvas Actions for Intelligent Canvas
  # Get task statuses for refresh
  def task_statuses
    task_ids = params[:task_ids] || []
    
    tasks = TaskSession.where(id: task_ids, user: current_user)
                       .includes(:task_dependencies)
    
    render json: {
      tasks: tasks.map do |task|
        {
          id: task.id,
          task_type: task.task_type,
          status: task.status,
          progress: task.progress,
          metadata: task.metadata
        }
      end
    }
  end
  
  def load_canvas
    canvas_type = params[:canvas_type]
    # Ensure canvas_data is a proper hash with indifferent access for ERB templates
    raw_canvas_data = params[:canvas_data] || {}
    canvas_data = if raw_canvas_data.respond_to?(:to_unsafe_h)
                    raw_canvas_data.to_unsafe_h.with_indifferent_access
                  elsif raw_canvas_data.is_a?(Hash)
                    raw_canvas_data.with_indifferent_access
                  else
                    {}.with_indifferent_access
                  end

    # If canvas_type is nil or empty, don't change the canvas
    if canvas_type.blank?
      Rails.logger.info "Scout: Canvas type is blank, keeping current canvas"
      render json: { success: false, error: "Canvas type not specified" }, status: :bad_request
      return
    end

    begin
      Rails.logger.info "Scout: Loading canvas - Type: #{canvas_type}, Data: #{canvas_data}"

      case canvas_type
      when "landing_page_viewer"
        canvas_content = render_landing_page_canvas(canvas_data)
        canvas_title = "Landing Page Viewer"
      when "landing_page_details"
        canvas_content = render_landing_page_details(canvas_data)
        canvas_title = "Landing Page Details"
      when "landing_page_generator"
        canvas_content = render_landing_page_generator(canvas_data)
        canvas_title = "Landing Page Generator"
      when "landing_page_editor"
        canvas_content = render_landing_page_editor(canvas_data)
        canvas_title = "Edit Landing Page"
      when "landing_page_versions"
        canvas_content = render_landing_page_versions(canvas_data)
        canvas_title = "Version History"
      when "interactive_wizard"
        canvas_content = render_interactive_wizard(canvas_data)
        canvas_title = determine_wizard_title(canvas_data)
      when "form_submissions"
        canvas_content = render_form_submissions_canvas(canvas_data)
        canvas_title = "Form Submissions"
      when "workflow_analytics"
        canvas_content = render_workflow_analytics_canvas(canvas_data)
        canvas_title = "Workflow Analytics"
      when "contact_viewer"
        canvas_content = render_contact_canvas(canvas_data)
        canvas_title = "Contacts"
      when "contact_detail"
        canvas_content = render_contact_detail_canvas(canvas_data)
        canvas_title = "Contact Details"
      when "pipeline_viewer"
        canvas_content = render_pipeline_canvas(canvas_data)
        canvas_title = "Sales Pipeline"
      when "campaign_viewer", "email_campaign_viewer"
        canvas_content = render_campaign_canvas(canvas_data)
        canvas_title = "Email Campaigns"
      when "analytics_dashboard"
        canvas_content = render_analytics_canvas(canvas_data)
        canvas_title = "Analytics Dashboard"
      when 'document_viewer'
        canvas_content = render_document_viewer_canvas(canvas_data)
        canvas_title = "Document Viewer"
      when 'image_viewer'
        canvas_content = render_image_viewer_canvas(canvas_data)
        canvas_title = canvas_data[:title] || canvas_data["title"] || "Generated Image"
      when 'document_search_results'
        canvas_content = render_document_search_results_canvas(canvas_data)
        canvas_title = "Document Search Results"
      when 'contact_generator'
        canvas_content = render_contact_generator(canvas_data)
        canvas_title = "Create Contact"
      when "user_profile"
        canvas_content = render_user_profile_canvas(canvas_data)
        canvas_title = "My Profile"
      when "business_profile"
        canvas_content = render_business_profile_canvas(canvas_data)
        canvas_title = "Business Settings"
      when "email_template_viewer"
        canvas_content = render_email_template_viewer(canvas_data)
        canvas_title = "Email Templates"
      when "email_template_editor"
        canvas_content = render_email_template_editor(canvas_data)
        canvas_title = "Edit Email Template"
      when "dynamic_canvas"
        canvas_content = render_dynamic_canvas(canvas_data)
        canvas_title = canvas_data["title"] || "Custom Analysis"
      when "freeform_canvas"
        canvas_content = render_freeform_canvas(canvas_data)
        canvas_title = canvas_data["title"] || "Custom Visualization"
      when "web_page_viewer"
        canvas_content = render_web_page_viewer(canvas_data)
        url = canvas_data["url"] || canvas_data[:url]
        domain = begin
          URI.parse(url).host
        rescue
          "Web Page"
        end
        canvas_title = canvas_data["title"] || domain || "Web Page"
      when "browser_session"
        canvas_content = render_to_string(
          partial: "scout/canvas/browser_session",
          locals: { canvas_data: canvas_data },
          formats: [:html]
        )
        url = canvas_data["url"] || canvas_data[:url]
        domain = begin
          URI.parse(url).host if url.present?
        rescue
          nil
        end
        canvas_title = domain || "Browser Session"
      when "task_progress"
        canvas_content = render_task_progress(canvas_data)
        canvas_title = "Task Progress"
      when "operations_command_center", "operations_dashboard"
        canvas_content = render_to_string(
          partial: "scout/canvas/operations_dashboard",
          locals: { canvas_data: canvas_data },
          formats: [:html]
        )
        canvas_title = "Operations Command Center"
      when "design_studio"
        canvas_content = render_to_string(
          partial: "scout/canvas/design_studio",
          locals: { canvas_data: canvas_data },
          formats: [:html]
        )
        canvas_title = "Design Studio"
      when "media_library"
        canvas_content = render_to_string(
          partial: "scout/canvas/media_library",
          locals: { canvas_data: canvas_data, entity: current_entity },
          formats: [:html]
        )
        canvas_title = "Media Library"
      when "my_creations"
        canvas_content = render_to_string(
          partial: "scout/canvas/my_creations",
          locals: { canvas_data: canvas_data, entity: current_entity },
          formats: [:html]
        )
        canvas_title = "Created Assets"
      when "template_library"
        canvas_content = render_to_string(
          partial: "scout/canvas/template_library",
          locals: { canvas_data: canvas_data },
          formats: [:html]
        )
        canvas_title = "Template Library"
      when "workflow_designer"
        canvas_content = render_to_string(
          partial: "scout/canvas/workflow_designer",
          locals: { canvas_data: canvas_data },
          formats: [:html]
        )
        canvas_title = "Workflow Designer"
      when "favorites"
        canvas_content = render_to_string(
          partial: "scout/canvas/favorites",
          locals: { canvas_data: canvas_data },
          formats: [:html]
        )
        canvas_title = "Favorites"
      when "work_inbox"
        canvas_content = render_to_string(
          partial: "scout/canvas/work_inbox",
          locals: { canvas_data: canvas_data },
          formats: [:html]
        )
        canvas_title = "Work Inbox"
      when "scheduled_tasks"
        canvas_content = render_to_string(
          partial: "scout/canvas/scheduled_tasks",
          formats: [:html],
          locals: { canvas_data: canvas_data }
        )
        canvas_title = "Tasks"
      when "scheduled_task_editor"
        canvas_content = render_to_string(
          partial: "scout/canvas/scheduled_task_editor",
          locals: { canvas_data: canvas_data },
          formats: [:html]
        )
        task_id = canvas_data&.dig('task_id') || canvas_data&.dig(:task_id)
        if task_id
          task = ScheduledAgentTask.find_by(id: task_id)
          canvas_title = "Edit: #{task&.name || 'Task'}"
        else
          canvas_title = "New Scheduled Task"
        end
      when "saved_visualizations"
        canvas_content = render_to_string(
          partial: "scout/canvas/saved_visualizations",
          locals: { canvas_data: canvas_data },
          formats: [:html]
        )
        canvas_title = "Saved Visualizations"
      when "campaign_editor"
        canvas_content = render_campaign_editor(canvas_data)
        canvas_title = "Campaign Editor"
      when "integrations_manager"
        # Always fetch integrations data for this canvas
        integrations = Integration.includes(oauth_configurations: :auth_configs).where(is_active: true).order(:name)
        # Show connections for the current user only (user credentials = user privacy)
        connections = current_user.connections.where(entity: current_entity).includes(:integration)

        canvas_data[:integrations] = integrations.map do |integration|
          oauth_config = integration.oauth_configurations.first
          auth_configs = oauth_config&.auth_configs&.order(:position) || []
          
          {
            id: integration.id,
            name: integration.name,
            slug: integration.slug,
            description: integration.description,
            category: integration.category,
            auth_type: integration.auth_type,
            icon_url: integration.icon_url,
            is_verified: integration.is_verified,
            operations_count: integration.integration_operations.count,
            is_connected: connections.any? { |c| c.integration_id == integration.id && c.status == "connected" },
            auth_configs: auth_configs.map do |ac|
              {
                auth_key: ac.auth_key,
                auth_value: ac.auth_value,
                auth_placement: ac.auth_placement,
                position: ac.position
              }
            end
          }
        end

        canvas_data[:connections] = connections.map do |connection|
          {
            id: connection.id,
            name: connection.name,
            status: connection.status,
            has_active_credentials: connection.integration_credentials.present?,
            last_used: connection.integration_logs.maximum(:created_at),
            operations_count: connection.integration.integration_operations.count,
            integration: {
              id: connection.integration.id,
              name: connection.integration.name,
              icon_url: connection.integration.icon_url
            }
          }
        end

        canvas_content = render_integrations_manager(canvas_data)
        canvas_title = "Integration Connections"
      when "integration_connect"
        canvas_content = render_integration_connect(canvas_data)
        canvas_title = "Connect Integration"
      when "integration_operations"
        canvas_content = render_integration_operations(canvas_data)
        canvas_title = "Integration Operations"
      when "parallel_tasks"
        @session_id = canvas_data['session_id'] || params[:session_id]
        
        # Load active tasks for the current user (only from last 24 hours to exclude stuck old tasks)
        active_tasks = TaskSession.where(
          user: current_user,
          status: ['active', 'pending', 'queued']
        ).where("created_at > ?", 24.hours.ago)
         .includes(:task_dependencies).order(created_at: :desc).limit(50)
        
        # Also load recently completed tasks (last hour)
        recent_completed = TaskSession.where(
          user: current_user,
          status: 'completed',
          completed_at: 1.hour.ago..Time.current
        ).order(completed_at: :desc).limit(20)
        
        # Load Amos jobs for the current user (most recent 20)
        @amos_jobs = Amos::JobRecord.joins("INNER JOIN scout_messages ON scout_messages.session_id = amos_jobs.session_id")
                                    .where(scout_messages: { user_id: current_user.id })
                                    .where("amos_jobs.created_at > ?", 24.hours.ago)
                                    .distinct
                                    .order(created_at: :desc)
                                    .limit(20)
        
        # Load Agent Plugin Executions (New System)
        agent_executions = AgentPluginExecution.where(user: current_user)
                                             .where("created_at > ?", 24.hours.ago)
                                             .includes(:agent_plugin)
                                             .order(created_at: :desc)
                                             .limit(20)

        # Combine and sort all tasks in descending order (newest first)
        all_tasks = (active_tasks + recent_completed).sort_by { |task| task.created_at }.reverse
        
        # Serialize tasks for the canvas
        tasks_data = all_tasks.map do |task|
          {
            id: task.id,
            type: task.task_type,
            description: task.metadata['description'] || "Task #{task.id}",
            status: task.status,
            progress: task.progress || 0,
            metadata: task.metadata,
            created_at: task.created_at,
            parent_conversation_id: task.parent_conversation_id,
            dependencies: task.task_dependencies.map { |d|
              {
                id: d.id,
                depends_on_task_id: d.depends_on_task_id,
                relationship_type: d.relationship_type,
                dependency_type: d.dependency_type,
                status: d.status
              }
            }
          }
        end
        
        # Add Amos jobs to the task list
        amos_tasks = @amos_jobs.map do |job|
          {
            id: "amos-#{job.job_id}",
            type: job.agent_type,
            description: job.input_data&.dig('task') || job.status_message || "#{job.agent_type.humanize} Job",
            status: job.status,
            progress: job.progress || (job.status == 'completed' ? 100 : 0),
            metadata: {
              job_id: job.job_id,
              agent_type: job.agent_type,
              started_at: job.started_at,
              completed_at: job.completed_at
            },
            created_at: job.created_at,
            parent_conversation_id: job.session_id,
            dependencies: []
          }
        end

        # Add Agent Plugin Executions to the task list
        plugin_tasks = agent_executions.map do |exec|
          {
            id: "#{exec.id}", # Use raw ID to match job_id
            type: exec.agent_plugin.slug,
            description: exec.input_context['task'] || exec.agent_plugin.name,
            status: exec.status,
            progress: exec.status == 'completed' ? 100 : (exec.status == 'running' || exec.status == 'waiting_for_input' ? 50 : 0),
            message: exec.result_data&.dig('message') || exec.status,
            metadata: {
              job_id: exec.id,
              agent_type: exec.agent_plugin.slug,
              agent_name: exec.agent_plugin.name,
              started_at: exec.started_at,
              completed_at: exec.completed_at,
              error: exec.error_message
            },
            created_at: exec.created_at,
            parent_conversation_id: exec.input_context['session_id'],
            dependencies: []
          }
        end
        
        tasks_data += amos_tasks + plugin_tasks
        tasks_data = tasks_data.sort_by { |t| t[:created_at] }.reverse
        
        @canvas_data = canvas_data.merge('tasks' => tasks_data)
        
        Rails.logger.info "ScoutController: Loading parallel tasks canvas with #{active_tasks.count} active tasks"
        
        canvas_content = render_to_string(
          partial: "scout/canvas/parallel_tasks",
          locals: { canvas_data: @canvas_data },
          formats: [:html]
        )
        canvas_title = "Task Monitor"
      when "module_manager"
        # Module Manager - view installed modules (only show modules visible to user)
        @modules = current_entity.app_modules.visible_to(current_user).order(updated_at: :desc)
        canvas_content = render_to_string(
          partial: "scout/canvas/module_manager",
          locals: { canvas_data: canvas_data },
          formats: [:html]
        )
        canvas_title = "Your Apps"
      when /^module_(.+)_automations$/
        # Module Automations - view workflows, scheduled tasks, webhooks for a module
        module_slug = $1
        @app_module = current_entity.app_modules.visible_to(current_user).find_by(slug: module_slug)
        if @app_module
          canvas_content = render_to_string(
            partial: "scout/canvas/module_automations",
            locals: { canvas_data: canvas_data },
            formats: [:html]
          )
          canvas_title = "#{@app_module.name} - Automations"
        else
          canvas_content = render_default_canvas
          canvas_title = "Module Not Found"
        end
      when "support_tickets"
        # Support Tickets - user-facing view of their tickets
        canvas_content = render_support_tickets_canvas(canvas_data)
        canvas_title = "My Support Tickets"
      when "module_marketplace"
        # Apps - unified marketplace for apps and modules
        canvas_content = render_to_string(
          partial: "scout/canvas/module_marketplace",
          locals: { canvas_data: canvas_data },
          formats: [:html]
        )
        canvas_title = "Apps"
      when "app_designer"
        # App Designer - create and manage apps
        canvas_content = render_to_string(
          partial: "scout/canvas/app_designer",
          locals: { canvas_data: canvas_data },
          formats: [:html]
        )
        canvas_title = "App Designer"
      when "execution_dashboard"
        # Execution Dashboard - real-time plan and agent activity
        dashboard_data = load_execution_dashboard_data
        canvas_content = render_to_string(
          partial: "scout/canvas/execution_dashboard",
          locals: dashboard_data,
          formats: [:html]
        )
        canvas_title = "Execution Dashboard"
      when "plan_details"
        # Plan Details - detailed view of a specific plan
        plan_data = load_plan_details_data(canvas_data)
        @plan = plan_data[:plan]  # Set instance variable for the partial
        canvas_content = render_to_string(
          partial: "scout/canvas/plan_details",
          locals: plan_data,
          formats: [:html]
        )
        canvas_title = @plan&.title || "Plan Details"
      when "module_design_preview"
        # Module Design Preview - shows what will be built for user approval
        design_data = load_module_design_data(canvas_data)
        @design = design_data[:design]
        @template_key = design_data[:template_key]
        @plan_id = design_data[:plan_id]
        canvas_content = render_to_string(
          partial: "scout/canvas/module_design_preview",
          locals: design_data,
          formats: [:html]
        )
        canvas_title = "#{@design&.dig(:name) || 'Module'} - Design Preview"
      else
        # Check for module canvases (format: module_<canvas_slug>)
        # The canvas_slug is the full slug from ModuleCanvas (e.g., social_media_calendar_list)
        if canvas_type.start_with?('module_')
          full_canvas_slug = canvas_type.sub('module_', '')
          Rails.logger.info "[ModuleCanvas] 🎨 Loading module canvas: #{full_canvas_slug}"
          module_canvas = load_module_canvas_by_slug(full_canvas_slug)
          if module_canvas
            canvas_content = module_canvas[:content]
            canvas_title = module_canvas[:title]
            Rails.logger.info "[ModuleCanvas] ✅ Loaded canvas '#{canvas_title}', content length: #{canvas_content&.length || 0}"
          else
            canvas_content = render_default_canvas
            canvas_title = "Module Not Found"
            Rails.logger.warn "[ModuleCanvas] ❌ Canvas not found: #{full_canvas_slug}"
          end
        # Dynamic fallback: Check if a partial exists for this canvas type
        # This allows adding new agent views without modifying the controller
        elsif lookup_context.template_exists?("scout/canvas/_#{canvas_type}")
          canvas_content = render_to_string(
            partial: "scout/canvas/#{canvas_type}", 
            locals: { 
              canvas_data: canvas_data,
              user: current_user,
              entity: current_entity
            },
            formats: [:html]
          )
          canvas_title = canvas_type.titleize
        else
          canvas_content = render_default_canvas
          canvas_title = ""
        end
      end

      render json: {
        success: true,
        canvas: {
          type: canvas_type,
          title: canvas_title,
          content: canvas_content,
          data: canvas_data
        }
      }
    rescue => e
      Rails.logger.error "Canvas loading error: #{e.class.name}: #{e.message}"
      Rails.logger.error "Canvas type: #{canvas_type}, Data: #{canvas_data}"
      Rails.logger.error e.backtrace.first(5).join("\n")

      render json: {
        success: false,
        error: "Sorry, I couldn't load that view. Error: #{e.message}"
      }, status: :ok
    end
  end

  def available_canvases
    begin
      # Return available canvas types for Scout
      canvases = [
        {
          type: "landing_page_viewer",
          name: "Landing Pages",
          description: "View and manage landing pages",
          icon: "globe"
        },
        {
          type: "contact_viewer",
          name: "Contacts",
          description: "View and manage contacts",
          icon: "users"
        },
        {
          type: "campaign_viewer",
          name: "Campaigns",
          description: "View and manage email campaigns",
          icon: "mail"
        },
        {
          type: "integrations_manager",
          name: "Integrations",
          description: "Manage external application connections",
          icon: "plug"
        },
        {
          type: "integration_connect",
          name: "Connect Integration",
          description: "Connect to an external service",
          icon: "link"
        },
        {
          type: "analytics_dashboard",
          name: "Analytics",
          description: "Marketing performance dashboard",
          icon: "bar-chart-2"
        },
        {
          type: "agent_marketplace",
          name: "Agent Marketplace",
          description: "Browse and use AI agents from the community",
          icon: "store"
        },
        {
          type: "favorites",
          name: "My Favorites",
          description: "View your favorite agents, tools, and integrations",
          icon: "star"
        },
        {
          type: "work_inbox",
          name: "Work Inbox",
          description: "View agent work items and task results",
          icon: "inbox"
        },
        {
          type: "scheduled_tasks",
          name: "Scheduled Tasks",
          description: "Manage your scheduled agent tasks",
          icon: "calendar"
        },
        {
          type: "pipeline_viewer",
          name: "Sales Pipeline",
          description: "View and manage sales opportunities in a Kanban board",
          icon: "kanban"
        },
        {
          type: "contact_detail",
          name: "Contact Detail",
          description: "View detailed contact information with activities and opportunities",
          icon: "user"
        },
        {
          type: "activities_viewer",
          name: "Activities",
          description: "View and manage CRM activities and tasks",
          icon: "check-square"
        },
        {
          type: "team_channels",
          name: "Team Channels",
          description: "Collaborate with your team and AI agents",
          icon: "message-circle"
        },
        {
          type: "notes",
          name: "Notes",
          description: "Personal notes and ideas",
          icon: "edit-3"
        },
        {
          type: "bookmarks",
          name: "Bookmarks",
          description: "Saved conversations, insights, and context",
          icon: "bookmark"
        },
        {
          type: "reminders",
          name: "Reminders",
          description: "Personal reminders and scheduled tasks",
          icon: "bell"
        },
        {
          type: "channels",
          name: "Channels",
          description: "Team channels for collaboration",
          icon: "hash"
        }
      ]

      # Add data-specific canvases if we have recent data
      if current_entity.landing_pages.recent.limit(1).exists?
        recent_page = current_entity.landing_pages.recent.first
        canvases << {
          type: "landing_page_generator",
          name: recent_page.title || "Recent Landing Page",
          description: "Landing page in progress",
          icon: "edit-2",
          data: { landing_page_id: recent_page.id }
        }
      end

      render json: { canvases: canvases }
    rescue => e
      Rails.logger.error "Available canvases error: #{e.message}"
      render json: { canvases: [] }
    end
  end
  
  def cancel_job
    job_id = params[:job_id]
    
    if job_id.blank?
      render json: { success: false, error: 'Job ID is required' }, status: 400
      return
    end
    
    Rails.logger.info "[Scout] Attempting to cancel job: #{job_id}"
    
    begin
      canceled = false
      
      # 1. Try AgentPluginExecution (New System)
      # Handle potential string IDs "plugin-123"
      clean_id = job_id.to_s.sub(/^plugin-/, '').sub(/^amos-/, '')
      
      if job_id.to_s.start_with?('plugin-') || AgentPluginExecution.exists?(clean_id)
        execution = AgentPluginExecution.find_by(id: clean_id)
        if execution
          # Update status
          execution.update!(
            status: 'cancelled', 
            completed_at: Time.current
          )
          # Manually fail/add error message since mark_failed! sets status to failed
          output = execution.output_result || {}
          output['error'] = 'Task was canceled by user'
          execution.update!(output_result: output)
          
          canceled = true
          
          # Attempt to find and cancel the SolidQueue job
          # The job argument is the execution ID integer
          SolidQueue::Job.where(queue_name: 'agents', finished_at: nil).each do |job|
             if job.arguments.is_a?(Array) && job.arguments.first == execution.id
               Rails.logger.info "[Scout] Canceling SolidQueue job #{job.id} for execution #{execution.id}"
               job.update!(finished_at: Time.current)
               SolidQueue::ReadyExecution.where(job_id: job.id).destroy_all
               SolidQueue::ClaimedExecution.where(job_id: job.id).destroy_all
             end
          end

          # Broadcast status update
          ScoutChannel.broadcast_to(session[:scout_session_id], {
            type: 'task_progress',
            job_id: job_id,
            task_id: job_id,
            status: 'canceled',
            message: 'Task was canceled by user'
          })
        end
      end
      
      # 2. Try Amos::JobRecord (Old System)
      # Only if not already canceled
      unless canceled
        amos_job = Amos::JobRecord.find_by(job_id: clean_id)
        
        if amos_job
          # Update Amos job status
          amos_job.update!(
            status: 'canceled',
            status_message: 'Task was canceled by user',
            completed_at: Time.current,
            error_data: { canceled: true, canceled_at: Time.current }
          )
          canceled = true
          
          # Find and cancel the SolidQueue job
          solid_queue_jobs = SolidQueue::Job
            .where(queue_name: 'agents', finished_at: nil)
            .where("arguments::text LIKE ?", "%#{clean_id}%")
          
          solid_queue_jobs.each do |job|
            Rails.logger.info "[Scout] Canceling SolidQueue job #{job.id}"
            job.update!(finished_at: Time.current)
            SolidQueue::ReadyExecution.where(job_id: job.id).destroy_all
            SolidQueue::ClaimedExecution.where(job_id: job.id).destroy_all
          end

          # Broadcast status update
          ScoutChannel.broadcast_to(session[:scout_session_id], {
            type: 'task_progress',
            job_id: "amos-#{clean_id}",
            task_id: "amos-#{clean_id}",
            status: 'canceled',
            message: 'Task was canceled by user'
          })
        end
      end

      if canceled
        render json: { success: true, job_id: job_id, status: 'canceled' }
      else
        render json: { success: false, error: "Job not found: #{job_id}" }, status: 404
      end
      
    rescue => e
      Rails.logger.error "[Scout] Error canceling job: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      render json: { success: false, error: e.message }, status: 500
    end
  end

  # Capture a web page screenshot and extract text
  # Called directly from the web_page_viewer canvas when iframe embedding fails
  def capture_web_page
    url = params[:url]
    request_id = params[:request_id] || SecureRandom.uuid

    if url.blank?
      render json: { success: false, error: "URL is required" }, status: :bad_request
      return
    end

    begin
      # Enqueue the capture job
      CaptureWebPageJob.perform_later(
        url: url,
        entity_id: current_entity.id,
        user_id: current_user.id,
        task_session_id: session[:scout_session_id],
        canvas_request_id: request_id
      )

      render json: {
        success: true,
        message: "Capture job started",
        request_id: request_id
      }
    rescue => e
      Rails.logger.error "[Scout] Error starting web page capture: #{e.message}"
      render json: { success: false, error: e.message }, status: :internal_server_error
    end
  end

  # Serve the latest browser session screenshot (PNG) from cache.
  # We intentionally avoid embedding base64 screenshots in ActionCable payloads because it:
  # - bloats logs
  # - makes canvases extremely heavy to render
  #
  # Params:
  # - session_id: Scout session id / browser session id
  # - token: random token to prevent easy guessing (optional but recommended)
  def browser_session_screenshot
    session_id = params[:session_id].to_s
    token = params[:token].to_s

    if session_id.blank? || token.blank?
      head :bad_request
      return
    end

    cache_key = "browser_session_screenshot:#{session_id}:#{token}"
    png_bytes = normalize_png_bytes(Rails.cache.read(cache_key))

    if png_bytes.blank?
      head :not_found
      return
    end

    # If the cache contains unexpected content, fail fast (prevents broken <img> + retry loops).
    unless png_bytes.is_a?(String) && png_bytes.bytesize >= 8 && png_bytes.b.start_with?(PNG_MAGIC)
      Rails.logger.warn "[Scout] browser_session_screenshot invalid bytes for #{session_id} (token=#{token} bytesize=#{png_bytes.respond_to?(:bytesize) ? png_bytes.bytesize : 'n/a'})"
      head :unprocessable_entity
      return
    end

    response.headers["Cache-Control"] = "no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    send_data png_bytes.b, type: "image/png", disposition: "inline", filename: "browser_session_#{session_id}.png"
  end

  # Force-capture a fresh screenshot for a browser session and return a new screenshot_url.
  # Useful when a cached token URL 404s (e.g., cache eviction or transient cache issues).
  def browser_session_screenshot_refresh
    session_id = params[:session_id].presence || session[:scout_session_id].to_s

    if session_id.blank?
      render json: { success: false, error: "Missing session_id" }, status: :bad_request
      return
    end

    browser_session = BrowserSessionService.find_or_create(
      user_id: current_user.id,
      session_id: session_id
    )

    png_bytes = browser_session.screenshot(format: :png, full_page: false)
    token = SecureRandom.hex(12)
    Rails.cache.write("browser_session_screenshot:#{session_id}:#{token}", png_bytes, expires_in: 5.minutes)

    render json: {
      success: true,
      screenshot_url: "/scout/browser_session_screenshot/#{session_id}?token=#{token}"
    }
  rescue StandardError => e
    Rails.logger.warn "[Scout] browser_session_screenshot_refresh failed: #{e.class} - #{e.message}"
    render json: { success: false, error: "Failed to capture screenshot" }, status: :internal_server_error
  end

  # Sync cookies from the interactive web proxy session into the automation browser session.
  # This is a "no-AI" endpoint intended to be called from the browser_session canvas UI.
  #
  # Params (JSON):
  # - session_id: browser session id (defaults to session[:scout_session_id])
  # - proxy_session_id: optional; defaults to session_id
  # - proxy_host: required (e.g. "resy.com")
  # - current_url: optional; if present, we refresh after applying cookies
  def browser_session_sync_proxy
    session_id = params[:session_id].presence || session[:scout_session_id].to_s
    proxy_session_id = params[:proxy_session_id].presence || session_id
    proxy_host = params[:proxy_host].to_s.strip
    current_url = params[:current_url].to_s.strip

    Rails.logger.info "[Scout] browser_session_sync_proxy start session_id=#{session_id} proxy_session_id=#{proxy_session_id} proxy_host=#{proxy_host} current_url=#{current_url.to_s.truncate(120)}"

    if session_id.blank? || proxy_host.blank?
      render json: { success: false, error: "Missing session_id or proxy_host" }, status: :bad_request
      return
    end

    cache_key = "web_proxy_cookie_jar:#{proxy_session_id}:#{proxy_host}"
    jar = Rails.cache.read(cache_key)

    Rails.logger.info "[Scout] browser_session_sync_proxy cookie_jar #{cache_key} type=#{jar.class.name} size=#{(jar.is_a?(Hash) ? jar.size : 0)}"

    unless jar.is_a?(Hash) && jar.any?
      render json: { success: false, error: "No proxy cookies found for #{proxy_host}. Make sure you logged in via the interactive view." },
             status: :unprocessable_entity
      return
    end

    browser_session =
      begin
        BrowserSessionService.find_or_create(
          user_id: current_user.id,
          session_id: session_id
        )
      rescue StandardError => e
        Rails.logger.error "[Scout] browser_session_sync_proxy find_or_create failed: #{e.class} - #{e.message}"
        Rails.logger.error e.backtrace.first(10).join("\n")
        render json: { success: false, error: "Failed to start browser session" }, status: :internal_server_error
        return
      end

    target_url = current_url.presence || "https://#{proxy_host}/"
    ok =
      begin
        browser_session.apply_cookie_jar(target_url, jar)
      rescue StandardError => e
        Rails.logger.error "[Scout] browser_session_sync_proxy apply_cookie_jar failed: #{e.class} - #{e.message}"
        Rails.logger.error e.backtrace.first(10).join("\n")
        false
      end

    unless ok
      render json: { success: false, error: "Failed to apply cookies to browser session" }, status: :internal_server_error
      return
    end

    # Persist cookies per-user so future tasks can reuse the logged-in session (best-effort).
    begin
      Rails.cache.write(
        "user_cookie_jar:#{current_user.id}:#{proxy_host}",
        jar,
        expires_in: 7.days
      )
    rescue StandardError => e
      Rails.logger.warn "[Scout] Failed to persist user cookie jar: #{e.message}"
    end

    # Navigate/refresh to let the site pick up the new cookies.
    # If current_url is blank (common when syncing from the interactive viewer canvas),
    # navigate to the host root so the agent session actually transitions to "logged in".
    begin
      browser_session.navigate(target_url)
    rescue StandardError => e
      Rails.logger.warn "[Scout] browser_session_sync_proxy navigate failed: #{e.message}"
    end

    # Broadcast updated browser session canvas (same pattern as ComputerUseTool).
    screenshot_url = nil
    begin
      png_bytes = browser_session.screenshot(format: :png, full_page: false)
      token = SecureRandom.hex(12)
      Rails.cache.write("browser_session_screenshot:#{session_id}:#{token}", png_bytes, expires_in: 5.minutes)
      screenshot_url = "/scout/browser_session_screenshot/#{session_id}?token=#{token}"
    rescue StandardError => e
      Rails.logger.warn "[Scout] browser_session_sync_proxy screenshot failed: #{e.message}"
    end

    url_now = target_url
    title_now = nil
    elements_now = []

    begin
      url_now = browser_session.current_page_url.presence || url_now
    rescue StandardError => e
      Rails.logger.warn "[Scout] browser_session_sync_proxy current_page_url failed: #{e.message}"
    end

    begin
      title_now = browser_session.page_title
    rescue StandardError => e
      Rails.logger.warn "[Scout] browser_session_sync_proxy page_title failed: #{e.message}"
    end

    begin
      elements_now = browser_session.interactive_elements
    rescue StandardError => e
      Rails.logger.warn "[Scout] browser_session_sync_proxy interactive_elements failed: #{e.message}"
    end

    ScoutChannel.broadcast_to(session_id, {
      type: "load_canvas",
      canvas_name: "browser_session",
      canvas_data: {
        session_id: session_id,
        url: url_now,
        title: title_now,
        screenshot_url: screenshot_url,
        action: "sync_proxy_session",
        message: "Synced login session for #{proxy_host}",
        interactive_elements: Array(elements_now).first(15),
        proxy_session_id: proxy_session_id,
        proxy_host: proxy_host,
        status: "active"
      }
    })

    render json: { success: true, cookie_count: jar.size }
  rescue StandardError => e
    Rails.logger.error "[Scout] browser_session_sync_proxy failed: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.first(8).join("\n")
    render json: { success: false, error: "Failed to sync login session" }, status: :internal_server_error
  end

  # Close/cancel the automation browser session (used for "take over" handoff).
  def browser_session_close
    session_id = params[:session_id].presence || session[:scout_session_id].to_s
    if session_id.blank?
      render json: { success: false, error: "Missing session_id" }, status: :bad_request
      return
    end

    BrowserSessionService.close_session(session_id)

    ScoutChannel.broadcast_to(session_id, {
      type: "load_canvas",
      canvas_name: "browser_session",
      canvas_data: {
        session_id: session_id,
        url: nil,
        title: "Browser Session",
        screenshot_url: nil,
        action: "close",
        message: "Agent browser session closed. You are in control now.",
        interactive_elements: [],
        status: "ready"
      }
    })

    render json: { success: true }
  rescue StandardError => e
    Rails.logger.warn "[Scout] browser_session_close failed: #{e.class} - #{e.message}"
    render json: { success: false, error: "Failed to close session" }, status: :internal_server_error
  end

  def clear_conversation
    session_id = session[:scout_session_id]
    if session_id
      # Clear Rails cache
      Rails.cache.delete("scout_conversation_#{session_id}")

      # Invalidate unified memory cache
      if current_user && current_entity
        memory = Scout::UnifiedMemory.new(user: current_user, entity: current_entity)
        memory.invalidate_l1_cache
      end

      session.delete(:scout_session_id)
    end

    render json: { success: true, message: "Conversation cleared" }
  end

  def conversation_export
    @session_id = session[:scout_session_id]
    @conversation_history = scout_conversation_history

    respond_to do |format|
      format.json { render json: @conversation_history }
      format.html # Will render conversation_export.html.erb if you create one
    end
  end

  # GET /scout/history?before_id=<id>&limit=20
  def history
    # Use continuous chat - query by user/entity, not session
    Rails.logger.info "📜 History request - user: #{current_user.id}, entity: #{current_entity&.id}"

    limit = params[:limit].to_i
    limit = 20 if limit <= 0 || limit > 100
    before_id = params[:before_id]

    # Query by user and entity for continuous chat
    scope = ScoutMessage.where(user_id: current_user.id, entity_id: current_entity&.id)
    
    # IMPORTANT: If user did a fresh start, only show messages after that time
    # This prevents old chat history from reloading after clicking "Fresh Start"
    if session[:scout_fresh_start_at].present?
      fresh_start_time = Time.parse(session[:scout_fresh_start_at]) rescue nil
      if fresh_start_time
        scope = scope.where("created_at > ?", fresh_start_time)
        Rails.logger.info "📜 Filtering to messages after fresh start: #{fresh_start_time}"
      end
    end
    
    total_for_user = scope.count
    Rails.logger.info "📜 Total messages for user/entity (after filters): #{total_for_user}"

    if before_id.present?
      # Load messages older than the given id
      before_message = ScoutMessage.find_by(id: before_id)
      scope = scope.where("created_at < ?", before_message.created_at) if before_message
    end

    # Get the most recent N messages, then sort them oldest-first for display
    # Using explicit ORDER BY and LIMIT to avoid .last() inconsistencies
    batch = scope.order(created_at: :desc).limit(limit).to_a.reverse
    Rails.logger.info "📜 Returning #{batch.count} messages (ordered oldest first)"

    render json: {
      messages: batch.map { |m| {
        id: m.id,
        role: m.role,
        content: m.content,
        timestamp: m.created_at.iso8601,
        metadata: m.metadata
      } },
      has_more: total_for_user > limit
    }
  end

  # GET /scout/conversations
  def conversations
    # Get recent conversations for this user
    recent_sessions = ScoutMessage
      .where(user_id: current_user.id)
      .select(:session_id, "MIN(created_at) as created_at", "COUNT(*) as message_count")
      .group(:session_id)
      .order("MIN(created_at) DESC")
      .limit(10)

    # Get first message for each session
    conversations = recent_sessions.map do |session|
      first_message = ScoutMessage
        .where(session_id: session.session_id, role: "user")
        .order(:created_at)
        .first

      {
        session_id: session.session_id,
        created_at: session.created_at,
        message_count: session.message_count,
        first_message: first_message&.content&.truncate(50)
      }
    end

    render json: conversations
  end

  # GET /scout/conversation/:session_id
  def conversation
    session_id = params[:session_id]
    messages = ScoutMessage
      .where(session_id: session_id, user_id: current_user.id)
      .order(:created_at)
      .map { |m| {
        role: m.role,
        content: m.content,
        created_at: m.created_at.iso8601
      } }

    render json: messages
  end

  # POST /scout/new_session (legacy - redirects to fresh_start)
  def new_session
    fresh_start
  end

  # POST /scout/fresh_start
  # Clears active context but preserves all memory
  def fresh_start
    session_id = session[:scout_session_id]
    
    # Clear working context from Redis (but NOT memory)
    if session_id
      begin
        $redis.del("scout:working_context:#{session_id}")
        Rails.logger.info "🔄 Fresh start: cleared working context for session #{session_id}"
      rescue => e
        Rails.logger.warn "Failed to clear Redis context: #{e.message}"
      end
    end
    
    # Clear Rails cache for this session
    Rails.cache.delete("scout_conversation_#{session_id}") if session_id
    
    # Clear L1 memory cache (so old messages don't appear in new session)
    l1_cache_key = "scout:memory:l1:#{current_user.id}:#{current_entity.id}"
    Rails.cache.delete(l1_cache_key)
    Rails.logger.info "🔄 Fresh start: cleared L1 memory cache"
    
    # NOTE: We intentionally DON'T clear TieredDiscoveryService cache here.
    # Discovery cache is prompt-based (same question = same tools needed).
    # It's also space-aware (different spaces have different cache keys).
    # 60-second TTL handles staleness naturally.
    
    # Generate new session ID (for active context tracking, not memory separation)
    session[:scout_session_id] = SecureRandom.uuid
    
    # Track when this fresh start happened - history will only show messages after this
    session[:scout_fresh_start_at] = Time.current.iso8601
    
    Rails.logger.info "🔄 Fresh start at #{session[:scout_fresh_start_at]} - new session: #{session[:scout_session_id]}"
    
    render json: { 
      success: true, 
      session_id: session[:scout_session_id],
      fresh_start_at: session[:scout_fresh_start_at],
      message: "Fresh start! Memory preserved, context cleared."
    }
  end

  # GET /scout/bookmarks
  # Returns user's saved bookmarks
  def bookmarks
    bookmarks = MemoryBookmark
      .where(user_id: current_user.id, entity_id: current_entity.id)
      .order(created_at: :desc)
      .limit(50)
      .map { |bookmark| bookmark.to_api_hash }
    
    render json: bookmarks
  rescue => e
    Rails.logger.error "Failed to load bookmarks: #{e.message}"
    render json: [], status: :ok
  end

  # GET /scout/bookmarks/:id
  # Returns a single bookmark with full content
  def show_bookmark
    bookmark = MemoryBookmark.find_by(
      id: params[:id],
      user_id: current_user.id,
      entity_id: current_entity.id
    )
    
    return render json: { error: "Bookmark not found" }, status: :not_found unless bookmark
    
    render json: {
      id: bookmark.id,
      title: bookmark.title,
      description: bookmark.description,
      content: bookmark.content_data,  # Use content_data to ensure proper hash
      content_type: bookmark.content_type,
      icon: bookmark.icon,
      context_messages: bookmark.context_messages,
      shareable: bookmark.shareable,
      share_url: bookmark.shareable ? "/shared/#{bookmark.share_token}" : nil,
      created_at: bookmark.created_at
    }
  rescue => e
    Rails.logger.error "Failed to load bookmark: #{e.message}"
    render json: { error: "Failed to load bookmark" }, status: :internal_server_error
  end

  # POST /scout/save_visualization
  # Saves a visualization/canvas directly with its HTML content
  def save_visualization
    title = params[:title]
    content_type = params[:content_type] || 'visualization'
    content = params[:content] || {}
    description = params[:description]
    
    return render json: { success: false, error: "Title is required" }, status: :bad_request if title.blank?
    return render json: { success: false, error: "Content is required" }, status: :bad_request if content.blank?
    
    begin
      bookmark = MemoryBookmark.create!(
        user: current_user,
        entity: current_entity,
        title: title,
        description: description,
        content_type: content_type,
        bookmark_type: 'saved',
        source: 'canvas',
        content: content.is_a?(ActionController::Parameters) ? content.to_unsafe_h : content,
        tags: ['visualization', 'dashboard']
      )
      
      Rails.logger.info "💾 Saved visualization bookmark ##{bookmark.id}: #{title}"
      
      render json: {
        success: true,
        bookmark_id: bookmark.id,
        title: bookmark.title,
        message: "Visualization saved successfully"
      }
    rescue => e
      Rails.logger.error "Failed to save visualization: #{e.message}"
      render json: { success: false, error: e.message }, status: :internal_server_error
    end
  end

  # GET /scout/document-status/:asset_id
  # API endpoint to check document indexing status
  def document_indexing_status
    asset_id = params[:asset_id]
    asset_type = params[:asset_type]
    return render json: { error: "asset_id required" }, status: :bad_request if asset_id.blank?

    # Check asset_type to look in correct table first
    if asset_type == 'document'
      # Look for RagDocument first
      rag_document = RagDocument.joins(:rag_store)
                               .where(rag_stores: { entity_id: current_entity.id })
                               .where(id: asset_id)
                               .first
      
      if rag_document
        return render json: calculate_rag_document_status(rag_document)
      end
      
      # Fallback to ImageAsset
      asset = current_entity.image_assets.find_by(id: asset_id)
    else
      # Look for ImageAsset first
      asset = current_entity.image_assets.find_by(id: asset_id)
      
      if !asset
        # Fallback to RagDocument
        rag_document = RagDocument.joins(:rag_store)
                                 .where(rag_stores: { entity_id: current_entity.id })
                                 .where(id: asset_id)
                                 .first
        
        if rag_document
          return render json: calculate_rag_document_status(rag_document)
        end
      end
    end
    
    return render json: { error: "Document not found" }, status: :not_found unless asset

    status = calculate_document_status(asset)
    render json: status
  end
  
  # Calculate status for RagDocument (uploaded documents/PDFs)
  def calculate_rag_document_status(rag_document)
    status = rag_document.processing_status
    chunk_count = rag_document.rag_chunks.count rescue 0
    
    case status
    when 'indexed', 'completed'
      {
        status: 'complete',
        stage: 4,
        total_stages: 4,
        message: 'Document ready for chat',
        ready_for_chat: true,
        processing_status: status,
        chunk_count: chunk_count,
        progress_percent: 100
      }
    when 'embedding', 'generating_embeddings'
      {
        status: 'embedding',
        stage: 4,
        total_stages: 4,
        message: 'Generating embeddings...',
        ready_for_chat: false,
        processing_status: status,
        chunk_count: chunk_count,
        progress_percent: 80
      }
    when 'chunking', 'chunked'
      {
        status: 'chunking',
        stage: 3,
        total_stages: 4,
        message: 'Splitting document into chunks...',
        ready_for_chat: false,
        processing_status: status,
        chunk_count: chunk_count,
        progress_percent: 60
      }
    when 'extracting', 'extracted'
      {
        status: 'extracting',
        stage: 2,
        total_stages: 4,
        message: 'Extracting text content...',
        ready_for_chat: false,
        processing_status: status,
        progress_percent: 40
      }
    when 'processing', 'uploaded'
      {
        status: 'processing',
        stage: 1,
        total_stages: 4,
        message: 'Processing document...',
        ready_for_chat: false,
        processing_status: status,
        progress_percent: 20
      }
    when 'failed', 'error'
      {
        status: 'failed',
        stage: 0,
        total_stages: 4,
        message: 'Document processing failed',
        ready_for_chat: false,
        processing_status: status,
        progress_percent: 0
      }
    else
      {
        status: 'pending',
        stage: 0,
        total_stages: 4,
        message: 'Preparing document...',
        ready_for_chat: false,
        processing_status: status || 'unknown',
        progress_percent: 10
      }
    end
  end

  # Save workflow from designer (auto-save)
  def save_workflow
    workflow_id = params[:workflow_id]
    # Use to_unsafe_h to permit all nested params for workflow_data (it's arbitrary JSON structure)
    workflow_data = params[:workflow_data].to_unsafe_h
    workflow_name = params[:workflow_name].presence || "Untitled Workflow"
    
    # Find or create the automation
    if workflow_id.present?
      automation = AutomationCode.find_by(id: workflow_id, entity: current_entity)
    end
    
    if automation
      # Update existing workflow
      Rails.logger.info "📝 Updating existing workflow #{automation.id}"
      automation.workflow_definition = workflow_data
      Rails.logger.info "📝 New workflow_definition: #{automation.workflow_definition.inspect[0..200]}"
    else
      # Create new workflow with required fields
      slug = workflow_name.parameterize.presence || "workflow-#{Time.current.to_i}"
      # Ensure unique slug
      base_slug = slug
      counter = 1
      while AutomationCode.exists?(entity: current_entity, slug: slug)
        slug = "#{base_slug}-#{counter}"
        counter += 1
      end
      
      automation = AutomationCode.new(
        entity: current_entity,
        created_by: current_user,
        name: workflow_name,
        slug: slug,
        description: "Created from workflow designer",
        trigger_type: 'manual',  # Default trigger type, can be updated from workflow
        status: 'draft',
        code: '# Workflow code will be generated from the visual definition',
        workflow_definition: workflow_data
      )
    end
    
    Rails.logger.info "📝 Attempting to save workflow, changes: #{automation.changes.keys}"
    
    if automation.save
      Rails.logger.info "✅ Workflow saved successfully: id=#{automation.id}"
      render json: { 
        success: true, 
        workflow_id: automation.id,
        message: 'Workflow saved'
      }
    else
      Rails.logger.error "❌ Failed to save workflow: #{automation.errors.full_messages.join(', ')}"
      render json: { 
        success: false, 
        error: automation.errors.full_messages.join(', ')
      }, status: :unprocessable_entity
    end
  rescue => e
    Rails.logger.error "Failed to save workflow: #{e.message}"
    render json: { success: false, error: e.message }, status: :internal_server_error
  end

  # Load a saved workflow for editing
  def load_workflow
    workflow_id = params[:workflow_id]
    
    automation = AutomationCode.find_by(id: workflow_id, entity: current_entity)
    
    if automation
      # Parse workflow_definition if it's a string
      workflow_def = automation.workflow_definition
      workflow_def = JSON.parse(workflow_def) if workflow_def.is_a?(String) rescue {}
      
      render json: {
        success: true,
        id: automation.id,
        name: automation.name,
        workflow_definition: workflow_def,
        status: automation.status
      }
    else
      render json: { success: false, error: 'Workflow not found' }, status: :not_found
    end
  rescue => e
    Rails.logger.error "Failed to load workflow: #{e.message}"
    render json: { success: false, error: e.message }, status: :internal_server_error
  end

  # Fetch items for workflow designer dropdowns
  def workflow_items
    item_type = params[:type]
    
    Rails.logger.info "🔧 Fetching workflow items: type=#{item_type}, entity=#{current_entity&.id}"
    
    items = case item_type
    when 'landing_page'
      # Include draft and published landing pages (exclude archived)
      pages = LandingPage.where(entity_id: current_entity&.id)
                         .where.not(status: 'archived')
                         .order(updated_at: :desc)
                         .limit(50)
      Rails.logger.info "🔧 Found #{pages.count} landing pages"
      pages.map { |lp| { id: lp.id, name: lp.name.presence || lp.title.presence || "Landing Page ##{lp.id}", status: lp.status } }
    when 'contact_form'
      # Contact forms from app modules (exclude disabled/failed)
      forms = AppModule.where(entity_id: current_entity&.id)
                       .where("module_type ILIKE '%form%' OR name ILIKE '%form%' OR name ILIKE '%contact%'")
                       .where.not(status: %w[disabled failed])
                       .order(updated_at: :desc)
                       .limit(50)
      Rails.logger.info "🔧 Found #{forms.count} contact forms"
      forms.map { |m| { id: m.id, name: m.name || "Form ##{m.id}" } }
    when 'app_module'
      # App modules (exclude disabled/failed)
      modules = AppModule.where(entity_id: current_entity&.id)
                         .where.not(status: %w[disabled failed])
                         .order(updated_at: :desc)
                         .limit(50)
      Rails.logger.info "🔧 Found #{modules.count} app modules"
      modules.map { |m| { id: m.id, name: m.name || "Module ##{m.id}" } }
    when 'email_template'
      templates = EmailTemplate.where(entity_id: current_entity&.id)
                               .order(updated_at: :desc)
                               .limit(50)
      Rails.logger.info "🔧 Found #{templates.count} email templates"
      templates.map { |t| { id: t.id, name: t.name.presence || t.subject.presence || "Template ##{t.id}", subject: t.subject } }
    else
      []
    end
    
    render json: { items: items }
  rescue => e
    Rails.logger.error "Failed to fetch workflow items: #{e.message}"
    render json: { items: [], error: e.message }
  end

  private

  # Load Hub data for Team Space view
  def load_hub_data
    # Load channels - create default 'general' channel if none exist
    @hub_channels = TeamChannel.where(entity_id: current_entity.id)
                               .order(:name)
                               .limit(20)
    
    if @hub_channels.empty?
      # Create default general channel for the team
      general = TeamChannel.create(
        entity_id: current_entity.id,
        name: 'general',
        description: 'General discussion for the team',
        channel_type: 'public',
        created_by_id: current_user.id
      )
      @hub_channels = [general] if general.persisted?
    end
    
    # Load team members (other users in this entity, excluding current user)
    @hub_team_members = current_entity.entity_users
                                      .joins(:user)
                                      .includes(:user)
                                      .where.not(user_id: current_user.id)
                                      .order('users.first_name ASC NULLS LAST, users.last_name ASC NULLS LAST')
                                      .limit(50)
    
    Rails.logger.info "🌐 Hub: Found #{@hub_team_members.count} team members for entity #{current_entity.id}"
    
    # Find or create DM with Amos (main agent)
    amos_agent = AgentPlugin.find_by(slug: 'amos', entity_id: current_entity.id) ||
                 AgentPlugin.find_by(slug: 'amos')
    
    if amos_agent
      @amos_dm_thread = HubThread.find_or_create_dm(
        entity: current_entity,
        participants: [current_user, amos_agent]
      )
    end
    
    # Load recent DMs
    @hub_dms = HubThread.where(entity_id: current_entity.id, thread_type: 'dm')
                        .joins(:hub_participants)
                        .where(hub_participants: { participant: current_user })
                        .distinct
                        .order(last_activity_at: :desc)
                        .limit(10)
    
    # Load all available agents: entity-specific + system-wide (entity_id: nil)
    # Status 'active' or 'probation' means available to use
    # In team space, show ALL agents (team is where you interact with everyone)
    current_space_slug = @current_space&.slug || 'team'
    @hub_agents = AgentPlugin.where(entity_id: [current_entity.id, nil])
                             .where(status: %w[active probation testing])
                             .for_space(current_space_slug)
                             .includes(:hub_presence)
                             .order(name: :asc)
                             .limit(20)
    
    Rails.logger.info "🌐 Hub: Found #{@hub_agents.count} agents for space '#{current_space_slug}'"
    
    # Load pending responses (threads with unread messages for the current user)
    @hub_pending_responses = HubThread.where(entity_id: current_entity.id)
                                      .joins(:hub_participants)
                                      .where(hub_participants: { participant: current_user })
                                      .where('hub_participants.unread_count > 0')
                                      .distinct
                                      .order(last_activity_at: :desc)
                                      .limit(10)
    
    # Count active agents
    @active_agent_count = HubPresence.where(entity_id: current_entity.id)
                                     .where(participant_type: 'AgentPlugin')
                                     .where(status: ['working', 'thinking'])
                                     .count
    
    # Load any pending notifications
    @hub_notifications = Hub::NotificationQueueService.new(user: current_user, entity: current_entity).queue(limit: 5)
  rescue => e
    Rails.logger.error "❌ Error loading Hub data: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    @hub_channels ||= []
    @hub_dms ||= []
    @hub_agents ||= []
    @hub_team_members ||= []
    @hub_pending_responses ||= []
    @active_agent_count ||= 0
    @hub_notifications ||= []
  end

  PNG_MAGIC = "\x89PNG\r\n\x1A\n".b

  # Some environments still end up caching base64 screenshots (or strings with the wrong encoding).
  # Normalize anything we read from cache to raw PNG bytes (ASCII-8BIT) before sending to <img>.
  def normalize_png_bytes(data)
    return nil if data.nil?
    return data if data.is_a?(String) && data.bytesize >= 8 && data.b.start_with?(PNG_MAGIC)
    return data unless data.is_a?(String)

    begin
      decoded = Base64.decode64(data).b
      return decoded if decoded.bytesize >= 8 && decoded.start_with?(PNG_MAGIC)
    rescue StandardError
      # ignore
    end

    data.b
  end

  # Support both Devise session auth (web) and Bearer token auth (mobile API)
  def authenticate_user_or_api!
    token = request.headers["Authorization"]&.gsub(/^Bearer /, "")

    if token.present?
      # Mobile API request with Bearer token
      @current_user = User.find_by(api_key: token)
      unless @current_user
        if request.format.json? || api_request?
          render json: { error: "Invalid token" }, status: :unauthorized
        else
          redirect_to new_user_session_path
        end
        return
      end
    else
      # Web request - use Devise session auth
      authenticate_user!
    end
  end

  # Check if this is an API request (Bearer token present)
  def api_request?
    request.headers["Authorization"]&.start_with?("Bearer ")
  end

  def is_approval_response?(message)
    approval_patterns = [
      /\b(approve|yes|go ahead|proceed|execute|looks good|lgtm)\b/i,
      /\b(modify|change|update|edit|adjust)\b/i,
      /\b(cancel|stop|no|abort|reject)\b/i
    ]

    approval_patterns.any? { |pattern| message.match?(pattern) }
  end

  def extract_approval_action(message)
    case message.downcase
    when /approve|yes|go ahead|proceed|execute|looks good|lgtm/
      "approve"
    when /modify|change|update|edit|adjust/
      "modify"
    when /cancel|stop|no|abort|reject/
      "cancel"
    else
      # Default to modify if unclear
      "modify"
    end
  end

  def stream_content_chunk(content)
    # Stream individual content chunks for real-time display
    data = JSON.generate({ type: "content", content: content })
    chunk = "data: #{data}\n\n"

    response.stream.write(chunk)

    # Try to flush
    begin
      response.stream.flush if response.stream.respond_to?(:flush)
    rescue
      # Ignore flush errors
    end
  rescue IOError, Errno::EPIPE, Errno::ECONNRESET => e
    # Client disconnected - this is normal, not an error
    Rails.logger.info "Client disconnected during content streaming: #{e.message}"
  rescue => e
    Rails.logger.error "Stream content chunk error: #{e.message}"
  end

  def stream_update(message)
    # Create the SSE (Server-Sent Events) format
    # Handle both string and hash data
    data = if message.is_a?(Hash)
      JSON.generate(message.merge(type: message[:type] || "update"))
    else
      JSON.generate({ type: "update", message: message })
    end
    chunk = "data: #{data}\n\n"

    response.stream.write(chunk)
    
    # Force flush to ensure immediate delivery
    begin
      response.stream.flush if response.stream.respond_to?(:flush)
    rescue => e
      # Ignore flush errors - client might have disconnected
      Rails.logger.debug "Flush failed (normal if client disconnected): #{e.message}"
    end
  rescue IOError, Errno::EPIPE, Errno::ECONNRESET => e
    # Client disconnected - this is normal, not an error
    Rails.logger.info "Client disconnected during streaming: #{e.message}"
  rescue => e
    Rails.logger.error "Stream update failed: #{e.message}"
  end

  def stream_transient_update(message)
    # Create transient messages for progress/tool updates
    data = JSON.generate({
      type: "transient",
      message: message,
      timestamp: Time.current.to_f
    })
    chunk = "data: #{data}\n\n"

    # Write and try to force immediate sending
    response.stream.write(chunk)

    # Try multiple methods to flush
    begin
      response.stream.flush if response.stream.respond_to?(:flush)
    rescue
      # Ignore flush errors
    end

    # Force Rails to send the response chunk immediately
    begin
      if defined?(ActionController::Live) && response.stream.is_a?(ActionController::Live::SSE)
        response.stream.instance_variable_get(:@stream).flush rescue nil
      end
    rescue
      # Ignore if this doesn't work
    end

    Rails.logger.info "Streamed update: #{message.to_s.lines.first&.strip.to_s[0..80]}..."

  rescue => e
    Rails.logger.error "Stream update error: #{e.message}"
  end

  def get_friendly_tool_name(tool_name)
    friendly_names = {
      'generate_ai_landing_page' => 'Generating landing page',
      'execute_integration' => 'Calling integration API',
      'get_data' => 'Fetching data',
      'create_object' => 'Creating record',
      'update_object' => 'Updating record',
      'create_rag_store' => 'Building knowledge base',
      'web_search' => 'Searching the web',
      'query_rag_store' => 'Querying documentation',
      'add_integration_endpoint' => 'Adding API endpoint',
      'generate_integration_scaffold' => 'Creating integration',
      'list_operations' => 'Listing available operations',
      'list_connections' => 'Checking connections',
      'aggregate_artifact_data' => 'Aggregating data',
      'create_dynamic_visualization' => 'Creating visualization'
    }
    friendly_names[tool_name] || tool_name.titleize
  end


  def stream_final_response(response_data)
    Rails.logger.info "🌊 stream_final_response called with data keys: #{response_data.keys}"
    Rails.logger.info "📝 Message length: #{response_data[:message]&.length} characters"
    Rails.logger.info "📝 Message preview: #{response_data[:message]&.first(100)}..."
    Rails.logger.info "📝 Message already saved: #{response_data[:message_already_saved]}"

    # Persist final assistant message as a safety net if not already saved
    if response_data[:message].present? && !response_data[:message_already_saved]
      begin
        save_scout_message("assistant", response_data[:message])
      rescue => e
        Rails.logger.warn "Final message save skipped/failed: #{e.message}"
      end
    end

    # Create the final SSE response
    data = JSON.generate({ type: "response", data: response_data })
    chunk = "data: #{data}\n\n"

    # Write and try to force immediate sending
    response.stream.write(chunk)

    # Try to flush
    begin
      response.stream.flush if response.stream.respond_to?(:flush)
    rescue
      # Ignore flush errors
    end

    Rails.logger.info "Streamed final response"

  rescue IOError, Errno::EPIPE, Errno::ECONNRESET => e
    # Client disconnected - this is normal, not an error
    Rails.logger.info "Client disconnected during final response: #{e.message}"
  rescue => e
    Rails.logger.error "Stream final response error: #{e.message}"
  end

  def check_active_job_status(response_data)
    Rails.logger.info "🔍 Checking active job status for response data: #{response_data.keys}"

    # Only check for job status if the response includes canvas data with landing_page_id
    unless response_data[:canvas_data]&.dig(:landing_page_id)
      Rails.logger.info "❌ No canvas_data or landing_page_id found"
      return nil
    end

    landing_page_id = response_data[:canvas_data][:landing_page_id]
    job_status_key = "job_status_#{current_user.id}_#{landing_page_id}"

    Rails.logger.info "🔍 Looking for job status with key: #{job_status_key}"

    # Get job status from cache
    job_status = Rails.cache.read(job_status_key)

    if job_status
      Rails.logger.info "📊 Found job status for LP #{landing_page_id}: #{job_status[:type]} (#{job_status[:status]})"

      # Don't clear processing status, only clear completed/failed status
      if job_status[:status].in?([ "completed", "failed" ])
        Rails.cache.delete(job_status_key)
        Rails.logger.info "🗑️ Cleared consumed job status from cache"
      else
        Rails.logger.info "⏳ Keeping processing job status in cache for future checks"
      end

      return job_status
    else
      Rails.logger.info "❌ No job status found in cache for key: #{job_status_key}"
    end

    nil
  end

  def send_job_started_status_if_exists(response_data)
    # Only check if there's a landing page job
    return unless response_data[:canvas_data]&.dig(:landing_page_id)

    landing_page_id = response_data[:canvas_data][:landing_page_id]
    job_status_key = "job_status_#{current_user.id}_#{landing_page_id}"

    # Get job status from cache
    job_status = Rails.cache.read(job_status_key)

    if job_status && job_status[:status] == "processing"
      Rails.logger.info "📡 Sending job_started status via SSE: #{job_status[:type]}"

      # Send job status through SSE
      job_data = JSON.generate({ type: "job_status", data: job_status })
      job_chunk = "data: #{job_data}\n\n"
      response.stream.write(job_chunk)
      response.stream.flush if response.stream.respond_to?(:flush)
    else
      Rails.logger.info "❌ No processing job status found to send"
    end
  end

  def monitor_parallel_tasks(tasks)
    Rails.logger.info "👀 Monitoring #{tasks.length} parallel tasks"
    
    # Stream initial task status
    tasks.each do |task|
      stream_update({
        type: 'task_progress',
        task_id: task.id,
        task_type: task.task_type,
        description: task.metadata['description'],
        status: 'queued',
        progress: 0,
        timestamp: Time.current.iso8601
      })
    end
    
    # The actual monitoring happens via ActionCable in TaskExecutionJob
    # This method just sets up the initial state
  end

  def current_entity
    @current_entity ||= current_user.entity
  end

  def ensure_entity_exists
    unless current_entity
      redirect_to new_entity_path, alert: "You need to set up your business profile first."
    end
  end

  def ensure_onboarded
    unless current_user.onboarded?
      redirect_to onboarding_path, notice: "Let's finish setting up your profile first."
    end
  end

  def scout_conversation_history
    session_id = session[:scout_session_id]
    return [] unless session_id

    Rails.cache.fetch("scout_conversation_#{session_id}", expires_in: 2.hours) || []
  end

  # Ensure the current session belongs to the current user
  # If there are messages from another user in this session, reset the session
  def ensure_user_owns_session!
    session_id = session[:scout_session_id]
    return unless session_id
    
    # Check if there are any messages in this session from a DIFFERENT user
    other_user_messages = ScoutMessage.where(session_id: session_id)
                                       .where.not(user_id: current_user.id)
                                       .exists?
    
    if other_user_messages
      Rails.logger.warn "⚠️ Session #{session_id} has messages from another user, generating new session for user #{current_user.id}"
      # Generate a new session ID for this user
      session[:scout_session_id] = SecureRandom.uuid
      # Clear the cache for the old session (for this user's perspective)
      Rails.cache.delete("scout_conversation_#{session_id}")
    end
  end

  # DB-backed persistent history, paged
  # Uses continuous chat - queries by user/entity, not session
  def persisted_history_last_k(k = 10)
    return [] unless current_user && current_entity
    
    # Query by user and entity for continuous chat
    ScoutMessage.where(user_id: current_user.id, entity_id: current_entity.id)
                .oldest_first
                .last(k)
                .map do |m|
      {
        role: m.role,
        content: m.content,
        timestamp: m.created_at.iso8601,
        metadata: m.metadata
      }
    end
  end

  def save_scout_message(role, message, metadata: {})
    # Require user and entity for continuous chat
    return unless current_user && current_entity

    # Don't save empty messages
    return if message.blank?

    # Validate role to prevent incorrect assignments
    unless %w[user assistant system].include?(role.to_s)
      Rails.logger.error "❌ Invalid role '#{role}' for message, defaulting to 'assistant'"
      role = "assistant"
    end

    # Check for potential duplicate user messages being saved as assistant
    if role == "assistant" && message.to_s.strip.length < 50
      recent_user_msg = ScoutMessage.where(
        user_id: current_user.id,
        entity_id: current_entity.id,
        role: "user",
        content: message
      ).where("created_at > ?", 10.seconds.ago).first

      if recent_user_msg
        Rails.logger.warn "⚠️ Skipping potential duplicate: identical user message found within 10 seconds"
        return
      end
    end

    # Log what we're about to save
    Rails.logger.info "💾 Saving #{role} message (#{message.class}): #{message.to_s.first(200)}..."

    # Use unified memory system for persistence + caching (continuous chat)
      memory = Scout::UnifiedMemory.new(user: current_user, entity: current_entity)
      memory.store_message(
        role: role,
        content: message,
        metadata: metadata
      )

    # Mirror the last 50 in cache for fast UI render (keyed by user/entity)
    cache_key = "scout_conversation_#{current_user.id}_#{current_entity.id}"
    conversation = persisted_history_last_k(50)
    Rails.cache.write(cache_key, conversation, expires_in: 12.hours)
    
    # Trigger proactive memory fetch for next response (only for user messages)
    # Use unified session key for continuous chat
    unified_session_key = "unified_#{current_user.id}_#{current_entity.id}_#{Date.current}"
    
    if role == 'user' && message.present?
      trigger_proactive_memory_fetch(unified_session_key, message)
    end
    
    # Trigger insight extraction periodically (every 10 messages)
    trigger_insight_extraction_if_needed(unified_session_key)
    
    # Trigger conversation summarization for long conversations
    trigger_summarization_if_needed(unified_session_key)
  end
  
  # Trigger conversation summarization for long chats
  def trigger_summarization_if_needed(session_id)
    return unless current_user && current_entity
    
    # Check if summarization is needed (threshold: 30 messages, window: 15)
    return unless ConversationSummary.needs_summarization?(
      session_id: session_id,
      threshold: 30,
      window_size: 15
    )
    
    # Debounce: only run if not recently run
    cache_key = "conversation_summary:#{session_id}"
    return if Rails.cache.exist?(cache_key)
    
    # Mark as running (expires in 10 minutes)
    Rails.cache.write(cache_key, true, expires_in: 10.minutes)
    
    # Queue the summarization job
    SummarizeConversationJob.perform_later(
      session_id,
      current_user.id,
      current_entity.id
    )
    
    Rails.logger.info "📚 Queued conversation summarization for session #{session_id}"
  rescue => e
    Rails.logger.warn "Failed to trigger summarization: #{e.message}"
    # Don't let this break message saving
  end
  
  # Trigger insight extraction job if enough new messages
  def trigger_insight_extraction_if_needed(session_id)
    return unless current_user && current_entity
    
    # Check message count
    message_count = ScoutMessage.where(session_id: session_id).count
    
    # Run extraction every 10 messages
    if message_count > 0 && (message_count % 10).zero?
      # Debounce: only run if not recently run
      cache_key = "insight_extraction:#{session_id}"
      return if Rails.cache.exist?(cache_key)
      
      # Mark as running (expires in 5 minutes)
      Rails.cache.write(cache_key, true, expires_in: 5.minutes)
      
      # Queue the extraction job
      ExtractConversationInsightsJob.perform_later(
        session_id,
        current_user.id,
        current_entity.id
      )
      
      Rails.logger.info "🧠 Queued insight extraction for session #{session_id} (#{message_count} messages)"
    end
  rescue => e
    Rails.logger.warn "Failed to trigger insight extraction: #{e.message}"
    # Don't let this break message saving
  end
  
  # Trigger proactive memory fetch for a user message
  # This runs in the background to pre-warm relevant memories for the next response
  def trigger_proactive_memory_fetch(session_id, message)
    return unless current_user && current_entity
    return unless message.present? && message.length > 10
    
    # Debounce: only run if not recently run for this session
    cache_key = "proactive_memory_trigger:#{session_id}"
    return if Rails.cache.exist?(cache_key)
    
    # Mark as triggered (expires in 30 seconds - just enough for one response cycle)
    Rails.cache.write(cache_key, true, expires_in: 30.seconds)
    
    # Queue the proactive memory job
    ProactiveMemoryJob.perform_later(
      current_user.id,
      current_entity.id,
      session_id,
      message
    )
    
    Rails.logger.debug "🧠 Triggered proactive memory fetch for message: #{message.truncate(50)}"
  rescue => e
    Rails.logger.debug "Failed to trigger proactive memory: #{e.message}"
    # Non-critical, don't break the flow
  end

  def create_welcome_message
    business_name = current_entity&.name || "your business"
    profile = current_user.business_profile
    entity = current_entity
    current_space_slug = @current_space&.slug || current_user.space_preference&.active_space || 'work'

    # Build subscription info if available
    subscription_info = ""
    if entity.subscription_status.present? && entity.plan_tier.present?
      plan_name = entity.plan_tier.titleize
      token_limit = entity.token_limit || 200_000
      token_limit_formatted = number_to_human(token_limit, format: '%n%u', units: { thousand: 'K', million: 'M' })

      if entity.subscription_status == 'trialing' && entity.trial_ends_at
        trial_days_left = ((entity.trial_ends_at - Time.current) / 1.day).ceil
        subscription_info = "\n\n You're on the **#{plan_name}** plan (#{token_limit_formatted} AI tokens/month). " \
                           "Your trial has #{trial_days_left} days remaining."
      elsif entity.subscription_status == 'active'
        subscription_info = "\n\n You're on the **#{plan_name}** plan with #{token_limit_formatted} AI tokens/month."
      end
    end

    # Build RAG store info (only show if there are actual knowledge bases)
    rag_info = build_rag_info

    # Different welcome messages based on space
    welcome_message = case current_space_slug
    when 'personal'
      "Welcome! I'm Amos, your personal AI assistant. " \
      "I can help you organize notes, set reminders, manage bookmarks, track tasks, and answer questions. " \
      "What can I help you with today?#{subscription_info}#{rag_info}"
    when 'team'
      "Welcome to the Team space! I'm Amos, and this is your hub for collaborating with AI agents. " \
      "Browse the agent marketplace, delegate tasks, and coordinate work across your team. " \
      "What would you like to accomplish?#{subscription_info}#{rag_info}"
    else
      # Work space (default)
      # Use sign_in_count to determine if returning user (> 1 means they've logged in before)
      is_returning_user = current_user.sign_in_count > 1

      if is_returning_user && profile&.industry.present?
        "Welcome back! I'm AMOS, your AI business partner. " \
        "I can help you analyze your #{profile.industry.downcase} business performance, " \
        "manage operations, automate workflows, handle integrations, create marketing materials, " \
        "and build custom apps to extend the platform. What would you like to explore today?#{subscription_info}#{rag_info}"
      elsif is_returning_user
        "Welcome back! I'm AMOS, your AI business partner. " \
        "I can help analyze your business performance, automate operations, manage data integrations, " \
        "create marketing materials, and build custom apps to extend the platform. " \
        "What would you like to explore today?#{subscription_info}#{rag_info}"
      else
        "Welcome to AMOS! I'm your AI business partner. " \
        "I can help analyze your business performance, automate operations, manage data integrations, " \
        "create marketing materials, and build custom apps to extend the platform. " \
        "What can I help you with today?#{subscription_info}#{rag_info}"
      end
    end

    save_scout_message("assistant", welcome_message)
  end

  def build_rag_info
    # RAG info is not shown in welcome message anymore
    # The system handles RAG stores internally without displaying to user
    # Users can check Admin > Services page for RAG system status
    ""
  end

  # Canvas rendering methods
  def render_landing_page_canvas(data = {})
    landing_pages = current_entity.landing_pages.recent.limit(20)

    render_to_string(
      partial: "scout/canvas/landing_page_viewer",
      locals: {
        landing_pages: landing_pages,
        entity: current_entity,
        user: current_user,
        canvas_data: data
      },
      formats: [:html]
    )
  end

  def render_landing_page_details(data = {})
    landing_page_id = data["landing_page_id"] || data[:landing_page_id]

    if landing_page_id.present?
      begin
        landing_page = current_entity.landing_pages.find(landing_page_id)
      rescue ActiveRecord::RecordNotFound
        # Fallback to most recent landing page if ID not found
        landing_page = current_entity.landing_pages.recent.first
      end
    else
      # Fallback to most recent landing page if no ID provided
      landing_page = current_entity.landing_pages.recent.first
    end

    # If no landing pages exist, return a helpful message
    if landing_page.nil?
      return render_to_string(
        inline: "<div class='text-center py-5'><h5>No Landing Pages Found</h5><p>Create your first landing page to get started.</p><button class='btn btn-primary' onclick='window.scoutCreateLandingPage()'>Create Landing Page</button></div>",
        formats: [:html]
      )
    end

    render_to_string(
      partial: "scout/canvas/landing_page_details",
      locals: {
        landing_page: landing_page,
        entity: current_entity,
        user: current_user,
        canvas_data: data
      },
      formats: [:html]
    )
  end

  def render_landing_page_generator(data = {})
    # Legacy method - now redirects to interactive workflow
    # The old generator canvas is deprecated in favor of interactive task workflow
    <<~HTML
      <div class="alert alert-info text-center p-4">
        <h5><i data-lucide="info" style="display: inline-block; width: 1.25rem; height: 1.25rem; margin-right: 0.5rem;"></i>Landing Page Creation Updated</h5>
        <p class="mb-3">Landing page creation now uses our improved interactive workflow.</p>
        <button class="btn btn-primary" onclick="window.scoutSendMessage?.('Create a landing page')">
          <i data-lucide="plus" style="display: inline-block; width: 1.25rem; height: 1.25rem; margin-right: 0.5rem;"></i>Start Creating Landing Page
        </button>
      </div>
      <script>
        if (typeof lucide !== 'undefined') {
          lucide.createIcons();
        }
      </script>
    HTML
  end

  def render_landing_page_editor(data = {})
    if data["landing_page_id"]
      landing_page = current_entity.landing_pages.find_by(id: data["landing_page_id"])
    end
    
    # Fallback: try to find the most recently created landing page for this user/entity if execution_id is present
    if landing_page.nil? && data["execution_id"]
      # Assuming the execution just finished and created a page
      landing_page = current_entity.landing_pages.order(created_at: :desc).first
    end
    
    # If still not found (e.g. first ever page), raise or handle gracefully
    if landing_page.nil?
      # Return an error view or a placeholder - just go to dashboard
      return render_default_canvas
    end

    render_to_string(
      partial: "scout/canvas/landing_page_editor",
      locals: {
        landing_page: landing_page,
        entity: current_entity,
        user: current_user
      },
      formats: [:html]
    )
  end

  def render_landing_page_versions(data = {})
    landing_page = nil
    
    if data["landing_page_id"]
      landing_page = current_entity.landing_pages.find_by(id: data["landing_page_id"])
    end
    
    if landing_page.nil?
      return render_default_canvas
    end

    render_to_string(
      partial: "scout/canvas/landing_page_versions",
      locals: {
        landing_page: landing_page,
        entity: current_entity,
        user: current_user
      },
      formats: [:html]
    )
  end

  def render_contact_canvas(data = {})
    contacts = current_entity.contacts.includes(:contact_groups).order(created_at: :desc).limit(50)

    # Get summary stats
    stats = {
      total_contacts: current_entity.contacts.count,
      recent_contacts: current_entity.contacts.where("created_at > ?", 7.days.ago).count,
      contact_groups: current_entity.contact_groups.count
    }

    render_to_string(
      partial: "scout/canvas/contact_viewer",
      locals: {
        contacts: contacts,
        stats: stats,
        entity: current_entity,
        user: current_user,
        canvas_data: data
      },
      formats: [:html]
    )
  end

  def render_contact_detail_canvas(data = {})
    contact_id = data[:contact_id] || data["contact_id"]
    contact = current_entity.contacts.find_by(id: contact_id)

    return render_contact_canvas(data) unless contact

    # Get contact's opportunities
    opportunities = contact.opportunities.includes(:user, :assigned_agent).ordered_by_position

    # Get contact's activities (most recent first)
    activities = contact.activities
                        .includes(:user, :performed_by_agent, :opportunity)
                        .order(created_at: :desc)
                        .limit(50)

    render_to_string(
      partial: "scout/canvas/contact_detail",
      locals: {
        contact: contact,
        opportunities: opportunities,
        activities: activities,
        entity: current_entity,
        user: current_user,
        canvas_data: data
      },
      formats: [:html]
    )
  end

  def render_support_tickets_canvas(data = {})
    # Get user's tickets grouped by status
    user_tickets = current_entity.support_tickets
                                 .where(user: current_user)
                                 .order(created_at: :desc)

    tickets = {
      open: user_tickets.where(status: 'open'),
      in_progress: user_tickets.where(status: %w[investigating debugging fixing testing pr_submitted]),
      resolved: user_tickets.where(status: %w[resolved closed]).limit(10),
      feature_requests: user_tickets.where(category: 'feature_request')
    }

    render_to_string(
      partial: "scout/canvas/support_tickets",
      locals: { 
        tickets: tickets,
        canvas_data: data
      },
      formats: [:html]
    )
  end

  def render_pipeline_canvas(data = {})
    # Get pipeline stats
    stats = Opportunity.pipeline_stats(current_entity)

    # Get opportunities grouped by stage
    opportunities = current_entity.opportunities
                                  .includes(:contact, :user, :assigned_agent)
                                  .ordered_by_position

    # Build pipeline hash with opportunities
    pipeline = Opportunity::STAGES.keys.each_with_object({}) do |stage, hash|
      stage_opps = opportunities.select { |o| o.stage == stage }
      hash[stage] = {
        info: Opportunity::STAGES[stage],
        opportunities: stage_opps.map do |o|
          {
            id: o.id,
            name: o.name,
            value: o.value,
            probability: o.probability,
            expected_close_date: o.expected_close_date,
            days_in_stage: o.days_in_stage,
            stale: o.stale?,
            contact_name: o.contact.full_name,
            assigned_to: o.assigned_name,
            assigned_type: o.user_id ? 'user' : (o.assigned_agent_id ? 'agent' : nil)
          }
        end,
        count: stage_opps.count,
        total_value: stage_opps.sum(&:value) || 0
      }
    end

    render_to_string(
      partial: "scout/canvas/pipeline_viewer",
      locals: {
        pipeline: pipeline,
        stats: stats,
        entity: current_entity,
        user: current_user,
        canvas_data: data
      },
      formats: [:html]
    )
  end

  def render_contact_generator(data = {})
    contact = current_entity.contacts.build
    contact_groups = current_entity.contact_groups.limit(20)

    render_to_string(
      partial: "scout/canvas/contact_generator",
      formats: [:html],
      locals: {
        contact: contact,
        contact_groups: contact_groups,
        entity: current_entity,
        user: current_user,
        canvas_data: data
      }
    )
  end

  def render_campaign_canvas(data = {})
    # Load campaigns first with associations
    campaigns = current_entity.campaigns
      .includes(:contact_groups, :email_template)
      .recent
      .limit(20)

    # Get all delivery stats in one query
    campaign_ids = campaigns.pluck(:id)
    delivery_stats = EmailDelivery
      .where(campaign_id: campaign_ids)
      .group(:campaign_id)
      .pluck(
        :campaign_id,
        Arel.sql("COUNT(*) FILTER (WHERE sent_at IS NOT NULL)"),
        Arel.sql("COUNT(*) FILTER (WHERE opened_at IS NOT NULL)"),
        Arel.sql("COUNT(*) FILTER (WHERE clicked_at IS NOT NULL)"),
        Arel.sql("MIN(sent_at)")
      )

    # Build a hash for quick lookup
    stats_by_campaign = {}
    delivery_stats.each do |campaign_id, sent_count, opened_count, clicked_count, first_sent|
      stats_by_campaign[campaign_id] = {
        sent_count: sent_count,
        opened_count: opened_count,
        clicked_count: clicked_count,
        first_sent_at: first_sent
      }
    end

    # Inject stats into campaigns
    campaigns.each do |campaign|
      if stats = stats_by_campaign[campaign.id]
        campaign.instance_variable_set(:@cached_sent_count, stats[:sent_count])
        campaign.instance_variable_set(:@cached_opened_count, stats[:opened_count])
        campaign.instance_variable_set(:@cached_clicked_count, stats[:clicked_count])
        campaign.instance_variable_set(:@cached_first_sent_at, stats[:first_sent_at])
      end
    end

    # Get summary stats
    stats = {
      total_campaigns: current_entity.campaigns.count,
      sent_campaigns: current_entity.campaigns.where(status: "sent").count,
      draft_campaigns: current_entity.campaigns.where(status: "draft").count
    }

    render_to_string(
      partial: "scout/canvas/campaign_viewer",
      locals: {
        campaigns: campaigns,
        stats: stats,
        entity: current_entity,
        user: current_user,
        canvas_data: data
      }
    )
  end

  def render_document_viewer_canvas(data = {})
    Rails.logger.info "🔍 render_document_viewer_canvas called with data: #{data.inspect}"
    
    # Build document URL from asset_id (single document view)
    if data[:asset_id]
      asset = nil
      asset_type = data[:asset_type]&.to_s
      
      # Use asset_type to look in the correct table first
      if asset_type == 'document'
        # Look for RagDocument first (PDFs, docs, etc.)
        Rails.logger.info "🔍 Looking for RagDocument first (asset_type: document)..."
        rag_document = RagDocument.joins(:rag_store).find_by(
          id: data[:asset_id], 
          rag_stores: { entity_id: current_entity.id }
        )
        
        if rag_document && rag_document.file.attached?
          asset = rag_document
          Rails.logger.info "✅ Found as RagDocument: #{rag_document.id}"
        else
          # Fallback to ImageAsset
          Rails.logger.info "🔍 Not found as RagDocument, trying ImageAsset..."
          asset = ImageAsset.find_by(id: data[:asset_id], entity: current_entity)
        end
      elsif asset_type == 'image'
        # Explicitly asked for image
        Rails.logger.info "🔍 Looking for ImageAsset (asset_type: image)..."
        asset = ImageAsset.find_by(id: data[:asset_id], entity: current_entity)
      else
        # No asset_type specified - try RagDocument first (most common for uploaded files)
        # then fall back to ImageAsset
        Rails.logger.info "🔍 No asset_type specified, checking RagDocument first (priority for uploads)..."
        rag_document = RagDocument.joins(:rag_store).find_by(
          id: data[:asset_id], 
          rag_stores: { entity_id: current_entity.id }
        )
        
        if rag_document && rag_document.file.attached?
          asset = rag_document
          Rails.logger.info "✅ Found as RagDocument: #{rag_document.id}"
        else
          # Fall back to ImageAsset
          Rails.logger.info "🔍 Not found as RagDocument, trying ImageAsset..."
          asset = ImageAsset.find_by(id: data[:asset_id], entity: current_entity)
          if asset
            Rails.logger.info "✅ Found as ImageAsset: #{asset.id}"
          end
        end
      end
      
      if asset && asset.file.attached?
        # Use rails_blob_path with disposition inline for PDFs
        data[:url] = rails_blob_path(asset.file, disposition: 'inline')
        data[:download_url] = rails_blob_path(asset.file, disposition: 'attachment')
        data[:content_type] = asset.file.content_type
        data[:filename] = asset.file.filename.to_s
        data[:size] = asset.file.byte_size
        data[:view_type] = 'single'
        
        # Add document-specific data
        if asset.is_a?(RagDocument)
          data[:document_id] = asset.id
          data[:processing_status] = asset.processing_status
        end
      else
        Rails.logger.error "❌ Document not found with asset_id: #{data[:asset_id]}"
      end
    else
      # Multi-document library view - show both ImageAssets and RagDocuments
      image_docs = current_entity.image_assets.order(created_at: :desc).map do |doc|
        {
          id: doc.id,
          title: doc.title,
          size: doc.file.blob.byte_size,
          content_type: doc.file.content_type,
          created_at: doc.created_at,
          url: rails_blob_url(doc.file),
          download_url: rails_blob_url(doc.file, disposition: 'attachment'),
          source: 'image_asset'
        }
      end
      
      rag_docs = RagDocument.joins(:rag_store)
        .where(rag_stores: { entity_id: current_entity.id })
        .order(created_at: :desc)
        .map do |doc|
          {
            id: doc.id,
            title: doc.original_filename,
            size: doc.file_size_bytes,
            content_type: doc.content_type,
            created_at: doc.created_at,
            url: doc.file.attached? ? rails_blob_url(doc.file) : nil,
            download_url: doc.file.attached? ? rails_blob_url(doc.file, disposition: 'attachment') : nil,
            source: 'rag_document'
          }
        end
      
      data[:view_type] = 'library'
      data[:documents] = (image_docs + rag_docs).sort_by { |d| d[:created_at] }.reverse
    end

    render_to_string(
      partial: 'scout/canvas/document_viewer',
      locals: {
        entity: current_entity,
        user: current_user,
        canvas_data: data
      }
    )
  end

  def render_image_viewer_canvas(data = {})
    Rails.logger.info "🖼️ render_image_viewer_canvas called with data: #{data.inspect}"

    # If we have an image_id, fetch the image asset details
    if data[:image_id]
      image_asset = ImageAsset.by_entity(current_entity.id).find_by(id: data[:image_id])

      if image_asset
        host = ENV.fetch("APP_HOST", "localhost:3000")

        data[:title] ||= image_asset.display_title
        data[:description] ||= image_asset.description

        if image_asset.file.attached?
          data[:image_url] ||= rails_blob_url(image_asset.file, host: host)
          data[:download_url] ||= rails_blob_url(image_asset.file, host: host, disposition: 'attachment')
        end

        data[:created_at] ||= image_asset.created_at.iso8601
        data[:provider] ||= image_asset.source
      end
    end

    render_to_string(
      partial: 'scout/canvas/image_viewer',
      locals: {
        entity: current_entity,
        user: current_user,
        canvas_data: data
      }
    )
  end

  def render_document_search_results_canvas(data = {})
    Rails.logger.info "🔍 render_document_search_results_canvas called with data: #{data.inspect}"
    
    # Extract search query and results from data
    search_query = data[:query] || ""
    search_results = data[:results] || []
    
    # If we have document IDs from search results, fetch full document details
    if search_results.is_a?(Array) && search_results.any?
      # Fetch documents by ID
      documents = []
      
      # Look for RagDocuments first
      rag_docs = RagDocument.joins(:rag_store)
        .where(id: search_results.map { |r| r[:document_id] || r[:id] })
        .where(rag_stores: { entity_id: current_entity.id })
      
      rag_docs.each do |doc|
        result_item = search_results.find { |r| (r[:document_id] || r[:id]).to_i == doc.id }
        documents << {
          id: doc.id,
          title: (result_item && result_item[:document_title]) || doc.original_filename,
          filename: doc.original_filename,
          content_type: doc.content_type,
          size: doc.file_size_bytes,
          relevance_score: (result_item && result_item[:relevance_score]) || (result_item && result_item[:score]) || 1.0,
          snippet: (result_item && result_item[:snippet]) || (result_item && result_item[:text]) || "No preview available",
          created_at: doc.created_at,
          url: doc.file.attached? ? rails_blob_url(doc.file, disposition: 'inline') : nil,
          download_url: doc.file.attached? ? rails_blob_url(doc.file, disposition: 'attachment') : nil
        }
      end
      
      # Sort by relevance score
      documents.sort_by! { |doc| -(doc[:relevance_score] || 0) }
      
      data[:documents] = documents
    else
      data[:documents] = []
    end
    
    data[:query] = search_query
    data[:total_results] = data[:documents].count
    
    render_to_string(
      partial: "scout/canvas/document_search_results",
      formats: [:html],
      locals: {
        entity: current_entity,
        user: current_user,
        canvas_data: data
      }
    )
  end
  
  def render_analytics_canvas(data = {})
    # Get analytics data for the dashboard
    analytics_data = {
      campaigns: current_entity.campaigns.includes(:email_deliveries).limit(10),
      recent_contacts: current_entity.contacts.where("created_at > ?", 30.days.ago).count,
      total_emails_sent: current_entity.campaigns.sum { |c| c.mailgun_stats&.dig("sent") || 0 },
      avg_open_rate: calculate_avg_open_rate,
      landing_pages: current_entity.landing_pages.count
    }

    render_to_string(
      partial: "scout/canvas/analytics_dashboard",
      locals: {
        analytics_data: analytics_data,
        entity: current_entity,
        user: current_user,
        canvas_data: data
      },
      formats: [:html]
    )
  end

  def render_default_canvas
    render_to_string(
      partial: "scout/canvas/default",
      locals: {
        entity: current_entity,
        user: current_user
      }
    )
  end

  # Load a module canvas by its full slug (e.g., "social_media_calendar_list")
  def load_module_canvas_by_slug(full_canvas_slug)
    # Normalize the slug (convert hyphens to underscores)
    normalized_slug = full_canvas_slug.to_s.gsub('-', '_')
    
    # Find the canvas by slug across all modules for this entity
    canvas = ModuleCanvas.joins(:app_module)
                         .where(app_modules: { entity_id: current_entity.id })
                         .find_by(slug: normalized_slug)
    
    # If exact match fails, try partial matching
    unless canvas
      # Try to find by partial match (e.g., "social_media_calendar" matches "social_media_calendar_list")
      canvas = ModuleCanvas.joins(:app_module)
                           .where(app_modules: { entity_id: current_entity.id })
                           .where("module_canvases.slug LIKE ?", "#{normalized_slug}%")
                           .where(is_default: true)
                           .first
      
      # If still no match, try any canvas that starts with the slug
      canvas ||= ModuleCanvas.joins(:app_module)
                             .where(app_modules: { entity_id: current_entity.id })
                             .where("module_canvases.slug LIKE ?", "#{normalized_slug}%")
                             .first
                             
      Rails.logger.info "[ModuleCanvas] Fuzzy matched '#{full_canvas_slug}' to '#{canvas&.slug}'" if canvas
    end
    
    return nil unless canvas

    app_module = canvas.app_module
    
    # Build data context for the canvas
    data_context = {
      module_slug: app_module.slug,
      canvas_slug: canvas.slug,
      title: canvas.name,
      user: current_user,
      entity: current_entity,
      module: app_module,
      schema: app_module.metadata&.dig('schema')
    }

    # Get canvas_data from params for form editing
    canvas_data = params[:canvas_data]&.to_unsafe_h || {}
    record_id = canvas_data['id'] || canvas_data[:id]
    
    # Load data from data sources OR by ID for form editing
    Rails.logger.info "[ModuleCanvas] 📊 Data sources: #{canvas.data_sources.inspect}, Record ID: #{record_id}"
    
    if canvas.data_sources.any?
      canvas.data_sources.each do |source|
        source = source.transform_keys(&:to_sym)
        Rails.logger.info "[ModuleCanvas] Processing data source type: #{source[:type]}"
        case source[:type].to_s
        when 'module_data', 'model'
          # Load data from dynamic module model
          records = load_module_data(app_module, current_entity)
          data_context[:records] = records
          data_context[:record_count] = records.count
          Rails.logger.info "[ModuleCanvas] ✅ Loaded #{records.count} records from module data"
        when 'tool'
          # TODO: Execute tool and add result to context
        end
      end
    elsif record_id.present? && canvas.canvas_type == 'form'
      # Form canvas with a record ID - load that specific record for editing
      Rails.logger.info "[ModuleCanvas] 📝 Loading record #{record_id} for form editing"
      record = load_module_record(app_module, current_entity, record_id)
      if record
        data_context[:record] = record
        data_context[:records] = [record]
        data_context[:record_count] = 1
        Rails.logger.info "[ModuleCanvas] ✅ Loaded record: #{record.try(:title) || record.id}"
      end
    elsif canvas.canvas_type == 'data_grid'
      # Data grid with no explicit data sources - default to loading module data
      Rails.logger.info "[ModuleCanvas] 📊 No data sources, loading default module data for grid"
      records = load_module_data(app_module, current_entity)
      data_context[:records] = records
      data_context[:record_count] = records.count
      Rails.logger.info "[ModuleCanvas] ✅ Loaded #{records.count} records (default)"
    end

    # Render the canvas with data
    Rails.logger.info "[ModuleCanvas] 🎨 Rendering canvas with #{data_context[:records]&.count || 0} records"
    rendered_content = render_module_canvas_with_data(canvas, data_context)

    {
      content: rendered_content,
      title: canvas.name,
      type: "module_#{canvas.slug}"
    }
  rescue => e
    Rails.logger.error "[ModuleCanvas] Error loading canvas #{full_canvas_slug}: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    nil
  end

  # Load data from a dynamic module's model
  def load_module_data(app_module, entity, limit: 50)
    Rails.logger.info "[ModuleCanvas] 📊 Loading data for module: #{app_module.slug}, entity: #{entity.id}"
    
    model_code = app_module.module_codes.where(code_type: 'model', status: 'deployed').first
    unless model_code
      Rails.logger.warn "[ModuleCanvas] ⚠️ No deployed model_code found for #{app_module.slug}"
      return []
    end

    model_class = Modules::DynamicModelLoader.instance.get_model(app_module, app_module.slug.classify)
    model_class ||= Modules::DynamicModelLoader.instance.load_model(model_code)
    unless model_class
      Rails.logger.warn "[ModuleCanvas] ⚠️ Could not load model class for #{app_module.slug}"
      return []
    end
    
    Rails.logger.info "[ModuleCanvas] ✅ Using model class: #{model_class.name}, table: #{model_class.table_name}"
    
    records = model_class.where(entity_id: entity.id).order(created_at: :desc).limit(limit)
    Rails.logger.info "[ModuleCanvas] 📊 Found #{records.count} records"
    records
  rescue => e
    Rails.logger.error "[ModuleCanvas] ❌ Error loading module data: #{e.message}"
    Rails.logger.error e.backtrace.first(3).join("\n")
    []
  end

  # Load a single record from a dynamic module by ID
  def load_module_record(app_module, entity, record_id)
    model_code = app_module.module_codes.where(code_type: 'model', status: 'deployed').first
    return nil unless model_code

    model_class = Modules::DynamicModelLoader.instance.get_model(app_module, app_module.slug.classify)
    model_class ||= Modules::DynamicModelLoader.instance.load_model(model_code)
    return nil unless model_class

    model_class.where(entity_id: entity.id).find_by(id: record_id)
  rescue => e
    Rails.logger.error "[ModuleCanvas] Error loading module record: #{e.message}"
    nil
  end

  # Render a module canvas with actual data
  def render_module_canvas_with_data(canvas, data_context)
    app_module = data_context[:module]
    schema = data_context[:schema] || app_module&.metadata&.dig('schema') || {}
    canvas_metadata = canvas.metadata || {}
    icon = canvas_metadata['icon'] || canvas_metadata[:icon] || schema.dig('module', 'icon') || 'database'
    
    # Route to appropriate renderer based on canvas type
    case canvas.canvas_type
    when 'form'
      # Use enhanced form renderer for rich form experience
      renderer = Modules::EnhancedFormRenderer.new(
        app_module: app_module,
        canvas: canvas,
        record: data_context[:record],
        user: current_user,
        entity: current_entity,
        context: data_context[:record] ? :edit : :create
      )
      renderer.render
    when 'calendar'
      render_module_calendar_canvas(canvas, data_context, app_module, icon)
    when 'kanban'
      render_module_kanban_canvas(canvas, data_context, app_module, icon)
    when 'dashboard', 'report'
      # Dashboard and report canvases use custom HTML content
      render_module_dashboard_canvas(canvas, data_context, app_module, icon)
    else # 'data_grid' or any other type
      render_module_list_canvas(canvas, data_context, app_module, schema, icon)
    end
  end

  # Render a form canvas for creating/editing records
  def render_module_form_canvas(canvas, data_context, app_module, schema, icon)
    record = data_context[:record]
    # Try canvas metadata first (form-specific fields), then schema, then module schema
    fields = canvas.metadata&.dig('fields') || schema.dig('fields') || app_module.metadata&.dig('schema', 'fields') || []
    is_edit = record.present?
    
    Rails.logger.info "[ModuleCanvas] 📝 Form rendering with #{fields.length} fields, is_edit: #{is_edit}"
    
    # Build form fields HTML
    form_fields = fields.map do |f|
      field_name = f['name']
      field_type = f['field_type'] || f['type'] || 'string'
      label = (f['label'] || field_name).to_s.titleize
      required = f['required'] ? 'required' : ''
      current_value = record.try(field_name) if record
      options = f['options'] || []
      reference_model = f['reference_model'] || f['references']
      
      input_html = case field_type.to_s.downcase
      when 'text'
        value = ERB::Util.html_escape(current_value || '')
        "<textarea name='#{field_name}' class='form-control' rows='3' #{required}>#{value}</textarea>"
      when 'boolean'
        checked = current_value ? 'checked' : ''
        "<input type='checkbox' name='#{field_name}' class='form-check-input' #{checked}>"
      when 'date'
        value = current_value.respond_to?(:strftime) ? current_value.strftime('%Y-%m-%d') : current_value
        "<input type='date' name='#{field_name}' class='form-control' value='#{value}' #{required}>"
      when 'datetime'
        value = current_value.respond_to?(:strftime) ? current_value.strftime('%Y-%m-%dT%H:%M') : current_value
        "<input type='datetime-local' name='#{field_name}' class='form-control' value='#{value}' #{required}>"
      when 'integer', 'decimal'
        "<input type='number' name='#{field_name}' class='form-control' value='#{current_value}' #{required}>"
      when 'json'
        value = current_value.is_a?(Hash) || current_value.is_a?(Array) ? current_value.to_json : current_value
        "<textarea name='#{field_name}' class='form-control font-monospace' rows='3'>#{ERB::Util.html_escape(value || '')}</textarea>"
      when 'enum', 'select'
        # Render a select dropdown with provided options
        option_tags = options.map do |opt|
          selected = current_value.to_s == opt.to_s ? 'selected' : ''
          "<option value='#{ERB::Util.html_escape(opt)}' #{selected}>#{ERB::Util.html_escape(opt)}</option>"
        end.join
        "<select name='#{field_name}' class='form-select' #{required}><option value=''>-- Select --</option>#{option_tags}</select>"
      when 'reference'
        # Render a dropdown populated with records from the referenced model
        render_reference_field(field_name, reference_model, current_value, required)
      else
        # Check if field name ends with _id and might be a reference
        if field_name.to_s.end_with?('_id')
          inferred_model = field_name.to_s.gsub(/_id$/, '').classify
          render_reference_field(field_name, inferred_model, current_value, required)
        else
          "<input type='text' name='#{field_name}' class='form-control' value='#{ERB::Util.html_escape(current_value || '')}' #{required}>"
        end
      end
      
      if field_type.to_s.downcase == 'boolean'
        "<div class='mb-3 form-check'><label class='form-check-label'>#{input_html} #{label}</label></div>"
      else
        "<div class='mb-3'><label class='form-label'>#{label}</label>#{input_html}</div>"
      end
    end.join("\n")
    
    action_text = is_edit ? "Update" : "Create"
    record_id = record&.id
    model_name = app_module.slug.classify
    list_canvas_slug = "module_#{app_module.slug}_list"
    
    <<~HTML
      <div class="module-form-canvas p-4" 
           data-controller="module-canvas"
           data-module-canvas-module-value="#{app_module.slug}"
           data-module-canvas-model-value="#{model_name}">
        
        <!-- Breadcrumb Navigation -->
        <nav aria-label="breadcrumb" class="mb-3">
          <ol class="breadcrumb">
            <li class="breadcrumb-item">
              <a href="#" onclick="navigateToCanvas('module_manager'); return false;">
                <i data-lucide="box" style="width: 14px; height: 14px;"></i> Installed Apps
              </a>
            </li>
            <li class="breadcrumb-item">
              <a href="#" onclick="navigateToCanvas('#{list_canvas_slug}'); return false;">#{app_module.name}</a>
            </li>
            <li class="breadcrumb-item active">#{is_edit ? 'Edit' : 'New'}</li>
          </ol>
        </nav>
        
        <div class="d-flex justify-content-between align-items-center mb-4">
          <h3>
            <i data-lucide="#{is_edit ? 'edit' : 'plus'}"></i> 
            #{is_edit ? 'Edit' : 'New'} #{app_module.name.singularize}
          </h3>
          <button class="btn btn-outline-secondary" onclick="navigateToCanvas('#{list_canvas_slug}')">
            <i data-lucide="arrow-left"></i> Back to List
          </button>
        </div>
        <div class="card">
          <div class="card-body">
            <form id="module-record-form" class="row" data-record-id="#{record_id}">
              <div class="col-md-8">
                #{form_fields}
              </div>
              <div class="col-12 mt-3">
                <button type="button" class="btn btn-primary" onclick="saveModuleRecord()">
                  <i data-lucide="save"></i> #{action_text}
                </button>
                <button type="button" class="btn btn-outline-secondary ms-2" onclick="navigateToCanvas('#{list_canvas_slug}')">
                  Cancel
                </button>
              </div>
            </form>
          </div>
        </div>
      </div>
      <script>
        // Direct canvas navigation - NO chat messages
        function navigateToCanvas(canvasSlug) {
          if (window.scoutController?.loadScoutCanvas) {
            window.scoutController.loadScoutCanvas(canvasSlug, {});
          } else {
            console.error('Scout controller not available for navigation');
          }
        }
        
        // Save via direct API call - NO chat messages
        async function saveModuleRecord() {
          const form = document.getElementById('module-record-form');
          const formData = new FormData(form);
          const data = {};
          formData.forEach((value, key) => { data[key] = value; });
          
          const recordId = form.dataset.recordId;
          const moduleSlug = '#{app_module.slug}';
          const modelName = '#{model_name}';
          
          const url = recordId && recordId !== ''
            ? '/api/modules/' + moduleSlug + '/models/' + modelName + '/' + recordId
            : '/api/modules/' + moduleSlug + '/models/' + modelName;
          const method = recordId && recordId !== '' ? 'PATCH' : 'POST';
          
          const saveBtn = form.querySelector('.btn-primary');
          const originalText = saveBtn.innerHTML;
          saveBtn.innerHTML = '<span class="spinner-border spinner-border-sm"></span> Saving...';
          saveBtn.disabled = true;
          
          try {
            const response = await fetch(url, {
              method: method,
              headers: {
                'Content-Type': 'application/json',
                'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
              },
              body: JSON.stringify(data)
            });
            
            if (response.ok) {
              if (window.showToast) {
                window.showToast('success', '#{app_module.name.singularize} saved successfully!');
              }
              navigateToCanvas('#{list_canvas_slug}');
            } else {
              const errorData = await response.json();
              if (window.showToast) {
                window.showToast('error', errorData.message || 'Failed to save record');
              } else {
                alert(errorData.message || 'Failed to save record');
              }
            }
          } catch (error) {
            console.error('Save failed:', error);
            if (window.showToast) {
              window.showToast('error', 'Failed to save. Please try again.');
            } else {
              alert('Failed to save. Please try again.');
            }
          } finally {
            saveBtn.innerHTML = originalText;
            saveBtn.disabled = false;
          }
        }
        
        if (window.lucide) lucide.createIcons();
      </script>
    HTML
  end

  # Render a calendar canvas for scheduling views
  def render_module_calendar_canvas(canvas, data_context, app_module, icon)
    records = data_context[:records] || []
    date_field = canvas.card_config&.dig('date_field') || canvas.metadata&.dig('date_field') || 'scheduled_for'
    title_field = canvas.card_config&.dig('title_field') || canvas.metadata&.dig('title_field') || 'title'
    color_field = canvas.card_config&.dig('color_field') || canvas.metadata&.dig('color_field') || 'status'
    
    # Build calendar events
    events = records.map do |record|
      date_value = record.try(date_field)
      next unless date_value
      
      {
        id: record.id,
        title: record.try(title_field) || "Record #{record.id}",
        start: date_value.respond_to?(:iso8601) ? date_value.iso8601 : date_value.to_s,
        color: status_color(record.try(color_field)),
        extendedProps: { status: record.try(color_field) }
      }
    end.compact
    
    <<~HTML
      <div class="module-calendar-canvas p-4" data-module="#{app_module.slug}">
        <div class="d-flex justify-content-between align-items-center mb-4">
          <h3><i data-lucide="calendar"></i> #{canvas.name}</h3>
          <button class="btn btn-primary" onclick="loadModuleForm()">
            <i data-lucide="plus"></i> Add New
          </button>
        </div>
        <div class="card">
          <div class="card-body">
            <div id="module-calendar" style="min-height: 600px;"></div>
          </div>
        </div>
      </div>
      <script>
        document.addEventListener('DOMContentLoaded', function() {
          const calendarEl = document.getElementById('module-calendar');
          if (calendarEl && typeof FullCalendar !== 'undefined') {
            const calendar = new FullCalendar.Calendar(calendarEl, {
              initialView: 'dayGridMonth',
              headerToolbar: {
                left: 'prev,next today',
                center: 'title',
                right: 'dayGridMonth,timeGridWeek,listWeek'
              },
              events: #{events.to_json},
              eventClick: function(info) {
                sendMessageToAmos('Show me details for #{app_module.name.singularize} ID ' + info.event.id);
              },
              dateClick: function(info) {
                sendMessageToAmos('Create a new #{app_module.name.singularize} for ' + info.dateStr);
              }
            });
            calendar.render();
          } else {
            calendarEl.innerHTML = '<div class="alert alert-info">Calendar view requires FullCalendar library. Showing list instead:</div>' +
              '<ul>' + #{events.map { |e| "<li>#{e[:start]}: #{e[:title]}</li>" }.join.to_json} + '</ul>';
          }
        });
        
        function sendMessageToAmos(message) {
          const messageInput = document.getElementById('message-input');
          const messageForm = document.getElementById('message-form');
          if (messageInput && messageForm) {
            messageInput.value = message;
            messageForm.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
          }
        }
        
        function loadModuleForm(recordId) {
          const canvasName = 'module_#{app_module.slug}_form';
          const canvasData = recordId ? { id: recordId } : {};
          
          fetch('/scout/load_canvas', {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
            },
            body: JSON.stringify({ canvas_type: canvasName, canvas_data: canvasData })
          })
          .then(response => response.json())
          .then(data => {
            if (data.success && data.canvas) {
              const canvasContainer = document.getElementById('canvas-content') || 
                                      document.querySelector('.canvas-body') ||
                                      document.querySelector('[data-scout-target="canvasContent"]');
              if (canvasContainer) {
                canvasContainer.innerHTML = data.canvas.content;
                if (window.lucide) lucide.createIcons();
              }
            }
          })
          .catch(err => console.error('Error loading form:', err));
        }
        
        if (window.lucide) lucide.createIcons();
      </script>
    HTML
  end
  
  # Render a kanban board canvas
  def render_module_kanban_canvas(canvas, data_context, app_module, icon)
    records = data_context[:records] || []
    column_field = canvas.card_config&.dig('column_field') || canvas.metadata&.dig('column_field') || 'status'
    card_fields = canvas.card_config&.dig('card_fields') || canvas.metadata&.dig('card_fields') || ['title']
    
    # Get column options from schema
    schema = app_module.metadata&.dig('schema') || {}
    status_field = schema.dig('fields')&.find { |f| f['name'] == column_field }
    columns = status_field&.dig('options') || ['draft', 'active', 'completed']
    columns = columns.map { |c| c.is_a?(Hash) ? c['value'] : c }
    
    # Group records by column
    grouped = records.group_by { |r| r.try(column_field).to_s }
    
    columns_html = columns.map do |column|
      column_records = grouped[column] || []
      cards_html = column_records.map do |record|
        card_content = card_fields.map do |field|
          value = record.try(field)
          "<div class='card-field'>#{format_field_value(value, field)}</div>"
        end.join
        
        <<~HTML
          <div class="kanban-card card mb-2" data-record-id="#{record.id}" onclick="loadModuleForm(#{record.id})">
            <div class="card-body p-2">
              <strong>#{ERB::Util.html_escape(record.try(:title) || "Record #{record.id}")}</strong>
              #{card_content}
            </div>
          </div>
        HTML
      end.join
      
      <<~HTML
        <div class="kanban-column col" data-column="#{column}">
          <div class="column-header mb-2 p-2 bg-light rounded d-flex justify-content-between">
            <strong>#{column.to_s.titleize}</strong>
            <span class="badge bg-secondary">#{column_records.count}</span>
          </div>
          <div class="column-cards" style="min-height: 200px;">
            #{cards_html}
          </div>
        </div>
      HTML
    end.join
    
    <<~HTML
      <div class="module-kanban-canvas p-4" data-module="#{app_module.slug}">
        <div class="d-flex justify-content-between align-items-center mb-4">
          <h3><i data-lucide="columns"></i> #{canvas.name}</h3>
          <button class="btn btn-primary" onclick="loadModuleForm()">
            <i data-lucide="plus"></i> Add New
          </button>
        </div>
        <div class="kanban-board row g-3">
          #{columns_html}
        </div>
      </div>
      <script>
        function sendMessageToAmos(message) {
          const messageInput = document.getElementById('message-input');
          const messageForm = document.getElementById('message-form');
          if (messageInput && messageForm) {
            messageInput.value = message;
            messageForm.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
          }
        }
        
        function loadModuleForm(recordId) {
          const canvasName = 'module_#{app_module.slug}_form';
          const canvasData = recordId ? { id: recordId } : {};
          
          fetch('/scout/load_canvas', {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
            },
            body: JSON.stringify({ canvas_type: canvasName, canvas_data: canvasData })
          })
          .then(response => response.json())
          .then(data => {
            if (data.success && data.canvas) {
              const canvasContainer = document.getElementById('canvas-content') || 
                                      document.querySelector('.canvas-body') ||
                                      document.querySelector('[data-scout-target="canvasContent"]');
              if (canvasContainer) {
                canvasContainer.innerHTML = data.canvas.content;
                if (window.lucide) lucide.createIcons();
              }
            }
          })
          .catch(err => console.error('Error loading form:', err));
        }
        
        if (window.lucide) lucide.createIcons();
      </script>
    HTML
  end
  
  def status_color(status)
    colors = {
      'draft' => '#6B7280',
      'pending_review' => '#F59E0B',
      'approved' => '#10B981',
      'rejected' => '#EF4444',
      'scheduled' => '#3B82F6',
      'published' => '#8B5CF6',
      'active' => '#10B981',
      'completed' => '#6366F1',
      'archived' => '#9CA3AF'
    }
    colors[status.to_s.downcase] || '#6B7280'
  end

  # Render a reference/foreign key field as a dropdown
  def render_reference_field(field_name, reference_model, current_value, required)
    # Map common model names to their classes
    model_class = case reference_model.to_s
    when 'LandingPage', 'landing_page', 'landing_pages'
      LandingPage
    when 'Contact', 'contact', 'contacts'
      Contact
    when 'Campaign', 'campaign', 'campaigns'
      Campaign
    when 'User', 'user', 'users'
      User
    when 'EmailTemplate', 'email_template', 'email_templates'
      EmailTemplate
    when 'Opportunity', 'opportunity', 'opportunities'
      Opportunity
    else
      # Try to constantize
      begin
        reference_model.to_s.classify.constantize
      rescue NameError
        nil
      end
    end
    
    unless model_class
      Rails.logger.warn "[ModuleCanvas] Could not find model class for reference: #{reference_model}"
      return "<input type='number' name='#{field_name}' class='form-control' value='#{current_value}' #{required} placeholder='Enter ID'>"
    end
    
    # Fetch records from the referenced model
    begin
      records = if model_class.respond_to?(:where) && model_class.column_names.include?('entity_id')
        model_class.where(entity_id: current_entity.id).limit(200)
      else
        model_class.limit(200)
      end
      
      # Build option tags
      option_tags = records.map do |rec|
        # Try different name attributes
        display_name = rec.try(:name) || rec.try(:title) || rec.try(:email) || "#{model_class.name} ##{rec.id}"
        selected = current_value.to_i == rec.id ? 'selected' : ''
        "<option value='#{rec.id}' #{selected}>#{ERB::Util.html_escape(display_name)}</option>"
      end.join
      
      "<select name='#{field_name}' class='form-select' #{required}><option value=''>-- Select #{reference_model.to_s.titleize} --</option>#{option_tags}</select>"
    rescue => e
      Rails.logger.error "[ModuleCanvas] Error loading reference options: #{e.message}"
      "<input type='number' name='#{field_name}' class='form-control' value='#{current_value}' #{required} placeholder='Enter ID'>"
    end
  end

  # Render a dashboard/report canvas with custom HTML content
  def render_module_dashboard_canvas(canvas, data_context, app_module, icon)
    records = data_context[:records] || []
    
    # Prepare data context for template rendering
    template_context = {
      module_slug: app_module.slug,
      canvas_slug: canvas.slug,
      title: canvas.name,
      record_count: records.count,
      records: records
    }
    
    # Get the custom HTML content from the canvas
    html_content = canvas.html_content
    
    # If no custom HTML, use a default dashboard layout
    if html_content.blank?
      html_content = default_dashboard_html(app_module, canvas, records, icon)
    else
      # Render the custom HTML with data context interpolation
      html_content = canvas.render_html(template_context)
    end
    
    # Wrap in a styled container
    <<~HTML
      <div class="module-dashboard p-4" data-module="#{app_module.slug}" data-canvas="#{canvas.slug}">
        <div class="d-flex justify-content-between align-items-center mb-4">
          <h4 class="mb-0">
            <i data-lucide="#{icon}" class="me-2"></i>
            #{ERB::Util.html_escape(canvas.name)}
          </h4>
          <div>
            <button class="btn btn-outline-secondary btn-sm me-2" onclick="window.scoutController.loadScoutCanvas('module_#{app_module.slug}_list')">
              <i data-lucide="list" class="me-1"></i> View List
            </button>
          </div>
        </div>
        <div class="dashboard-content">
          #{html_content}
        </div>
      </div>
      #{canvas.css_content.present? ? "<style>#{canvas.css_content}</style>" : ""}
      #{canvas.js_content.present? ? "<script>#{canvas.js_content}</script>" : ""}
    HTML
  end

  # Default dashboard HTML when no custom content is provided
  def default_dashboard_html(app_module, canvas, records, icon)
    record_count = records.count
    
    <<~HTML
      <div class="row">
        <div class="col-md-4">
          <div class="card bg-primary text-white mb-3">
            <div class="card-body">
              <div class="d-flex align-items-center">
                <i data-lucide="database" class="me-3" style="width: 32px; height: 32px;"></i>
                <div>
                  <h2 class="mb-0">#{record_count}</h2>
                  <small>Total Records</small>
                </div>
              </div>
            </div>
          </div>
        </div>
        <div class="col-md-8">
          <div class="card mb-3">
            <div class="card-header">Recent Activity</div>
            <div class="card-body">
              #{records.any? ? "<p>#{record_count} records in this module.</p>" : "<p class='text-muted'>No data yet. Create your first record to see activity here.</p>"}
            </div>
          </div>
        </div>
      </div>
    HTML
  end

  # Render a list/grid canvas for viewing records
  # Uses Stimulus controller for direct UI actions (NOT chat-based)
  def render_module_list_canvas(canvas, data_context, app_module, schema, icon)
    records = data_context[:records] || []
    canvas_metadata = canvas.metadata || {}
    display_fields = canvas_metadata['display_fields'] || canvas_metadata[:display_fields]
    model_name = app_module.slug.classify  # e.g., "InventoryManagement"
    
    if display_fields.blank?
      fields = schema.dig('fields') || []
      display_fields = fields.first(6).map { |f| f['name'] }
    end
    
    display_fields = ['title', 'content', 'status', 'created_at'] if display_fields.blank?
    
    # Build the table HTML with actual data
    if records.any?
      rows_html = records.map do |record|
        cells = display_fields.map do |field|
          value = record.respond_to?(field) ? record.send(field) : record[field]
          formatted = format_field_value(value, field)
          "<td>#{ERB::Util.html_escape(formatted)}</td>"
        end.join
        
        # Use data attributes for Stimulus controller - NO chat messages!
        actions = <<~HTML
          <td class="text-end">
            <button class="btn btn-sm btn-outline-primary me-1" 
                    data-row-action="edit" 
                    data-id="#{record.id}"
                    title="Edit">
              <i data-lucide="edit-2" style="width: 14px; height: 14px;"></i>
            </button>
            <button class="btn btn-sm btn-outline-danger" 
                    data-row-action="delete" 
                    data-id="#{record.id}"
                    title="Delete">
              <i data-lucide="trash-2" style="width: 14px; height: 14px;"></i>
            </button>
          </td>
        HTML
        
        "<tr data-id=\"#{record.id}\">#{cells}#{actions}</tr>"
      end.join("\n")
      
      table_body = rows_html
    else
      table_body = <<~HTML
        <tr>
          <td colspan="#{display_fields.count + 1}" class="text-center py-4 text-muted">
            <i data-lucide="inbox" style="width: 48px; height: 48px;" class="mb-2 opacity-50"></i>
            <p>No records yet. Click "Add New" to create your first record.</p>
          </td>
        </tr>
      HTML
    end
    
    header_cells = display_fields.map { |f| "<th>#{f.to_s.titleize}</th>" }.join + "<th class=\"text-end\">Actions</th>"
    
    # Use Stimulus controller for all button actions - direct API calls, no chat!
    <<~HTML
      <div class="module-canvas p-4" 
           data-controller="module-canvas" 
           data-module-canvas-module-value="#{app_module.slug}"
           data-module-canvas-model-value="#{model_name}">
        
        <!-- Breadcrumb Navigation -->
        <nav aria-label="breadcrumb" class="mb-3">
          <ol class="breadcrumb">
            <li class="breadcrumb-item">
              <a href="#" onclick="window.scoutController?.loadScoutCanvas('module_manager', {}); return false;">
                <i data-lucide="box" style="width: 14px; height: 14px;"></i> Installed Apps
              </a>
            </li>
            <li class="breadcrumb-item active">#{app_module.name}</li>
          </ol>
        </nav>
        
        <div class="d-flex justify-content-between align-items-center mb-4">
          <h3><i data-lucide="#{icon}"></i> #{app_module.name}</h3>
          <div class="d-flex gap-2">
            <button class="btn btn-outline-secondary" 
                    data-action="click->module-canvas#performAction" 
                    data-action-name="refresh">
              <i data-lucide="refresh-cw"></i> Refresh
            </button>
            <button class="btn btn-primary" 
                    data-action="click->module-canvas#performAction" 
                    data-action-name="add">
              <i data-lucide="plus"></i> Add New
            </button>
          </div>
        </div>
        
        <div class="card">
          <div class="table-responsive">
            <table class="table table-hover mb-0">
              <thead>
                <tr>#{header_cells}</tr>
              </thead>
              <tbody id="module-data-list">
                #{table_body}
              </tbody>
            </table>
          </div>
        </div>
        
        <div class="mt-3 text-muted small">
          Showing #{records.count} record(s)
        </div>
      </div>
      
      <script>
        // Initialize Lucide icons
        if (window.lucide) lucide.createIcons();
      </script>
    HTML
  end

  # Format a field value for display
  def format_field_value(value, field_name)
    return '-' if value.nil?
    
    case value
    when Array
      value.join(', ')
    when Hash
      value.to_json[0..50] + (value.to_json.length > 50 ? '...' : '')
    when Time, DateTime
      value.strftime('%Y-%m-%d %H:%M')
    when Date
      value.strftime('%Y-%m-%d')
    when TrueClass, FalseClass
      value ? '✓' : '✗'
    else
      value.to_s.truncate(100)
    end
  end

  # Load a module canvas from the Extensible Module System (legacy method)
  def load_module_canvas(module_slug, canvas_slug)
    app_module = current_entity.app_modules.visible_to(current_user).find_by(slug: module_slug)
    return nil unless app_module

    canvas = ModuleCanvas.where(app_module_id: app_module.id).find_by(slug: canvas_slug)
    return nil unless canvas

    # Build data context for the canvas
    data_context = {
      module_slug: module_slug,
      canvas_slug: canvas_slug,
      title: canvas.name,
      user: current_user,
      entity: current_entity
    }

    # Load data from data sources
    canvas.data_sources.each do |source|
      source = source.transform_keys(&:to_sym)
      case source[:type]
      when 'model'
        # TODO: Load model data when dynamic models are implemented
      when 'tool'
        # TODO: Execute tool and add result to context
      end
    end

    {
      content: canvas.render_html(data_context),
      title: canvas.name,
      type: canvas.full_canvas_type
    }
  rescue => e
    Rails.logger.error "[ModuleCanvas] Error loading #{module_slug}/#{canvas_slug}: #{e.message}"
    nil
  end

  def render_user_profile_canvas(data = {})
    render_to_string(
      partial: "scout/canvas/user_profile",
      locals: {
        user: current_user,
        entity: current_entity,
        canvas_data: data
      }
    )
  end

  def render_business_profile_canvas(data = {})
    render_to_string(
      partial: "scout/canvas/business_profile",
      locals: {
        business_profile: current_user.business_profile,
        user: current_user,
        entity: current_entity,
        canvas_data: data
      }
    )
  end

  def calculate_avg_open_rate
    campaigns_with_stats = current_entity.campaigns.where.not(mailgun_stats: nil)
    return 0 if campaigns_with_stats.empty?

    total_sent = 0
    total_opened = 0

    campaigns_with_stats.each do |campaign|
      sent = campaign.mailgun_stats&.dig("sent") || 0
      opened = campaign.mailgun_stats&.dig("opened") || 0
      total_sent += sent
      total_opened += opened
    end

    return 0 if total_sent == 0
    ((total_opened.to_f / total_sent) * 100).round(1)
  end

  def render_email_template_viewer(data = {})
    templates = current_entity.email_templates.order(created_at: :desc)

    # Get stats
    total_count = templates.count
    used_count = templates.joins(:campaigns).distinct.count

    stats = {
      total_templates: total_count,
      active_templates: used_count,
      used_templates: used_count,
      unused_templates: total_count - used_count
    }

    render_to_string(
      partial: "scout/canvas/email_template_viewer",
      locals: {
        templates: templates,
        stats: stats,
        entity: current_entity,
        user: current_user,
        canvas_data: data
      }
    )
  end

  def render_email_template_editor(data = {})
    template_id = data["template_id"] || data[:template_id]
    email_template = current_entity.email_templates.find(template_id)

    render_to_string(
      partial: "scout/canvas/email_template_editor",
      locals: {
        email_template: email_template,
        entity: current_entity,
        user: current_user,
        canvas_data: data
      }
    )
  end

  def render_web_page_viewer(data = {})
    # Ensure data has indifferent access
    data = data.to_h.with_indifferent_access if data.respond_to?(:to_h)

    render_to_string(
      partial: "scout/canvas/web_page_viewer",
      locals: { canvas_data: data }
    )
  end

  def render_dynamic_canvas(data = {})
    # Ensure data has indifferent access
    data = data.to_h.with_indifferent_access if data.respond_to?(:to_h)
    
    # If we have a structured result but no html_content, try to format it
    if data['html_content'].blank? && (result = data['result']).present?
      # Check if result is a JSON string and parse it
      if result.is_a?(String) && result.strip.start_with?('{')
        begin
          result = JSON.parse(result)
        rescue JSON::ParserError
          # keep as string
        end
      end
      
      if result.is_a?(Hash)
        # Handle "format" field if present (from Universal Output Requirement)
        if result['format'].present? && result['content'].present?
          case result['format']
          when 'markdown'
            renderer = Redcarpet::Render::HTML.new(hard_wrap: true, filter_html: true)
            markdown = Redcarpet::Markdown.new(renderer, autolink: true, tables: true, fenced_code_blocks: true)
            html = "<div class='report-container markdown-content'>#{markdown.render(result['content'])}</div>"
          when 'html'
            html = "<div class='report-container'>#{result['content']}</div>"
          when 'json'
            # Fallback to JSON tree or existing logic for structured data
            # For now, just pretty print it in a pre block or rely on existing visualization tool
            # Ideally we'd have a JSON viewer component
            html = "<div class='report-container'><pre>#{JSON.pretty_generate(result['content'])}</pre></div>"
          when 'code'
            # Use markdown code block rendering
            renderer = Redcarpet::Render::HTML.new(hard_wrap: true, filter_html: true)
            markdown = Redcarpet::Markdown.new(renderer, autolink: true, tables: true, fenced_code_blocks: true)
            code_block = "```\n#{result['content']}\n```"
            html = "<div class='report-container markdown-content'>#{markdown.render(code_block)}</div>"
          when 'text'
            html = "<div class='report-container'><pre>#{result['content']}</pre></div>"
          else
            # Default handling
            html = "<div class='report-container'><p>#{result['content']}</p></div>"
          end
          
          data['html_content'] = html
          data['title'] ||= result['title'] || "Agent Result"
        else
          # Legacy/Fallback Hash handling (e.g. direct structure without 'format' wrapper)
          # Convert hash to HTML report
          html = "<div class='report-container'>"
          
          # Title
          html += "<h1>#{result['title']}</h1>" if result['title']
          
          # Executive Summary
          if result['executive_summary']
            html += "<div class='ai-insight-box'><h3>Executive Summary</h3><p>#{result['executive_summary']}</p></div>"
          end
          
          # Main Findings
          if result['main_findings'].is_a?(Array)
            html += "<h3>Main Findings</h3><ul>"
            result['main_findings'].each do |finding|
              html += "<li>#{finding}</li>"
            end
            html += "</ul>"
          elsif result['main_findings'].is_a?(String)
            html += "<h3>Main Findings</h3><p>#{result['main_findings']}</p>"
          end
          
          # Analysis
          if result['analysis']
            html += "<h3>Analysis</h3><p>#{result['analysis']}</p>"
          end
          
          # Conclusion
          if result['conclusion']
             html += "<div class='ai-recommendation'><h3>Conclusion</h3><p>#{result['conclusion']}</p></div>"
          end
          
          # Sources
          if result['sources'].is_a?(Array)
            html += "<h3>Sources</h3><ul>"
            result['sources'].each do |source|
              if source.is_a?(Hash)
                html += "<li><a href='#{source['url']}' target='_blank'>#{source['title'] || source['url']}</a></li>"
              else
                html += "<li>#{source}</li>"
              end
            end
            html += "</ul>"
          end
          
          html += "</div>"
          data['html_content'] = html
          data['title'] ||= result['title'] || "Research Report"
        end
      elsif result.is_a?(String)
         # Check for markdown content
         renderer = Redcarpet::Render::HTML.new(hard_wrap: true, filter_html: true)
         markdown = Redcarpet::Markdown.new(renderer, autolink: true, tables: true, fenced_code_blocks: true)
         
         html_content = markdown.render(result)
         data['html_content'] = "<div class='report-container markdown-content'>#{html_content}</div>"
      end
    end

    render_to_string(
      partial: "scout/canvas/dynamic_canvas",
      locals: {
        entity: current_entity,
        user: current_user,
        canvas_data: data
      }
    )
  end

  def render_freeform_canvas(data = {})
    # Freeform canvas gives AI complete creative freedom
    # Uses sandboxed iframe for security
    data = data.to_h.with_indifferent_access if data.respond_to?(:to_h)

    render_to_string(
      partial: "scout/canvas/freeform_canvas",
      locals: {
        canvas_data: data
      }
    )
  end

  def render_interactive_wizard(data = {})
    # Convert ActionController::Parameters to hash recursively
    if data.is_a?(ActionController::Parameters)
      data = JSON.parse(data.to_json).with_indifferent_access
    end

    render_to_string(
      partial: "scout/canvas/interactive_wizard",
      locals: {
        entity: current_entity,
        user: current_user,
        canvas_data: data,
        step: data[:step],
        form: data[:form],
        progress: data[:progress]
      }
    )
  end

  def determine_wizard_title(canvas_data)
    step = canvas_data[:step]
    progress = canvas_data[:progress]

    if step && step[:config] && step[:config][:title]
      step[:config][:title]
    elsif progress && progress[:workflow_type]
      case progress[:workflow_type]
      when "landing_page_creation"
        "Landing Page Wizard"
      when "campaign_creation"
        "Campaign Wizard"
      else
        "Interactive Wizard"
      end
    else
      "Interactive Wizard"
    end
  end

  def render_form_submissions_canvas(data = {})
    # Load form submissions data
    submissions_data = load_form_submissions_data(data)

    render_to_string(
      partial: "scout/canvas/form_submissions",
      locals: {
        entity: current_entity,
        user: current_user,
        canvas_data: submissions_data
      }
    )
  end

  def load_form_submissions_data(filters = {})
    # Base query for submissions from user's landing pages
    base_query = LandingPageSubmission.joins(:landing_page)
                                      .where(landing_pages: { user: current_user, entity: current_entity })
                                      .includes(:contact, :landing_page)

    # Apply filters
    if filters[:landing_page_id]
      base_query = base_query.where(landing_page_id: filters[:landing_page_id])
    end

    if filters[:form_type].present?
      base_query = base_query.where(form_type: filters[:form_type])
    end

    if filters[:status].present?
      base_query = base_query.where(status: filters[:status])
    end

    case filters[:time_range]
    when "today"
      base_query = base_query.today
    when "week"
      base_query = base_query.this_week
    when "month"
      base_query = base_query.this_month
    end

    # Get submissions with pagination
    submissions = base_query.recent.limit(50)

    # Calculate stats
    stats = calculate_submission_stats(base_query)

    # Format submissions for display
    formatted_submissions = submissions.map do |submission|
      {
        id: submission.id,
        form_type: submission.form_type,
        status: submission.status,
        submitted_at: submission.submitted_at.iso8601,
        processed_at: submission.processed_at&.iso8601,
        contact_info: submission.contact_info,
        utm_params: submission.utm_params,
        source_ip: submission.source_ip,
        referrer: submission.referrer,
        landing_page: {
          id: submission.landing_page.id,
          title: submission.landing_page.title,
          slug: submission.landing_page.slug
        },
        submission_data: submission.submission_data
      }
    end

    {
      submissions: formatted_submissions,
      stats: stats,
      landing_page: filters[:landing_page_id] ?
        LandingPage.find_by(id: filters[:landing_page_id], user: current_user) : nil,
      pagination: {
        current_count: formatted_submissions.length,
        total_count: base_query.count,
        has_previous: false, # TODO: Implement pagination
        has_next: formatted_submissions.length >= 50
      }
    }
  end

  def calculate_submission_stats(base_query)
    total = base_query.count
    processed = base_query.where(status: [ "processed", "duplicate" ]).count
    pending = base_query.where(status: "pending").count
    failed = base_query.where(status: "failed").count
    spam = base_query.where(status: "spam").count

    conversion_rate = total > 0 ? (processed.to_f / total * 100).round(1) : 0.0

    {
      total: total,
      processed: processed,
      pending: pending,
      failed: failed,
      spam: spam,
      conversion_rate: conversion_rate
    }
  end

  def render_workflow_analytics_canvas(data = {})
    # Load analytics data
    analytics_data = load_workflow_analytics_data(data)

    render_to_string(
      partial: "scout/canvas/workflow_analytics",
      locals: {
        entity: current_entity,
        user: current_user,
        canvas_data: analytics_data
      }
    )
  end

  def load_workflow_analytics_data(options = {})
    period = (options[:period] || 30).to_i.days

    # Get analytics from ObservabilityService
    observability = ObservabilityService.instance

    {
      workflow_analytics: observability.workflow_analytics(period),
      tool_analytics: observability.tool_analytics(period),
      user_analytics: observability.user_analytics(period),
      ai_metrics: observability.ai_metrics(period),
      performance_metrics: observability.performance_metrics(period),
      period_days: period.to_i / 1.day,
      generated_at: Time.current
    }
  end

  def render_task_progress(data = {})
    # Handle both symbol and string keys
    data = data.with_indifferent_access if data.is_a?(Hash)

    # If we have progress data from workflow, use it
    if data[:progress] && !data[:tasks]
      Rails.logger.info "📋 Converting workflow progress to task list format"
      # Use the task_session_id if provided
      if data[:task_session_id]
        task_session = TaskSession.find_by(id: data[:task_session_id])
        if task_session
          workflow_engine = WorkflowEngine.new(task_session)
          workflow_progress = workflow_engine.progress
          workflow = workflow_engine.instance_variable_get(:@workflow)

          data = {
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
    end

    # If no data provided, try to load from TaskSession
    # Skip loading if we have workflow approval data
    if (data.empty? || data.nil? || data[:tasks].nil?) && !data[:awaiting_approval] && !data["awaiting_approval"]
      session_id = session[:scout_session_id]

      # If we have a specific task_session_id, load that regardless of status
      if data[:task_session_id] || data["task_session_id"]
        task_session_id = data[:task_session_id] || data["task_session_id"]
        task_session = TaskSession.where(user: current_user, id: task_session_id).first
      else
        # Try to find active task session
        task_session = TaskSession.active
                                 .where(user: current_user)
                                 .where("metadata->>'session_id' = ?", session_id)
                                 .first
      end

      if task_session
        # Check if we have a task list in state
        if task_session.state&.dig("task_list")
          data = task_session.state["task_list"]
          Rails.logger.info "📋 Loaded task list from TaskSession state: #{data[:tasks]&.size} tasks"
        elsif task_session.workflow_spec
          # Convert workflow to task list format for display with proper state restoration
          workflow_engine = WorkflowEngine.new(task_session)
          workflow_progress = workflow_engine.progress

          # Get workflow instance to access steps
          workflow = workflow_engine.instance_variable_get(:@workflow)

          # Try to get workflow execution for accurate step statuses
          workflow_execution = task_session.workflow_execution

          data = {
            tasks: workflow.steps.map do |step|
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
            end,
            workflow_status: workflow_progress[:status],
            progress: workflow_progress
          }
          Rails.logger.info "📋 Loaded task list from TaskSession workflow: #{data[:tasks]&.size} tasks"
        else
          Rails.logger.info "📋 TaskSession found but no task list or workflow"
          data = { tasks: [] }
        end
      else
        Rails.logger.info "📋 No active task session found for session: #{session_id}"
        data = { tasks: [] }
      end
    else
      Rails.logger.info "📋 Using provided task data: #{data[:tasks]&.size} tasks"
    end

    # Check if this is a workflow approval
    if data[:awaiting_approval] || data["awaiting_approval"]
      render_to_string(
        partial: "scout/canvas/workflow_approval",
        locals: {
          entity: current_entity,
          user: current_user,
          data: data
        }
      )
    else
      render_to_string(
        partial: "scout/canvas/task_progress",
        locals: {
          entity: current_entity,
          user: current_user,
          task_list: data
        }
      )
    end
  end

  def render_integrations_manager(data = {})
    render_to_string(partial: "scout/canvas/integrations_manager", locals: { canvas_data: data })
  end

  def render_integration_connect(data = {})
    render_to_string(partial: "scout/canvas/integration_connect", locals: { canvas_data: data })
  end

  def render_integration_operations(data = {})
    render_to_string(partial: "scout/canvas/integration_operations", locals: { canvas_data: data })
  end

  def render_campaign_editor(data = {})
    # Load campaign if ID provided
    campaign = if data[:campaign_id]
      current_entity.campaigns.find_by(id: data[:campaign_id])
    else
      current_entity.campaigns.build
    end

    # Load contact groups and email templates
    contact_groups = current_entity.contact_groups.active
    email_templates = current_entity.email_templates

    render_to_string(
      partial: "scout/canvas/campaign_editor",
      locals: {
        campaign: campaign,
        contact_groups: contact_groups,
        email_templates: email_templates,
        entity: current_entity,
        user: current_user,
        data: data
      }
    )
  end

  private

  def should_use_parallel_processing?(message, attached_files = [])
    # Determine if request is complex enough for parallel processing
    return true if attached_files.present? && attached_files.length > 1  # Changed from > 2 to > 1
    
    # Voice mode always uses parallel for immediate response
    return true if params[:voice_mode] == 'true'
    
    # Workflows will be detected by the AI and handled through parallel processing automatically
    # No need to duplicate pattern matching here
    
    # Check for multi-part requests - more inclusive patterns
    return true if message.match?(/\band\s+(also|then)/i)  # "and also", "and then"
    return true if message.match?(/\b(both|multiple|several)\b/i)
    return true if message.match?(/(pull|fetch|get|show|give).*\band.*?(overview|summary|list|analyze)/i)
    return true if message.match?(/analyze.*schedule|schedule.*analyze/i)
    return true if message.match?(/compare.*create|create.*compare/i)
    return true if message.scan(/\?/).count > 1  # Changed from > 2 to > 1
    
    # Check for lists of items
    return true if message.match?(/\b(first|second|third|1\.|2\.|3\.)\b/i)
    
    # Check for specific complex patterns
    complex_patterns = [
      /analyze.*campaigns?.*(?:and|then|also|plus).*(?:schedule|create|send|give|show)/i,
      /(?:gather|collect|compile|pull|fetch).*data.*(?:and|then|also).*(?:report|analyze|overview)/i,
      /research.*market.*(?:and|then).*(?:create|draft)/i,
      /(top|best|highest).*\d+.*(?:and|also|plus).*(?:overview|summary|analyze)/i,  # "top 10 X and also Y"
      /\w+\s+(?:and|&)\s+\w+/i  # Simple "X and Y" pattern
    ]
    
    is_complex = complex_patterns.any? { |pattern| message.match?(pattern) }
    
    # Log decision for debugging
    if is_complex
      Rails.logger.info "🚀 Parallel processing triggered for: #{message[0..100]}..."
    else
      Rails.logger.info "🔄 Sequential processing for: #{message[0..100]}..."
      Rails.logger.info "Patterns checked: attached_files=#{attached_files.length}, and/also=#{message.match?(/\band\s+(also|then)/i)}, pull/and=#{message.match?(/(pull|fetch|get|show|give).*\band.*?(overview|summary|list|analyze)/i)}"
    end
    
    is_complex
  end
  
  def stream_voice_task_progress(tasks)
    tasks.each do |task|
      next if task.task_type == 'voice_immediate' # Already handled
      
      # Stream progress updates for background tasks
      stream_update({
        type: 'task_progress',
        task_id: task.id,
        task_type: task.task_type,
        description: task.metadata['description'],
        status: 'queued'
      })
    end
  end
  
  
  def get_recent_history(limit = 5)
    ScoutConversation.for_session(@session_id)
                     .recent
                     .limit(limit)
                     .map(&:to_ai_message)
  end
  
  def extract_response_sources(tools_used)
    # Extract source information from tools_used array
    # Specifically looks for read_document tool calls which indicate RAG/document sources
    return [] unless tools_used.is_a?(Array)

    sources = []

    tools_used.each do |tool|
      # Handle different tool format variations
      tool_name = case tool
                  when Hash
                    tool[:name] || tool['name']
                  when String
                    tool
                  else
                    nil
                  end

      next unless tool_name

      # If read_document tool was used, mark as document source
      if tool_name.to_s.include?('read_document')
        sources << {
          type: 'documents',
          count: 1
        }
      end
    end

    # Remove duplicates and return
    sources.uniq { |s| s[:type] }
  end

  def calculate_document_status(asset)
    # Find RagStore and RagDocument for this asset
    rag_stores = current_entity.rag_stores
    rag_document = rag_stores
      .joins(:rag_documents)
      .where("rag_documents.original_filename LIKE ?", "%#{asset.title}%")
      .first&.rag_documents&.first

    if rag_document.nil?
      # Document uploaded but not yet indexed
      return {
        status: "pending",
        asset_id: asset.id,
        title: asset.title,
        stage: 0,
        total_stages: 4,
        message: "Document uploaded but not yet indexed",
        ready_for_chat: false
      }
    end

    # Get processing jobs for this RAG document
    processing_jobs = RagProcessingJob.joins(:rag_store)
      .where(rag_stores: { id: rag_document.rag_store_id })
      .order(created_at: :desc)

    # Determine current stage and status
    status_response = {
      asset_id: asset.id,
      title: asset.title,
      rag_document_id: rag_document.id
    }

    # Check embedding status first (final stage)
    embedding_job = processing_jobs.where(job_type: "embedding_batch").first

    if embedding_job&.status_completed?
      # Fully indexed and ready for chat
      embedded_count = rag_document.embedded_chunks_count
      total_chunks = rag_document.chunks_count

      status_response.merge!(
        status: "complete",
        stage: 4,
        total_stages: 4,
        message: "Ready to use in chat",
        ready_for_chat: true,
        embedded_chunks: embedded_count,
        total_chunks: total_chunks,
        progress_percent: (total_chunks.zero? ? 0 : (embedded_count.to_f / total_chunks * 100).round(1))
      )
    elsif embedding_job&.status_processing?
      # Embedding in progress
      embedded_count = rag_document.embedded_chunks_count
      total_chunks = rag_document.chunks_count

      status_response.merge!(
        status: "embedding",
        stage: 4,
        total_stages: 4,
        message: "Generating embeddings... #{embedded_count}/#{total_chunks} complete",
        ready_for_chat: false,
        embedded_chunks: embedded_count,
        total_chunks: total_chunks,
        progress_percent: (total_chunks.zero? ? 0 : (embedded_count.to_f / total_chunks * 100).round(1))
      )
    elsif embedding_job&.status_failed?
      # Embedding failed
      status_response.merge!(
        status: "embedding_failed",
        stage: 4,
        total_stages: 4,
        message: "Embedding generation failed",
        ready_for_chat: false,
        error: embedding_job.error_message
      )
    else
      # Check chunking status
      chunking_job = processing_jobs.where(job_type: "chunking").first

      if chunking_job&.status_completed?
        total_chunks = rag_document.chunks_count
        status_response.merge!(
          status: "chunking_complete",
          stage: 3,
          total_stages: 4,
          message: "Chunking complete (#{total_chunks} chunks), generating embeddings...",
          ready_for_chat: false,
          total_chunks: total_chunks
        )
      elsif chunking_job&.status_processing?
        status_response.merge!(
          status: "chunking",
          stage: 3,
          total_stages: 4,
          message: "Breaking document into chunks...",
          ready_for_chat: false
        )
      elsif chunking_job&.status_failed?
        status_response.merge!(
          status: "chunking_failed",
          stage: 3,
          total_stages: 4,
          message: "Chunking failed",
          ready_for_chat: false,
          error: chunking_job.error_message
        )
      else
        # Check docling status
        docling_job = processing_jobs.where(job_type: "docling_extraction").first

        if docling_job&.status_completed?
          status_response.merge!(
            status: "extraction_complete",
            stage: 2,
            total_stages: 4,
            message: "Text extraction complete, processing chunks...",
            ready_for_chat: false
          )
        elsif docling_job&.status_processing?
          status_response.merge!(
            status: "extracting",
            stage: 2,
            total_stages: 4,
            message: "Extracting text from document...",
            ready_for_chat: false
          )
        elsif docling_job&.status_failed?
          status_response.merge!(
            status: "extraction_failed",
            stage: 2,
            total_stages: 4,
            message: "Text extraction failed",
            ready_for_chat: false,
            error: docling_job.error_message
          )
        else
          # Check pipeline status
          pipeline_job = processing_jobs.where(job_type: "pipeline").first || processing_jobs.where(job_type: "document_pipeline").first

          if pipeline_job&.status_completed?
            status_response.merge!(
              status: "pipeline_complete",
              stage: 1,
              total_stages: 4,
              message: "Queued for text extraction...",
              ready_for_chat: false
            )
          elsif pipeline_job&.status_processing?
            status_response.merge!(
              status: "uploading",
              stage: 1,
              total_stages: 4,
              message: "Uploading document to storage...",
              ready_for_chat: false
            )
          elsif pipeline_job&.status_failed?
            status_response.merge!(
              status: "upload_failed",
              stage: 1,
              total_stages: 4,
              message: "Upload failed",
              ready_for_chat: false,
              error: pipeline_job.error_message
            )
          else
            status_response.merge!(
              status: "pending",
              stage: 0,
              total_stages: 4,
              message: "Waiting to be processed...",
              ready_for_chat: false
            )
          end
        end
      end
    end

    status_response
  end
  
  # Search documents for Scout
  def search_documents(query)
    return [] if query.blank?
    
    service = DocumentSearchService.new(current_entity)
    results = service.search(query: query, filters: {})
    
    # Format results for Scout
    results[:documents].map do |doc|
      {
        id: doc.id,
        title: doc.display_title,
        content_preview: doc.summary || doc.extracted_text&.truncate(200),
        url: document_path(doc),
        type: doc.rag_store.name,
        relevance_score: results[:search_type] == 'semantic' ? 'high' : 'medium'
      }
    end
  end
  
  # Search image assets
  def search_images(query)
    return [] if query.blank?
    
    images = current_entity.image_assets
                          .where("title ILIKE :query OR description ILIKE :query", query: "%#{query}%")
                          .limit(10)
                          
    images.map do |img|
      {
        id: img.id,
        title: img.title,
        url: rails_blob_url(img.file),
        thumbnail_url: rails_blob_url(img.file.variant(resize_to_fit: [200, 200])),
        type: 'image'
      }
    end
  end

  private

  def image_file?(file)
    %w[image/jpeg image/jpg image/png image/gif image/webp image/svg+xml].include?(file.content_type)
  end
  
  def handle_image_upload(file)
    # Create ImageAsset for images
    image_asset = ImageAsset.create!(
      entity: current_entity,
      user: current_user,
      title: file.original_filename,
      file: file,
      source: "upload"  # Valid values: upload, ai, placeholder
    )

    {
      url: rails_blob_url(image_asset.file),
      filename: file.original_filename,
      content_type: file.content_type,
      size: file.size,
      asset_id: image_asset.id,
      asset_type: 'image'
    }
  end
  
  def handle_document_upload(file)
    # Find or create Scout collection
    rag_store = current_entity.rag_stores.find_or_create_by!(
      name: "Scout Chat Documents",
      app_name: "scout",
      store_type: "entity"
    ) do |store|
      store.status = "active"
      store.user = current_user
    end
    
    # Calculate file hash for duplicate detection
    file_hash = Digest::SHA256.hexdigest(file.read)
    file.rewind # Important: rewind after reading
    
    Rails.logger.info "Calculated file hash: #{file_hash}"
    
    # Check for existing document with same hash
    existing_doc = rag_store.rag_documents.find_by(file_hash: file_hash)
    if existing_doc
      Rails.logger.info "Found existing document with same hash: #{existing_doc.id}"
      # Return existing document info
      return {
        url: rails_blob_url(existing_doc.file),
        filename: existing_doc.original_filename,
        content_type: existing_doc.content_type,
        size: existing_doc.file_size_bytes,
        asset_id: existing_doc.id,
        asset_type: 'document',
        processing: existing_doc.processing_status == 'processing',
        duplicate: true
      }
    end
    
    # Create document with immediate processing
    rag_document = rag_store.rag_documents.create!(
      original_filename: file.original_filename,
      content_type: file.content_type,
      file_size_bytes: file.size,
      file_hash: file_hash,
      processing_status: 'processing'
    )
    
    # Attach file and process
    rag_document.file.attach(file)
    
    # Queue document processing
    Rag::DocumentPipelineJob.perform_later(rag_document.id, auto_categorize: true)
    
    {
      url: rails_blob_url(rag_document.file),
      filename: file.original_filename,
      content_type: file.content_type,
      size: file.size,
      asset_id: rag_document.id,
      asset_type: 'document',
      processing: true
    }
  end
  
  def handle_temporary_upload(file)
    # Create a temporary RagDocument in a dedicated temporary store
    # This ensures the document can be found via read_document tool
    # and will be cleaned up after 24 hours
    
    # Find or create a temporary documents store for this entity
    temp_store = current_entity.rag_stores.find_or_create_by!(
      name: "Temporary Chat Documents",
      app_name: "scout_temp",
      store_type: "entity"
    ) do |store|
      store.status = "active"
      store.user = current_user
    end
    
    # Calculate file hash for duplicate detection
    file_hash = Digest::SHA256.hexdigest(file.read)
    file.rewind
    
    # Create temporary document with expiry metadata
    rag_document = temp_store.rag_documents.create!(
      original_filename: file.original_filename,
      content_type: file.content_type,
      file_size_bytes: file.size,
      file_hash: file_hash,
      processing_status: 'ready', # Temporary docs skip RAG indexing
      metadata: {
        temporary: true,
        expires_at: 24.hours.from_now.iso8601,
        session_id: session[:scout_session_id]
      }
    )
    
    # Attach the file
    rag_document.file.attach(file)
    
    Rails.logger.info "📎 Created temporary document: #{rag_document.id} - #{file.original_filename}"
    
    {
      url: rails_blob_url(rag_document.file),
      filename: file.original_filename,
      content_type: file.content_type,
      size: file.size,
      temporary: true,
      asset_id: rag_document.id,
      asset_type: 'document'  # Use 'document' so read_document tool can find it
    }
  end
  
  # ===== AMOS INTEGRATION METHODS =====
  
  def initialize_amos_orchestrator
    # Create or retrieve Amos orchestrator for this session
    # Pass the actual request host so callbacks work correctly
    # Pass fresh_start_at to filter out old messages from before "Fresh Start"
    fresh_start_time = session[:scout_fresh_start_at].present? ? 
      (Time.parse(session[:scout_fresh_start_at]) rescue nil) : nil
    
    Amos::Orchestrator.new(current_user, current_entity, @session_id, 
      request_host: request.host_with_port,
      fresh_start_at: fresh_start_time
    )
  end
  
  def setup_amos_streaming
    # Set up a callback to stream Amos responses back through SSE
    @orchestrator.on_stream do |response|
      case response[:type]
      when 'assistant_message', 'amos_response'
        # Only stream if this is a streaming chunk, not the complete message
        # Complete messages are handled by ActionCable separately
        if response[:metadata]&.dig(:streaming)
          Rails.logger.debug "[Scout SSE] Streaming chunk to frontend: #{response[:content][0..20]}..."
          stream_update(response[:content])
          
          # Chunks are now properly paced at the source
          # No additional delay needed here
        elsif response[:metadata]&.dig(:complete)
          # Complete message - just save it, don't stream it
          # The UI already has this content from streaming chunks
          save_scout_message("assistant", response[:content])
        elsif !response[:metadata]&.dig(:streaming) && !response[:metadata]&.dig(:already_saved)
          # Non-streaming message (like delegation acknowledgments)
          stream_update(response[:content])
          save_scout_message("assistant", response[:content])
        end
        
      when 'job_status'
        # Stream job status updates
        stream_update({
          type: 'job_status',
          job_id: response[:job_id],
          status: response[:status],
          message: response[:message],
          progress: response[:progress]
        })
        
      when 'input_request'
        # Handle input requests from agents
        stream_update({
          type: 'input_request',
          job_id: response[:job_id],
          prompt: response[:prompt],
          options: response[:options]
        })
        
      when 'canvas_update'
        # Handle canvas updates
        stream_update({
          type: 'load_canvas',
          canvas: response[:canvas],
          canvas_data: response[:canvas_data]
        })
        
      when 'error'
        # Stream errors
        stream_update("❌ #{response[:message]}")
      end
    end
  end
  
    def process_through_amos(message, file_urls, canvas, model_preference)
      # Build metadata for Amos - ensure canvas is a regular hash
      canvas_hash = if canvas.is_a?(ActionController::Parameters)
                      canvas.permit!.to_h
                    elsif canvas.respond_to?(:to_h)
                      canvas.to_h
                    else
                      canvas || {}
                    end
      
      # Get model mode from session (set by slider: auto/fast/balanced/powerful)
      current_model_mode = session[:model_mode]&.to_sym || :auto
      
      metadata = {
        attached_files: file_urls,
        canvas: canvas_hash,
        model_preference: model_preference, # nil when using slider mode
        model_mode: current_model_mode,     # The slider mode
        voice_mode: params[:voice_mode] == 'true'
      }
      
      Rails.logger.info "[Scout] Model selection - explicit: #{model_preference.inspect}, mode: #{current_model_mode}"
    
    # Build enhanced message if files are attached
    enhanced_message = message
    if file_urls.any?
      Rails.logger.info "🔍 AMOS file_urls: #{file_urls.inspect}"
      # Include asset_id so AMOS can use read_document tool
      file_details = file_urls.map do |f|
        # Support both asset_id and document_id for backward compatibility
        id = f['asset_id'] || f['document_id']
        asset_type = f['asset_type'] || 'image' # Default to image for backward compatibility
        processing_note = f['processing'] ? " - PROCESSING" : ""
        "📎 #{f['filename']} (asset_id: #{id}, asset_type: #{asset_type}, type: #{f['content_type']}#{processing_note})"
      end.join(", ")

      enhanced_message = "#{message}\n\n[Attached Files: #{file_details}]\n\nIMPORTANT: Use the read_document tool with the asset_id AND asset_type to extract content from these files before responding. If a document shows PROCESSING, it may still be extracting content."
      metadata[:file_urls] = file_urls
    end
    
    # Save enhanced user message
    save_scout_message("user", enhanced_message)
    
    # Process through Amos with enhanced message
    @orchestrator.process_message(enhanced_message, source: :user, metadata: metadata)
    
    # Wait for Amos to complete processing
    wait_for_amos_completion
    
  rescue => e
    Rails.logger.error "[Scout] Amos processing error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    stream_update("❌ An error occurred while processing your request. Please try again.")
  end
  
  def wait_for_amos_completion
    # Keep the connection alive while Amos processes
    # This replaces the complex parallel processing logic
    timeout = 5.minutes
    start_time = Time.current
    
    loop do
      # Check if all jobs are complete
      active_jobs = @orchestrator.query_job_status.select { |j| 
        j[:status][:status].in?(['queued', 'running', 'waiting_for_input'])
      }
      
      break if active_jobs.empty?
      
      # Check timeout
      if Time.current - start_time > timeout
        Rails.logger.warn "[Scout] Amos processing timeout after #{timeout}"
        stream_update("⏱️ Processing is taking longer than expected. Tasks will continue in the background.")
        break
      end
      
      # Send keepalive
      response.stream.write(":\n\n") rescue nil
      
      sleep 0.5
    end
  end
  
  # ===== END AMOS INTEGRATION =====

  # ===== AMOS SPACES =====
  public  # Make these actions accessible as routes

  # POST /scout/switch_space
  def switch_space
    space_slug = params[:space]&.to_s
    
    # Map legacy space names to new 3-mode architecture
    space_slug = case space_slug
                 when 'work', 'team' then 'operations'
                 else space_slug
                 end

    # Validate against enabled spaces
    valid_spaces = SpaceDefinition.enabled.pluck(:slug)
    unless valid_spaces.include?(space_slug)
      render json: { success: false, error: "Invalid space: #{space_slug}" }, status: :unprocessable_entity
      return
    end

    space_pref = current_user.space_preference || current_user.build_space_preference
    
    # Enable the space if not already enabled (user clicked on it, so they want it)
    unless space_pref.space_enabled?(space_slug)
      space_pref.enable_space(space_slug)
    end

    if space_pref.switch_to(space_slug)
      space_def = SpaceDefinition.find_by(slug: space_slug)
      
      # Determine if sidebar should be shown based on new mode
      show_sidebar = space_slug.in?(['operations', 'design'])
      
      render json: {
        success: true,
        space: space_slug,
        name: space_def&.name,
        tool_loadout: space_def&.tool_loadout,
        show_collab_sidebar: show_sidebar
      }
    else
      render json: { success: false, error: "Failed to switch space" }, status: :unprocessable_entity
    end
  end

  # ===== CONVERSATION SEARCH =====
  
  # Search across all conversation history (Amos + agents)
  def search_history
    query = params[:q].to_s.strip
    
    if query.length < 2
      render json: { success: false, error: "Query too short" }, status: :unprocessable_entity
      return
    end
    
    # Search in ConversationLog for this user
    results = ConversationLog
                .where(entity: current_entity)
                .where("content ILIKE ?", "%#{query}%")
                .order(created_at: :desc)
                .limit(20)
                .map do |log|
      {
        id: log.id,
        role: log.role,
        content: log.content.to_s.truncate(200),
        agent_name: log.agent_name,
        session_id: log.session_id,
        created_at: log.created_at,
        time_ago: time_ago_in_words(log.created_at) + ' ago'
      }
    end
    
    render json: { success: true, results: results, query: query }
  rescue => e
    Rails.logger.error "Search error: #{e.message}"
    render json: { success: false, error: "Search failed" }, status: :internal_server_error
  end
  
  # ===== AGENT QUESTIONS (Sidebar Integration) =====
  
  # Get pending questions for a specific agent
  def agent_questions
    agent_id = params[:agent_id]
    
    # Use same query logic as index action for consistency
    questions = AgentInputRequest
                  .joins(agent_plugin_execution: :agent_plugin)
                  .where(agent_plugin_executions: { 
                    user: current_user,
                    status: 'waiting_for_input',
                    agent_plugin_id: agent_id
                  })
                  .where(status: 'pending')
                  .order(priority: :desc, created_at: :asc)
    
    render json: {
      success: true,
      agent_id: agent_id,
      questions: questions.map do |q|
        execution = q.agent_plugin_execution
        {
          id: q.id,
          question: q.question,
          variable_name: q.variable_name,
          context: q.context_data,
          priority: q.priority > 7 ? 'high' : 'normal',
          execution_id: execution&.id,
          agent_name: execution&.agent_plugin&.name || q.agent_name,
          created_at: q.created_at,
          time_ago: time_ago_in_words(q.created_at) + ' ago'
        }
      end
    }
  end
  
  # Answer a pending agent question
  def answer_agent_question
    question_id = params[:question_id]
    answer = params[:answer]
    
    input_request = AgentInputRequest.find_by(id: question_id)
    
    unless input_request
      render json: { success: false, error: "Question not found" }, status: :not_found
      return
    end
    
    # Verify ownership
    unless input_request.agent_plugin_execution&.user_id == current_user.id
      render json: { success: false, error: "Unauthorized" }, status: :unauthorized
      return
    end
    
    begin
      # Mark the input request as answered
      input_request.update!(
        response: answer,
        status: 'answered',
        answered_at: Time.current
      )
      
      # Resume the execution
      execution = input_request.agent_plugin_execution
      if execution
        execution.update!(status: 'running')
        
        # Enqueue the job to continue execution with the answer
        AgentContinueJob.perform_async(
          execution.id,
          input_request.variable_name,
          answer
        )
      end
      
      # Mark related work items as read
      AgentWorkItem.where(
        agent_plugin_execution: execution,
        requires_action: true
      ).update_all(
        read: true,
        read_at: Time.current,
        requires_action: false
      )
      
      render json: {
        success: true,
        message: "Answer sent successfully",
        execution_status: execution&.status
      }
    rescue => e
      Rails.logger.error "Error answering agent question: #{e.message}"
      render json: { success: false, error: e.message }, status: :unprocessable_entity
    end
  end
  
  # Skip a pending agent question
  def skip_agent_question
    question_id = params[:question_id]
    
    input_request = AgentInputRequest.find_by(id: question_id)
    
    unless input_request
      render json: { success: false, error: "Question not found" }, status: :not_found
      return
    end
    
    # Verify ownership
    unless input_request.agent_plugin_execution&.user_id == current_user.id
      render json: { success: false, error: "Unauthorized" }, status: :unauthorized
      return
    end
    
    begin
      # Mark as skipped
      input_request.update!(
        status: 'skipped',
        skipped_at: Time.current
      )
      
      # Mark related work items as read
      execution = input_request.agent_plugin_execution
      AgentWorkItem.where(
        agent_plugin_execution: execution,
        requires_action: true
      ).update_all(
        read: true,
        read_at: Time.current,
        requires_action: false
      )
      
      render json: {
        success: true,
        message: "Question skipped"
      }
    rescue => e
      Rails.logger.error "Error skipping agent question: #{e.message}"
      render json: { success: false, error: e.message }, status: :unprocessable_entity
    end
  end
  
  # ===== END AMOS SPACES =====

  # ===== EXECUTION DASHBOARD HELPERS =====
  private

  def load_execution_dashboard_data
    entity = current_entity

    # Active plans (executing or paused)
    active_plans = ExecutionPlan.where(entity: entity)
      .where(status: %w[executing paused])
      .order(created_at: :desc)
      .limit(10)

    # Pending plans (ready or planning, awaiting action)
    pending_plans = ExecutionPlan.where(entity: entity)
      .where(status: %w[ready planning])
      .order(created_at: :desc)
      .limit(10)

    # Agent activity - find running executions
    agent_activity = AgentPluginExecution.includes(:agent_plugin)
      .where(status: 'running')
      .where('created_at > ?', 1.hour.ago)
      .order(created_at: :desc)
      .limit(10)
      .map do |exec|
        step_info = extract_step_info_from_execution(exec)
        {
          agent_name: exec.agent_plugin&.name || 'Unknown Agent',
          status: 'running',
          task: exec.result_summary&.truncate(50) || step_info[:task] || 'Processing...',
          plan_id: step_info[:plan_id],
          started_at: exec.created_at
        }
      end

    # Add idle agents
    active_agents = AgentPlugin.where(status: 'active').limit(20)
    running_agent_ids = agent_activity.map { |a| a[:agent_name] }
    
    idle_agents = active_agents.reject { |a| running_agent_ids.include?(a.name) }.first(5).map do |agent|
      {
        agent_name: agent.name,
        status: 'idle',
        task: nil,
        plan_id: nil
      }
    end
    
    agent_activity = agent_activity + idle_agents

    # Recent completions - completed steps from plans
    recent_completions = gather_recent_completions(entity)

    {
      active_plans: active_plans,
      pending_plans: pending_plans,
      agent_activity: agent_activity,
      recent_completions: recent_completions
    }
  end

  def load_plan_details_data(canvas_data)
    plan_id = canvas_data&.dig('plan_id') || canvas_data&.dig(:plan_id)
    plan = ExecutionPlan.find_by(id: plan_id, entity: current_entity)

    {
      plan: plan,
      phases: plan&.phases || [],
      validation: plan ? PlannerService.new(entity: current_entity, user: current_user).validate_plan(plan) : nil
    }
  end

  def load_module_design_data(canvas_data)
    template_key = canvas_data&.dig('template_key') || canvas_data&.dig(:template_key)
    plan_id = canvas_data&.dig('plan_id') || canvas_data&.dig(:plan_id)
    session_id = canvas_data&.dig('session_id') || canvas_data&.dig(:session_id)
    direct_design = canvas_data&.dig('design') || canvas_data&.dig(:design)
    
    # Priority: 1) Direct design data, 2) Session-based design, 3) Template-based design
    design = if direct_design
      # Design passed directly from propose_module_schema tool
      symbolize_keys_deep(direct_design)
    elsif session_id
      # Load from ModuleDesignSession
      build_design_from_session(session_id)
    else
      # Fallback to template-based design
      build_design_from_template(template_key)
    end
    
    {
      design: design,
      template_key: template_key,
      plan_id: plan_id,
      session_id: session_id
    }
  end
  
  def build_design_from_session(session_id)
    session = ModuleDesignSession.find_by(id: session_id, entity_id: current_entity.id)
    return nil unless session
    
    proposed = session.proposed_schema || {}
    fields = proposed['fields'] || []
    views = proposed['suggested_views'] || %w[list form detail]
    
    {
      name: proposed['module_name'] || session.module_name,
      description: proposed['description'] || "Custom module for #{session.module_name}",
      session_id: session.id,
      models: [
        {
          name: (proposed['module_name'] || session.module_name).to_s.singularize.classify,
          description: proposed['description'],
          fields: fields.map do |f|
            {
              name: f['name'],
              type: f['field_type'] || f['type'],
              field_type: f['field_type'] || f['type'],
              required: f['required'] || false,
              description: f['description']
            }
          end
        }
      ],
      views: views.map do |v|
        case v.to_s.downcase
        when 'list', 'data_grid'
          { name: 'List View', description: 'See all records with search and filters' }
        when 'form'
          { name: 'Add/Edit Form', description: 'Add and edit records easily' }
        when 'detail'
          { name: 'Detail View', description: 'See full information for any record' }
        when 'dashboard'
          { name: 'Dashboard', description: 'Overview with stats and charts' }
        else
          { name: v.to_s.titleize, description: nil }
        end
      end,
      features: [
        "Track #{fields.count} different pieces of information",
        "Full search and filtering capabilities",
        "Export data to CSV/Excel",
        "Mobile-friendly interface",
        "AI-powered assistance",
        "Secure, multi-tenant data storage"
      ],
      ai_capabilities: [
        "Create new #{session.module_name&.downcase || 'records'}",
        "Search and filter your data",
        "Generate reports and analytics",
        "Answer questions about your #{session.module_name&.downcase || 'data'}",
        "Help with data entry and updates",
        "Set up automations and alerts"
      ]
    }
  end
  
  def symbolize_keys_deep(obj)
    case obj
    when Hash
      obj.map { |k, v| [k.to_sym, symbolize_keys_deep(v)] }.to_h
    when Array
      obj.map { |v| symbolize_keys_deep(v) }
    else
      obj
    end
  end

  def build_design_from_template(template_key)
    return nil unless template_key
    
    installer = Modules::TemplateInstaller.new(entity: current_entity, user: current_user)
    template = Modules::TemplateInstaller::TEMPLATES[template_key]
    return nil unless template
    
    # Build a user-friendly design structure
    {
      name: template[:name],
      description: template[:description],
      icon: template[:icon],
      features: template[:features],
      models: build_models_from_template(template_key),
      views: build_views_from_template(template_key, template),
      ai_capabilities: build_ai_capabilities(template_key, template)
    }
  end

  def build_models_from_template(template_key)
    case template_key
    when 'inventory_management'
      [
        {
          name: 'Category',
          description: 'Organize products into categories',
          fields: [
            { name: 'name', type: 'string', required: true, description: 'Category name' },
            { name: 'description', type: 'text', required: false, description: 'Category description' }
          ]
        },
        {
          name: 'Supplier',
          description: 'Track supplier information',
          fields: [
            { name: 'name', type: 'string', required: true, description: 'Supplier company name' },
            { name: 'contact_name', type: 'string', required: false, description: 'Primary contact person' },
            { name: 'email', type: 'string', required: false, description: 'Contact email' },
            { name: 'phone', type: 'string', required: false, description: 'Phone number' }
          ]
        },
        {
          name: 'Product',
          description: 'Your inventory items',
          fields: [
            { name: 'name', type: 'string', required: true, description: 'Product name' },
            { name: 'sku', type: 'string', required: true, description: 'Stock Keeping Unit (unique identifier)' },
            { name: 'description', type: 'text', required: false, description: 'Product description' },
            { name: 'price', type: 'decimal', required: true, description: 'Unit price' },
            { name: 'quantity', type: 'integer', required: true, description: 'Current stock level' },
            { name: 'reorder_threshold', type: 'integer', required: false, description: 'Minimum quantity before alert' },
            { name: 'category', type: 'reference', required: false, description: 'Product category' },
            { name: 'supplier', type: 'reference', required: false, description: 'Primary supplier' }
          ]
        },
        {
          name: 'Stock Movement',
          description: 'Track inventory changes',
          fields: [
            { name: 'product', type: 'reference', required: true, description: 'Which product' },
            { name: 'quantity_change', type: 'integer', required: true, description: 'Amount added/removed' },
            { name: 'movement_type', type: 'string', required: true, description: 'Type (in, out, adjustment)' },
            { name: 'notes', type: 'text', required: false, description: 'Reason for movement' }
          ]
        },
        {
          name: 'Stock Alert',
          description: 'Low stock notifications',
          fields: [
            { name: 'product', type: 'reference', required: true, description: 'Which product' },
            { name: 'alert_type', type: 'string', required: true, description: 'Type of alert' },
            { name: 'severity', type: 'string', required: true, description: 'Low, Medium, High' },
            { name: 'resolved', type: 'boolean', required: false, description: 'Has been addressed' }
          ]
        }
      ]
    else
      # Generic fields from the installer
      installer = Modules::TemplateInstaller.new(entity: current_entity, user: current_user)
      fields = installer.template_fields(template_key) || []
      [{
        name: 'Record',
        description: 'Main data model',
        fields: fields.map { |f| { name: f[:name], type: f[:field_type], required: f[:required], description: f[:description] } }
      }]
    end
  end

  def build_views_from_template(template_key, template)
    base_views = [
      { name: 'Dashboard', description: 'Overview with key metrics and charts' },
      { name: 'Data Grid', description: 'List view with search and filters' },
      { name: 'Add/Edit Form', description: 'Create and modify records' }
    ]
    
    case template_key
    when 'inventory_management'
      base_views + [
        { name: 'Low Stock Alerts', description: 'Products below reorder threshold' },
        { name: 'Stock Movement Log', description: 'History of inventory changes' }
      ]
    when 'project_management'
      base_views + [
        { name: 'Kanban Board', description: 'Visual task management' },
        { name: 'Timeline View', description: 'Project schedule overview' }
      ]
    else
      base_views
    end
  end

  def build_ai_capabilities(template_key, template)
    base_capabilities = [
      "Create and manage #{template[:name].downcase} records",
      "Search and filter your data",
      "Generate reports and summaries",
      "Answer questions about your data"
    ]
    
    case template_key
    when 'inventory_management'
      base_capabilities + [
        "Alert you when stock is low",
        "Track stock movements and history"
      ]
    when 'project_management'
      base_capabilities + [
        "Update task statuses",
        "Track project progress"
      ]
    else
      base_capabilities
    end
  end

  def extract_step_info_from_execution(execution)
    context = execution.context_data || {}
    {
      plan_id: context['plan_id'] || context[:plan_id],
      step_id: context['step_id'] || context[:step_id],
      task: context['task_description'] || context[:task_description]
    }
  end

  def gather_recent_completions(entity)
    # Get completed steps from execution logs of active/recent plans
    recent_plans = ExecutionPlan.where(entity: entity)
      .where('updated_at > ?', 24.hours.ago)
      .order(updated_at: :desc)
      .limit(10)

    completions = []
    recent_plans.each do |plan|
      plan.all_steps.select { |s| s['status'] == 'completed' }.each do |step|
        completions << {
          step_name: step['name'],
          agent_name: step['agent']&.titleize&.gsub('_', ' '),
          completed_at: step['completed_at'] ? Time.parse(step['completed_at']) : plan.updated_at,
          plan_id: plan.id
        }
      end
    end

    completions.sort_by { |c| c[:completed_at] }.reverse.first(10)
  end

  # Helper methods for canvas rendering
  helper_method :plan_status_color, :complexity_color, :status_badge_class, :priority_badge_class

  def status_badge_class(status)
    case status.to_s
    when 'open' then 'info'
    when 'investigating', 'debugging' then 'warning'
    when 'fixing', 'testing' then 'primary'
    when 'pr_submitted', 'pr_approved' then 'cyan'
    when 'resolved', 'closed' then 'success'
    when 'wont_fix' then 'secondary'
    else 'secondary'
    end
  end

  def priority_badge_class(priority)
    case priority.to_s
    when 'critical' then 'danger'
    when 'high' then 'warning'
    when 'medium' then 'info'
    when 'low' then 'secondary'
    else 'secondary'
    end
  end

  def plan_status_color(status)
    case status.to_s
    when 'executing' then 'primary'
    when 'completed' then 'success'
    when 'failed' then 'danger'
    when 'paused' then 'warning'
    when 'ready' then 'info'
    when 'planning' then 'secondary'
    when 'cancelled' then 'dark'
    else 'secondary'
    end
  end

  def complexity_color(complexity)
    case complexity.to_s
    when 'simple' then 'success'
    when 'medium' then 'info'
    when 'complex' then 'warning'
    when 'epic' then 'danger'
    else 'secondary'
    end
  end

  # ===== END EXECUTION DASHBOARD HELPERS =====

end
