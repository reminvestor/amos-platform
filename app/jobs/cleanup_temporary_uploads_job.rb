class CleanupTemporaryUploadsJob < ApplicationJob
  queue_as :maintenance

  # How long to keep web page screenshots (local storage only)
  WEB_CAPTURE_RETENTION = 24.hours

  def perform
    Rails.logger.info "🧹 Starting temporary uploads cleanup..."

    cleanup_temporary_blobs
    cleanup_web_captures

    Rails.logger.info "✅ Cleanup complete"
  end

  private

  def cleanup_temporary_blobs
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

    Rails.logger.info "  Cleaned up #{expired_count} temporary blobs"
  end

  def cleanup_web_captures
    captures_dir = Rails.root.join("public", "web_captures")
    return unless Dir.exist?(captures_dir)

    cutoff_time = WEB_CAPTURE_RETENTION.ago
    deleted_count = 0

    Dir.glob(captures_dir.join("*.png")).each do |filepath|
      begin
        file_mtime = File.mtime(filepath)
        if file_mtime < cutoff_time
          File.delete(filepath)
          deleted_count += 1
          Rails.logger.info "  Deleted old web capture: #{File.basename(filepath)}"
        end
      rescue => e
        Rails.logger.error "  Failed to delete #{filepath}: #{e.message}"
      end
    end

    Rails.logger.info "  Cleaned up #{deleted_count} web captures older than #{WEB_CAPTURE_RETENTION.inspect}"
  end
end
