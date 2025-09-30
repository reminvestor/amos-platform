module Agents
  class MonitoringController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_admin_access
    
    def index
      @agents = AgentRegistry.instance.all_agents
      @system_metrics = PerformanceMonitor.instance.system_metrics
      @active_traces = DecisionTracer.instance.active_traces
    end
    
    def agent_details
      agent_id = params[:id]
      
      @agent = AgentRegistry.instance.find(agent_id)
      @metrics = PerformanceMonitor.instance.agent_metrics(agent_id)
      @traces = DecisionTracer.instance.trace_history(agent_id: agent_id, time_range: 24.hours)
      @memory_snapshot = @agent&.memory&.snapshot
      
      respond_to do |format|
        format.html
        format.json { render json: agent_data }
      end
    end
    
    def performance_metrics
      time_range = params[:time_range]&.to_i&.hours || 1.hour
      
      metrics = {
        system: PerformanceMonitor.instance.system_metrics(time_range),
        agents: agent_performance_data(time_range),
        resources: ResourceManager.new(current_entity).usage_stats,
        circuit_breakers: CircuitBreakerRegistry.instance.status
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
      
      traces = DecisionTracer.instance.trace_history(filters)
      
      render json: {
        traces: traces,
        summary: summarize_traces(traces)
      }
    end
    
    def collaboration_network
      network = PerformanceMonitor.instance.collaboration_network
      
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
      
      insights = LearningEngine.instance.get_performance_analytics(time_range)
      
      render json: insights
    end
    
    def resource_usage
      @resource_stats = ResourceManager.new(current_entity).usage_stats
      @token_usage = ResourceManager.new(current_entity).token_usage_stats(time_range: 24.hours)
      @cost_breakdown = CostTracker.new(current_entity).current_totals
      
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
      report_type = params[:type] || 'full'
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
        redirect_to root_path, alert: 'Access denied'
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
      agents = AgentRegistry.instance.all_agents
      
      agents.map do |agent|
        metrics = PerformanceMonitor.instance.agent_metrics(agent.id, time_range)
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
      agent = AgentRegistry.instance.find(agent_id)
      agent&.role || 'unknown'
    end
    
    def fetch_recent_alerts
      # Fetch from various sources
      performance_alerts = PerformanceMonitor.instance.system_metrics[:alerts] || []
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
      when 'performance'
        PerformanceReport.new(
          PerformanceMonitor.instance.instance_variable_get(:@metrics),
          time_range
        ).generate
      when 'learning'
        LearningEngine.instance.get_performance_analytics(time_range)
      when 'full'
        {
          performance: generate_report('performance', time_range),
          learning: generate_report('learning', time_range),
          resources: ResourceManager.new(current_entity).usage_stats,
          generated_at: Time.current
        }
      end
    end
  end
end




