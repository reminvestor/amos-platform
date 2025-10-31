# Keep-alive mechanism for SSE streams during long operations
module Scout
  module StreamingKeepalive
    extend ActiveSupport::Concern
    
    # Send keep-alive ping to prevent connection timeout
    def stream_keepalive
      # Send a minimal comment that won't be displayed but keeps connection open
      # SSE comments start with colon
      response.stream.write(":keepalive #{Time.current.to_i}\n\n")
      
      # Flush to ensure it's sent
      begin
        response.stream.flush if response.stream.respond_to?(:flush)
      rescue IOError, Errno::EPIPE, Errno::ECONNRESET => e
        # Connection already closed
        Rails.logger.debug "Keep-alive skipped - client disconnected: #{e.message}"
        raise e # Re-raise to stop the keep-alive thread
      end
    end
    
    # Start a background thread to send keep-alive pings
    def start_keepalive_thread
      @keepalive_running = true
      @keepalive_thread = Thread.new do
        begin
          while @keepalive_running
            sleep 15 # Send ping every 15 seconds
            stream_keepalive if @keepalive_running
          end
        rescue IOError, Errno::EPIPE, Errno::ECONNRESET => e
          Rails.logger.info "Keep-alive thread stopped - client disconnected"
        rescue => e
          Rails.logger.error "Keep-alive thread error: #{e.message}"
        end
      end
    end
    
    # Stop the keep-alive thread
    def stop_keepalive_thread
      @keepalive_running = false
      @keepalive_thread&.kill
      @keepalive_thread = nil
    end
  end
end
