class DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :set_current_admin
  layout 'customer_admin'

  def index
    @entity = current_entity

    # Quick stats
    @campaigns_count = current_user.campaigns.where(entity: @entity).count
    @contacts_count = current_user.contacts.where(entity: @entity).count
    @landing_pages_count = current_user.landing_pages.where(entity: @entity).count
    @email_templates_count = current_user.email_templates.where(entity: @entity).count

    # Recent activity
    @recent_campaigns = current_user.campaigns.where(entity: @entity).order(created_at: :desc).limit(5)
    @recent_landing_pages = current_user.landing_pages.where(entity: @entity).order(created_at: :desc).limit(5)
    @recent_contacts = current_user.contacts.where(entity: @entity).order(created_at: :desc).limit(5)

    # Connections
    @active_connections = current_user.connections.where(status: "connected").includes(:integration)

    # AI Usage Stats (for the current user/entity)
    @ai_usage = calculate_user_ai_usage
  end

  private

  def set_current_admin
    # Set @current_admin to current_user for admin layout compatibility
    @current_admin = current_user
  end

  def calculate_user_ai_usage
    # Get AI usage from task sessions and scout messages
    timeframe = 30.days.ago

    {
      conversations_this_month: current_user.scout_conversations.where(created_at: timeframe..).count,
      messages_this_month: current_user.scout_messages.where(created_at: timeframe..).count,
      workflows_this_month: current_user.task_sessions.where(created_at: timeframe..).count,
      workflows_completed: current_user.task_sessions.where(status: "completed", created_at: timeframe..).count,
      # Placeholder for actual token tracking - will be real when implemented
      estimated_tokens: current_user.scout_messages.where(created_at: timeframe..).count * 500,
      estimated_cost: (current_user.scout_messages.where(created_at: timeframe..).count * 500 * 0.00002).round(2)
    }
  end
end
