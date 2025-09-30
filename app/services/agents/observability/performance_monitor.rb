module Agents
  module Observability
    class PerformanceMonitor
      include Singleton
      
      def initialize
        @metrics = Concurrent::Hash.new { |h, k| h[k] = AgentMetrics.new(k) }
        @alerts = Concurrent::Array.new
        @thresholds = load_thresholds
        @monitoring_thread = start_monitoring
      end
      
      # Record agent action
      def record_action(agent_id, action_type, duration, success, metadata = {})
        metrics = @metrics[agent_id]
        
        metrics.record_action(action_type, duration, success, metadata)
        
        # Check for threshold violations
        check_thresholds(agent_id, metrics)
        
        # Emit metrics event
        emit_metrics_event(agent_id, action_type, duration, success)
      end
      
      # Record resource usage
      def record_resource_usage(agent_id, resource_type, amount)
        @metrics[agent_id].record_resource(resource_type, amount)
      end
      
      # Record collaboration
      def record_collaboration(agent_id, other_agent_id, collaboration_type, outcome)
        @metrics[agent_id].record_collaboration(other_agent_id, collaboration_type, outcome)
      end
      
      # Get agent performance metrics
      def agent_metrics(agent_id, time_range = 1.hour)
        @metrics[agent_id].summary(time_range)
      end
      
      # Get system-wide metrics
      def system_metrics(time_range = 1.hour)
        {
          total_agents: @metrics.size,
          active_agents: count_active_agents(time_range),
          total_actions: sum_metric(:action_count),
          success_rate: calculate_overall_success_rate,
          resource_usage: aggregate_resource_usage,
          top_performers: identify_top_performers,
          bottlenecks: identify_bottlenecks,
          alerts: @alerts.last(20)
        }
      end
      
      # Get collaboration network
      def collaboration_network
        network = Hash.new { |h, k| h[k] = [] }
        
        @metrics.each do |agent_id, metrics|
          metrics.collaborations.each do |collab|
            network[agent_id] << {
              partner: collab[:other_agent_id],
              type: collab[:type],
              count: collab[:count],
              success_rate: collab[:success_rate]
            }
          end
        end
        
        network
      end
      
      # Generate performance report
      def generate_report(time_range = 24.hours)
        PerformanceReport.new(@metrics, time_range).generate
      end
      
      # Set alert threshold
      def set_threshold(metric_name, threshold_value, comparison = :greater_than)
        @thresholds[metric_name] = {
          value: threshold_value,
          comparison: comparison
        }
      end
      
      private
      
      def load_thresholds
        {
          error_rate: { value: 0.1, comparison: :greater_than },
          response_time_p95: { value: 5.0, comparison: :greater_than },
          resource_usage: { value: 1000, comparison: :greater_than },
          idle_time: { value: 300, comparison: :greater_than }
        }
      end
      
      def check_thresholds(agent_id, metrics)
        summary = metrics.summary(5.minutes)
        
        @thresholds.each do |metric_name, threshold|
          value = summary[metric_name]
          next unless value
          
          # Handle resource_usage which is a hash
          if metric_name == :resource_usage && value.is_a?(Hash)
            total_usage = value.values.sum
            if violates_threshold?(total_usage, threshold)
              create_alert(agent_id, metric_name, total_usage, threshold)
            end
          elsif !value.is_a?(Hash)
            if violates_threshold?(value, threshold)
              create_alert(agent_id, metric_name, value, threshold)
            end
          end
        end
      end
      
      def violates_threshold?(value, threshold)
        case threshold[:comparison]
        when :greater_than
          value > threshold[:value]
        when :less_than
          value < threshold[:value]
        when :equal_to
          value == threshold[:value]
        else
          false
        end
      end
      
      def create_alert(agent_id, metric_name, value, threshold)
        alert = {
          agent_id: agent_id,
          metric: metric_name,
          value: value,
          threshold: threshold[:value],
          timestamp: Time.current,
          severity: determine_severity(metric_name, value, threshold[:value])
        }
        
        @alerts << alert
        
        # Notify alert handlers
        notify_alert(alert)
      end
      
      def determine_severity(metric_name, value, threshold)
        ratio = value / threshold.to_f
        
        case metric_name
        when :error_rate
          ratio > 2 ? :critical : :warning
        when :response_time_p95
          ratio > 3 ? :critical : :warning
        else
          :info
        end
      end
      
      def notify_alert(alert)
        ActiveSupport::Notifications.instrument('agent.performance_alert', alert)
        
        # Log critical alerts
        if alert[:severity] == :critical
          Rails.logger.error "CRITICAL: Agent #{alert[:agent_id]} - #{alert[:metric]} = #{alert[:value]}"
        end
      end
      
      def count_active_agents(time_range)
        @metrics.count do |_, metrics|
          metrics.last_action_time && metrics.last_action_time > time_range.ago
        end
      end
      
      def sum_metric(metric_name)
        @metrics.sum { |_, metrics| metrics.send(metric_name) }
      end
      
      def calculate_overall_success_rate
        total_actions = sum_metric(:action_count)
        return 1.0 if total_actions == 0
        
        successful_actions = sum_metric(:successful_actions)
        successful_actions.to_f / total_actions
      end
      
      def aggregate_resource_usage
        resources = Hash.new(0)
        
        @metrics.each_value do |metrics|
          metrics.resource_usage.each do |type, amount|
            resources[type] += amount
          end
        end
        
        resources
      end
      
      def identify_top_performers
        @metrics
          .map { |id, m| { agent_id: id, score: m.performance_score } }
          .sort_by { |a| -a[:score] }
          .first(5)
      end
      
      def identify_bottlenecks
        bottlenecks = []
        
        # Slow agents
        slow_agents = @metrics.select do |id, metrics|
          metrics.average_response_time > 3.0
        end
        
        if slow_agents.any?
          bottlenecks << {
            type: :slow_response,
            agents: slow_agents.keys,
            impact: :high
          }
        end
        
        # High error rate agents
        error_prone = @metrics.select do |id, metrics|
          metrics.error_rate > 0.1
        end
        
        if error_prone.any?
          bottlenecks << {
            type: :high_errors,
            agents: error_prone.keys,
            impact: :critical
          }
        end
        
        bottlenecks
      end
      
      def emit_metrics_event(agent_id, action_type, duration, success)
        ActiveSupport::Notifications.instrument('agent.action_performed', {
          agent_id: agent_id,
          action_type: action_type,
          duration: duration,
          success: success
        })
      end
      
      def start_monitoring
        Thread.new do
          loop do
            begin
              # Collect and publish metrics every minute
              sleep 60
              publish_metrics
              cleanup_old_data
            rescue => e
              Rails.logger.error "Performance monitoring error: #{e.message}"
            end
          end
        end
      end
      
      def publish_metrics
        snapshot = {
          timestamp: Time.current,
          system: system_metrics(5.minutes),
          agents: @metrics.transform_values { |m| m.summary(5.minutes) }
        }
        
        # Broadcast via ActionCable
        ActionCable.server.broadcast('agent_performance', snapshot)
        
        # Store snapshot
        store_metrics_snapshot(snapshot)
      end
      
      def store_metrics_snapshot(snapshot)
        key = "metrics:snapshot:#{snapshot[:timestamp].to_i}"
        ($redis || Redis.new).setex(key, 24.hours, snapshot.to_json)
      end
      
      def cleanup_old_data
        @metrics.each_value(&:cleanup_old_data)
        
        # Keep only recent alerts
        @alerts.shift while @alerts.size > 1000
      end
    end
    
    # Per-agent metrics collector
    class AgentMetrics
      attr_reader :agent_id, :action_count, :successful_actions, :last_action_time
      
      def initialize(agent_id)
        @agent_id = agent_id
        @action_count = Concurrent::AtomicFixnum.new(0)
        @successful_actions = Concurrent::AtomicFixnum.new(0)
        @failed_actions = Concurrent::AtomicFixnum.new(0)
        @action_durations = Concurrent::Array.new
        @resource_usage = Concurrent::Hash.new { |h, k| h[k] = Concurrent::AtomicFixnum.new(0) }
        @collaborations = Concurrent::Array.new
        @last_action_time = nil
        @created_at = Time.current
      end
      
      def record_action(action_type, duration, success, metadata = {})
        @action_count.increment
        @last_action_time = Time.current
        
        if success
          @successful_actions.increment
        else
          @failed_actions.increment
        end
        
        @action_durations << {
          type: action_type,
          duration: duration,
          success: success,
          timestamp: Time.current,
          metadata: metadata
        }
        
        # Keep only recent data
        trim_old_actions
      end
      
      def record_resource(resource_type, amount)
        @resource_usage[resource_type].increment(amount)
      end
      
      def record_collaboration(other_agent_id, collaboration_type, outcome)
        @collaborations << {
          other_agent_id: other_agent_id,
          type: collaboration_type,
          outcome: outcome,
          timestamp: Time.current
        }
      end
      
      def summary(time_range = 1.hour)
        recent_actions = recent_actions(time_range)
        
        {
          agent_id: @agent_id,
          uptime: Time.current - @created_at,
          action_count: @action_count.value,
          success_rate: calculate_success_rate,
          error_rate: calculate_error_rate,
          average_response_time: calculate_average_duration(recent_actions),
          response_time_p95: calculate_percentile(recent_actions, 0.95),
          response_time_p99: calculate_percentile(recent_actions, 0.99),
          resource_usage: @resource_usage.transform_values(&:value),
          recent_failures: recent_failures(time_range),
          idle_time: calculate_idle_time,
          performance_score: calculate_performance_score
        }
      end
      
      def performance_score
        calculate_performance_score
      end
      
      def average_response_time
        calculate_average_duration(@action_durations)
      end
      
      def error_rate
        calculate_error_rate
      end
      
      def cleanup_old_data
        trim_old_actions
        trim_old_collaborations
      end
      
      private
      
      def recent_actions(time_range)
        cutoff = Time.current - time_range
        @action_durations.select { |a| a[:timestamp] > cutoff }
      end
      
      def calculate_success_rate
        total = @action_count.value
        return 1.0 if total == 0
        
        @successful_actions.value.to_f / total
      end
      
      def calculate_error_rate
        total = @action_count.value
        return 0.0 if total == 0
        
        @failed_actions.value.to_f / total
      end
      
      def calculate_average_duration(actions)
        return 0 if actions.empty?
        
        total = actions.sum { |a| a[:duration] }
        total / actions.size
      end
      
      def calculate_percentile(actions, percentile)
        return 0 if actions.empty?
        
        sorted = actions.map { |a| a[:duration] }.sort
        index = (sorted.size * percentile).ceil - 1
        sorted[index] || sorted.last
      end
      
      def recent_failures(time_range)
        recent_actions(time_range)
          .select { |a| !a[:success] }
          .group_by { |a| a[:type] }
          .transform_values(&:count)
      end
      
      def calculate_idle_time
        return 0 unless @last_action_time
        
        Time.current - @last_action_time
      end
      
      def calculate_performance_score
        # Composite score based on multiple factors
        success_weight = calculate_success_rate * 40
        speed_weight = [1.0 - (average_response_time / 10.0), 0].max * 30
        efficiency_weight = calculate_efficiency_score * 20
        reliability_weight = [1.0 - calculate_error_rate, 0].max * 10
        
        success_weight + speed_weight + efficiency_weight + reliability_weight
      end
      
      def calculate_efficiency_score
        return 1.0 if @action_count.value == 0
        
        # Resource usage per action
        total_resources = @resource_usage.values.sum(&:value)
        resources_per_action = total_resources.to_f / @action_count.value
        
        # Lower is better
        case resources_per_action
        when 0..10 then 1.0
        when 11..50 then 0.8
        when 51..100 then 0.6
        else 0.4
        end
      end
      
      def trim_old_actions
        cutoff = 1.hour.ago
        @action_durations.delete_if { |a| a[:timestamp] < cutoff }
      end
      
      def trim_old_collaborations
        cutoff = 1.hour.ago
        @collaborations.delete_if { |c| c[:timestamp] < cutoff }
      end
    end
    
    # Performance report generator
    class PerformanceReport
      def initialize(metrics, time_range)
        @metrics = metrics
        @time_range = time_range
      end
      
      def generate
        {
          summary: generate_summary,
          agent_rankings: generate_rankings,
          resource_analysis: analyze_resources,
          collaboration_analysis: analyze_collaboration,
          trend_analysis: analyze_trends,
          recommendations: generate_recommendations
        }
      end
      
      private
      
      def generate_summary
        summaries = @metrics.values.map { |m| m.summary(@time_range) }
        
        {
          total_agents: @metrics.size,
          total_actions: summaries.sum { |s| s[:action_count] },
          overall_success_rate: calculate_weighted_success_rate(summaries),
          average_response_time: calculate_weighted_average_time(summaries),
          total_resource_usage: aggregate_resources(summaries)
        }
      end
      
      def generate_rankings
        rankings = @metrics.map do |id, metrics|
          summary = metrics.summary(@time_range)
          {
            agent_id: id,
            performance_score: summary[:performance_score],
            action_count: summary[:action_count],
            success_rate: summary[:success_rate],
            avg_response_time: summary[:average_response_time]
          }
        end
        
        rankings.sort_by { |r| -r[:performance_score] }
      end
      
      def analyze_resources
        resource_by_agent = {}
        resource_totals = Hash.new(0)
        
        @metrics.each do |agent_id, metrics|
          summary = metrics.summary(@time_range)
          resource_by_agent[agent_id] = summary[:resource_usage]
          
          summary[:resource_usage].each do |type, amount|
            resource_totals[type] += amount
          end
        end
        
        {
          by_agent: resource_by_agent,
          totals: resource_totals,
          top_consumers: identify_top_consumers(resource_by_agent)
        }
      end
      
      def analyze_collaboration
        collaboration_graph = Hash.new { |h, k| h[k] = Hash.new(0) }
        
        @metrics.each do |agent_id, metrics|
          metrics.collaborations.each do |collab|
            collaboration_graph[agent_id][collab[:other_agent_id]] += 1
          end
        end
        
        {
          collaboration_matrix: collaboration_graph,
          most_collaborative: find_most_collaborative(collaboration_graph),
          isolated_agents: find_isolated_agents(collaboration_graph)
        }
      end
      
      def analyze_trends
        # Simplified trend analysis
        # In production, would use time-series analysis
        {
          performance_trend: :stable,
          resource_trend: :increasing,
          error_trend: :decreasing
        }
      end
      
      def generate_recommendations
        recommendations = []
        
        # Check for underperforming agents
        underperformers = @metrics.select do |_, m|
          m.performance_score < 50
        end
        
        if underperformers.any?
          recommendations << {
            type: :performance,
            message: "#{underperformers.size} agents performing below threshold",
            agents: underperformers.keys,
            action: "Review agent configurations and workload"
          }
        end
        
        # Check for resource hogs
        resource_hogs = identify_resource_hogs
        if resource_hogs.any?
          recommendations << {
            type: :resources,
            message: "High resource consumption detected",
            agents: resource_hogs,
            action: "Optimize resource usage or increase limits"
          }
        end
        
        recommendations
      end
      
      def calculate_weighted_success_rate(summaries)
        total_actions = summaries.sum { |s| s[:action_count] }
        return 1.0 if total_actions == 0
        
        weighted_sum = summaries.sum do |s|
          s[:success_rate] * s[:action_count]
        end
        
        weighted_sum / total_actions
      end
      
      def calculate_weighted_average_time(summaries)
        total_actions = summaries.sum { |s| s[:action_count] }
        return 0 if total_actions == 0
        
        weighted_sum = summaries.sum do |s|
          s[:average_response_time] * s[:action_count]
        end
        
        weighted_sum / total_actions
      end
      
      def aggregate_resources(summaries)
        resources = Hash.new(0)
        
        summaries.each do |summary|
          summary[:resource_usage].each do |type, amount|
            resources[type] += amount
          end
        end
        
        resources
      end
      
      def identify_top_consumers(resource_by_agent)
        top_by_type = {}
        
        resource_types = resource_by_agent.values.flat_map(&:keys).uniq
        
        resource_types.each do |type|
          consumers = resource_by_agent.map do |agent_id, resources|
            { agent_id: agent_id, amount: resources[type] || 0 }
          end
          
          top_by_type[type] = consumers
            .sort_by { |c| -c[:amount] }
            .first(3)
        end
        
        top_by_type
      end
      
      def find_most_collaborative(collaboration_graph)
        collaboration_counts = collaboration_graph.map do |agent_id, partners|
          { agent_id: agent_id, partner_count: partners.size }
        end
        
        collaboration_counts
          .sort_by { |c| -c[:partner_count] }
          .first(5)
      end
      
      def find_isolated_agents(collaboration_graph)
        all_agents = @metrics.keys
        collaborative_agents = collaboration_graph.keys
        
        all_agents - collaborative_agents
      end
      
      def identify_resource_hogs
        @metrics.select do |agent_id, metrics|
          summary = metrics.summary(@time_range)
          total_resources = summary[:resource_usage].values.sum
          
          total_resources > 1000 # Threshold
        end.keys
      end
    end
  end
end
