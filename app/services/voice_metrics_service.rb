# VoiceMetricsService - Track and analyze STT voice transcription usage and performance
#
# Responsibilities:
# - Record voice session metrics (duration, provider, success/failure)
# - Track provider performance (latency, success rate, uptime)
# - Generate analytics reports
# - Support fallback usage tracking
#
# Usage:
#   service = VoiceMetricsService.new
#   service.record_session_metric(voice_session, "eleven_labs", connection_time_ms: 150)
#   report = service.generate_provider_report("deepgram", days: 7)
class VoiceMetricsService
  METRICS_RETENTION_DAYS = 30

  # Record metrics for a completed voice session
  #
  # @param voice_session [VoiceSession] The session
  # @param provider [String] STT provider used
  # @param metrics [Hash] Connection and performance metrics
  def record_session_metric(voice_session, provider, metrics = {})
    metric_key = "voice:session:metrics:#{voice_session.session_id}"

    data = {
      session_id: voice_session.session_id,
      entity_id: voice_session.entity_id,
      user_id: voice_session.user_id,
      provider: provider,
      timestamp: Time.current,
      connection_time_ms: metrics[:connection_time_ms] || 0,
      transcript_count: metrics[:transcript_count] || 0,
      duration_seconds: metrics[:duration_seconds] || 0,
      success: metrics[:success].nil? ? true : metrics[:success],
      error: metrics[:error],
      fallback_used: metrics[:fallback_used] || false
    }

    Rails.cache.write(metric_key, data, expires_in: METRICS_RETENTION_DAYS.days)

    # Also aggregate to provider metrics
    aggregate_provider_metric(provider, data)

    data
  end

  # Get statistics for a provider over a time period
  #
  # @param provider [String] Provider name
  # @param days [Integer] Number of days to analyze (default: 7)
  # @return [Hash] Provider statistics
  def get_provider_statistics(provider, days: 7)
    from_date = days.days.ago
    metrics = get_provider_metrics(provider, from_date)

    total_sessions = metrics.length
    successful_sessions = metrics.count { |m| m["success"] }
    failed_sessions = total_sessions - successful_sessions

    success_rate = total_sessions > 0 ? (successful_sessions.to_f / total_sessions * 100).round(2) : 0
    avg_connection_time = total_sessions > 0 ? (metrics.sum { |m| m["connection_time_ms"] } / total_sessions).round(2) : 0
    avg_session_duration = total_sessions > 0 ? (metrics.sum { |m| m["duration_seconds"] } / total_sessions).round(2) : 0

    fallback_sessions = metrics.count { |m| m["fallback_used"] }
    fallback_rate = total_sessions > 0 ? (fallback_sessions.to_f / total_sessions * 100).round(2) : 0

    {
      provider: provider,
      period_days: days,
      timestamp: Time.current,
      total_sessions: total_sessions,
      successful_sessions: successful_sessions,
      failed_sessions: failed_sessions,
      success_rate_percent: success_rate,
      avg_connection_time_ms: avg_connection_time,
      avg_session_duration_seconds: avg_session_duration,
      fallback_sessions: fallback_sessions,
      fallback_rate_percent: fallback_rate,
      common_errors: get_common_errors(metrics, limit: 5)
    }
  end

  # Compare two providers
  #
  # @param provider1 [String] First provider
  # @param provider2 [String] Second provider
  # @param days [Integer] Period to compare
  # @return [Hash] Comparison data
  def compare_providers(provider1, provider2, days: 7)
    stats1 = get_provider_statistics(provider1, days: days)
    stats2 = get_provider_statistics(provider2, days: days)

    {
      timestamp: Time.current,
      period_days: days,
      provider1: stats1,
      provider2: stats2,
      winner: determine_best_provider(stats1, stats2),
      recommendation: generate_recommendation(stats1, stats2)
    }
  end

  # Generate entity-level usage report
  #
  # @param entity_id [Integer] Entity ID
  # @param days [Integer] Period
  # @return [Hash] Usage report
  def get_entity_usage_report(entity_id, days: 7)
    from_date = days.days.ago
    all_metrics = get_all_metrics_for_period(from_date)
    entity_metrics = all_metrics.select { |m| m["entity_id"] == entity_id }

    provider_breakdown = {}
    ["eleven_labs", "deepgram"].each do |provider|
      provider_metrics = entity_metrics.select { |m| m["provider"] == provider }
      provider_breakdown[provider] = {
        sessions: provider_metrics.length,
        success_rate: provider_metrics.length > 0 ?
          (provider_metrics.count { |m| m["success"] }.to_f / provider_metrics.length * 100).round(2) : 0
      }
    end

    {
      entity_id: entity_id,
      period_days: days,
      total_sessions: entity_metrics.length,
      provider_breakdown: provider_breakdown,
      most_used_provider: get_most_used_provider(provider_breakdown)
    }
  end

  # Get recent session performance
  #
  # @param limit [Integer] Number of recent sessions
  # @return [Array] Recent sessions
  def get_recent_sessions(limit: 10)
    all_metrics = get_all_metrics_for_period(Time.current - 1.day)
    all_metrics.sort_by { |m| m["timestamp"] }.reverse.take(limit)
  end

  # Health check - monitor for issues
  #
  # @return [Hash] Health status
  def check_voice_system_health
    stats_seven_days = {}
    stats_one_day = {}

    ["eleven_labs", "deepgram"].each do |provider|
      stats_seven_days[provider] = get_provider_statistics(provider, days: 7)
      stats_one_day[provider] = get_provider_statistics(provider, days: 1)
    end

    {
      timestamp: Time.current,
      seven_day_stats: stats_seven_days,
      one_day_stats: stats_one_day,
      alerts: generate_health_alerts(stats_seven_days, stats_one_day)
    }
  end

  private

  def aggregate_provider_metric(provider, metric)
    key = "voice:provider:metrics:#{provider}:#{metric[:timestamp].strftime('%Y-%m-%d')}"
    metrics = Rails.cache.read(key) || []
    metrics << metric
    Rails.cache.write(key, metrics, expires_in: METRICS_RETENTION_DAYS.days)
  end

  def get_provider_metrics(provider, from_date)
    metrics = []

    (from_date.to_date..Date.today).each do |date|
      key = "voice:provider:metrics:#{provider}:#{date.strftime('%Y-%m-%d')}"
      day_metrics = Rails.cache.read(key) || []
      metrics.concat(day_metrics)
    end

    metrics
  end

  def get_all_metrics_for_period(from_date)
    metrics = []

    (from_date.to_date..Date.today).each do |date|
      ["eleven_labs", "deepgram"].each do |provider|
        key = "voice:provider:metrics:#{provider}:#{date.strftime('%Y-%m-%d')}"
        day_metrics = Rails.cache.read(key) || []
        metrics.concat(day_metrics)
      end
    end

    metrics
  end

  def get_common_errors(metrics, limit: 5)
    error_counts = {}

    metrics.each do |metric|
      next unless metric["error"]

      error = metric["error"]
      error_counts[error] = (error_counts[error] || 0) + 1
    end

    error_counts
      .sort_by { |_, count| count }
      .reverse
      .take(limit)
      .map { |error, count| { error: error, count: count } }
  end

  def determine_best_provider(stats1, stats2)
    # Score based on multiple factors
    score1 = (stats1[:success_rate_percent] || 0) - (stats1[:avg_connection_time_ms] || 0) / 100
    score2 = (stats2[:success_rate_percent] || 0) - (stats2[:avg_connection_time_ms] || 0) / 100

    score1 > score2 ? stats1[:provider] : stats2[:provider]
  end

  def generate_recommendation(stats1, stats2)
    success_rate_diff = (stats1[:success_rate_percent] || 0) - (stats2[:success_rate_percent] || 0)
    latency_diff = (stats2[:avg_connection_time_ms] || 0) - (stats1[:avg_connection_time_ms] || 0)

    if success_rate_diff > 10
      "#{stats1[:provider]} has significantly better success rate (#{success_rate_diff.round(1)}% higher)"
    elsif success_rate_diff < -10
      "#{stats2[:provider]} has significantly better success rate (#{(-success_rate_diff).round(1)}% higher)"
    elsif latency_diff > 100
      "#{stats1[:provider]} has lower latency (#{latency_diff.round(0)}ms faster)"
    else
      "Both providers performing similarly. Choose based on other factors."
    end
  end

  def get_most_used_provider(breakdown)
    breakdown.max_by { |_, data| data[:sessions] }&.first
  end

  def generate_health_alerts(seven_day_stats, one_day_stats)
    alerts = []

    seven_day_stats.each do |provider, stats|
      if stats[:success_rate_percent] < 80
        alerts << {
          severity: "warning",
          message: "#{provider}: Success rate below 80% (#{stats[:success_rate_percent]}%) over past 7 days"
        }
      end

      if stats[:success_rate_percent] < 50
        alerts << {
          severity: "critical",
          message: "#{provider}: Success rate critically low (#{stats[:success_rate_percent]}%) over past 7 days"
        }
      end
    end

    one_day_stats.each do |provider, stats|
      if one_day_stats[provider][:total_sessions] > 0 && one_day_stats[provider][:success_rate_percent] < 50
        alerts << {
          severity: "critical",
          message: "#{provider}: Critical failure rate in past 24 hours (#{100 - one_day_stats[provider][:success_rate_percent]}% failures)"
        }
      end
    end

    alerts
  end
end
