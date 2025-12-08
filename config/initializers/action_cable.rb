# Ensure ActionCable uses Redis for pub/sub in ALL processes (web + workers)
# This is critical for broadcasts from SolidQueue workers to reach web clients

Rails.application.configure do
  # Force ActionCable to use the cable.yml configuration
  # This ensures background workers can broadcast to web clients via Redis pub/sub
  
  config.after_initialize do
    if defined?(ActionCable::Server::Base)
      # Get the cable configuration
      cable_config = Rails.application.config_for(:cable)
      
      process_type = defined?(SolidQueue::Supervisor) ? "WORKER" : "WEB"
      
      Rails.logger.info "[ActionCable:#{process_type}] Initializing with adapter: #{cable_config[:adapter]}"
      Rails.logger.info "[ActionCable:#{process_type}] Redis URL: #{cable_config[:url]&.gsub(/\/\/.*@/, '//***@')}"
      Rails.logger.info "[ActionCable:#{process_type}] Channel prefix: #{cable_config[:channel_prefix]}"
      
      # Ensure the pubsub adapter is properly initialized
      # This is especially important for non-server processes (like SolidQueue workers)
      if cable_config[:adapter] == 'redis'
        begin
          # Force initialization of the pubsub adapter
          pubsub = ActionCable.server.pubsub
          Rails.logger.info "[ActionCable:#{process_type}] ✅ Pubsub adapter class: #{pubsub.class.name}"
          
          # Test Redis connection
          if pubsub.respond_to?(:redis) || pubsub.instance_variable_get(:@redis_connection)
            Rails.logger.info "[ActionCable:#{process_type}] ✅ Redis connection available"
          end
        rescue => e
          Rails.logger.error "[ActionCable:#{process_type}] ❌ Failed to initialize pubsub: #{e.message}"
          Rails.logger.error e.backtrace.first(5).join("\n")
        end
      else
        Rails.logger.warn "[ActionCable:#{process_type}] ⚠️ Using #{cable_config[:adapter]} adapter - cross-process broadcasts may not work"
      end
    end
  end
end
