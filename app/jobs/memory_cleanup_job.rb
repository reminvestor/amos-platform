# MemoryCleanupJob
#
# Handles memory retention policies for STORAGE OPTIMIZATION ONLY.
#
# IMPORTANT: This job only cleans up RAW MESSAGE TEXT to save storage.
# It NEVER deletes learned knowledge:
#   ✅ MemorySegment (summaries) - KEPT FOREVER
#   ✅ UserMemory (preferences, facts) - KEPT FOREVER
#   ✅ ScoutLearning (patterns) - KEPT FOREVER
#   ✅ BusinessInsight - KEPT FOREVER
#   ✅ MemoryBookmark (saved items) - KEPT FOREVER
#
# Scout compresses but NEVER forgets important information.
#
# Run schedule: Daily at 3 AM
#
class MemoryCleanupJob < ApplicationJob
  queue_as :low_priority

  # Default retention policies
  # NOTE: nil = keep forever (recommended default)
  DEFAULT_RETENTION = {
    raw_messages_days: nil,       # nil = keep forever, or set days to clean old messages
    summarized_messages_days: nil, # nil = keep forever (summarized msg references)
    inactive_segments_days: nil,  # nil = never archive segments (they're the memory!)
    bookmarks_days: nil,          # ALWAYS nil - never delete user bookmarks
    min_messages_to_keep: 500     # Always keep at least 500 messages per user
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

  # Delete RAW MESSAGE TEXT beyond retention period (if configured)
  # IMPORTANT: This only deletes the conversation text, NOT learned knowledge
  # MemorySegments, UserMemory, ScoutLearning etc are NEVER deleted here
  def delete_expired_messages
    # If retention is nil, keep everything forever (recommended default)
    return unless @options[:raw_messages_days].present?

    cutoff = @options[:raw_messages_days].days.ago

    Rails.logger.info "🧹 Cleaning raw messages older than #{cutoff}"
    Rails.logger.info "🧹 NOTE: Learned knowledge (segments, preferences, facts) is NEVER deleted"

    # Only delete messages that have been summarized (knowledge extracted)
    # NEVER delete unsummarized messages - they haven't been learned from yet!
    
    # Group by user/entity to respect min_messages_to_keep
    ScoutMessage.where(summarized: true)
                .where("created_at < ?", cutoff)
                .group(:user_id, :entity_id)
                .having("COUNT(*) > ?", @options[:min_messages_to_keep])
                .pluck(:user_id, :entity_id)
                .each do |user_id, entity_id|
      
      # Always keep minimum messages
      messages_to_keep = ScoutMessage.where(user_id: user_id, entity_id: entity_id)
                                     .order(created_at: :desc)
                                     .limit(@options[:min_messages_to_keep])
                                     .pluck(:id)

      # Only delete old, already-summarized messages
      deleted = ScoutMessage.where(user_id: user_id, entity_id: entity_id)
                            .where(summarized: true)  # Must be summarized first!
                            .where("created_at < ?", cutoff)
                            .where.not(id: messages_to_keep)
                            .delete_all

      @stats[:messages_deleted] += deleted
    end
  end

  # Archive old segments (mark inactive, but NEVER delete)
  # Segments ARE the learned knowledge - deleting them would erase memory!
  def cleanup_segments
    # By default, never archive or delete segments
    return unless @options[:inactive_segments_days].present?

    cutoff = @options[:inactive_segments_days].days.ago

    # Only mark as inactive (not deleted!) - they can still be searched
    archived = MemorySegment.where(active: true)
                            .where("period_end < ?", cutoff)
                            .where("last_retrieved_at IS NULL OR last_retrieved_at < ?", 90.days.ago)
                            .update_all(active: false)

    @stats[:segments_archived] = archived

    # NEVER delete segments - they contain learned knowledge
    # If storage is a concern, they should be compressed, not deleted
    @stats[:segments_deleted] = 0
    
    Rails.logger.info "🧹 Archived #{archived} old segments (NOT deleted - knowledge preserved)"
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
