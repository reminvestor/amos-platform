# Admin::MemoryController
#
# Dashboard for monitoring the unified memory system.
# Shows statistics, health metrics, and allows manual cleanup.
#
class Admin::MemoryController < Admin::BaseController
  before_action :authorize_admin!, only: [:cleanup, :purge]

  # GET /admin/memory
  def index
    @stats = calculate_memory_stats
    @recent_segments = MemorySegment.order(created_at: :desc).limit(10)
    @recent_bookmarks = MemoryBookmark.order(created_at: :desc).limit(10)
    @entity_stats = calculate_entity_stats
  end

  # GET /admin/memory/health
  def health
    @health = {
      redis_connected: redis_connected?,
      redis_memory_usage: redis_memory_usage,
      postgres_message_count: ScoutMessage.count,
      segment_count: MemorySegment.count,
      bookmark_count: MemoryBookmark.count,
      oldest_unsummarized: ScoutMessage.where(summarized: false).minimum(:created_at),
      jobs_queued: jobs_queued_count
    }

    respond_to do |format|
      format.html
      format.json { render json: @health }
    end
  end

  # POST /admin/memory/cleanup
  # Run manual cleanup
  def cleanup
    authorize_admin!(:editor)

    options = {
      retention_days: params[:retention_days]&.to_i || 90,
      summarize_unsummarized: params[:summarize_unsummarized] == 'true'
    }

    MemoryCleanupJob.perform_later(options)

    redirect_to admin_memory_path, notice: "Memory cleanup job queued"
  end

  # DELETE /admin/memory/purge/:entity_id
  # Purge all memory for an entity (dangerous!)
  def purge
    authorize_admin!(:super_admin)

    entity = Entity.find(params[:entity_id])

    # Queue deletion jobs
    ScoutMessage.where(entity: entity).in_batches.destroy_all
    MemorySegment.where(entity: entity).destroy_all
    MemoryBookmark.where(entity: entity).destroy_all
    ConversationSummary.where(entity: entity).destroy_all

    redirect_to admin_memory_path, notice: "Memory purged for #{entity.name}"
  end

  # GET /admin/memory/entity/:id
  def entity_detail
    @entity = Entity.find(params[:id])
    @messages = ScoutMessage.where(entity: @entity).order(created_at: :desc).limit(100)
    @segments = MemorySegment.where(entity: @entity).order(created_at: :desc)
    @bookmarks = MemoryBookmark.where(entity: @entity).order(created_at: :desc)

    @stats = {
      total_messages: ScoutMessage.where(entity: @entity).count,
      summarized_messages: ScoutMessage.where(entity: @entity, summarized: true).count,
      active_segments: MemorySegment.where(entity: @entity, active: true).count,
      bookmarks: @bookmarks.count,
      oldest_message: ScoutMessage.where(entity: @entity).minimum(:created_at),
      newest_message: ScoutMessage.where(entity: @entity).maximum(:created_at)
    }
  end

  private

  def calculate_memory_stats
    {
      # Message stats
      total_messages: ScoutMessage.count,
      messages_today: ScoutMessage.where("created_at > ?", Time.current.beginning_of_day).count,
      messages_this_week: ScoutMessage.where("created_at > ?", 1.week.ago).count,
      summarized_messages: ScoutMessage.where(summarized: true).count,
      summarization_rate: calculate_summarization_rate,

      # Memory layers
      l1_messages: ScoutMessage.where(memory_layer: 'l1').count,
      l2_messages: ScoutMessage.where(memory_layer: 'l2').count,
      l3_messages: ScoutMessage.where(memory_layer: 'l3').count,

      # Segments
      total_segments: MemorySegment.count,
      active_segments: MemorySegment.where(active: true).count,
      daily_segments: MemorySegment.where(segment_type: 'daily').count,
      weekly_segments: MemorySegment.where(segment_type: 'weekly').count,

      # Bookmarks
      total_bookmarks: MemoryBookmark.count,
      shared_bookmarks: MemoryBookmark.where(shareable: true).count,
      total_bookmark_views: MemoryBookmark.sum(:view_count),

      # Entities using memory
      entities_with_messages: ScoutMessage.distinct.count(:entity_id),
      users_with_messages: ScoutMessage.distinct.count(:user_id),

      # Storage estimates
      estimated_tokens: estimate_total_tokens,
      estimated_storage_mb: estimate_storage_mb
    }
  end

  def calculate_entity_stats
    Entity.joins(:scout_messages)
          .group('entities.id', 'entities.name')
          .select('entities.id, entities.name, COUNT(scout_messages.id) as message_count')
          .order('message_count DESC')
          .limit(20)
  end

  def calculate_summarization_rate
    total = ScoutMessage.where("created_at < ?", 24.hours.ago).count
    return 0 if total.zero?

    summarized = ScoutMessage.where(summarized: true).where("created_at < ?", 24.hours.ago).count
    ((summarized.to_f / total) * 100).round(1)
  end

  def estimate_total_tokens
    # Rough estimate: average message ~200 chars = ~50 tokens
    (ScoutMessage.count * 50)
  end

  def estimate_storage_mb
    # Rough estimate based on average message size
    avg_message_size = 500 # bytes
    ((ScoutMessage.count * avg_message_size) / 1_000_000.0).round(2)
  end

  def redis_connected?
    $redis.ping == "PONG"
  rescue
    false
  end

  def redis_memory_usage
    info = $redis.info("memory")
    {
      used_memory_human: info["used_memory_human"],
      used_memory_peak_human: info["used_memory_peak_human"]
    }
  rescue
    { error: "Could not retrieve Redis memory info" }
  end

  def jobs_queued_count
    # Check Sidekiq queue
    if defined?(Sidekiq)
      Sidekiq::Queue.new('low_priority').size
    else
      0
    end
  rescue
    0
  end
end
