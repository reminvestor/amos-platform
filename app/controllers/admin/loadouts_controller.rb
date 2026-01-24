# frozen_string_literal: true

module Admin
  class LoadoutsController < Admin::BaseController
    before_action :set_entity

    def index
      @health_monitor = LoadoutHealthMonitor.new(entity: @entity)
      @loadout_health = @health_monitor.all_health_scores

      # Categorize by status
      @healthy_count = @loadout_health.count { |h| h[:status] == :healthy }
      @warning_count = @loadout_health.count { |h| h[:status] == :warning }
      @critical_count = @loadout_health.count { |h| h[:status] == :critical }

      # Total interactions
      @total_interactions = LoadoutMetric.for_entity(@entity.id).recent(7.days).count

      # Recent tickets
      @recent_tickets = PlatformEvolutionTicket.for_entity(@entity.id)
                                               .order(created_at: :desc)
                                               .limit(10)
      @open_tickets_count = PlatformEvolutionTicket.for_entity(@entity.id).open_tickets.count
    end

    def show
      @loadout_slug = params[:id]
      @optimization_service = LoadoutOptimizationService.new(entity: @entity)
      @health = @optimization_service.health_summary(loadout_slug: @loadout_slug, window: 7.days)
      @suggestions = @optimization_service.suggest_improvements(@loadout_slug)

      @plugin = AgentPlugin.find_by(slug: @loadout_slug)
      @versions = @plugin&.loadout_versions&.order(version_number: :desc)&.limit(10) || []

      # Recent metrics
      @recent_metrics = LoadoutMetric.for_loadout(@loadout_slug)
                                     .for_entity(@entity.id)
                                     .order(created_at: :desc)
                                     .limit(50)
    end

    def metrics
      @loadout_slug = params[:id]

      # Time range
      @range = (params[:range] || '7d').to_s
      window = case @range
               when '24h' then 1.day
               when '7d' then 7.days
               when '30d' then 30.days
               else 7.days
               end

      @metrics = LoadoutMetric.for_loadout(@loadout_slug)
                              .for_entity(@entity.id)
                              .recent(window)
                              .order(created_at: :desc)

      # Group by day for chart
      @daily_stats = @metrics.group_by { |m| m.created_at.to_date }
                             .transform_values do |day_metrics|
                               {
                                 total: day_metrics.count,
                                 successes: day_metrics.count { |m| m.event_type == 'success' },
                                 failures: day_metrics.count { |m| m.event_type == 'failure' },
                                 hallucinations: day_metrics.count { |m| m.event_type == 'hallucination' }
                               }
                             end
    end

    def health_check
      monitor = LoadoutHealthMonitor.new(entity: @entity)
      results = monitor.run_health_check

      render json: results
    end

    def apply_fix
      @loadout_slug = params[:id]
      fix_type = params[:fix_type]

      monitor = LoadoutHealthMonitor.new(entity: @entity)
      result = monitor.apply_emergency_fix(@loadout_slug, fix_type: fix_type)

      render json: result
    end

    private

    def set_entity
      @entity = current_entity
    end

    helper_method :health_badge_class, :health_score_badge, :priority_badge_class, :status_badge_class, :canvas_for_loadout

    def health_badge_class(status)
      case status
      when :healthy then 'bg-success'
      when :warning then 'bg-warning text-dark'
      when :critical then 'bg-danger'
      else 'bg-secondary'
      end
    end

    def health_score_badge(score)
      if score >= 80
        'bg-success'
      elsif score >= 60
        'bg-warning text-dark'
      else
        'bg-danger'
      end
    end

    def priority_badge_class(priority)
      case priority
      when 'critical' then 'bg-danger'
      when 'high' then 'bg-warning text-dark'
      when 'medium' then 'bg-info'
      else 'bg-secondary'
      end
    end

    def status_badge_class(status)
      case status
      when 'open' then 'bg-primary'
      when 'in_progress' then 'bg-info'
      when 'completed' then 'bg-success'
      when 'rejected' then 'bg-secondary'
      when 'blocked' then 'bg-danger'
      else 'bg-secondary'
      end
    end

    def canvas_for_loadout(slug)
      PluginInjectionService::CANVAS_PLUGIN_MAP.key(slug)
    end
  end
end
