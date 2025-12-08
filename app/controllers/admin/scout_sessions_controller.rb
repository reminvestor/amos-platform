# Admin controller for managing Scout conversation sessions
class Admin::ScoutSessionsController < Admin::BaseController

  # GET /admin/scout_sessions
  def index
    @sessions = ScoutMessage
      .select(:session_id, :user_id, :entity_id, 
              'MIN(created_at) as started_at', 
              'MAX(created_at) as last_message_at', 
              'COUNT(*) as message_count')
      .group(:session_id, :user_id, :entity_id)
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

    # Get memory stats from database
    first_msg = @messages.first
    @memory_stats = if first_msg&.user_id && first_msg&.entity_id
      {
        total_messages: ScoutMessage.where(user_id: first_msg.user_id, entity_id: first_msg.entity_id).count,
        memory_segments: MemorySegment.where(user_id: first_msg.user_id, entity_id: first_msg.entity_id, active: true).count,
        bookmarks: MemoryBookmark.where(user_id: first_msg.user_id, entity_id: first_msg.entity_id).count
      }
    else
      nil
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
          memory_stats: @memory_stats
        }
      end
    end
  end

  # DELETE /admin/scout_sessions/:session_id
  def destroy
    session_id = params[:id]

    # Delete from database
    ScoutMessage.where(session_id: session_id).delete_all

    # Clear Rails cache
    Rails.cache.delete("scout_conversation_#{session_id}")

    respond_to do |format|
      format.html { redirect_to admin_scout_sessions_path, notice: 'Session cleared successfully' }
      format.json { render json: { success: true, message: 'Session cleared' } }
    end
  end

end
