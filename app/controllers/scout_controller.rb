class ScoutController < ApplicationController
  include ActionController::Live  # Enable real-time streaming
  include ActionView::Helpers::NumberHelper  # For number formatting
  include Scout::Streaming  # Streaming helpers extracted to concern

  before_action :authenticate_user!
  before_action :ensure_entity_exists
  before_action :ensure_onboarded

  layout "scout"

  def index
    @session_id = session[:scout_session_id] ||= SecureRandom.uuid
    @conversation_history = persisted_history_last_k(10)

    # Load available RAG stores for the entity
    @rag_stores = RagLoaderService.load_for_entity(current_entity)

    # Check if user recently created a landing page (within last 5 minutes)
    # This helps users who missed the streaming response know their page was created
    recent_landing_page = current_entity.landing_pages.where(created_at: 5.minutes.ago..Time.current).first
    if recent_landing_page
      flash.now[:success] = "🎉 Your landing page '#{recent_landing_page.title}' was created successfully! You can access it from the Landing Pages section."
    end

    # If this is a fresh start, add Scout's welcome message
    if @conversation_history.empty?
      create_welcome_message
      @conversation_history = persisted_history_last_k(10)
      # Don't auto-load any canvas - let user interact naturally
      # @auto_load_canvas = "default" unless params[:load].present?
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
        # Check if any files are in RAG storage
        rag_files = file_urls.select { |f| f['rag_store_id'].present? }
        non_rag_files = file_urls.reject { |f| f['rag_store_id'].present? }

        file_details = []

        # Build message based on storage type
        if rag_files.any?
          rag_details = rag_files.map do |f|
            "📎 #{f['filename']} (rag_store_id: #{f['rag_store_id']}, asset_id: #{f['asset_id']}, chunks: #{f['chunks_created']})"
          end
          file_details.concat(rag_details)
        end

        if non_rag_files.any?
          non_rag_details = non_rag_files.map do |f|
            "📎 #{f['filename']} (asset_id: #{f['asset_id']}, type: #{f['content_type']})"
          end
          file_details.concat(non_rag_details)
        end

        storage_context = []
        if rag_files.any?
          storage_context << "IMPORTANT: #{rag_files.length} document(s) have been uploaded and ALREADY STORED in your RAG knowledge base with vector embeddings. These are permanently available for querying."
          storage_context << "- To query these documents, use the query_rag_store tool (no app_name needed - it will search all your documents)"
          storage_context << "- You do NOT need to store these documents again - they are already indexed"
        end

        if non_rag_files.any?
          storage_context << "- For images/non-document files, use the read_document tool with the asset_id to view them"
        end

        enhanced_message = "#{user_message}\n\n[Attached Files: #{file_details.join(', ')}]\n\n#{storage_context.join("\n")}"
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
    rag_stores_created = []
    documents_processed = 0
    storage_type = params[:storage_type] || 'long-term' # Default to long-term if not specified

    Rails.logger.info "📎 Upload request - storage_type: #{storage_type}"

    # Ensure scout_session_id exists for short-term storage
    session[:scout_session_id] ||= SecureRandom.uuid if storage_type == 'short-term'

    # Initialize document processor
    document_processor = Scout::DocumentProcessor.new(
      entity: current_entity,
      user: current_user,
      session_id: session[:scout_session_id],
      url_generator: ->(file) { rails_blob_url(file) }
    )

    if params[:files].present?
      params[:files].each do |index, file|
        if file.is_a?(ActionDispatch::Http::UploadedFile)
          extension = File.extname(file.original_filename).downcase
          is_document = Scout::DocumentProcessor.document_file?(extension)

          Rails.logger.info "📎 Processing file: #{file.original_filename}, extension: #{extension}, is_document: #{is_document}"

          # Differentiate between documents and images
          if is_document
            Rails.logger.info "📄 Routing to RAG processing pipeline (storage: #{storage_type})"
            # Process documents with Docling → RAG pipeline
            result = document_processor.process_for_rag(file, storage_type: storage_type)

            if result[:success]
              uploaded_urls << {
                url: result[:url],
                filename: file.original_filename,
                content_type: file.content_type,
                size: file.size,
                asset_id: result[:asset_id],
                rag_store_id: result[:rag_store_id],
                processed_with: result[:processor],
                chunks_created: result[:chunks_count]
              }
              # Track document processing success
              documents_processed += 1
              # Only track rag_store_id for long-term storage
              rag_stores_created << result[:rag_store_id] if result[:rag_store_id]
            else
              # Fallback to ImageAsset if RAG processing fails
              Rails.logger.warn "RAG processing failed for #{file.original_filename}: #{result[:error]}"
              image_asset = document_processor.create_image_asset(file)
              uploaded_urls << document_processor.build_image_asset_response(image_asset, file)
            end
          else
            # Keep images in Active Storage (existing behavior)
            Rails.logger.info "🖼️ Routing to Active Storage (image/unsupported file)"
            image_asset = document_processor.create_image_asset(file)
            uploaded_urls << document_processor.build_image_asset_response(image_asset, file)
          end
        end
      end
    end

    response_data = {
      success: true,
      urls: uploaded_urls
    }

    # Add RAG info if documents were processed
    if documents_processed > 0
      response_data[:rag_stores_created] = rag_stores_created if rag_stores_created.any?
      if storage_type == 'short-term'
        response_data[:message] = "#{documents_processed} document(s) processed for this conversation"
      else
        response_data[:message] = "#{documents_processed} document(s) processed and added to your knowledge base"
      end
    end

    render json: response_data
  rescue => e
    Rails.logger.error "File upload error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    render json: { success: false, error: e.message }, status: 500
  end

  # Delete document from session (Redis) or long-term (database) storage
  def delete_document
    filename = params[:filename]
    storage_type = params[:storage_type]

    unless filename
      render json: { success: false, error: "Filename is required" }, status: 400
      return
    end

    begin
      if storage_type == 'short-term'
        # Delete from Redis
        scout_session_id = session[:scout_session_id]

        unless scout_session_id
          render json: { success: false, error: "No active session found" }, status: 400
          return
        end

        session_key = "rag:session:#{scout_session_id}:documents"
        deleted = $redis.hdel(session_key, filename)

        if deleted > 0
          Rails.logger.info "🗑️ Deleted session document: #{filename}"
          render json: {
            success: true,
            message: "Document deleted from session"
          }
        else
          render json: { success: false, error: "Document not found in session" }, status: 404
        end

      else
        # Delete from database (long-term storage)
        rag_document_id = params[:rag_document_id]

        unless rag_document_id
          render json: { success: false, error: "Document ID is required for long-term storage" }, status: 400
          return
        end

        rag_document = RagDocument.joins(:rag_store)
                                   .where(rag_stores: { entity_id: current_entity.id })
                                   .find_by(id: rag_document_id)

        unless rag_document
          render json: { success: false, error: "Document not found or access denied" }, status: 404
          return
        end

        rag_store = rag_document.rag_store
        rag_document_filename = rag_document.original_filename

        # Delete chunks first (cascade should handle this, but being explicit)
        rag_document.rag_chunks.destroy_all

        # Delete document
        rag_document.destroy!

        # If this was the last document in the RAG store, delete the store too
        if rag_store.rag_documents.count == 0
          rag_store.destroy!
          Rails.logger.info "🗑️ Deleted RagStore #{rag_store.id} (was empty after deleting document)"
        end

        Rails.logger.info "🗑️ Deleted database document: #{rag_document_filename} (ID: #{rag_document_id})"

        render json: {
          success: true,
          message: "Document permanently deleted from knowledge base"
        }
      end

    rescue => e
      Rails.logger.error "Delete document error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      render json: { success: false, error: e.message }, status: 500
    end
  end

  # Move session document from Redis to long-term database storage
  def move_to_long_term
    filename = params[:filename]

    unless filename
      render json: { success: false, error: "Filename is required" }, status: 400
      return
    end

    begin
      scout_session_id = session[:scout_session_id]

      unless scout_session_id
        render json: { success: false, error: "No active session found" }, status: 400
        return
      end

      session_key = "rag:session:#{scout_session_id}:documents"
      doc_json = $redis.hget(session_key, filename)

      unless doc_json
        render json: { success: false, error: "Document not found in session" }, status: 404
        return
      end

      # Parse document data from Redis
      doc_data = JSON.parse(doc_json)

      Rails.logger.info "📦 Moving '#{filename}' from session to long-term storage"

      # Create RagStore for permanent storage
      rag_store = RagStore.create!(
        entity: current_entity,
        name: "Saved: #{filename}",
        app_name: "Scout Session Save - #{Time.current.strftime('%Y-%m-%d %H:%M')}",
        store_type: "entity",
        pinecone_index: "amos-rag-#{Rails.env}",
        pinecone_namespace: "entity_#{current_entity.id}_#{SecureRandom.hex(4)}",
        processing_method: "docling"
      )

      # Create RagDocument
      rag_document = RagDocument.create!(
        rag_store: rag_store,
        original_filename: filename,
        file_hash: doc_data['file_hash'] || Digest::SHA256.hexdigest(filename),
        page_count: doc_data['page_count'],
        docling_metadata: {
          asset_id: doc_data['asset_id'],
          asset_url: doc_data['asset_url'],
          moved_from_session: true,
          original_session_id: scout_session_id,
          moved_at: Time.current.iso8601
        }
      )

      # Create RagChunks
      chunks_created = 0
      doc_data['chunks']&.each do |chunk|
        RagChunk.create!(
          rag_document: rag_document,
          content: chunk['content'],
          chunk_index: chunk['index'],
          chunk_type: chunk['type'] || 'text'
        )
        chunks_created += 1
      end

      Rails.logger.info "✅ Moved '#{filename}' to long-term storage (#{chunks_created} chunks, RagStore ID: #{rag_store.id})"

      # Remove from Redis session storage (no longer needed in temporary storage)
      deleted = $redis.hdel(session_key, filename)
      Rails.logger.info "🗑️  Removed '#{filename}' from session storage" if deleted > 0

      render json: {
        success: true,
        message: "Document saved permanently and removed from session",
        rag_store_id: rag_store.id,
        rag_document_id: rag_document.id,
        chunks_count: chunks_created
      }

    rescue => e
      Rails.logger.error "Move to long-term error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      render json: { success: false, error: e.message }, status: 500
    end
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

    Rails.logger.info "Scout streaming chat - Session: #{@session_id}, User: #{current_user.id}, Message: #{user_message}"
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

      # Fetch session documents from Redis
      session_documents = []
      begin
        session_key = "rag:session:#{session.id}:documents"
        Rails.logger.info "🔍 Looking for session documents with key: #{session_key}"

        redis_docs = $redis.hgetall(session_key)
        Rails.logger.info "📦 Redis returned #{redis_docs.keys.length} documents"

        redis_docs.each do |filename, doc_json|
          doc_data = JSON.parse(doc_json)
          session_documents << {
            filename: doc_data['filename'],
            chunks: doc_data['chunks'],
            storage_type: 'session'
          }
        end

        if session_documents.any?
          Rails.logger.info "📚 Found #{session_documents.length} session document(s) for context"
          session_documents.each do |doc|
            Rails.logger.info "  📄 #{doc[:filename]} with #{doc[:chunks].length} chunks"
          end
        else
          Rails.logger.warn "⚠️ No session documents found for session #{session.id}"
        end
      rescue => e
        Rails.logger.error "Error fetching session documents: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
      end

      # Build enhanced message if files are attached
      enhanced_message = user_message
      metadata = {}

      if file_urls.any?
        # Check if any files are in RAG storage
        rag_files = file_urls.select { |f| f['rag_store_id'].present? }
        non_rag_files = file_urls.reject { |f| f['rag_store_id'].present? }

        file_details = []

        # Build message based on storage type
        if rag_files.any?
          rag_details = rag_files.map do |f|
            "📎 #{f['filename']} (rag_store_id: #{f['rag_store_id']}, asset_id: #{f['asset_id']}, chunks: #{f['chunks_created']})"
          end
          file_details.concat(rag_details)
        end

        if non_rag_files.any?
          non_rag_details = non_rag_files.map do |f|
            "📎 #{f['filename']} (asset_id: #{f['asset_id']}, type: #{f['content_type']})"
          end
          file_details.concat(non_rag_details)
        end

        storage_context = []
        if rag_files.any?
          storage_context << "IMPORTANT: #{rag_files.length} document(s) have been uploaded and ALREADY STORED in your RAG knowledge base with vector embeddings. These are permanently available for querying."
          storage_context << "- To query these documents, use the query_rag_store tool (no app_name needed - it will search all your documents)"
          storage_context << "- You do NOT need to store these documents again - they are already indexed"
        end

        if non_rag_files.any?
          storage_context << "- For images/non-document files, use the read_document tool with the asset_id to view them"
        end

        enhanced_message = "#{user_message}\n\n[Attached Files: #{file_details.join(', ')}]\n\n#{storage_context.join("\n")}"
        metadata[:file_urls] = file_urls
      end

      # Add session documents to the enhanced message if available
      if session_documents.any?
        session_doc_details = session_documents.map do |doc|
          chunk_count = doc[:chunks].length
          "📄 #{doc[:filename]} (#{chunk_count} text chunks available)"
        end.join("\n")

        # Include all chunks in the context
        all_chunks_text = session_documents.map do |doc|
          "=== Document: #{doc[:filename]} ===\n" +
          doc[:chunks].map.with_index do |chunk, idx|
            "[Chunk #{idx + 1}]\n#{chunk['content']}"
          end.join("\n\n")
        end.join("\n\n" + "="*50 + "\n\n")

        enhanced_message = "#{enhanced_message}\n\n[Session Documents Available:]\n#{session_doc_details}\n\n[Document Content:]\n#{all_chunks_text}\n\nYou can use the information from these documents to answer questions."
        metadata[:session_documents] = session_documents
      end

      # Save user message with file info
      save_scout_message("user", enhanced_message, metadata: metadata)
      stream_update("📚 Loading conversation history...")

      # Get conversation history (last 20 messages for active window)
      conversation_history = persisted_history_last_k(20)
      stream_update("📚 Loading conversation history (#{conversation_history.length} messages)")

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
          sources: result[:sources] || [],
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
    rescue IOError, Errno::EPIPE, Errno::ECONNRESET => e
      # Client disconnected - this is normal, not an error
      Rails.logger.info "Client disconnected during chat stream: #{e.message}"
      puts "ℹ️ Client disconnected (normal): #{e.message}"
      STDOUT.flush
      
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

  # Analytics service instance
  def analytics_service
    @analytics_service ||= Scout::Analytics.new(entity: current_entity, user: current_user)
  end

  # Job status checker instance
  def job_status_checker
    @job_status_checker ||= Scout::JobStatusChecker.new(user: current_user, stream: response.stream)
  end

  # Task progress loader instance
  def task_progress_loader
    @task_progress_loader ||= Scout::TaskProgressLoader.new(
      user: current_user,
      session_id: session[:scout_session_id]
    )
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

  # Streaming methods moved to Scout::Streaming concern
  # See app/controllers/concerns/scout/streaming.rb

  def check_active_job_status(response_data)
    job_status_checker.check_active_job_status(response_data)
  end

  def send_job_started_status_if_exists(response_data)
    job_status_checker.send_job_started_status_if_exists(response_data)
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
    documents = []

    # Fetch short-term documents from Redis (session-based)
    begin
      # Use scout_session_id for consistency across requests
      scout_session_id = session[:scout_session_id]
      if scout_session_id
        session_key = "rag:session:#{scout_session_id}:documents"
        Rails.logger.info "📚 Fetching Redis documents with key: #{session_key}"
        redis_docs = $redis.hgetall(session_key)
        Rails.logger.info "📚 Found #{redis_docs.keys.length} documents in Redis"

        redis_docs.each do |filename, doc_json|
          doc_data = JSON.parse(doc_json)
          documents << {
            filename: doc_data['filename'],
            url: doc_data['asset_url'],
            content_type: 'application/pdf', # Assumed for RAG documents
            size: nil,
            size_human: 'Unknown',
            storage_type: 'short-term',
            chunks_count: doc_data['chunks']&.length || 0,
            uploaded_at: doc_data['uploaded_at']
          }
        end
      end
    rescue => e
      Rails.logger.error "Error fetching Redis documents: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end

    # Fetch long-term documents from database (recent uploads for this entity)
    rag_stores = current_entity.rag_stores
                               .where(store_type: 'entity')
                               .where('created_at > ?', 7.days.ago)
                               .includes(rag_documents: :rag_chunks)
                               .order(created_at: :desc)

    rag_stores.each do |store|
      store.rag_documents.each do |doc|
        # Get the ImageAsset for the document
        asset_id = doc.docling_metadata&.dig('asset_id')
        asset = nil

        if asset_id
          asset = ImageAsset.find_by(id: asset_id, entity: current_entity)
        end

        # Fallback: try to find by filename if asset_id not found
        unless asset
          asset = current_entity.image_assets
                                .where("title LIKE ?", "%#{doc.original_filename}%")
                                .where("created_at >= ?", doc.created_at - 5.minutes)
                                .order(created_at: :desc)
                                .first
        end

        # Only include documents that have URLs
        if asset && asset.file.attached?
          documents << {
            filename: doc.original_filename,
            url: rails_blob_url(asset.file),
            content_type: 'application/pdf',
            size: asset.file.byte_size,
            size_human: number_to_human_size(asset.file.byte_size),
            storage_type: 'long-term',
            chunks_count: doc.rag_chunks.count,
            uploaded_at: doc.created_at.iso8601,
            rag_document_id: doc.id,
            rag_store_id: store.id
          }
        end
      end
    end

    # If specific asset_id is requested, include it (for backward compatibility)
    if data[:asset_id]
      asset = ImageAsset.find_by(id: data[:asset_id], entity: current_entity)
      if asset && asset.file.attached?
        # Check if already in documents array
        unless documents.any? { |d| d[:filename] == asset.title }
          documents << {
            filename: asset.title || 'Uploaded File',
            url: rails_blob_url(asset.file),
            content_type: asset.file.content_type,
            size: asset.file.byte_size,
            size_human: number_to_human_size(asset.file.byte_size),
            storage_type: 'long-term',
            uploaded_at: asset.created_at.iso8601
          }
        end
      end
    end

    # Prepare canvas data
    canvas_data = {
      documents: documents,
      document_count: documents.length
    }

    render_to_string(
      partial: 'scout/canvas/document_viewer',
      locals: {
        entity: current_entity,
        user: current_user,
        canvas_data: canvas_data
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
    analytics_service.calculate_avg_open_rate
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
    analytics_service.load_form_submissions_data(filters)
  end

  def calculate_submission_stats(base_query)
    analytics_service.calculate_submission_stats(base_query)
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
    analytics_service.load_workflow_analytics_data(options)
  end

  def render_task_progress(data = {})
    # Load task data using the task progress loader service
    task_data = task_progress_loader.load_task_data(data)

    # Render appropriate partial based on workflow approval status
    if task_progress_loader.is_workflow_approval?(task_data)
      render_to_string(
        partial: "scout/canvas/workflow_approval",
        locals: {
          entity: current_entity,
          user: current_user,
          data: task_data
        }
      )
    else
      render_to_string(
        partial: "scout/canvas/task_progress",
        locals: {
          entity: current_entity,
          user: current_user,
          task_list: task_data
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

  # RAG Upload Helper Methods

  # Check if file is a document that should be processed with Docling
  # Document processing methods moved to Scout::DocumentProcessor service
  # See app/services/scout/document_processor.rb
end
