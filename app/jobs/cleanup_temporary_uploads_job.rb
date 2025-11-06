class CleanupTemporaryUploadsJob < ApplicationJob
  queue_as :maintenance
  
  def perform
    Rails.logger.info "🧹 Starting temporary uploads cleanup..."
    
    # Find expired temporary blobs
    expired_blobs = ActiveStorage::Blob
      .where("metadata @> ?", { temporary: true }.to_json)
      .where("(metadata->>'expires_at')::timestamp < ?", Time.current)
    
    expired_count = expired_blobs.count
    
    # Delete expired blobs
    expired_blobs.find_each do |blob|
      begin
        blob.purge
        Rails.logger.info "  Purged temporary blob: #{blob.filename}"
      rescue => e
        Rails.logger.error "  Failed to purge blob #{blob.id}: #{e.message}"
      end
    end
    
    Rails.logger.info "✅ Cleaned up #{expired_count} temporary uploads"
  end
end
