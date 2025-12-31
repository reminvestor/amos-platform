# frozen_string_literal: true

module Planner
  # AnalyticsService - Learns from plan execution to improve future plans
  #
  # Analyzes:
  # - Which agent assignments work best for step types
  # - Actual vs estimated durations
  # - Common failure patterns
  # - Optimal phase structures
  #
  class AnalyticsService
    attr_reader :entity

    def initialize(entity: nil)
      @entity = entity
    end

    # ============================================
    # PLAN ANALYSIS
    # ============================================

    # Analyze a completed plan and update learning data
    def analyze_completed_plan(plan)
      return unless plan.status.in?(%w[completed failed])

      analysis = {
        plan_id: plan.id,
        title: plan.title,
        complexity: plan.complexity,
        success: plan.status == 'completed',
        duration_actual: plan.actual_duration_minutes,
        duration_estimated: plan.estimated_duration_minutes,
        steps_completed: plan.completed_steps,
        steps_failed: plan.failed_steps,
        step_analytics: analyze_steps(plan),
        agent_performance: analyze_agent_performance(plan),
        failure_patterns: extract_failure_patterns(plan)
      }

      # Update template if one was used
      update_template_from_plan(plan, analysis)

      # Learn from agent assignments
      learn_agent_assignments(analysis)

      # Learn duration estimates
      learn_durations(analysis)

      analysis
    end

    # Get recommended agent for a step type
    def recommend_agent_for_step(step_description, tools_needed)
      # Look at historical success rates
      step_type = infer_step_type(step_description, tools_needed)
      
      agent_scores = AgentPlugin.where(status: 'active').map do |agent|
        historical = get_agent_step_history(agent.slug, step_type)
        
        {
          agent_slug: agent.slug,
          agent_name: agent.name,
          success_rate: historical[:success_rate],
          avg_duration: historical[:avg_duration],
          sample_size: historical[:sample_size],
          has_tools: (tools_needed - agent.agent_tools.pluck(:tool_name)).empty?,
          score: calculate_agent_score(agent, historical, tools_needed)
        }
      end

      agent_scores.sort_by { |a| -a[:score] }.first(3)
    end

    # Get estimated duration for a step type
    def estimate_step_duration(step_description, agent_slug = nil)
      step_type = infer_step_type(step_description, [])
      
      durations = StepDurationLearning.where(step_type: step_type)
      durations = durations.where(agent_slug: agent_slug) if agent_slug
      
      if durations.any?
        durations.average(:actual_duration_minutes).to_f.round
      else
        # Default estimates by step type
        default_durations[step_type] || 5
      end
    end

    # Get common failure patterns for a request type
    def get_failure_patterns(request_keywords)
      patterns = FailurePatternLearning.where(
        "keywords && ARRAY[?]::varchar[]",
        request_keywords
      ).order(occurrence_count: :desc).limit(5)

      patterns.map do |p|
        {
          pattern: p.pattern_description,
          occurrences: p.occurrence_count,
          mitigation: p.mitigation_suggestion
        }
      end
    end

    # ============================================
    # DASHBOARD METRICS
    # ============================================

    def overall_metrics(days: 30)
      plans = ExecutionPlan.where('created_at > ?', days.days.ago)
      plans = plans.where(entity: entity) if entity

      completed = plans.where(status: 'completed')
      failed = plans.where(status: 'failed')

      {
        total_plans: plans.count,
        completed_plans: completed.count,
        failed_plans: failed.count,
        success_rate: plans.count > 0 ? (completed.count.to_f / plans.count * 100).round(1) : 0,
        avg_duration: completed.average(:actual_duration_minutes)&.round(1) || 0,
        avg_steps: plans.average(:total_steps)&.round(1) || 0,
        complexity_breakdown: plans.group(:complexity).count,
        by_day: plans.group("DATE(created_at)").count
      }
    end

    def agent_leaderboard(days: 30)
      # Aggregate step performance by agent
      plans = ExecutionPlan.where('created_at > ?', days.days.ago)
      plans = plans.where(entity: entity) if entity

      agent_stats = {}

      plans.each do |plan|
        plan.all_steps.each do |step|
          next unless step['agent']
          
          agent_stats[step['agent']] ||= { completed: 0, failed: 0, total_time: 0 }
          
          if step['status'] == 'completed'
            agent_stats[step['agent']][:completed] += 1
            if step['started_at'] && step['completed_at']
              duration = (Time.parse(step['completed_at']) - Time.parse(step['started_at'])) / 60
              agent_stats[step['agent']][:total_time] += duration
            end
          elsif step['status'] == 'failed'
            agent_stats[step['agent']][:failed] += 1
          end
        end
      end

      agent_stats.map do |slug, stats|
        total = stats[:completed] + stats[:failed]
        {
          agent_slug: slug,
          agent_name: AgentPlugin.find_by(slug: slug)&.name || slug.titleize,
          total_steps: total,
          success_rate: total > 0 ? (stats[:completed].to_f / total * 100).round(1) : 0,
          avg_duration: stats[:completed] > 0 ? (stats[:total_time] / stats[:completed]).round(1) : 0
        }
      end.sort_by { |a| -a[:success_rate] }
    end

    def template_performance(days: 30)
      PlanTemplate.active.map do |template|
        {
          name: template.name,
          slug: template.slug,
          times_used: template.times_used,
          success_rate: template.success_rate&.round(2) || 0,
          avg_duration: template.average_duration_minutes&.round(1) || template.estimated_duration_minutes
        }
      end.sort_by { |t| -t[:times_used] }
    end

    private

    def analyze_steps(plan)
      plan.all_steps.map do |step|
        duration = nil
        if step['started_at'] && step['completed_at']
          duration = (Time.parse(step['completed_at']) - Time.parse(step['started_at'])) / 60
        end

        {
          id: step['id'],
          name: step['name'],
          agent: step['agent'],
          status: step['status'],
          estimated_minutes: step['estimated_minutes'],
          actual_minutes: duration&.round(1),
          accuracy: duration && step['estimated_minutes'] ? 
            ((duration / step['estimated_minutes']) * 100).round(1) : nil,
          error: step['error']
        }
      end
    end

    def analyze_agent_performance(plan)
      by_agent = {}

      plan.all_steps.each do |step|
        next unless step['agent']

        by_agent[step['agent']] ||= { completed: 0, failed: 0, skipped: 0 }
        by_agent[step['agent']][step['status'].to_sym] ||= 0
        by_agent[step['agent']][step['status'].to_sym] += 1
      end

      by_agent
    end

    def extract_failure_patterns(plan)
      plan.all_steps
          .select { |s| s['status'] == 'failed' }
          .map { |s| { step: s['name'], agent: s['agent'], error: s['error'] } }
    end

    def update_template_from_plan(plan, analysis)
      # Check if plan was created from a template
      template_event = plan.execution_log.find { |e| e['event'] == 'template_applied' }
      return unless template_event

      # Extract template slug from message
      match = template_event['message']&.match(/\(([^)]+)\)/)
      return unless match

      template = PlanTemplate.find_by(slug: match[1])
      return unless template

      template.record_outcome(
        success: analysis[:success],
        duration_minutes: analysis[:duration_actual]
      )
    end

    def learn_agent_assignments(analysis)
      analysis[:step_analytics].each do |step|
        next unless step[:agent] && step[:status]

        # Store or update agent-step-type performance
        # This could be stored in a learning table for future recommendations
        Rails.cache.write(
          "agent_step_perf:#{step[:agent]}:#{infer_step_type(step[:name], [])}",
          {
            last_status: step[:status],
            last_duration: step[:actual_minutes],
            updated_at: Time.current
          },
          expires_in: 90.days
        )
      end
    end

    def learn_durations(analysis)
      analysis[:step_analytics].each do |step|
        next unless step[:actual_minutes]

        # Store duration learning data
        # This helps improve estimates over time
        step_type = infer_step_type(step[:name], [])
        cache_key = "step_duration_avg:#{step_type}"
        
        current = Rails.cache.read(cache_key) || { sum: 0, count: 0 }
        current[:sum] += step[:actual_minutes]
        current[:count] += 1
        
        Rails.cache.write(cache_key, current, expires_in: 90.days)
      end
    end

    def get_agent_step_history(agent_slug, step_type)
      cache_key = "agent_step_perf:#{agent_slug}:#{step_type}"
      data = Rails.cache.read(cache_key)

      if data
        {
          success_rate: data[:last_status] == 'completed' ? 0.8 : 0.3,
          avg_duration: data[:last_duration] || 5,
          sample_size: 1
        }
      else
        { success_rate: 0.5, avg_duration: 5, sample_size: 0 }
      end
    end

    def calculate_agent_score(agent, historical, tools_needed)
      score = 0
      
      # Has all required tools
      score += 50 if historical[:has_tools] != false
      
      # Historical success rate
      score += (historical[:success_rate] * 30)
      
      # Sample size (more data = more confidence)
      score += [historical[:sample_size] * 2, 10].min
      
      # Faster is better
      score += (10 - [historical[:avg_duration], 10].min) if historical[:avg_duration]
      
      score
    end

    def infer_step_type(description, tools)
      desc_lower = description.to_s.downcase

      if desc_lower.include?('discover') || desc_lower.include?('requirement') || desc_lower.include?('gather')
        'discovery'
      elsif desc_lower.include?('design') || desc_lower.include?('blueprint') || desc_lower.include?('architect')
        'design'
      elsif desc_lower.include?('build') || desc_lower.include?('create') || desc_lower.include?('module')
        'build'
      elsif desc_lower.include?('test') || desc_lower.include?('verify') || desc_lower.include?('preview')
        'test'
      elsif desc_lower.include?('deploy') || desc_lower.include?('publish')
        'deploy'
      elsif desc_lower.include?('review') || desc_lower.include?('approval')
        'review'
      else
        'custom'
      end
    end

    def default_durations
      {
        'discovery' => 5,
        'design' => 10,
        'build' => 15,
        'test' => 5,
        'deploy' => 3,
        'review' => 5,
        'custom' => 5
      }
    end
  end
end

