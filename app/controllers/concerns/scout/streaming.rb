module Scout
  module Streaming
    extend ActiveSupport::Concern

    # Stream individual content chunks for real-time display
    def stream_content_chunk(content)
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
    rescue IOError, Errno::EPIPE, Errno::ECONNRESET => e
      # Client disconnected - this is normal, not an error
      Rails.logger.info "Client disconnected during content streaming: #{e.message}"
      puts "ℹ️ Client disconnected (normal): #{e.message}"
      STDOUT.flush
    rescue => e
      Rails.logger.error "Stream content chunk error: #{e.message}"
      puts "❌ Stream content chunk error: #{e.message}"
      STDOUT.flush
    end

    # Stream update messages
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
    rescue IOError, Errno::EPIPE, Errno::ECONNRESET => e
      # Client disconnected - this is normal, not an error
      Rails.logger.info "Client disconnected during streaming: #{e.message}"
      puts "ℹ️ Client disconnected (normal): #{e.message}"
      STDOUT.flush
    rescue => e
      Rails.logger.error "Stream update failed: #{e.message}"
      puts "❌ Stream update failed: #{e.message}"
      STDOUT.flush
    end

    # Stream transient updates (for progress indicators)
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

    # Stream final response
    def stream_final_response(response_data)
      Rails.logger.info "🌊 stream_final_response called with data keys: #{response_data.keys}"
      Rails.logger.info "📝 Message length: #{response_data[:message]&.length} characters"
      Rails.logger.info "📝 Message preview: #{response_data[:message]&.first(100)}..."
      Rails.logger.info "📝 Message already saved: #{response_data[:message_already_saved]}"
      Rails.logger.info "🤖 Model used: #{response_data[:model_used].inspect}"
      Rails.logger.info "🤖 Model name: #{response_data[:model_name].inspect}"

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
