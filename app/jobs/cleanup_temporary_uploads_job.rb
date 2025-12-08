class CleanupTemporaryUploadsJob < ApplicationJob
  queue_as :maintenance
  
  def perform
    Rails.logger.info "🧹 Starting temporary uploads cleanup..."
    
    # Find expired temporary blobs
    # Note: metadata column type varies - use LIKE for text, @> for jsonb
    expired_blobs = ActiveStorage::Blob
      .where("metadata::text LIKE ?", '%"temporary":true%')
      .where("metadata::text LIKE ?", '%expires_at%')
    
    expired_count = 0
    
    # Delete expired blobs (check expiration in Ruby since column type varies)
    expired_blobs.find_each do |blob|
      begin
        metadata = blob.metadata
        next unless metadata.is_a?(Hash) && metadata['temporary'] == true
        
        expires_at = metadata['expires_at']
        next unless expires_at.present?
        
        # Parse expiration time
        expiry_time = Time.parse(expires_at) rescue nil
        next unless expiry_time && expiry_time < Time.current
        
        blob.purge
        expired_count += 1
        Rails.logger.info "  Purged temporary blob: #{blob.filename}"
      rescue => e
        Rails.logger.error "  Failed to purge blob #{blob.id}: #{e.message}"
      end
    end
    
    Rails.logger.info "✅ Cleaned up #{expired_count} temporary uploads"
  end
end
