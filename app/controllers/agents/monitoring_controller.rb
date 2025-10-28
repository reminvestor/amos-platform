module Agents
  class MonitoringController < ApplicationController
    layout 'admin'
    before_action :authenticate_user!
    before_action :ensure_admin_access
    before_action :set_current_admin

    def index
      @agents = Agents::Communication::AgentRegistry.instance.active_agents
      @system_metrics = Agents::Observability::PerformanceMonitor.instance.system_metrics
      @active_traces = Agents::Observability::DecisionTracer.instance.active_traces
    end

    def agent_details
      agent_id = params[:id]

      @agent = Agents::Communication::AgentRegistry.instance.find(agent_id)
      @metrics = Agents::Observability::PerformanceMonitor.instance.agent_metrics(agent_id)
      @traces = Agents::Observability::DecisionTracer.instance.trace_history(agent_id: agent_id, time_range: 24.hours)
      @memory_snapshot = @agent&.memory&.snapshot

      respond_to do |format|
        format.html
        format.json { render json: agent_data }
      end
    end

    def performance_metrics
      time_range = params[:time_range]&.to_i&.hours || 1.hour

      metrics = {
        system: Agents::Observability::PerformanceMonitor.instance.system_metrics(time_range),
        agents: agent_performance_data(time_range),
        resources: current_entity ? ResourceManager.new(current_entity).resource_usage_summary : {},
        circuit_breakers: Agents::Observability::CircuitBreakerRegistry.instance.status
      }

      render json: metrics
    end

    def decision_traces
      filters = {
        agent_id: params[:agent_id],
        decision_type: params[:decision_type],
        time_range: (params[:hours]&.to_i || 24).hours,
        outcome: params[:outcome]&.to_sym
      }.compact

      traces = Agents::Observability::DecisionTracer.instance.trace_history(filters)

      render json: {
        traces: traces,
        summary: summarize_traces(traces)
      }
    end

    def collaboration_network
      network = Agents::Observability::PerformanceMonitor.instance.collaboration_network

      # Convert to D3.js format
      nodes = network.keys.map { |id| { id: id, group: agent_group(id) } }
      links = []

      network.each do |source, targets|
        targets.each do |target_data|
          links << {
            source: source,
            target: target_data[:partner],
            value: target_data[:count],
            type: target_data[:type]
          }
        end
      end

      render json: { nodes: nodes, links: links }
    end

    def learning_insights
      time_range = (params[:days]&.to_i || 7).days

      insights = Agents::Observability::LearningEngine.instance.get_performance_analytics(time_range)

      render json: insights
    end

    def resource_usage
      if current_entity
        resource_manager = ResourceManager.new(current_entity)
        @resource_stats = resource_manager.resource_usage_summary
        @token_usage = {
          current: current_entity.token_usage,
          limit: current_entity.token_limit,
          percentage: current_entity.token_limit ? ((current_entity.token_usage.to_f / current_entity.token_limit) * 100).round(2) : 0
        }
        @cost_breakdown = AiUsageLog.for_entity(current_entity.id).within(30.days).sum(:cost_cents) / 100.0
      else
        @resource_stats = {}
        @token_usage = {}
        @cost_breakdown = 0
      end

      respond_to do |format|
        format.html
        format.json {
          render json: {
            resources: @resource_stats,
            tokens: @token_usage,
            costs: @cost_breakdown
          }
        }
      end
    end

    def alerts
      @alerts = fetch_recent_alerts
      @alert_summary = summarize_alerts(@alerts)

      respond_to do |format|
        format.html
        format.json { render json: { alerts: @alerts, summary: @alert_summary } }
      end
    end

    def export_report
      report_type = params[:type] || "full"
      time_range = (params[:days]&.to_i || 7).days

      report = generate_report(report_type, time_range)

      respond_to do |format|
        format.pdf { send_data report.to_pdf, filename: "agent_report_#{Date.current}.pdf" }
        format.csv { send_data report.to_csv, filename: "agent_report_#{Date.current}.csv" }
        format.json { render json: report.to_h }
      end
    end

    private

    def ensure_admin_access
      unless current_user.admin? || current_user.developer_mode?
        redirect_to scout_path, alert: "Access denied"
      end
    end
    
    def set_current_admin
      # Find or create admin user for the current user
      @current_admin = AdminUser.find_by(email: current_user.email) || 
                       AdminUser.find_by(user_id: current_user.id)
      
      # If no admin exists but user is admin, show message
      unless @current_admin
        Rails.logger.warn "User #{current_user.email} is admin but has no AdminUser record"
        @current_admin = OpenStruct.new(
          id: current_user.id,
          full_name: current_user.full_name,
          email: current_user.email,
          role: 'viewer'
        )
      end
    end

    def agent_data
      {
        agent: {
          id: @agent.id,
          role: @agent.role,
          state: @agent.state,
          capabilities: @agent.capabilities
        },
        metrics: @metrics,
        traces: @traces.first(10),
        memory: @memory_snapshot
      }
    end

    def agent_performance_data(time_range)
      agents = Agents::Communication::AgentRegistry.instance.active_agents

      agents.map do |agent|
        metrics = Agents::Observability::PerformanceMonitor.instance.agent_metrics(agent.id, time_range)
        {
          id: agent.id,
          role: agent.role,
          metrics: metrics
        }
      end
    end

    def summarize_traces(traces)
      {
        total: traces.size,
        by_outcome: traces.group_by { |t| t[:outcome] }.transform_values(&:count),
        average_duration: traces.sum { |t| t[:duration] || 0 } / traces.size.to_f,
        average_confidence: traces.sum { |t| t[:quality_metrics][:average_confidence] || 0 } / traces.size.to_f
      }
    end

    def agent_group(agent_id)
      agent = Agents::Communication::AgentRegistry.instance.find(agent_id)
      agent&.role || "unknown"
    end

    def fetch_recent_alerts
      # Fetch from various sources
      performance_alerts = Agents::Observability::PerformanceMonitor.instance.system_metrics[:alerts] || []
      resource_alerts = fetch_resource_alerts
      circuit_breaker_alerts = fetch_circuit_breaker_alerts

      (performance_alerts + resource_alerts + circuit_breaker_alerts)
        .sort_by { |a| a[:timestamp] }
        .reverse
        .first(100)
    end

    def fetch_resource_alerts
      # Implementation to fetch resource-related alerts
      []
    end

    def fetch_circuit_breaker_alerts
      # Implementation to fetch circuit breaker alerts
      []
    end

    def summarize_alerts(alerts)
      {
        total: alerts.size,
        by_severity: alerts.group_by { |a| a[:severity] }.transform_values(&:count),
        by_type: alerts.group_by { |a| a[:metric] || a[:type] }.transform_values(&:count),
        critical_count: alerts.count { |a| a[:severity] == :critical }
      }
    end

    def generate_report(report_type, time_range)
      case report_type
      when "performance"
        Agents::Observability::PerformanceReport.new(
          Agents::Observability::PerformanceMonitor.instance.instance_variable_get(:@metrics),
          time_range
        ).generate
      when "learning"
        Agents::Observability::LearningEngine.instance.get_performance_analytics(time_range)
        when "full"
        {
          performance: generate_report("performance", time_range),
          learning: generate_report("learning", time_range),
          resources: current_entity ? ResourceManager.new(current_entity).resource_usage_summary : {},
          generated_at: Time.current
        }
      end
    end
  end
end
