# Admin controller for managing Scout conversation sessions
class Admin::ScoutSessionsController < Admin::BaseController

  # GET /admin/scout_sessions
  def index
    @sessions = ScoutMessage
      .select(:session_id, 'MIN(created_at) as started_at', 'MAX(created_at) as last_message_at', 'COUNT(*) as message_count')
      .group(:session_id)
      .order('MAX(created_at) DESC')
      .limit(100)

    respond_to do |format|
      format.html
      format.json { render json: @sessions }
    end
  end

  # GET /admin/scout_sessions/:session_id
  def show
    @session_id = params[:id]
    @messages = ScoutMessage.for_session(@session_id).oldest_first

    # Get Redis stats if available
    begin
      memory = Scout::MemoryTools.new(@session_id)
      @redis_stats = memory.session_stats
    rescue => e
      Rails.logger.error "Failed to get Redis stats: #{e.message}"
      @redis_stats = nil
    end

    respond_to do |format|
      format.html
      format.json do
        render json: {
          session_id: @session_id,
          messages: @messages.map { |m|
            {
              id: m.id,
              role: m.role,
              content: m.content,
              created_at: m.created_at.iso8601,
              metadata: m.metadata
            }
          },
          redis_stats: @redis_stats
        }
      end
    end
  end

  # DELETE /admin/scout_sessions/:session_id
  def destroy
    session_id = params[:id]

    # Delete from database
    ScoutMessage.where(session_id: session_id).delete_all

    # Clear Redis
    begin
      memory = Scout::MemoryTools.new(session_id)
      memory.clear_session
    rescue => e
      Rails.logger.warn "Failed to clear Redis for session #{session_id}: #{e.message}"
    end

    # Clear Rails cache
    Rails.cache.delete("scout_conversation_#{session_id}")

    respond_to do |format|
      format.html { redirect_to admin_scout_sessions_path, notice: 'Session cleared successfully' }
      format.json { render json: { success: true, message: 'Session cleared' } }
    end
  end

  # POST /admin/scout_sessions/:session_id/sync_redis
  # Sync database messages to Redis for a session
  def sync_redis
    session_id = params[:id]

    begin
      memory = Scout::MemoryTools.new(session_id)

      # Clear existing Redis data
      memory.clear_session

      # Load all messages from database
      messages = ScoutMessage.for_session(session_id).oldest_first

      # Store each message in Redis
      synced_count = 0
      messages.each do |msg|
        if memory.store_message(msg.role, msg.content, msg.metadata || {})
          synced_count += 1
        end
      end

      render json: {
        success: true,
        message: "Synced #{synced_count} messages to Redis",
        session_id: session_id,
        synced_count: synced_count
      }
    rescue => e
      Rails.logger.error "Redis sync failed: #{e.message}"
      render json: {
        success: false,
        error: "Failed to sync to Redis: #{e.message}"
      }, status: 500
    end
  end

end
