class Entity::ObservabilityController < Entity::BaseController

  def index
    @timeframe = params[:timeframe] || "30d"
    timeframe_start = case @timeframe
    when "today" then 24.hours.ago
    when "7d" then 7.days.ago
    when "30d" then 30.days.ago
    else 30.days.ago
    end

    # AI Usage for this entity
    @ai_stats = {
      conversations: current_user.scout_conversations.where(created_at: timeframe_start..).count,
      messages: current_user.scout_messages.where(created_at: timeframe_start..).count,
      workflows_started: current_user.task_sessions.where(created_at: timeframe_start..).count,
      workflows_completed: current_user.task_sessions.where(status: "completed", created_at: timeframe_start..).count,
      workflows_failed: current_user.task_sessions.where(status: "failed", created_at: timeframe_start..).count,
      estimated_tokens: current_user.scout_messages.where(created_at: timeframe_start..).count * 500,
      estimated_cost: (current_user.scout_messages.where(created_at: timeframe_start..).count * 500 * 0.00002).round(2)
    }

    # Integration Usage
    @integration_stats = {
      active_connections: current_user.connections.where(status: "connected").count,
      api_calls: IntegrationLog.joins(connection: :entity)
                               .where(connections: { entity_id: current_entity.id })
                               .where(created_at: timeframe_start..).count,
      failed_calls: IntegrationLog.joins(connection: :entity)
                                  .where(connections: { entity_id: current_entity.id })
                                  .where("response_status >= 400")
                                  .where(created_at: timeframe_start..).count
    }

    # Campaign Stats
    @campaign_stats = {
      total: current_user.campaigns.where(entity: current_entity, created_at: timeframe_start..).count,
      sent: current_user.campaigns.where(entity: current_entity, status: "sent", created_at: timeframe_start..).count,
      draft: current_user.campaigns.where(entity: current_entity, status: "draft", created_at: timeframe_start..).count
    }

    # Recent Activity
    @recent_workflows = current_user.task_sessions.order(created_at: :desc).limit(10)
  end
end
