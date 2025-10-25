class ScoutController < ApplicationController
  include ActionController::Live  # Enable real-time streaming
  include ActionView::Helpers::NumberHelper  # For number formatting

  before_action :authenticate_user!
  before_action :ensure_entity_exists
  before_action :ensure_onboarded

  layout "scout"

  def index
    @session_id = session[:scout_session_id] ||= SecureRandom.uuid
    @conversation_history = persisted_history_last_k(10)

    # Load available RAG stores for the entity
    @rag_stores = RagLoaderService.load_for_entity(current_entity)

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

      # Save Scout's response
      save_scout_message("assistant", response[:message])

      # Return structured response
      render json: {
        message: response[:message],
        tools_used: response[:tools_used],
        tools_list: response[:tools_list],
        success_count: response[:success_count],
        error_count: response[:error_count],
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
        # Include asset_id so AMOS can use read_document tool
        file_details = file_urls.map do |f|
          "📎 #{f['filename']} (asset_id: #{f['asset_id']}, type: #{f['content_type']})"
        end.join(", ")

        enhanced_message = "#{user_message}\n\n[Attached Files: #{file_details}]\n\nIMPORTANT: Use the read_document tool with the asset_id to extract content from these files before responding."
        metadata[:file_urls] = file_urls
      end

      # Save user message with file info
      save_scout_message("user", enhanced_message, metadata: metadata)

      # Initialize interactive task service
      interactive_service = InteractiveTaskService.new(current_user, current_entity, @session_id)

      # Add file URLs to context if present
      if file_urls.any?
        interactive_service.set_context(attached_files: file_urls)
      end

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
    uploaded_urls = []

    if params[:files].present?
      params[:files].each do |index, file|
        if file.is_a?(ActionDispatch::Http::UploadedFile)
          # Create ImageAsset for each uploaded file
          image_asset = ImageAsset.create!(
            entity: current_entity,
            user: current_user,
            title: file.original_filename,
            file: file,
            source: "upload"
          )

          uploaded_urls << {
            url: rails_blob_url(image_asset.file),
            filename: file.original_filename,
            content_type: file.content_type,
            size: file.size,
            asset_id: image_asset.id
          }
        end
      end
    end

    render json: { success: true, urls: uploaded_urls }
  rescue => e
    Rails.logger.error "File upload error: #{e.message}"
    render json: { success: false, error: e.message }, status: 500
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
    model_override = params[:model_override]&.strip # For voice assistant to use Haiku

    Rails.logger.info "Scout streaming chat - Session: #{@session_id}, User: #{current_user.id}, Message: #{user_message}"
    Rails.logger.info "Model override: #{model_override}" if model_override.present?
    puts "🚨 PRODUCTION DEBUG: Scout chat request received - #{Time.current}"
    STDOUT.flush
    Rails.logger.info "Current canvas context: #{current_canvas.inspect}" if current_canvas
    Rails.logger.info "Chat context: #{context.inspect}" if context
    Rails.logger.info "File URLs: #{file_urls.inspect}" if file_urls.any?

    if user_message.blank?
      render json: { error: "Message cannot be empty" }, status: 400
      return
    end

    # Set streaming headers
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
    response.headers["Connection"] = "keep-alive"
    response.headers["X-Accel-Buffering"] = "no" # Prevent nginx buffering
    response.headers["Access-Control-Allow-Origin"] = "*"
    puts "🚨 PRODUCTION DEBUG: SSE Headers set - #{Time.current}"
    STDOUT.flush

    # Force the headers to be sent immediately
    response.status = 200

    begin
      # Send immediate response to establish streaming
      stream_update("💬 Message received")

      # Build enhanced message if files are attached
      enhanced_message = user_message
      metadata = {}

      if file_urls.any?
        # Include asset_id so AMOS can use read_document tool
        file_details = file_urls.map do |f|
          "📎 #{f['filename']} (asset_id: #{f['asset_id']}, type: #{f['content_type']})"
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

      # Store model override for this request (voice assistant uses Haiku for speed)
      if model_override.present?
        RequestStore.store[:model_override] = model_override
        Rails.logger.info "🎤 Voice assistant model override set: #{model_override}"
      end

      # Use InteractiveTaskService with streaming updates
      stream_update("🧠 Analyzing your request...")
      stream_update("📋 Detecting task mode and preparing workflow...")
      interactive_service = InteractiveTaskService.new(current_user, current_entity, session[:scout_session_id])

      # Set up progress callback for streaming updates
      interactive_service.on_progress do |progress_data|
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
            # Don't show tool complete messages - too noisy
          when 'cache_metrics'
            # Stream cache performance metrics to frontend
            stream_update({
              type: 'cache_metrics',
              cache_creation: progress_data[:cache_creation] || 0,
              cache_read: progress_data[:cache_read] || 0,
              tokens: progress_data[:tokens]
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
      if current_canvas.dig("data", "awaiting_approval") && is_approval_response?(user_message)
        stream_update("📋 Processing your plan feedback...")
        approval_action = extract_approval_action(user_message)
        result = interactive_service.handle_plan_approval(approval_action, user_message)
      else
        # Process message using InteractiveTaskService
        stream_update("🎯 Processing your request...")

        # Add file URLs to context if present
        if file_urls.any?
          interactive_service.set_context(attached_files: file_urls)
        end

        result = interactive_service.process_message(user_message, conversation_history, current_canvas)
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
        if canvas && canvas != "conversation" && result[:mode] != "autonomous"
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

        # Check if workflow approval is needed
        if result[:workflow_approval_needed]
          final_response[:workflow_approval] = {
            task_session_id: result[:task_session_id],
            workflow_spec: result[:workflow_spec]
          }
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
      response.stream.close
    end
  end

  # Template/Canvas Actions for Intelligent Canvas
  def load_canvas
    canvas_type = params[:canvas_type]
    canvas_data = params[:canvas_data] || {}

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
      when "campaign_viewer"
        canvas_content = render_campaign_canvas(canvas_data)
        canvas_title = "Campaigns"
      when "analytics_dashboard"
        canvas_content = render_analytics_canvas(canvas_data)
        canvas_title = "Analytics Dashboard"
      when 'document_viewer'
        canvas_content = render_document_viewer_canvas(canvas_data)
        canvas_title = "Document Viewer"
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
        integrations = Integration.where(is_active: true).order(:name)
        connections = current_user.connections.includes(:integration)

        canvas_data[:integrations] = integrations.map do |integration|
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
            is_connected: connections.any? { |c| c.integration_id == integration.id && c.status == "connected" }
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
          icon: "fas fa-globe"
        },
        {
          type: "contact_viewer",
          name: "Contacts",
          description: "View and manage contacts",
          icon: "fas fa-users"
        },
        {
          type: "campaign_viewer",
          name: "Campaigns",
          description: "View and manage email campaigns",
          icon: "fas fa-envelope"
        },
        {
          type: "integrations_manager",
          name: "Integrations",
          description: "Manage external application connections",
          icon: "fas fa-plug"
        },
        {
          type: "integration_connect",
          name: "Connect Integration",
          description: "Connect to an external service",
          icon: "fas fa-link"
        },
        {
          type: "analytics_dashboard",
          name: "Analytics",
          description: "Marketing performance dashboard",
          icon: "fas fa-chart-bar"
        }
      ]

      # Add data-specific canvases if we have recent data
      if current_entity.landing_pages.recent.limit(1).exists?
        recent_page = current_entity.landing_pages.recent.first
        canvases << {
          type: "landing_page_generator",
          name: recent_page.title || "Recent Landing Page",
          description: "Landing page in progress",
          icon: "fas fa-edit",
          data: { landing_page_id: recent_page.id }
        }
      end

      render json: { canvases: canvases }
    rescue => e
      Rails.logger.error "Available canvases error: #{e.message}"
      render json: { canvases: [] }
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
    puts "🚨 PRODUCTION DEBUG: Streaming content chunk: #{content.inspect}"
    puts "🔍 Content length: #{content.length}, newlines: #{content.count("\n")}"
    STDOUT.flush

    data = JSON.generate({ type: "content", content: content })
    chunk = "data: #{data}\n\n"

    response.stream.write(chunk)

    # Try to flush
    begin
      response.stream.flush if response.stream.respond_to?(:flush)
    rescue
      # Ignore flush errors
    end

    puts "✅ Content chunk streamed successfully"
    STDOUT.flush
  rescue => e
    Rails.logger.error "Stream content chunk error: #{e.message}"
    puts "❌ Stream content chunk error: #{e.message}"
    STDOUT.flush
  end

  def stream_update(message)
    puts "🚨 PRODUCTION DEBUG: Streaming update: #{message}"
    STDOUT.flush
    # Create the SSE (Server-Sent Events) format
    # Handle both string and hash data
    data = if message.is_a?(Hash)
      JSON.generate(message.merge(type: message[:type] || "update"))
    else
      JSON.generate({ type: "update", message: message })
    end
    chunk = "data: #{data}\n\n"

    response.stream.write(chunk)

    puts "✅ Update streamed successfully"
    STDOUT.flush
  rescue => e
    puts "❌ Stream update failed: #{e.message}"
    STDOUT.flush
  end

  def stream_transient_update(message)
    puts "🚨 PRODUCTION DEBUG: Streaming transient update: #{message}"
    STDOUT.flush
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
        <h5><i class="fas fa-info-circle me-2"></i>Landing Page Creation Updated</h5>
        <p class="mb-3">Landing page creation now uses our improved interactive workflow.</p>
        <button class="btn btn-primary" onclick="window.scoutSendMessage?.('Create a landing page')">
          <i class="fas fa-plus me-2"></i>Start Creating Landing Page
        </button>
      </div>
    HTML
  end

  def render_landing_page_editor(data = {})
    landing_page = current_entity.landing_pages.find(data["landing_page_id"])

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
    # Build document URL from asset_id
    if data[:asset_id]
      asset = ImageAsset.find_by(id: data[:asset_id], entity: current_entity)
      if asset && asset.file.attached?
        data[:url] = rails_blob_url(asset.file)
        data[:download_url] = rails_blob_url(asset.file, disposition: 'attachment')
      end
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
end
