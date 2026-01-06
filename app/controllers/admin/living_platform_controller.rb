# frozen_string_literal: true

module Admin
  class LivingPlatformController < Admin::BaseController
    before_action :set_entity, only: [:show, :perception, :goals, :reflections, :cycles, :lifecycle]

    # GET /admin/living_platform
    def index
      @entities = Entity.all.order(:name)
      
      # Global stats
      @global_stats = {
        total_goals: AgentGoal.count,
        pending_goals: AgentGoal.pending.count,
        completed_goals: AgentGoal.completed.count,
        total_perceptions: PlatformPerception.count,
        total_anomalies: PlatformAnomaly.active.count,
        total_reflections: AgentReflection.count,
        total_cycles: EvolutionCycle.count,
        total_lifecycle_events: AgentLifecycleEvent.count
      }

      # Recent activity
      @recent_perceptions = PlatformPerception.recent.limit(5)
      @recent_goals = AgentGoal.recent.limit(10)
      @recent_anomalies = PlatformAnomaly.active.recent.limit(10)
      @recent_cycles = EvolutionCycle.recent.limit(5)

      # System health
      @system_health = calculate_system_health
    end

    # GET /admin/living_platform/:entity_id
    def show
      @perception = PlatformPerception.where(entity: @entity).recent.first
      @goals = AgentGoal.where(entity: @entity).recent.limit(20)
      @anomalies = PlatformAnomaly.where(entity: @entity).active.recent.limit(10)
      @recent_cycles = EvolutionCycle.where(entity: @entity).recent.limit(5)
      
      @entity_stats = {
        health_score: @perception&.overall_health_score,
        health_trend: PlatformPerception.health_trend(@entity, days: 7),
        active_goals: AgentGoal.where(entity: @entity).active.count,
        pending_anomalies: @anomalies.count,
        evolution_velocity: EvolutionCycle.evolution_velocity(@entity, days: 30)
      }

      # Cost tracking
      @cost_stats = calculate_cost_stats(@entity)
    end

    # GET /admin/living_platform/:entity_id/perception
    def perception
      @perceptions = PlatformPerception.where(entity: @entity).recent.page(params[:page]).per(20)
      @health_trend = get_health_trend_data(@entity)
      @anomaly_trend = get_anomaly_trend_data(@entity)
    end

    # GET /admin/living_platform/:entity_id/goals
    def goals
      @goals = AgentGoal.where(entity: @entity).recent.page(params[:page]).per(30)
      @goal_stats = {
        by_type: AgentGoal.where(entity: @entity).group(:goal_type).count,
        by_status: AgentGoal.where(entity: @entity).group(:status).count,
        completion_rate: calculate_goal_completion_rate(@entity)
      }
    end

    # GET /admin/living_platform/:entity_id/reflections
    def reflections
      @reflections = AgentReflection.where(entity: @entity).recent.page(params[:page]).per(30)
      @reflection_stats = {
        avg_score: AgentReflection.where(entity: @entity).average(:overall_score)&.round(1),
        common_issues: AgentReflection.common_issues(@entity, days: 30),
        common_gaps: AgentReflection.common_knowledge_gaps(@entity, days: 30)
      }
    end

    # GET /admin/living_platform/:entity_id/cycles
    def cycles
      @cycles = EvolutionCycle.where(entity: @entity).recent.page(params[:page]).per(20)
      @cycle_stats = {
        total_promotions: EvolutionCycle.total_promotions(@entity, days: 30),
        avg_experiment_success: EvolutionCycle.average_experiment_success_rate(@entity, days: 30),
        evolution_velocity: EvolutionCycle.evolution_velocity(@entity, days: 30)
      }
    end

    # GET /admin/living_platform/:entity_id/lifecycle
    def lifecycle
      @events = AgentLifecycleEvent.where(entity: @entity).recent.page(params[:page]).per(30)
      @lifecycle_stats = AgentLifecycleEvent.lifecycle_stats(@entity, days: 30)
      @knowledge_archives = GlobalKnowledgeArchive.where(entity: @entity).recent.limit(20)
    end

    # POST /admin/living_platform/:entity_id/run_perception
    def run_perception
      entity = Entity.find(params[:entity_id])
      LivingPlatform::PerceptionJob.perform_later(entity.id, perception_type: 'triggered')
      
      redirect_to admin_living_platform_path(entity), notice: 'Perception job queued'
    end

    # POST /admin/living_platform/:entity_id/run_desire_engine
    def run_desire_engine
      entity = Entity.find(params[:entity_id])
      LivingPlatform::DesireEngineJob.perform_later(entity.id, triggered: true)
      
      redirect_to admin_living_platform_path(entity), notice: 'Desire Engine job queued'
    end

    # POST /admin/living_platform/:entity_id/run_evolution
    def run_evolution
      entity = Entity.find(params[:entity_id])
      LivingPlatform::EvolutionCycleJob.perform_later(entity.id, cycle_type: 'triggered')
      
      redirect_to admin_living_platform_path(entity), notice: 'Evolution Cycle job queued'
    end

    # POST /admin/living_platform/:entity_id/run_benchmark
    def run_benchmark
      entity = Entity.find(params[:entity_id])
      quick = params[:quick] == 'true'
      
      # Run benchmark inline for now (could be async)
      benchmark = Benchmarks::LivingPlatformBenchmark.new(entity: entity)
      @results = quick ? benchmark.run_quick_benchmark : benchmark.run_full_benchmark
      
      respond_to do |format|
        format.html { redirect_to admin_living_platform_path(entity), notice: "Benchmark complete: #{@results[:overall][:grade]}" }
        format.json { render json: @results }
      end
    end

    # GET /admin/living_platform/benchmark_results
    def benchmark_results
      @results = BenchmarkRun.where(benchmark_category: 'living_platform')
                             .order(created_at: :desc)
                             .page(params[:page]).per(20)
    end

    # POST /admin/living_platform/:entity_id/resolve_anomaly/:anomaly_id
    def resolve_anomaly
      anomaly = PlatformAnomaly.find(params[:anomaly_id])
      anomaly.resolve!(notes: params[:notes])
      
      redirect_to admin_living_platform_path(params[:entity_id]), notice: 'Anomaly resolved'
    end

    # POST /admin/living_platform/:entity_id/cancel_goal/:goal_id
    def cancel_goal
      goal = AgentGoal.find(params[:goal_id])
      goal.cancel!(params[:reason])
      
      redirect_to admin_living_platform_goals_path(params[:entity_id]), notice: 'Goal cancelled'
    end

    private

    def set_entity
      @entity = Entity.find(params[:entity_id] || params[:id])
    end

    def calculate_system_health
      perceptions = PlatformPerception.where('perceived_at > ?', 24.hours.ago)
      
      return { score: 'N/A', status: 'unknown' } if perceptions.empty?
      
      avg_health = perceptions.average(:overall_health_score)&.round(2)
      total_anomalies = perceptions.sum(&:critical_anomalies)
      
      status = if avg_health >= 0.8 && total_anomalies.zero?
        'healthy'
      elsif avg_health >= 0.6
        'attention_needed'
      else
        'critical'
      end
      
      { score: avg_health, status: status, anomalies: total_anomalies }
    end

    def calculate_cost_stats(entity)
      # Get token usage from AI logs
      recent_usage = AiUsageLog.where(entity: entity)
        .where('created_at > ?', 7.days.ago)
      
      # Calculate by source
      living_platform_usage = recent_usage.where("metadata->>'source' IN (?)", 
        %w[perception desire_engine metacognition evolution_cycle])
      
      {
        total_tokens_7d: recent_usage.sum(:input_tokens) + recent_usage.sum(:output_tokens),
        living_platform_tokens: living_platform_usage.sum(:input_tokens) + living_platform_usage.sum(:output_tokens),
        estimated_cost_7d: estimate_cost(recent_usage),
        living_platform_cost: estimate_cost(living_platform_usage)
      }
    end

    def estimate_cost(usage_logs)
      # Rough cost estimation (Claude Sonnet pricing)
      input_tokens = usage_logs.sum(:input_tokens)
      output_tokens = usage_logs.sum(:output_tokens)
      
      input_cost = input_tokens * 0.003 / 1000  # $3/M input
      output_cost = output_tokens * 0.015 / 1000  # $15/M output
      
      (input_cost + output_cost).round(2)
    end

    def calculate_goal_completion_rate(entity)
      total = AgentGoal.where(entity: entity).count
      completed = AgentGoal.where(entity: entity, status: 'completed').count
      
      return 0 if total.zero?
      (completed.to_f / total * 100).round(1)
    end

    def get_health_trend_data(entity)
      PlatformPerception.where(entity: entity)
        .where('perceived_at > ?', 7.days.ago)
        .order(:perceived_at)
        .pluck(:perceived_at, :overall_health_score)
        .map { |date, score| { date: date.to_date.to_s, score: score } }
    end

    def get_anomaly_trend_data(entity)
      PlatformAnomaly.where(entity: entity)
        .where('created_at > ?', 7.days.ago)
        .group("DATE(created_at)")
        .count
        .map { |date, count| { date: date.to_s, count: count } }
    end
  end
end


