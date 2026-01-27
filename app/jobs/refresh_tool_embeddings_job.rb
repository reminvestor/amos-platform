# frozen_string_literal: true

# RefreshToolEmbeddingsJob
#
# Regenerates embeddings for class-based tools in the background.
# This runs periodically to ensure tool discovery via RAG works efficiently.
#
# Schedule: Runs daily (see config/recurring.yml)
#
class RefreshToolEmbeddingsJob < ApplicationJob
  queue_as :maintenance
  
  # Don't retry if it fails - will run again on schedule
  discard_on StandardError
  
  def perform
    Rails.logger.info "🔄 [RefreshToolEmbeddingsJob] Starting tool embeddings refresh..."
    
    start_time = Time.current
    
    begin
      service = ClassToolEmbeddingsService.instance
      
      # Check if embeddings are already cached
      if service.ready?
        Rails.logger.info "📚 [RefreshToolEmbeddingsJob] Tool embeddings already cached - skipping"
        return
      end
      
      # Generate embeddings synchronously (this is a background job)
      service.send(:generate_all_embeddings)
      
      duration = ((Time.current - start_time) * 1000).round
      Rails.logger.info "✅ [RefreshToolEmbeddingsJob] Completed in #{duration}ms"
    rescue => e
      Rails.logger.error "❌ [RefreshToolEmbeddingsJob] Failed: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      # Don't raise - let it fail silently and try again later
    end
  end
end
