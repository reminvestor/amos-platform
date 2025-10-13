# Auto-discover integration operations on startup
# This keeps the database in sync with generated integration code

Rails.application.config.after_initialize do
  # Only run in development and production (not in test or rake tasks)
  next if Rails.env.test? || defined?(Rails::Console) || File.basename($PROGRAM_NAME) == 'rake'
  
  Rails.logger.info "🔍 Starting integration operation auto-discovery..."
  
  begin
    result = OperationDiscoveryService.discover_all
    
    if result[:success]
      Rails.logger.info "✅ Integration discovery complete: #{result[:discovered]} operations discovered"
      
      if result[:errors].any?
        Rails.logger.warn "⚠️ Discovery errors: #{result[:errors].length}"
        result[:errors].each { |error| Rails.logger.warn "  - #{error}" }
      end
    else
      Rails.logger.error "❌ Integration discovery failed"
    end
  rescue => e
    Rails.logger.error "❌ Integration discovery error: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
  end
end

