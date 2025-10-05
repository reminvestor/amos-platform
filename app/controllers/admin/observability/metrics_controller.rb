class Admin::Observability::MetricsController < Admin::BaseController
  def ai_usage
    @timeframe = params[:timeframe] || '24h'
    
    @stats = {
      total_ai_calls: calculate_ai_calls(@timeframe),
      total_tokens: calculate_tokens(@timeframe),
      estimated_cost: calculate_cost(@timeframe),
      avg_response_time: calculate_avg_response_time(@timeframe)
    }
    
    @usage_by_user = calculate_usage_by_user(@timeframe)
    @usage_by_model = calculate_usage_by_model(@timeframe)
  end
  
  def workflows
    @timeframe = params[:timeframe] || '7d'
    
    @stats = {
      total_workflows: TaskSession.where(created_at: timeframe_start(@timeframe)..).count,
      completed: TaskSession.where(status: 'completed', created_at: timeframe_start(@timeframe)..).count,
      failed: TaskSession.where(status: 'failed', created_at: timeframe_start(@timeframe)..).count,
      active: TaskSession.where(status: 'active').count
    }
    
    @recent_workflows = TaskSession.order(created_at: :desc).limit(20)
  end
  
  def errors
    @timeframe = params[:timeframe] || '24h'
    
    @error_logs = IntegrationLog.where('response_status >= 400')
                                .where(created_at: timeframe_start(@timeframe)..)
                                .order(created_at: :desc)
                                .limit(100)
    
    @error_rate = calculate_error_rate(@timeframe)
  end
  
  def performance
    @timeframe = params[:timeframe] || '24h'
    
    @stats = {
      avg_response_time: calculate_avg_api_response_time(@timeframe),
      p95_response_time: calculate_p95_response_time(@timeframe),
      slowest_operations: find_slowest_operations(@timeframe)
    }
  end
  
  private
  
  def timeframe_start(timeframe)
    case timeframe
    when '1h' then 1.hour.ago
    when '24h' then 24.hours.ago
    when '7d' then 7.days.ago
    when '30d' then 30.days.ago
    else 24.hours.ago
    end
  end
  
  def calculate_ai_calls(timeframe)
    # Placeholder - would query ObservabilityEvent or similar
    rand(100..1000)
  end
  
  def calculate_tokens(timeframe)
    rand(10_000..100_000)
  end
  
  def calculate_cost(timeframe)
    (calculate_tokens(timeframe) * 0.00002).round(2)
  end
  
  def calculate_avg_response_time(timeframe)
    rand(500..2000)
  end
  
  def calculate_usage_by_user(timeframe)
    []
  end
  
  def calculate_usage_by_model(timeframe)
    []
  end
  
  def calculate_error_rate(timeframe)
    total = IntegrationLog.where(created_at: timeframe_start(timeframe)..).count
    errors = IntegrationLog.where('response_status >= 400').where(created_at: timeframe_start(timeframe)..).count
    total > 0 ? ((errors.to_f / total) * 100).round(2) : 0
  end
  
  def calculate_avg_api_response_time(timeframe)
    IntegrationLog.where(created_at: timeframe_start(timeframe)..)
                  .average(:duration_ms)&.round(0) || 0
  end
  
  def calculate_p95_response_time(timeframe)
    durations = IntegrationLog.where(created_at: timeframe_start(timeframe)..)
                              .where.not(duration_ms: nil)
                              .pluck(:duration_ms)
                              .sort
    return 0 if durations.empty?
    
    index = (durations.length * 0.95).ceil - 1
    durations[index] || 0
  end
  
  def find_slowest_operations(timeframe)
    IntegrationLog.where(created_at: timeframe_start(timeframe)..)
                  .where.not(duration_ms: nil)
                  .group(:operation_id)
                  .average(:duration_ms)
                  .sort_by { |_, avg| -avg }
                  .first(10)
  end
end

