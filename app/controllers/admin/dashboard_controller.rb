class Admin::DashboardController < Admin::BaseController
  def index
    @stats = {
      # User stats
      total_users: User.count,
      active_users_today: User.where("current_sign_in_at > ?", 24.hours.ago).count,
      new_users_this_week: User.where(created_at: 1.week.ago..).count,

      # Integration stats
      total_integrations: Integration.count,
      active_connections: Connection.active.count,
      failed_connections: Connection.failing.count,

      # API activity
      api_calls_today: integration_logs_today.count,
      api_errors_today: integration_logs_today.where("response_status >= 400").count,

      # AI usage stats
      ai_tokens_today: calculate_ai_tokens_today,
      ai_cost_today: calculate_ai_cost_today,

      # Campaign stats
      campaigns_sent_today: Campaign.where(status: "sent").where(created_at: 24.hours.ago..).count,
      total_campaigns: Campaign.count,
      total_contacts: Contact.count
    }

    # Recent activity
    @recent_api_calls = IntegrationLog.includes(:connection)
                                      .order(created_at: :desc)
                                      .limit(10)

    @recent_admin_activity = AdminActivity.includes(:admin_user)
                                          .order(created_at: :desc)
                                          .limit(10) rescue []

    # Failing connections
    @failing_connections = Connection.where.not(status: "connected").includes(:integration).limit(10)

    # Chart data
    @api_usage_chart_data = generate_api_usage_chart_data
    @error_rate_chart_data = generate_error_rate_chart_data
  end

  private

  def integration_logs_today
    @integration_logs_today ||= IntegrationLog.where(created_at: 24.hours.ago..)
  end

  def calculate_ai_tokens_today
    # This would aggregate from ObservabilityEvent or similar
    # For now, return a placeholder
    rand(10_000..50_000)
  end

  def calculate_ai_cost_today
    # Calculate based on token usage and model rates
    # For now, return a placeholder
    (calculate_ai_tokens_today * 0.00002).round(2)
  end

  def generate_api_usage_chart_data
    # Group by hour for the last 24 hours
    hours = (0..23).map { |h| h.hours.ago.beginning_of_hour }

    data = IntegrationLog.where(created_at: 24.hours.ago..)
                         .group_by_hour(:created_at)
                         .count

    {
      labels: hours.map { |h| h.strftime("%-l %p") },
      datasets: [ {
        label: "API Calls",
        data: hours.map { |h| data[h] || 0 },
        borderColor: "rgb(59, 130, 246)",
        backgroundColor: "rgba(59, 130, 246, 0.1)"
      } ]
    }
  end

  def generate_error_rate_chart_data
    # Calculate error rate by hour
    hours = (0..23).map { |h| h.hours.ago.beginning_of_hour }

    total_by_hour = IntegrationLog.where(created_at: 24.hours.ago..)
                                  .group_by_hour(:created_at)
                                  .count

    errors_by_hour = IntegrationLog.where(created_at: 24.hours.ago..)
                                   .where("response_status >= 400")
                                   .group_by_hour(:created_at)
                                   .count

    {
      labels: hours.map { |h| h.strftime("%-l %p") },
      datasets: [ {
        label: "Error Rate %",
        data: hours.map do |h|
          total = total_by_hour[h] || 0
          errors = errors_by_hour[h] || 0
          total > 0 ? ((errors.to_f / total) * 100).round(2) : 0
        end,
        borderColor: "rgb(239, 68, 68)",
        backgroundColor: "rgba(239, 68, 68, 0.1)"
      } ]
    }
  end
end
