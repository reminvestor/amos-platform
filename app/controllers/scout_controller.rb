class ScoutController < ApplicationController
  include ActionController::Live  # Enable real-time streaming
  include ActionView::Helpers::NumberHelper  # For number formatting
  include Scout::Streaming  # Streaming helpers
  include Scout::StreamingKeepalive  # Keep-alive for long operations

  before_action :authenticate_user!
  before_action :ensure_entity_exists
  before_action :ensure_onboarded

  layout "scout"

  def index
    @session_id = session[:scout_session_id] ||= SecureRandom.uuid
    @conversation_history = persisted_history_last_k(10)
    @show_parallel_tasks = true

    # Load available RAG stores for the entity
    @rag_stores = RagLoaderService.load_for_entity(current_entity)

    # Check if user recently created a landing page (within last 5 minutes)
    # This helps users who missed the streaming response know their page was created
    recent_landing_page = current_entity.landing_pages.where(created_at: 5.minutes.ago..Time.current).first
    if recent_landing_page
      flash.now[:success] = "🎉 Your landing page '#{recent_landing_page.title}' was created successfully! You can access it from the Landing Pages section."
    end

    # If this is a fresh start, add Scout's welcome message and load default canvas
    if @conversation_history.empty?
      create_welcome_message
      @conversation_history = persisted_history_last_k(10)
      @auto_load_canvas = "default" unless params[:load].present?
    end

    # Business context for display
    @business_profile = current_user.business_profile
    @entity = current_entity

    # Handle auto-load parameters
    @auto_load_canvas = params[:load] if params[:load].present?
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
      main_chat_loadout = AgentLoadout.new(agent_role: "main_chat")
      generic_tools_service = ScoutGenericToolsServiceV2.new(
        current_user,
        current_entity,
        session[:scout_session_id],
        agent_loadout: main_chat_loadout
      )

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
          "📎 #{f['filename']} (asset_id: #{id}, type: #{f['content_type']})"
        end.join(", ")

        enhanced_message = "#{user_message}\n\n[Attached Files: #{file_details}]\n\nIMPORTANT: Use the read_document tool with the asset_id to extract content from these files before responding."
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
    @session_id = session[:scout_session_id] ||= SecureRandom.uuid
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
      
      # Send immediate response to establish streaming
      stream_update("💬 Message received")
      
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
          "📎 #{f['filename']} (asset_id: #{id}, type: #{f['content_type']})"
        end.join(", ")

        enhanced_message = "#{user_message}\n\n[Attached Files: #{file_details}]\n\nIMPORTANT: Use the read_document tool with the asset_id to extract content from these files before responding."
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
    canvas_data = params[:canvas_data] || {}

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
      when "campaign_viewer", "email_campaign_viewer"
        canvas_content = render_campaign_canvas(canvas_data)
        canvas_title = "Email Campaigns"
      when "analytics_dashboard"
        canvas_content = render_analytics_canvas(canvas_data)
        canvas_title = "Analytics Dashboard"
      when 'document_viewer'
        canvas_content = render_document_viewer_canvas(canvas_data)
        canvas_title = "Document Viewer"
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
      when "task_progress"
        canvas_content = render_task_progress(canvas_data)
        canvas_title = "Task Progress"
      when "campaign_editor"
        canvas_content = render_campaign_editor(canvas_data)
        canvas_title = "Campaign Editor"
      when "integrations_manager"
        # Always fetch integrations data for this canvas
        integrations = Integration.includes(oauth_configurations: :auth_configs).where(is_active: true).order(:name)
        connections = current_user.connections.includes(:integration)

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
        
        # Load all active tasks for the current user
        active_tasks = TaskSession.where(
          user: current_user,
          status: ['active', 'pending', 'queued']
        ).includes(:task_dependencies).order(created_at: :desc).limit(50)
        
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
          locals: {
            canvas_data: @canvas_data
          }
        )
        canvas_title = "Task Monitor"
      else
        canvas_content = render_default_canvas
        canvas_title = ""
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

  def clear_conversation
    session_id = session[:scout_session_id]
    if session_id
      # Clear Rails cache
      Rails.cache.delete("scout_conversation_#{session_id}")

      # Clear Redis history
      begin
        memory = Scout::MemoryTools.new(session_id)
        memory.clear_session
      rescue => e
        Rails.logger.warn "Failed to clear Redis history: #{e.message}"
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
    session_id = session[:scout_session_id]
    limit = params[:limit].to_i
    limit = 20 if limit <= 0 || limit > 100
    before_id = params[:before_id]

    scope = ScoutMessage.for_session(session_id).oldest_first
    if before_id.present?
      # Load messages older than the given id
      before_message = ScoutMessage.find_by(id: before_id)
      scope = scope.where("created_at < ?", before_message.created_at) if before_message
    end

    batch = scope.last(limit)
    render json: {
      messages: batch.map { |m| {
        id: m.id,
        role: m.role,
        content: m.content,
        timestamp: m.created_at.iso8601,
        metadata: m.metadata
      } },
      has_more: ScoutMessage.for_session(session_id).count > (before_id.present? ? ScoutMessage.for_session(session_id).where("created_at <= ?", batch.first&.created_at).count : batch.count)
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

  # POST /scout/new_session
  def new_session
    # Clear old session cache if exists
    old_session_id = session[:scout_session_id]
    if old_session_id
      Rails.cache.delete("scout_conversation_#{old_session_id}")
    end

    # Create new session
    session[:scout_session_id] = SecureRandom.uuid
    render json: { session_id: session[:scout_session_id] }
  end

  # GET /scout/document-status/:asset_id
  # API endpoint to check document indexing status
  def document_indexing_status
    asset_id = params[:asset_id]
    return render json: { error: "asset_id required" }, status: :bad_request if asset_id.blank?

    # Check for both ImageAsset and RagDocument
    asset = current_entity.image_assets.find_by(id: asset_id)
    
    if !asset
      # Try to find as RagDocument - query RagDocument model directly
      rag_document = RagDocument.joins(:rag_store)
                               .where(rag_stores: { entity_id: current_entity.id })
                               .where(id: asset_id)
                               .first
      
      if rag_document
        # Convert RagDocument status to expected format
        return render json: {
          indexed: rag_document.processing_status == 'indexed',
          processing_status: rag_document.processing_status,
          chunk_count: rag_document.rag_chunks.count,
          error: nil  # RagDocument doesn't have an error field
        }
      end
      
      return render json: { error: "Document not found" }, status: :not_found
    end

    status = calculate_document_status(asset)
    render json: status
  end

  private

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

  # DB-backed persistent history, paged
  def persisted_history_last_k(k = 10)
    session_id = session[:scout_session_id]
    return [] unless session_id
    ScoutMessage.for_session(session_id).oldest_first.last(k).map do |m|
      {
        role: m.role,
        content: m.content,
        timestamp: m.created_at.iso8601,
        metadata: m.metadata
      }
    end
  end

  def save_scout_message(role, message, metadata: {})
    session_id = session[:scout_session_id]
    return unless session_id

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
        session_id: session_id,
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

    # Persist in DB (durable) with transaction safety
    ScoutMessage.create!(
      user_id: current_user.id,
      entity_id: current_entity&.id,
      session_id: session_id,
      role: role,
      content: message,
      metadata: metadata
    )

    # Also store in Redis for extended history access
    begin
      memory = Scout::MemoryTools.new(session_id)
      memory.store_message(role, message, metadata)
    rescue => e
      Rails.logger.warn "Failed to store message in Redis: #{e.message}"
      # Continue - Redis storage is optional enhancement
    end

    # Mirror the last 50 in cache for fast UI render
    conversation = persisted_history_last_k(50)
    Rails.cache.write("scout_conversation_#{session_id}", conversation, expires_in: 12.hours)
  end

  def create_welcome_message
    business_name = current_entity&.name || "your business"
    profile = current_user.business_profile
    entity = current_entity

    # Build subscription info if available
    subscription_info = ""
    if entity.subscription_status.present? && entity.plan_tier.present?
      plan_name = entity.plan_tier.titleize
      token_limit = entity.token_limit || 200_000
      token_limit_formatted = number_to_human(token_limit, format: '%n%u', units: { thousand: 'K', million: 'M' })

      if entity.subscription_status == 'trialing' && entity.trial_ends_at
        trial_days_left = ((entity.trial_ends_at - Time.current) / 1.day).ceil
        subscription_info = "\n\n✨ You're on the **#{plan_name}** plan (#{token_limit_formatted} AI tokens/month). " \
                           "Your trial has #{trial_days_left} days remaining."
      elsif entity.subscription_status == 'active'
        subscription_info = "\n\n✨ You're on the **#{plan_name}** plan with #{token_limit_formatted} AI tokens/month."
      end
    end

    # Build RAG store info (only show if there are actual knowledge bases)
    rag_info = build_rag_info

    welcome_message = if profile&.industry.present?
      "Welcome back! I'm Amos, your AI business automation assistant for #{business_name}. " \
      "I can help you analyze your #{profile.industry.downcase} business performance, " \
      "manage operations, automate workflows, handle integrations, and create marketing materials. " \
      "What would you like to explore today? 🎯#{subscription_info}#{rag_info}"
    else
      "Welcome to Amos! I'm your AI business automation assistant for #{business_name}. " \
      "I can help analyze your business performance, automate operations, manage data integrations, " \
      "and create marketing materials. What can I help you with today? 🚀#{subscription_info}#{rag_info}"
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
      }
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
        inline: "<div class='text-center py-5'><h5>No Landing Pages Found</h5><p>Create your first landing page to get started.</p><button class='btn btn-primary' onclick='window.scoutCreateLandingPage()'>Create Landing Page</button></div>"
      )
    end

    render_to_string(
      partial: "scout/canvas/landing_page_details",
      locals: {
        landing_page: landing_page,
        entity: current_entity,
        user: current_user,
        canvas_data: data
      }
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
      # Return an error view or a placeholder
      return render_to_string(
        partial: "scout/canvas/default",
        locals: {
          title: "Landing Page Not Found",
          message: "Could not locate the generated landing page. Please check the Tasks view."
        }
      )
    end

    render_to_string(
      partial: "scout/canvas/landing_page_editor",
      locals: {
        landing_page: landing_page,
        entity: current_entity,
        user: current_user
      }
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
      }
    )
  end

  def render_contact_generator(data = {})
    contact = current_entity.contacts.build
    contact_groups = current_entity.contact_groups.limit(20)

    render_to_string(
      partial: "scout/canvas/contact_generator",
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
      # Try to find as ImageAsset first
      asset = ImageAsset.find_by(id: data[:asset_id], entity: current_entity)
      
      # If not found, try as RagDocument
      if !asset
        rag_document = RagDocument.joins(:rag_store).find_by(
          id: data[:asset_id], 
          rag_stores: { entity_id: current_entity.id }
        )
        
        if rag_document && rag_document.file.attached?
          # Use RagDocument's attached file
          asset = rag_document
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
      }
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

  def render_dynamic_canvas(data = {})
    render_to_string(
      partial: "scout/canvas/dynamic_canvas",
      locals: {
        entity: current_entity,
        user: current_user,
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
      source: "chat"
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
    # Create a temporary blob with expiry
    blob = ActiveStorage::Blob.create_and_upload!(
      io: file,
      filename: file.original_filename,
      content_type: file.content_type,
      metadata: { 
        temporary: true,
        expires_at: 24.hours.from_now
      }
    )
    
    {
      url: rails_blob_url(blob),
      filename: file.original_filename,
      content_type: file.content_type,
      size: file.size,
      temporary: true,
      asset_type: 'temporary'
    }
  end
  
  # ===== AMOS INTEGRATION METHODS =====
  
  def initialize_amos_orchestrator
    # Create or retrieve Amos orchestrator for this session
    # Pass the actual request host so callbacks work correctly
    Amos::Orchestrator.new(current_user, current_entity, @session_id, 
      request_host: request.host_with_port
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
      
      metadata = {
        attached_files: file_urls,
        canvas: canvas_hash,
        model_preference: model_preference,
        voice_mode: params[:voice_mode] == 'true'
      }
    
    # Build enhanced message if files are attached
    enhanced_message = message
    if file_urls.any?
      Rails.logger.info "🔍 AMOS file_urls: #{file_urls.inspect}"
      # Include asset_id so AMOS can use read_document tool
      file_details = file_urls.map do |f|
        # Support both asset_id and document_id for backward compatibility
        id = f['asset_id'] || f['document_id']
        processing_note = f['processing'] ? " - PROCESSING" : ""
        "📎 #{f['filename']} (asset_id: #{id}, type: #{f['content_type']}#{processing_note})"
      end.join(", ")

      enhanced_message = "#{message}\n\n[Attached Files: #{file_details}]\n\nIMPORTANT: Use the read_document tool with the asset_id to extract content from these files before responding. If a document shows PROCESSING, it may still be extracting content."
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
end
