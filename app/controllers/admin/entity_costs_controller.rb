# app/controllers/admin/entity_costs_controller.rb
class Admin::EntityCostsController < ApplicationController
  before_action :authenticate_admin!
  before_action :set_entity, only: [:show, :export]
  layout 'admin'

  def index
    @entities = Entity.includes(:entity_cost_summaries)
                      .order('entity_cost_summaries.total_cost DESC')
                      .page(params[:page])

    # Date range filter
    @start_date = params[:start_date]&.to_date || 30.days.ago.to_date
    @end_date = params[:end_date]&.to_date || Date.current

    # Calculate metrics for all entities
    @total_costs = calculate_total_costs(@entities, @start_date, @end_date)
    @top_spenders = identify_top_spenders(@entities, @start_date, @end_date, limit: 10)
    @cost_by_category = aggregate_costs_by_category(@start_date, @end_date)
    @cost_trends = calculate_cost_trends(@start_date, @end_date)
  end

  def show
    @tracker = EntityCostTracker.new(@entity)

    # Date range from params or defaults
    @start_date = params[:start_date]&.to_date || 30.days.ago.to_date
    @end_date = params[:end_date]&.to_date || Date.current

    # Entity-specific metrics
    @usage_metrics = @entity.entity_usage_metrics
                            .where(tracked_at: @start_date..@end_date)
                            .order(tracked_at: :desc)

    @cost_summaries = @entity.entity_cost_summaries
                             .where(summary_date: @start_date..@end_date)
                             .order(summary_date: :desc)

    @total_cost = @tracker.get_total_cost(start_date: @start_date, end_date: @end_date)
    @costs_by_category = @tracker.get_costs_by_category(start_date: @start_date, end_date: @end_date)
    @daily_costs = @tracker.get_daily_costs(days: (@end_date - @start_date).to_i)
    @top_cost_drivers = @tracker.identify_cost_drivers(start_date: @start_date, end_date: @end_date)
    @peer_benchmark = @tracker.benchmark_against_peers

    # Service-specific breakdowns
    @ai_usage = @tracker.get_ai_usage_details(@start_date, @end_date)
    @email_usage = @tracker.get_email_usage_details(@start_date, @end_date)
    @storage_usage = @tracker.get_storage_usage_details(@start_date, @end_date)

    # Alerts and thresholds
    @threshold_alerts = check_threshold_alerts(@entity)
    @projected_overage = @tracker.project_monthly_overage
  end

  def export
    @tracker = EntityCostTracker.new(@entity)
    start_date = params[:start_date]&.to_date || 30.days.ago.to_date
    end_date = params[:end_date]&.to_date || Date.current

    respond_to do |format|
      format.csv do
        send_data generate_csv(@entity, start_date, end_date),
                  filename: "entity_costs_#{@entity.id}_#{Date.current}.csv"
      end
      format.json do
        render json: {
          entity: @entity.attributes.slice('id', 'name', 'billing_tier'),
          period: { start: start_date, end: end_date },
          total_cost: @tracker.get_total_cost(start_date: start_date, end_date: end_date),
          costs_by_category: @tracker.get_costs_by_category(start_date: start_date, end_date: end_date),
          daily_costs: @tracker.get_daily_costs(days: (end_date - start_date).to_i),
          metrics: @entity.entity_usage_metrics.where(tracked_at: start_date..end_date)
        }
      end
    end
  end

  def bulk_analysis
    authenticate_admin!

    # Analyze costs across all entities
    @analysis_period = params[:period] || 'monthly'
    @category_filter = params[:category]

    @insights = {
      highest_cost_entities: Entity.joins(:entity_cost_summaries)
                                   .group('entities.id')
                                   .order('SUM(entity_cost_summaries.total_cost) DESC')
                                   .limit(20),
      fastest_growing_costs: analyze_cost_growth_rates,
      anomalies: detect_cost_anomalies,
      optimization_opportunities: identify_optimization_opportunities
    }

    respond_to do |format|
      format.html
      format.json { render json: @insights }
    end
  end

  private

  def set_entity
    @entity = Entity.find(params[:id])
  end

  def authenticate_admin!
    unless current_user&.admin?
      redirect_to root_path, alert: 'Not authorized to access admin area'
    end
  end

  def calculate_total_costs(entities, start_date, end_date)
    EntityCostSummary.where(entity: entities, summary_date: start_date..end_date)
                     .sum(:total_cost)
  end

  def identify_top_spenders(entities, start_date, end_date, limit: 10)
    entities.joins(:entity_cost_summaries)
            .where(entity_cost_summaries: { summary_date: start_date..end_date })
            .group('entities.id')
            .order('SUM(entity_cost_summaries.total_cost) DESC')
            .limit(limit)
            .pluck('entities.id', 'entities.name', 'SUM(entity_cost_summaries.total_cost)')
            .map { |id, name, cost| { id: id, name: name, total_cost: cost } }
  end

  def aggregate_costs_by_category(start_date, end_date)
    EntityCostSummary.where(summary_date: start_date..end_date)
                     .group(:summary_date)
                     .sum(:ai_chat_cost, :email_cost, :storage_cost, :compute_cost,
                         :bandwidth_cost, :integration_cost, :other_costs)
  end

  def calculate_cost_trends(start_date, end_date)
    daily_costs = EntityCostSummary.where(summary_date: start_date..end_date)
                                   .group(:summary_date)
                                   .sum(:total_cost)

    # Calculate moving average and trend
    costs_array = daily_costs.sort.map { |date, cost| cost }
    {
      daily: daily_costs,
      moving_average_7d: calculate_moving_average(costs_array, 7),
      trend: calculate_trend_direction(costs_array)
    }
  end

  def check_threshold_alerts(entity)
    alerts = []
    tracker = EntityCostTracker.new(entity)
    current_costs = tracker.get_costs_by_category

    entity.cost_thresholds.each do |category, threshold|
      current = current_costs[category.to_sym] || 0
      if current > threshold
        alerts << {
          category: category,
          threshold: threshold,
          current: current,
          overage_percent: ((current - threshold) / threshold * 100).round(2)
        }
      end
    end

    alerts
  end

  def generate_csv(entity, start_date, end_date)
    require 'csv'

    CSV.generate(headers: true) do |csv|
      csv << ['Date', 'Category', 'Service', 'Quantity', 'Rate', 'Cost (USD)', 'Usage Type']

      entity.entity_usage_metrics
            .where(tracked_at: start_date..end_date)
            .order(tracked_at: :asc)
            .each do |metric|
        csv << [
          metric.tracked_at.strftime('%Y-%m-%d %H:%M'),
          metric.category,
          metric.service,
          metric.quantity,
          metric.rate,
          metric.calculated_cost_usd,
          metric.usage_type
        ]
      end
    end
  end

  def get_ai_usage_details(entity, start_date, end_date)
    entity.entity_usage_metrics
          .where(category: 'ai_chat', tracked_at: start_date..end_date)
          .group(:service)
          .pluck(
            :service,
            'SUM(quantity) as total_tokens',
            'SUM(calculated_cost_usd) as total_cost',
            'COUNT(*) as conversation_count'
          )
  end

  def get_email_usage_details(entity, start_date, end_date)
    entity.entity_usage_metrics
          .where(category: 'email', tracked_at: start_date..end_date)
          .group(:service)
          .pluck(
            :service,
            'SUM(quantity) as emails_sent',
            'SUM(calculated_cost_usd) as total_cost'
          )
  end

  def get_storage_usage_details(entity, start_date, end_date)
    entity.entity_usage_metrics
          .where(category: 'storage', tracked_at: start_date..end_date)
          .group(:service)
          .pluck(
            :service,
            'AVG(quantity) as avg_gb_stored',
            'SUM(calculated_cost_usd) as total_cost'
          )
  end

  def analyze_cost_growth_rates
    # Compare this month to last month for all entities
    current_month_start = Date.current.beginning_of_month
    last_month_start = 1.month.ago.beginning_of_month
    last_month_end = 1.month.ago.end_of_month

    Entity.joins(:entity_cost_summaries)
          .select('entities.*,
                   SUM(CASE WHEN summary_date >= ? THEN total_cost ELSE 0 END) as current_month_cost,
                   SUM(CASE WHEN summary_date BETWEEN ? AND ? THEN total_cost ELSE 0 END) as last_month_cost',
                   current_month_start, last_month_start, last_month_end)
          .group('entities.id')
          .having('last_month_cost > 0')
          .order('(current_month_cost - last_month_cost) / last_month_cost DESC')
          .limit(10)
  end

  def detect_cost_anomalies
    # Find entities with unusual cost spikes
    anomalies = []

    Entity.find_each do |entity|
      tracker = EntityCostTracker.new(entity)
      recent_costs = tracker.get_daily_costs(days: 30)

      next if recent_costs.empty?

      avg_cost = recent_costs.values.sum / recent_costs.size
      std_dev = Math.sqrt(recent_costs.values.map { |c| (c - avg_cost) ** 2 }.sum / recent_costs.size)

      recent_costs.each do |date, cost|
        if cost > avg_cost + (2 * std_dev) # 2 standard deviations above mean
          anomalies << {
            entity_id: entity.id,
            entity_name: entity.name,
            date: date,
            cost: cost,
            expected_range: "#{(avg_cost - std_dev).round(2)} - #{(avg_cost + std_dev).round(2)}"
          }
        end
      end
    end

    anomalies.sort_by { |a| -a[:cost] }.first(20)
  end

  def identify_optimization_opportunities
    opportunities = []

    Entity.includes(:entity_usage_metrics).find_each do |entity|
      # Check for underutilized services
      if entity.billing_tier == 'premium' &&
         entity.entity_usage_metrics.where(category: 'ai_chat').recent.count < 10
        opportunities << {
          entity_id: entity.id,
          type: 'downgrade_tier',
          potential_savings: estimate_tier_savings(entity)
        }
      end

      # Check for inefficient storage usage
      storage_metrics = entity.entity_usage_metrics.where(category: 'storage').recent
      if storage_metrics.any? { |m| m.service == 's3_standard' && m.quantity > 100 }
        opportunities << {
          entity_id: entity.id,
          type: 'optimize_storage',
          recommendation: 'Consider S3 Intelligent-Tiering for infrequently accessed data'
        }
      end
    end

    opportunities
  end

  def calculate_moving_average(values, window)
    return [] if values.empty? || window > values.size

    values.each_cons(window).map { |w| w.sum / window.to_f }
  end

  def calculate_trend_direction(values)
    return 'stable' if values.size < 2

    recent_avg = values.last(7).sum / [values.size, 7].min.to_f
    older_avg = values.first(7).sum / [values.size, 7].min.to_f

    change_percent = ((recent_avg - older_avg) / older_avg * 100).abs

    if change_percent < 5
      'stable'
    elsif recent_avg > older_avg
      'increasing'
    else
      'decreasing'
    end
  end

  def estimate_tier_savings(entity)
    current_tier_cost = {
      'premium' => 500,
      'standard' => 200,
      'starter' => 50,
      'free' => 0
    }[entity.billing_tier] || 0

    recommended_tier = recommend_tier_based_on_usage(entity)
    recommended_cost = current_tier_cost[recommended_tier] || 0

    current_tier_cost - recommended_cost
  end

  def recommend_tier_based_on_usage(entity)
    monthly_usage = entity.entity_usage_metrics.recent.count

    case monthly_usage
    when 0..10 then 'free'
    when 11..100 then 'starter'
    when 101..1000 then 'standard'
    else 'premium'
    end
  end
end