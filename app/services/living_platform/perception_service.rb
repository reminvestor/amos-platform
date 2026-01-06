# frozen_string_literal: true

module LivingPlatform
  # PerceptionService - Global Platform Awareness
  #
  # The Perception Service provides the platform with "senses" - the ability
  # to observe and understand its own state. It detects anomalies, identifies
  # opportunities, and triggers autonomous responses.
  #
  # This runs periodically and creates PlatformPerception records that drive
  # the DesireEngine and EvolutionCycle.
  #
  # Integration:
  # - Creates PlatformPerception snapshots
  # - Detects and records PlatformAnomalies
  # - Can trigger DesireEngine goals for critical issues
  # - Feeds into EvolutionCycle for analysis
  #
  class PerceptionService
    attr_reader :entity

    # Thresholds for anomaly detection
    PERFORMANCE_DROP_THRESHOLD = 0.15  # 15% drop triggers anomaly
    ERROR_SPIKE_THRESHOLD = 2.0        # 2x normal error rate
    INACTIVITY_THRESHOLD = 3.days
    SUCCESS_RATE_WARNING = 0.7
    SUCCESS_RATE_CRITICAL = 0.5

    def initialize(entity = nil)
      @entity = entity
    end

    # Main entry point - perceive the entire platform or a single entity
    def perceive(type: 'routine')
      if entity
        perceive_entity(type: type)
      else
        perceive_global(type: type)
      end
    end

    # Perceive a single entity
    def perceive_entity(type: 'routine')
      Rails.logger.info "[PerceptionService] Perceiving entity #{entity.id} (#{type})"
      
      start_time = Time.current
      
      # Gather metrics
      metrics = gather_entity_metrics
      
      # Detect anomalies
      anomalies = detect_anomalies(metrics)
      
      # Identify opportunities
      opportunities = identify_opportunities(metrics)
      
      # Identify threats
      threats = identify_threats(metrics, anomalies)
      
      # Calculate health score
      health_score = calculate_health_score(metrics, anomalies)
      
      # Create perception record
      perception = PlatformPerception.create!(
        entity: entity,
        perceived_at: Time.current,
        perception_type: type,
        overall_health_score: health_score,
        health_breakdown: metrics[:health_breakdown],
        active_agents: metrics[:active_agents],
        tasks_completed_24h: metrics[:tasks_completed_24h],
        tasks_failed_24h: metrics[:tasks_failed_24h],
        success_rate_24h: metrics[:success_rate_24h],
        anomalies: anomalies.map(&:summary),
        anomaly_count: anomalies.count,
        critical_anomalies: anomalies.count(&:critical?),
        opportunities: opportunities,
        threats: threats,
        metrics_snapshot: metrics
      )
      
      # Create anomaly records
      anomalies.each do |anomaly|
        anomaly.update!(platform_perception: perception) if anomaly.persisted?
      end
      
      # Trigger autonomous actions for critical issues
      autonomous_actions = handle_critical_issues(perception, anomalies)
      perception.update!(
        autonomous_actions_triggered: autonomous_actions,
        actions_count: autonomous_actions.count
      )
      
      duration_ms = ((Time.current - start_time) * 1000).round
      Rails.logger.info "[PerceptionService] Perception complete in #{duration_ms}ms. " \
                        "Health: #{(health_score * 100).round}%, " \
                        "Anomalies: #{anomalies.count}, Actions: #{autonomous_actions.count}"
      
      perception
    end

    # Perceive all entities (global)
    def perceive_global(type: 'routine')
      Rails.logger.info "[PerceptionService] Running global perception"
      
      perceptions = Entity.find_each.map do |e|
        @entity = e
        perceive_entity(type: type)
      end
      
      # Create summary perception
      global_health = perceptions.sum { |p| p.overall_health_score.to_f } / perceptions.count
      total_anomalies = perceptions.sum(&:anomaly_count)
      
      PlatformPerception.create!(
        entity: nil,  # Global
        perceived_at: Time.current,
        perception_type: type,
        overall_health_score: global_health,
        health_breakdown: {
          entities_healthy: perceptions.count(&:healthy?),
          entities_needing_attention: perceptions.count(&:needs_attention?),
          total_entities: perceptions.count
        },
        active_agents: perceptions.sum(&:active_agents),
        tasks_completed_24h: perceptions.sum(&:tasks_completed_24h),
        tasks_failed_24h: perceptions.sum(&:tasks_failed_24h),
        anomaly_count: total_anomalies,
        critical_anomalies: perceptions.sum(&:critical_anomalies)
      )
    end

    private

    # ═══════════════════════════════════════════════════════════════════════════
    # METRICS GATHERING
    # ═══════════════════════════════════════════════════════════════════════════

    def gather_entity_metrics
      now = Time.current
      yesterday = 24.hours.ago
      last_week = 7.days.ago
      
      executions_24h = AgentPluginExecution.joins(:agent_plugin)
        .where(agent_plugins: { entity_id: entity.id })
        .where('agent_plugin_executions.created_at > ?', yesterday)
      
      executions_week = AgentPluginExecution.joins(:agent_plugin)
        .where(agent_plugins: { entity_id: entity.id })
        .where('agent_plugin_executions.created_at > ?', last_week)
      
      completed_24h = executions_24h.where(status: 'completed').count
      failed_24h = executions_24h.where(status: 'failed').count
      total_24h = completed_24h + failed_24h
      
      completed_week = executions_week.where(status: 'completed').count
      failed_week = executions_week.where(status: 'failed').count
      total_week = completed_week + failed_week
      
      # Per-agent breakdown
      agent_health = {}
      entity.agent_plugins.where(status: 'active').find_each do |agent|
        agent_execs = executions_24h.where(agent_plugin_id: agent.id)
        completed = agent_execs.where(status: 'completed').count
        failed = agent_execs.where(status: 'failed').count
        total = completed + failed
        
        agent_health[agent.slug] = {
          completed: completed,
          failed: failed,
          total: total,
          success_rate: total > 0 ? (completed.to_f / total) : 1.0,
          avg_duration_ms: agent_execs.where(status: 'completed').average(:duration_ms)&.round,
          last_execution: agent_execs.maximum(:created_at)
        }
      end
      
      {
        active_agents: entity.agent_plugins.where(status: 'active').count,
        tasks_completed_24h: completed_24h,
        tasks_failed_24h: failed_24h,
        success_rate_24h: total_24h > 0 ? (completed_24h.to_f / total_24h) : 1.0,
        tasks_completed_week: completed_week,
        tasks_failed_week: failed_week,
        success_rate_week: total_week > 0 ? (completed_week.to_f / total_week) : 1.0,
        health_breakdown: agent_health,
        avg_duration_24h: executions_24h.where(status: 'completed').average(:duration_ms)&.round,
        previous_perception: get_previous_metrics
      }
    end

    def get_previous_metrics
      prev = PlatformPerception.where(entity: entity).recent.first
      return nil unless prev
      
      {
        success_rate_24h: prev.success_rate_24h,
        overall_health_score: prev.overall_health_score,
        perceived_at: prev.perceived_at
      }
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # ANOMALY DETECTION
    # ═══════════════════════════════════════════════════════════════════════════

    def detect_anomalies(metrics)
      anomalies = []
      
      # Check for performance drops
      anomalies.concat(detect_performance_drops(metrics))
      
      # Check for error spikes
      anomalies.concat(detect_error_spikes(metrics))
      
      # Check for stale agents
      anomalies.concat(detect_stale_agents(metrics))
      
      # Check for capacity issues
      anomalies.concat(detect_capacity_issues(metrics))
      
      anomalies
    end

    def detect_performance_drops(metrics)
      anomalies = []
      prev = metrics[:previous_perception]
      
      if prev && prev[:success_rate_24h]
        current = metrics[:success_rate_24h]
        previous = prev[:success_rate_24h]
        
        if previous > 0 && (previous - current) / previous > PERFORMANCE_DROP_THRESHOLD
          drop_percent = ((previous - current) / previous * 100).round(1)
          
          anomalies << PlatformAnomaly.create_from_detection(
            entity: entity,
            type: 'performance_drop',
            severity: drop_percent > 30 ? 'critical' : (drop_percent > 20 ? 'high' : 'medium'),
            title: "Success rate dropped #{drop_percent}%",
            details: {
              description: "Success rate dropped from #{(previous * 100).round}% to #{(current * 100).round}%",
              previous_rate: previous,
              current_rate: current,
              deviation_percent: drop_percent
            },
            metrics: { previous: previous, current: current }
          )
        end
      end
      
      # Check individual agents for drops
      metrics[:health_breakdown].each do |agent_slug, agent_metrics|
        if agent_metrics[:success_rate] < SUCCESS_RATE_CRITICAL && agent_metrics[:total] >= 5
          agent = entity.agent_plugins.find_by(slug: agent_slug)
          next unless agent
          
          anomalies << PlatformAnomaly.create_from_detection(
            entity: entity,
            type: 'performance_drop',
            severity: 'high',
            title: "Agent #{agent_slug} critically underperforming",
            target: agent,
            details: {
              description: "Agent #{agent_slug} has a #{(agent_metrics[:success_rate] * 100).round}% success rate",
              success_rate: agent_metrics[:success_rate],
              total_tasks: agent_metrics[:total],
              deviation_percent: (1 - agent_metrics[:success_rate]) * 100
            },
            metrics: agent_metrics
          )
        end
      end
      
      anomalies
    end

    def detect_error_spikes(metrics)
      anomalies = []
      
      # Compare daily to weekly average
      daily_failures = metrics[:tasks_failed_24h]
      weekly_avg_daily = metrics[:tasks_failed_week].to_f / 7
      
      if weekly_avg_daily > 0 && daily_failures > weekly_avg_daily * ERROR_SPIKE_THRESHOLD
        spike_ratio = (daily_failures / weekly_avg_daily).round(1)
        
        anomalies << PlatformAnomaly.create_from_detection(
          entity: entity,
          type: 'error_spike',
          severity: spike_ratio > 5 ? 'critical' : (spike_ratio > 3 ? 'high' : 'medium'),
          title: "Error spike: #{spike_ratio}x normal rate",
          details: {
            description: "#{daily_failures} failures today vs #{weekly_avg_daily.round} daily average",
            current_failures: daily_failures,
            average_failures: weekly_avg_daily,
            spike_ratio: spike_ratio,
            deviation_percent: (spike_ratio - 1) * 100
          },
          metrics: { daily: daily_failures, weekly_avg: weekly_avg_daily }
        )
      end
      
      anomalies
    end

    def detect_stale_agents(metrics)
      anomalies = []
      
      metrics[:health_breakdown].each do |agent_slug, agent_metrics|
        last_exec = agent_metrics[:last_execution]
        
        if last_exec.nil? || last_exec < INACTIVITY_THRESHOLD.ago
          agent = entity.agent_plugins.find_by(slug: agent_slug)
          next unless agent
          
          days_inactive = last_exec ? ((Time.current - last_exec) / 1.day).round : 999
          
          anomalies << PlatformAnomaly.create_from_detection(
            entity: entity,
            type: 'stale_agent',
            severity: days_inactive > 30 ? 'medium' : 'low',
            title: "Agent #{agent_slug} inactive for #{days_inactive} days",
            target: agent,
            details: {
              description: "Agent #{agent_slug} has had no activity for #{days_inactive} days",
              last_execution: last_exec,
              days_inactive: days_inactive
            },
            metrics: { days_inactive: days_inactive }
          )
        end
      end
      
      anomalies
    end

    def detect_capacity_issues(metrics)
      anomalies = []
      
      # Find overloaded agents (> 50 tasks/day with declining success)
      metrics[:health_breakdown].each do |agent_slug, agent_metrics|
        if agent_metrics[:total] > 50 && agent_metrics[:success_rate] < SUCCESS_RATE_WARNING
          agent = entity.agent_plugins.find_by(slug: agent_slug)
          next unless agent
          
          anomalies << PlatformAnomaly.create_from_detection(
            entity: entity,
            type: 'capacity_issue',
            severity: 'medium',
            title: "Agent #{agent_slug} may be overloaded",
            target: agent,
            details: {
              description: "Agent #{agent_slug} handled #{agent_metrics[:total]} tasks " \
                           "with #{(agent_metrics[:success_rate] * 100).round}% success",
              task_count: agent_metrics[:total],
              success_rate: agent_metrics[:success_rate]
            },
            metrics: agent_metrics
          )
        end
      end
      
      anomalies
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # OPPORTUNITY IDENTIFICATION
    # ═══════════════════════════════════════════════════════════════════════════

    def identify_opportunities(metrics)
      opportunities = []
      
      # Agents performing exceptionally well - candidates for promotion
      metrics[:health_breakdown].each do |agent_slug, agent_metrics|
        if agent_metrics[:success_rate] > 0.95 && agent_metrics[:total] >= 20
          opportunities << {
            type: 'high_performer',
            description: "Agent #{agent_slug} is excelling (#{(agent_metrics[:success_rate] * 100).round}% success)",
            value: 0.8,
            action: 'Consider giving more responsibilities or using as mentor'
          }
        end
      end
      
      # Underutilized capacity
      low_usage_agents = metrics[:health_breakdown].select do |_, m|
        m[:total] < 5 && m[:success_rate] >= SUCCESS_RATE_WARNING
      end
      
      if low_usage_agents.any?
        opportunities << {
          type: 'underutilized_capacity',
          description: "#{low_usage_agents.count} agents have low utilization but good performance",
          value: 0.6,
          agents: low_usage_agents.keys,
          action: 'Consider routing more tasks to these agents'
        }
      end
      
      opportunities
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # THREAT IDENTIFICATION
    # ═══════════════════════════════════════════════════════════════════════════

    def identify_threats(metrics, anomalies)
      threats = []
      
      # Critical anomalies are immediate threats
      critical_anomalies = anomalies.select(&:critical?)
      if critical_anomalies.any?
        threats << {
          type: 'critical_anomalies',
          description: "#{critical_anomalies.count} critical anomalies detected",
          urgency: 'immediate',
          anomaly_ids: critical_anomalies.map(&:id)
        }
      end
      
      # Declining overall health trend
      if metrics[:success_rate_24h] < metrics[:success_rate_week]
        decline = ((metrics[:success_rate_week] - metrics[:success_rate_24h]) / metrics[:success_rate_week] * 100).round(1)
        
        if decline > 10
          threats << {
            type: 'declining_health',
            description: "Overall success rate declining (#{decline}% below weekly average)",
            urgency: decline > 20 ? 'immediate' : 'soon',
            current_rate: metrics[:success_rate_24h],
            weekly_rate: metrics[:success_rate_week]
          }
        end
      end
      
      threats
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # HEALTH CALCULATION
    # ═══════════════════════════════════════════════════════════════════════════

    def calculate_health_score(metrics, anomalies)
      score = 1.0
      
      # Reduce for low success rate (guard against NaN)
      success_rate = metrics[:success_rate_24h].to_f
      success_rate = 1.0 if success_rate.nan? || success_rate < 0 || success_rate > 1.0
      if success_rate < 1.0
        score -= (1.0 - success_rate) * 0.4
      end
      
      # Reduce for anomalies
      anomaly_penalty = anomalies.sum do |a|
        case a.severity
        when 'critical' then 0.15
        when 'high' then 0.1
        when 'medium' then 0.05
        when 'low' then 0.02
        else 0
        end
      end
      score -= [anomaly_penalty, 0.4].min
      
      # Reduce for inactive agents (if many) - guard against division by zero
      stale_count = anomalies.count { |a| a.anomaly_type == 'stale_agent' }
      total_agents = [metrics[:active_agents].to_i, 1].max
      stale_ratio = stale_count.to_f / total_agents
      stale_ratio = 0.0 if stale_ratio.nan?
      score -= stale_ratio * 0.1
      
      # Ensure valid result
      score = 0.0 if score.nan?
      [[score, 0.0].max, 1.0].min.round(4)
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # AUTONOMOUS ACTIONS
    # ═══════════════════════════════════════════════════════════════════════════

    def handle_critical_issues(perception, anomalies)
      actions = []
      
      critical = anomalies.select(&:critical?)
      
      critical.each do |anomaly|
        action = handle_critical_anomaly(anomaly)
        actions << action if action
      end
      
      actions
    end

    def handle_critical_anomaly(anomaly)
      case anomaly.anomaly_type
      when 'performance_drop'
        # Create immediate improvement goal
        goal = anomaly.create_remediation_goal!
        { type: 'goal_created', goal_id: goal.id, anomaly_id: anomaly.id }
        
      when 'error_spike'
        # Create investigation goal
        goal = anomaly.create_remediation_goal!
        { type: 'goal_created', goal_id: goal.id, anomaly_id: anomaly.id }
        
      else
        nil
      end
    rescue => e
      Rails.logger.error "[PerceptionService] Failed to handle anomaly #{anomaly.id}: #{e.message}"
      nil
    end
  end
end

