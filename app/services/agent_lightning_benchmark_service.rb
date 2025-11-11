# Performance Benchmarking Service for Agent Lightning
# Measures and compares agent performance before/after training
class AgentLightningBenchmarkService
  attr_reader :entity, :before_date, :after_date

  def initialize(entity, before_date = 30.days.ago, after_date = Time.current)
    @entity = entity
    @before_date = before_date
    @after_date = after_date
  end

  # Get comprehensive benchmark report
  def generate_report
    {
      entity_name: @entity.name,
      generated_at: Time.current.iso8601,
      period: {
        before: @before_date.iso8601,
        after: @after_date.iso8601
      },
      summary: benchmark_summary,
      metrics: detailed_metrics,
      improvements: calculate_improvements,
      recommendations: generate_recommendations
    }
  end

  # Summary benchmark data
  def benchmark_summary
    before = get_period_metrics(@before_date, 30.days.before(@before_date))
    after = get_period_metrics(@after_date, 30.days.before(@after_date))

    {
      before: before,
      after: after,
      period: {
        before_traces: before[:total_traces],
        after_traces: after[:total_traces],
        before_days: 30,
        after_days: 30
      }
    }
  end

  # Detailed metric breakdown
  def detailed_metrics
    {
      success_metrics: benchmark_success_rate,
      cost_metrics: benchmark_costs,
      performance_metrics: benchmark_performance,
      quality_metrics: benchmark_quality,
      tool_metrics: benchmark_tool_performance,
      llm_metrics: benchmark_llm_performance
    }
  end

  # Calculate improvements
  def calculate_improvements
    before = get_period_metrics(30.days.before(@before_date), 60.days.before(@before_date))
    after = get_period_metrics(@after_date, 30.days.before(@after_date))

    success_improvement = if before[:success_rate].zero?
      0
    else
      ((after[:success_rate] - before[:success_rate]) / before[:success_rate] * 100).round(1)
    end

    cost_improvement = if before[:avg_cost].zero?
      0
    else
      ((before[:avg_cost] - after[:avg_cost]) / before[:avg_cost] * 100).round(1)
    end

    token_improvement = if before[:avg_tokens].zero?
      0
    else
      ((before[:avg_tokens] - after[:avg_tokens]) / before[:avg_tokens] * 100).round(1)
    end

    latency_improvement = if before[:avg_latency].zero?
      0
    else
      ((before[:avg_latency] - after[:avg_latency]) / before[:avg_latency] * 100).round(1)
    end

    {
      success_rate_improvement: success_improvement,
      cost_improvement: cost_improvement,
      token_improvement: token_improvement,
      latency_improvement: latency_improvement,
      overall_improvement: (success_improvement + cost_improvement + token_improvement + latency_improvement) / 4
    }
  end

  # Specific metric benchmarks
  private

  def get_period_metrics(start_date, compare_start_date)
    traces = @entity.agent_lightning_traces.where("created_at BETWEEN ? AND ?", start_date, start_date + 30.days)
    return default_metrics if traces.empty?

    {
      total_traces: traces.count,
      success_rate: calculate_success_rate(traces),
      avg_tokens: traces.average(:token_count).to_i,
      total_tokens: traces.sum(:token_count),
      avg_cost: traces.average(:cost_estimate).to_f,
      total_cost: traces.sum(:cost_estimate).to_f,
      avg_duration: traces.average(:duration_ms).to_i,
      avg_reward: traces.average(:reward_signal).to_f,
      llm_calls: @entity.agent_llm_calls.where("called_at BETWEEN ? AND ?", start_date, start_date + 30.days).count,
      tool_executions: @entity.agent_tool_executions.where("started_at BETWEEN ? AND ?", start_date, start_date + 30.days).count,
      avg_latency: @entity.agent_llm_calls.where("called_at BETWEEN ? AND ?", start_date, start_date + 30.days).average(:latency_ms).to_i
    }
  end

  def default_metrics
    {
      total_traces: 0,
      success_rate: 0,
      avg_tokens: 0,
      total_tokens: 0,
      avg_cost: 0.0,
      total_cost: 0.0,
      avg_duration: 0,
      avg_reward: 0.0,
      llm_calls: 0,
      tool_executions: 0,
      avg_latency: 0
    }
  end

  def calculate_success_rate(traces)
    return 0 if traces.empty?
    (traces.count { |t| t.reward_signal && t.reward_signal > 0.7 }.to_f / traces.count * 100).round(1)
  end

  def benchmark_success_rate
    before = @entity.agent_lightning_traces.where("created_at BETWEEN ? AND ?", 60.days.ago, 30.days.ago)
    after = @entity.agent_lightning_traces.where("created_at BETWEEN ? AND ?", @before_date, @after_date)

    before_rate = calculate_success_rate(before)
    after_rate = calculate_success_rate(after)

    {
      before: before_rate,
      after: after_rate,
      improvement: (after_rate - before_rate).round(1),
      improvement_percentage: before_rate.zero? ? 0 : ((after_rate - before_rate) / before_rate * 100).round(1)
    }
  end

  def benchmark_costs
    before = @entity.agent_lightning_traces.where("created_at BETWEEN ? AND ?", 60.days.ago, 30.days.ago)
    after = @entity.agent_lightning_traces.where("created_at BETWEEN ? AND ?", @before_date, @after_date)

    before_avg = before.average(:cost_estimate).to_f
    after_avg = after.average(:cost_estimate).to_f

    before_total = before.sum(:cost_estimate).to_f
    after_total = after.sum(:cost_estimate).to_f

    {
      before_avg: before_avg.round(4),
      after_avg: after_avg.round(4),
      avg_improvement: (before_avg - after_avg).round(4),
      avg_improvement_percentage: before_avg.zero? ? 0 : ((before_avg - after_avg) / before_avg * 100).round(1),
      before_total: before_total.round(2),
      after_total: after_total.round(2),
      total_savings: (before_total - after_total).round(2)
    }
  end

  def benchmark_performance
    before_calls = @entity.agent_llm_calls.where("called_at BETWEEN ? AND ?", 60.days.ago, 30.days.ago)
    after_calls = @entity.agent_llm_calls.where("called_at BETWEEN ? AND ?", @before_date, @after_date)

    before_latency = before_calls.average(:latency_ms).to_i
    after_latency = after_calls.average(:latency_ms).to_i

    {
      before_latency: before_latency,
      after_latency: after_latency,
      improvement: (before_latency - after_latency),
      improvement_percentage: before_latency.zero? ? 0 : ((before_latency - after_latency).to_f / before_latency * 100).round(1)
    }
  end

  def benchmark_quality
    before = @entity.agent_lightning_traces.where("created_at BETWEEN ? AND ?", 60.days.ago, 30.days.ago)
    after = @entity.agent_lightning_traces.where("created_at BETWEEN ? AND ?", @before_date, @after_date)

    before_reward = before.average(:reward_signal).to_f
    after_reward = after.average(:reward_signal).to_f

    {
      before: before_reward.round(2),
      after: after_reward.round(2),
      improvement: (after_reward - before_reward).round(2),
      improvement_percentage: before_reward.zero? ? 0 : ((after_reward - before_reward) / before_reward * 100).round(1)
    }
  end

  def benchmark_tool_performance
    before_execs = @entity.agent_tool_executions.where("started_at BETWEEN ? AND ?", 60.days.ago, 30.days.ago)
    after_execs = @entity.agent_tool_executions.where("started_at BETWEEN ? AND ?", @before_date, @after_date)

    before_success = before_execs.empty? ? 0 : (before_execs.count { |e| e.status == 'success' }.to_f / before_execs.count * 100).round(1)
    after_success = after_execs.empty? ? 0 : (after_execs.count { |e| e.status == 'success' }.to_f / after_execs.count * 100).round(1)

    {
      before_success_rate: before_success,
      after_success_rate: after_success,
      improvement: (after_success - before_success).round(1),
      before_count: before_execs.count,
      after_count: after_execs.count
    }
  end

  def benchmark_llm_performance
    before_calls = @entity.agent_llm_calls.where("called_at BETWEEN ? AND ?", 60.days.ago, 30.days.ago)
    after_calls = @entity.agent_llm_calls.where("called_at BETWEEN ? AND ?", @before_date, @after_date)

    before_success = before_calls.empty? ? 0 : (before_calls.count { |c| c.status == 'success' }.to_f / before_calls.count * 100).round(1)
    after_success = after_calls.empty? ? 0 : (after_calls.count { |c| c.status == 'success' }.to_f / after_calls.count * 100).round(1)

    before_tokens = before_calls.average(:total_tokens).to_i
    after_tokens = after_calls.average(:total_tokens).to_i

    {
      before_success_rate: before_success,
      after_success_rate: after_success,
      success_improvement: (after_success - before_success).round(1),
      before_avg_tokens: before_tokens,
      after_avg_tokens: after_tokens,
      token_improvement: (before_tokens - after_tokens).to_i
    }
  end

  def generate_recommendations
    improvements = calculate_improvements

    recommendations = []

    # Success rate recommendation
    if improvements[:success_rate_improvement] > 10
      recommendations << {
        category: "Success Rate",
        status: "✅ Excellent",
        message: "Success rate improved by #{improvements[:success_rate_improvement]}%",
        priority: "low"
      }
    elsif improvements[:success_rate_improvement] < 0
      recommendations << {
        category: "Success Rate",
        status: "⚠️ Declining",
        message: "Success rate declined by #{improvements[:success_rate_improvement].abs}%",
        priority: "high",
        action: "Review recent system changes and training data quality"
      }
    end

    # Cost recommendation
    if improvements[:cost_improvement] > 20
      recommendations << {
        category: "Cost Efficiency",
        status: "✅ Great",
        message: "Costs reduced by #{improvements[:cost_improvement]}%",
        priority: "low"
      }
    end

    # Token improvement
    if improvements[:token_improvement] > 15
      recommendations << {
        category: "Token Optimization",
        status: "✅ Good",
        message: "Token usage reduced by #{improvements[:token_improvement]}%",
        priority: "low"
      }
    end

    # Latency improvement
    if improvements[:latency_improvement] > 20
      recommendations << {
        category: "Latency",
        status: "✅ Improved",
        message: "Latency reduced by #{improvements[:latency_improvement]}%",
        priority: "low"
      }
    elsif improvements[:latency_improvement] < -10
      recommendations << {
        category: "Latency",
        status: "⚠️ Degraded",
        message: "Latency increased by #{improvements[:latency_improvement].abs}%",
        priority: "medium",
        action: "Review LLM model selection and caching strategy"
      }
    end

    # Overall recommendation
    if improvements[:overall_improvement] > 15
      recommendations << {
        category: "Overall",
        status: "✅ Excellent Progress",
        message: "Agent Lightning is providing measurable improvements across all metrics",
        priority: "low"
      }
    end

    recommendations
  end
end
