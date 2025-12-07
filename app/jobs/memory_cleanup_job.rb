# MemoryCleanupJob
#
# Handles memory retention policies:
# - Archives old messages (moves to L3/L4)
# - Deletes messages beyond retention period
# - Cleans up orphaned segments
# - Applies relevance decay to old segments
#
# Run schedule: Daily at 3 AM
#
class MemoryCleanupJob < ApplicationJob
  queue_as :low_priority

  # Default retention policies
  DEFAULT_RETENTION = {
    raw_messages_days: 90,       # Keep raw messages for 90 days
    summarized_messages_days: 365, # Keep summarized references for 1 year
    inactive_segments_days: 180,  # Archive inactive segments after 6 months
    bookmarks_days: nil,          # Never auto-delete bookmarks
    min_messages_to_keep: 100     # Always keep at least 100 messages per user
  }.freeze

  def perform(options = {})
    @options = DEFAULT_RETENTION.merge(options.symbolize_keys)
    @stats = { messages_archived: 0, messages_deleted: 0, segments_archived: 0, segments_deleted: 0 }

    Rails.logger.info "🧹 MemoryCleanupJob: Starting with options #{@options}"

    # Run cleanup tasks
    archive_old_messages
    delete_expired_messages
    cleanup_segments
    apply_relevance_decay
    cleanup_redis_l2

    Rails.logger.info "🧹 MemoryCleanupJob: Complete - #{@stats}"

    @stats
  rescue => e
    Rails.logger.error "MemoryCleanupJob error: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    raise
  end

  private

  # Move old unsummarized messages to L3 (trigger summarization)
  def archive_old_messages
    cutoff = @options[:raw_messages_days].days.ago

    # Find entities with old unsummarized messages
    entity_ids = ScoutMessage.where(summarized: false)
                             .where("created_at < ?", cutoff)
                             .distinct
                             .pluck(:entity_id)

    entity_ids.each do |entity_id|
      entity = Entity.find_by(id: entity_id)
      next unless entity

      # Get users with messages in this entity
      user_ids = ScoutMessage.where(entity_id: entity_id, summarized: false)
                             .where("created_at < ?", cutoff)
                             .distinct
                             .pluck(:user_id)

      user_ids.each do |user_id|
        # Queue summarization for this user/entity
        CreateMemorySegmentJob.perform_later(user_id, entity_id, 'daily')
        @stats[:messages_archived] += 1
      end
    end
  end

  # Delete messages beyond retention period (if summarized)
  def delete_expired_messages
    return unless @options[:summarized_messages_days].present?

    cutoff = @options[:summarized_messages_days].days.ago

    # Only delete summarized messages beyond retention
    # SECURITY: This is a global cleanup, but messages are already scoped per-user
    # and we're only deleting old, summarized content
    
    # Group by user/entity to respect min_messages_to_keep
    ScoutMessage.where(summarized: true)
                .where("created_at < ?", cutoff)
                .group(:user_id, :entity_id)
                .having("COUNT(*) > ?", @options[:min_messages_to_keep])
                .pluck(:user_id, :entity_id)
                .each do |user_id, entity_id|
      
      # Keep minimum messages, delete the rest
      messages_to_keep = ScoutMessage.where(user_id: user_id, entity_id: entity_id)
                                     .order(created_at: :desc)
                                     .limit(@options[:min_messages_to_keep])
                                     .pluck(:id)

      deleted = ScoutMessage.where(user_id: user_id, entity_id: entity_id)
                            .where(summarized: true)
                            .where("created_at < ?", cutoff)
                            .where.not(id: messages_to_keep)
                            .delete_all

      @stats[:messages_deleted] += deleted
    end
  end

  # Archive/delete old segments
  def cleanup_segments
    return unless @options[:inactive_segments_days].present?

    cutoff = @options[:inactive_segments_days].days.ago

    # Archive inactive segments
    archived = MemorySegment.where(active: true)
                            .where("period_end < ?", cutoff)
                            .where("last_retrieved_at IS NULL OR last_retrieved_at < ?", 30.days.ago)
                            .update_all(active: false)

    @stats[:segments_archived] = archived

    # Delete very old inactive segments (1 year)
    if @options[:summarized_messages_days].present?
      deleted = MemorySegment.where(active: false)
                             .where("updated_at < ?", @options[:summarized_messages_days].days.ago)
                             .delete_all

      @stats[:segments_deleted] = deleted
    end
  end

  # Apply relevance decay to old segments
  def apply_relevance_decay
    # Segments older than 7 days: 10% decay
    MemorySegment.where(active: true)
                 .where("period_end < ?", 7.days.ago)
                 .where("relevance_decay > 0.1")
                 .update_all("relevance_decay = relevance_decay * 0.9")

    # Segments older than 30 days: 20% decay
    MemorySegment.where(active: true)
                 .where("period_end < ?", 30.days.ago)
                 .where("relevance_decay > 0.1")
                 .update_all("relevance_decay = relevance_decay * 0.8")

    # Segments older than 90 days: 30% decay
    MemorySegment.where(active: true)
                 .where("period_end < ?", 90.days.ago)
                 .where("relevance_decay > 0.1")
                 .update_all("relevance_decay = relevance_decay * 0.7")
  end

  # Clean up expired Redis L2 data
  def cleanup_redis_l2
    # Redis handles TTL automatically, but we can clean up orphaned keys
    begin
      pattern = "scout:memory:l2:*"
      cursor = "0"
      cleaned = 0

      loop do
        cursor, keys = $redis.scan(cursor, match: pattern, count: 100)

        keys.each do |key|
          # Extract user_id and entity_id from key
          # Format: scout:memory:l2:user_id:entity_id
          parts = key.split(":")
          next unless parts.length >= 5

          user_id = parts[3].to_i
          entity_id = parts[4].to_i

          # Check if user/entity still exists
          unless User.exists?(user_id) && Entity.exists?(entity_id)
            $redis.del(key)
            cleaned += 1
          end
        end

        break if cursor == "0"
      end

      Rails.logger.info "🧹 Cleaned #{cleaned} orphaned Redis keys" if cleaned > 0
    rescue => e
      Rails.logger.warn "Redis cleanup failed: #{e.message}"
    end
  end
end
