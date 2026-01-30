module Scout
  module Streaming
    extend ActiveSupport::Concern

    # Custom exception to signal client disconnection up the call stack
    class ClientDisconnectedError < StandardError; end

    included do
      # Track client connection status
      attr_accessor :client_disconnected
    end

    # Check if client is still connected
    def client_connected?
      !@client_disconnected
    end

    # Mark client as disconnected and optionally raise exception
    def mark_client_disconnected!(raise_exception: false)
      @client_disconnected = true
      Rails.logger.info "🔌 Client disconnected - marking for early termination"
      raise ClientDisconnectedError, "Client disconnected" if raise_exception
    end

    # Stream individual content chunks for real-time display
    def stream_content_chunk(content)
      # Check if client already disconnected
      raise ClientDisconnectedError, "Client already disconnected" if @client_disconnected

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
      # Client disconnected - mark and raise to stop the streaming loop
      Rails.logger.info "🔌 Client disconnected during content streaming: #{e.message}"
      mark_client_disconnected!(raise_exception: true)
    rescue ClientDisconnectedError
      # Re-raise to propagate up
      raise
    rescue => e
      Rails.logger.error "Stream content chunk error: #{e.message}"
    end

    # Stream update messages
    def stream_update(message)
      # Check if client already disconnected
      raise ClientDisconnectedError, "Client already disconnected" if @client_disconnected

      # Create the SSE (Server-Sent Events) format
      # Handle both string and hash data
      data = if message.is_a?(Hash)
        JSON.generate(message.merge(type: message[:type] || "update"))
      else
        JSON.generate({ type: "update", message: message })
      end
      chunk = "data: #{data}\n\n"

      response.stream.write(chunk)
    rescue IOError, Errno::EPIPE, Errno::ECONNRESET => e
      # Client disconnected - mark and raise to stop the streaming loop
      Rails.logger.info "🔌 Client disconnected during streaming: #{e.message}"
      mark_client_disconnected!(raise_exception: true)
    rescue ClientDisconnectedError
      # Re-raise to propagate up
      raise
    rescue => e
      Rails.logger.error "Stream update failed: #{e.message}"
    end

    # Stream transient updates (for progress indicators)
    def stream_transient_update(message)
      # Check if client already disconnected
      raise ClientDisconnectedError, "Client already disconnected" if @client_disconnected

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
    rescue IOError, Errno::EPIPE, Errno::ECONNRESET => e
      # Client disconnected - mark and raise to stop the streaming loop
      Rails.logger.info "🔌 Client disconnected during transient streaming: #{e.message}"
      mark_client_disconnected!(raise_exception: true)
    rescue ClientDisconnectedError
      # Re-raise to propagate up
      raise
    rescue => e
      Rails.logger.error "Stream transient update error: #{e.message}"
    end

    # Stream immediate "thinking" indicator - shows animated dots while processing starts
    # This provides instant feedback before any actual work begins
    def stream_thinking_indicator
      return if @client_disconnected

      Rails.logger.info "🤔 [Scout SSE] Sending thinking indicator..."
      
      data = JSON.generate({
        type: "thinking",
        message: "Thinking",
        timestamp: Time.current.to_f
      })
      chunk = "data: #{data}\n\n"

      response.stream.write(chunk)
      response.stream.flush if response.stream.respond_to?(:flush)
      
      Rails.logger.info "🤔 [Scout SSE] Thinking indicator sent successfully"
    rescue IOError, Errno::EPIPE, Errno::ECONNRESET => e
      Rails.logger.info "🔌 Client disconnected during thinking indicator: #{e.message}"
      mark_client_disconnected!
    rescue => e
      Rails.logger.error "Stream thinking indicator error: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
    end

    # Stream "working" indicator - shows during tool execution with animated dots
    # Provides feedback during longer operations like creating landing pages
    def stream_working_indicator(tool_name = nil)
      return if @client_disconnected

      friendly_name = tool_name ? get_friendly_tool_name(tool_name) : "Working"
      
      data = JSON.generate({
        type: "working",
        message: friendly_name,
        tool_name: tool_name,
        timestamp: Time.current.to_f
      })
      chunk = "data: #{data}\n\n"

      response.stream.write(chunk)
      response.stream.flush if response.stream.respond_to?(:flush)
    rescue IOError, Errno::EPIPE, Errno::ECONNRESET => e
      Rails.logger.info "🔌 Client disconnected during working indicator: #{e.message}"
      mark_client_disconnected!
    rescue => e
      Rails.logger.error "Stream working indicator error: #{e.message}"
    end

    # Stream final response
    def stream_final_response(response_data)
      # Don't try to send if client already disconnected
      return if @client_disconnected

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
      # Client disconnected - this is final response so just log, don't raise
      Rails.logger.info "🔌 Client disconnected during final response: #{e.message}"
      @client_disconnected = true
    rescue => e
      Rails.logger.error "Stream final response error: #{e.message}"
    end

    # Get friendly name for tool display
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
  end
end
