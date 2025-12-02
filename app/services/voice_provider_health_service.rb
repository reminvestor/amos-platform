# VoiceProviderHealthService - Monitor STT provider availability and performance
#
# Responsibilities:
# - Check health of Eleven Labs and Deepgram providers
# - Track provider uptime and response times
# - Report health status for monitoring/alerting
# - Support circuit breaker pattern
#
# Usage:
#   service = VoiceProviderHealthService.new
#   status = service.check_provider_health("eleven_labs")
#   metrics = service.get_provider_metrics("deepgram")
class VoiceProviderHealthService
  HEALTH_CHECK_TIMEOUT = 5  # seconds
  METRICS_RETENTION_DAYS = 7

  attr_reader :provider_metrics

  def initialize
    @provider_metrics = {}
  end

  # Check health of a specific STT provider
  #
  # @param provider [String] Provider name ("eleven_labs" or "deepgram")
  # @return [Hash] Health status with availability and latency
  def check_provider_health(provider)
    case provider
    when "eleven_labs"
      check_eleven_labs_health
    when "deepgram"
      check_deepgram_health
    else
      { status: "unknown", provider: provider, error: "Unknown provider" }
    end
  end

  # Get all provider health statuses
  #
  # @return [Hash] Health status for all providers
  def check_all_providers_health
    {
      timestamp: Time.current,
      eleven_labs: check_eleven_labs_health,
      deepgram: check_deepgram_health,
      summary: generate_health_summary
    }
  end

  # Get performance metrics for a provider
  #
  # @param provider [String] Provider name
  # @return [Hash] Performance statistics
  def get_provider_metrics(provider)
    metrics = Rails.cache.read("voice:provider:metrics:#{provider}")
    metrics || { provider: provider, status: "no_data", error: "No metrics collected yet" }
  end

  # Record successful connection
  #
  # @param provider [String] Provider name
  # @param connection_time [Float] Time to connect in milliseconds
  def record_successful_connection(provider, connection_time)
    record_metric(provider, "success", connection_time)
  end

  # Record failed connection
  #
  # @param provider [String] Provider name
  # @param error_message [String] Error description
  def record_failed_connection(provider, error_message)
    record_metric(provider, "failure", nil, error_message)
  end

  # Get provider health summary for UI/dashboard
  #
  # @return [Hash] Summary with uptime percentage and recommendations
  def get_health_summary
    metrics = {
      timestamp: Time.current,
      providers: {}
    }

    ["eleven_labs", "deepgram"].each do |provider|
      health = check_provider_health(provider)
      metrics[:providers][provider] = {
        status: health[:status],
        latency_ms: health[:latency_ms],
        available: health[:available],
        last_checked: health[:timestamp]
      }
    end

    metrics[:recommended_provider] = determine_recommended_provider(metrics[:providers])
    metrics
  end

  # Check if provider should be used based on circuit breaker
  #
  # @param provider [String] Provider name
  # @param failure_threshold [Integer] Failures before circuit opens (default: 5)
  # @return [Boolean] Whether provider is available
  def is_provider_available?(provider, failure_threshold: 5)
    failures = get_recent_failure_count(provider)
    failures < failure_threshold
  end

  private

  def check_eleven_labs_health
    start_time = Time.current
    begin
      # Note: Many Eleven Labs API keys are scoped to specific endpoints (e.g., transcription only)
      # and may not have user_read permission. We test with /v1/user but handle permission errors gracefully.
      response = HTTParty.get(
        "https://api.elevenlabs.io/v1/user",
        headers: {
          "xi-api-key" => ENV["ELEVEN_LABS_API_KEY"]
        },
        timeout: HEALTH_CHECK_TIMEOUT
      )

      latency = ((Time.current - start_time) * 1000).to_i

      if response.success?
        {
          status: "healthy",
          provider: "eleven_labs",
          available: true,
          latency_ms: latency,
          timestamp: Time.current,
          message: "Eleven Labs API responding normally"
        }
      elsif response.code == 401
        # Check if it's a permission error (key is valid but lacks user_read permission)
        begin
          error_detail = JSON.parse(response.body)
          if error_detail.dig("detail", "status") == "missing_permissions"
            # API key is valid but lacks this specific permission - still usable for transcription
            {
              status: "healthy",
              provider: "eleven_labs",
              available: true,
              latency_ms: latency,
              timestamp: Time.current,
              message: "Eleven Labs API key valid (limited permissions)"
            }
          else
            {
              status: "unhealthy",
              provider: "eleven_labs",
              available: false,
              latency_ms: latency,
              timestamp: Time.current,
              error: "HTTP #{response.code}: #{response.message}"
            }
          end
        rescue JSON::ParserError
          {
            status: "unhealthy",
            provider: "eleven_labs",
            available: false,
            latency_ms: latency,
            timestamp: Time.current,
            error: "HTTP #{response.code}: #{response.message}"
          }
        end
      else
        {
          status: "unhealthy",
          provider: "eleven_labs",
          available: false,
          latency_ms: latency,
          timestamp: Time.current,
          error: "HTTP #{response.code}: #{response.message}"
        }
      end
    rescue Timeout::Error
      {
        status: "timeout",
        provider: "eleven_labs",
        available: false,
        latency_ms: ((Time.current - start_time) * 1000).to_i,
        timestamp: Time.current,
        error: "Health check timed out after #{HEALTH_CHECK_TIMEOUT}s"
      }
    rescue => e
      {
        status: "error",
        provider: "eleven_labs",
        available: false,
        latency_ms: ((Time.current - start_time) * 1000).to_i,
        timestamp: Time.current,
        error: e.message
      }
    end
  end

  def check_deepgram_health
    start_time = Time.current
    begin
      response = HTTParty.get(
        "https://api.deepgram.com/v1/status",
        headers: {
          "Authorization" => "Token #{ENV['DEEPGRAM_API_KEY']}"
        },
        timeout: HEALTH_CHECK_TIMEOUT
      )

      latency = ((Time.current - start_time) * 1000).to_i

      if response.success?
        {
          status: "healthy",
          provider: "deepgram",
          available: true,
          latency_ms: latency,
          timestamp: Time.current,
          message: "Deepgram API responding normally"
        }
      else
        {
          status: "unhealthy",
          provider: "deepgram",
          available: false,
          latency_ms: latency,
          timestamp: Time.current,
          error: "HTTP #{response.code}: #{response.message}"
        }
      end
    rescue Timeout::Error
      {
        status: "timeout",
        provider: "deepgram",
        available: false,
        latency_ms: ((Time.current - start_time) * 1000).to_i,
        timestamp: Time.current,
        error: "Health check timed out after #{HEALTH_CHECK_TIMEOUT}s"
      }
    rescue => e
      {
        status: "error",
        provider: "deepgram",
        available: false,
        latency_ms: ((Time.current - start_time) * 1000).to_i,
        timestamp: Time.current,
        error: e.message
      }
    end
  end

  def record_metric(provider, result_type, connection_time = nil, error_message = nil)
    cache_key = "voice:provider:metrics:#{provider}"
    metrics = Rails.cache.read(cache_key) || {
      provider: provider,
      total_attempts: 0,
      successful: 0,
      failed: 0,
      avg_latency_ms: 0,
      last_error: nil,
      updated_at: Time.current
    }

    metrics[:total_attempts] += 1

    if result_type == "success"
      metrics[:successful] += 1
      # Update rolling average
      avg = metrics[:avg_latency_ms]
      metrics[:avg_latency_ms] = ((avg * (metrics[:successful] - 1)) + connection_time) / metrics[:successful]
    else
      metrics[:failed] += 1
      metrics[:last_error] = error_message
    end

    metrics[:updated_at] = Time.current
    Rails.cache.write(cache_key, metrics, expires_in: METRICS_RETENTION_DAYS.days)
  end

  def get_recent_failure_count(provider)
    metrics = Rails.cache.read("voice:provider:metrics:#{provider}")
    metrics ? metrics[:failed] : 0
  end

  def generate_health_summary
    eleven_labs_health = check_provider_health("eleven_labs")
    deepgram_health = check_provider_health("deepgram")

    both_healthy = eleven_labs_health[:available] && deepgram_health[:available]
    one_healthy = eleven_labs_health[:available] || deepgram_health[:available]

    {
      overall_status: both_healthy ? "healthy" : (one_healthy ? "degraded" : "unavailable"),
      both_providers_available: both_healthy,
      recommended_action: recommend_action(eleven_labs_health, deepgram_health)
    }
  end

  def determine_recommended_provider(providers)
    eleven_labs = providers["eleven_labs"]
    deepgram = providers["deepgram"]

    return "eleven_labs" if eleven_labs[:available] && !deepgram[:available]
    return "deepgram" if deepgram[:available] && !eleven_labs[:available]

    # Both available - recommend based on latency
    if eleven_labs[:available] && deepgram[:available]
      return (eleven_labs[:latency_ms] || 999) < (deepgram[:latency_ms] || 999) ? "eleven_labs" : "deepgram"
    end

    nil  # Neither available
  end

  def recommend_action(eleven_labs_health, deepgram_health)
    if !eleven_labs_health[:available] && !deepgram_health[:available]
      "CRITICAL: Both providers unavailable. Voice features disabled. Check API credentials and network connectivity."
    elsif !eleven_labs_health[:available]
      "WARNING: Eleven Labs unavailable. Using Deepgram fallback. Check Eleven Labs API status."
    elsif !deepgram_health[:available]
      "WARNING: Deepgram unavailable. Fallback not available if Eleven Labs fails. Consider investigating Deepgram status."
    else
      "OK: Both providers healthy and available."
    end
  end
end
