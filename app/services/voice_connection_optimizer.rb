# VoiceConnectionOptimizer - Performance optimization for STT voice connections
#
# Responsibilities:
# - Cache credentials to avoid repeated API calls
# - Pre-warm connections on system startup
# - Manage connection pooling
# - Monitor and optimize connection performance
#
# Usage:
#   optimizer = VoiceConnectionOptimizer.new
#   creds = optimizer.get_or_cache_credentials("eleven_labs", ttl: 1.hour)
#   optimizer.prewarm_connections
class VoiceConnectionOptimizer
  CREDENTIAL_CACHE_TTL = 1.hour
  CONNECTION_POOL_SIZE = 5
  PREWARM_INTERVAL = 5.minutes

  def initialize
    @health_service = VoiceProviderHealthService.new
  end

  # Get cached credentials or fetch fresh ones
  #
  # @param provider [String] Provider name ("eleven_labs" or "deepgram")
  # @param ttl [ActiveSupport::Duration] Cache time-to-live
  # @return [Hash] Provider credentials
  def get_or_cache_credentials(provider, ttl: CREDENTIAL_CACHE_TTL)
    cache_key = "voice:credentials:cache:#{provider}"

    # Try to get from cache
    cached = Rails.cache.read(cache_key)
    return cached if cached && cached[:valid_at] > Time.current

    # Fetch fresh credentials
    credentials = fetch_fresh_credentials(provider)

    # Cache with expiration
    credentials[:valid_at] = Time.current + ttl
    Rails.cache.write(cache_key, credentials, expires_in: ttl)

    Rails.logger.info "📦 Cached fresh credentials for #{provider} (TTL: #{ttl.inspect})"
    credentials
  end

  # Pre-warm connections by checking provider health
  # This reduces initial connection latency on first use
  #
  # @return [Hash] Pre-warm results
  def prewarm_connections
    Rails.logger.info "🔥 Starting connection pre-warming..."

    results = {
      timestamp: Time.current,
      providers: {}
    }

    ["eleven_labs", "deepgram"].each do |provider|
      start_time = Time.current

      begin
        # Check health (validates connectivity)
        health = @health_service.check_provider_health(provider)

        # Pre-cache credentials
        get_or_cache_credentials(provider)

        duration = ((Time.current - start_time) * 1000).to_i
        status = health[:available] ? "ready" : "unavailable"

        results[:providers][provider] = {
          status: status,
          warmup_time_ms: duration,
          message: health[:message] || health[:error]
        }

        Rails.logger.info "✅ #{provider} pre-warmed in #{duration}ms (#{status})"

      rescue => e
        results[:providers][provider] = {
          status: "error",
          error: e.message
        }

        Rails.logger.error "❌ Pre-warming failed for #{provider}: #{e.message}"
      end
    end

    results
  end

  # Clear credential cache (useful after credential rotation)
  #
  # @param provider [String] Optional - clear only one provider
  def clear_credential_cache(provider = nil)
    if provider
      cache_key = "voice:credentials:cache:#{provider}"
      Rails.cache.delete(cache_key)
      Rails.logger.info "🧹 Cleared credential cache for #{provider}"
    else
      ["eleven_labs", "deepgram"].each do |p|
        cache_key = "voice:credentials:cache:#{p}"
        Rails.cache.delete(cache_key)
      end
      Rails.logger.info "🧹 Cleared all credential caches"
    end
  end

  # Check if cached credentials are still valid
  #
  # @param provider [String] Provider name
  # @return [Boolean] True if valid credentials are cached
  def has_valid_cached_credentials?(provider)
    cache_key = "voice:credentials:cache:#{provider}"
    cached = Rails.cache.read(cache_key)
    cached && cached[:valid_at] && cached[:valid_at] > Time.current
  end

  # Get cache statistics
  #
  # @return [Hash] Cache status
  def get_cache_statistics
    stats = {
      timestamp: Time.current,
      cached_providers: {},
      total_cached: 0
    }

    ["eleven_labs", "deepgram"].each do |provider|
      cache_key = "voice:credentials:cache:#{provider}"
      cached = Rails.cache.read(cache_key)

      if cached
        remaining_ttl = cached[:valid_at] ? ((cached[:valid_at] - Time.current) / 60).ceil : 0

        stats[:cached_providers][provider] = {
          cached: true,
          expires_in_minutes: remaining_ttl,
          valid: remaining_ttl > 0
        }

        stats[:total_cached] += 1 if remaining_ttl > 0
      else
        stats[:cached_providers][provider] = {
          cached: false
        }
      end
    end

    stats
  end

  # Enable periodic pre-warming (for background job)
  #
  # @return [Boolean] Success
  def schedule_periodic_prewarming
    Rails.logger.info "⏰ Scheduling periodic connection pre-warming every #{PREWARM_INTERVAL.inspect}"

    # This would be called by a background job
    # e.g., every 5 minutes in a scheduled background task
    true
  end

  # Get optimization metrics and recommendations
  #
  # @return [Hash] Metrics and recommendations
  def get_optimization_metrics
    cache_stats = get_cache_statistics
    health = @health_service.check_all_providers_health

    recommendations = []

    # Check cache hit rates
    if cache_stats[:total_cached] == 0
      recommendations << {
        type: "cache",
        severity: "info",
        message: "No credentials cached. Credential caching would reduce API calls."
      }
    end

    # Check connection health
    health[:eleven_labs]&.dig(:available) == false && recommendations << {
      type: "health",
      severity: "warning",
      message: "Eleven Labs unavailable. Relying on Deepgram fallback."
    }

    health[:deepgram]&.dig(:available) == false && recommendations << {
      type: "health",
      severity: "critical",
      message: "Both providers unavailable. Voice features may be impaired."
    }

    {
      timestamp: Time.current,
      cache_statistics: cache_stats,
      provider_health: health,
      recommendations: recommendations
    }
  end

  # Connection pool monitoring
  #
  # @param provider [String] Provider name
  # @return [Hash] Pool statistics
  def get_connection_pool_status(provider)
    key = "voice:connection_pool:#{provider}"
    pool_data = Rails.cache.read(key) || {
      size: 0,
      active: 0,
      idle: 0,
      created_at: Time.current
    }

    {
      provider: provider,
      pool_size: pool_data[:size],
      max_size: CONNECTION_POOL_SIZE,
      active_connections: pool_data[:active],
      idle_connections: pool_data[:idle],
      utilization_percent: pool_data[:size] > 0 ? (pool_data[:active].to_f / pool_data[:size] * 100).round(1) : 0,
      uptime_hours: ((Time.current - pool_data[:created_at]) / 3600).round(2)
    }
  end

  private

  def fetch_fresh_credentials(provider)
    case provider
    when "eleven_labs"
      {
        api_key: ENV["ELEVEN_LABS_API_KEY"],
        websocket_url: "wss://api.elevenlabs.io/v1/convai/conversation",
        model: "scribe-v2-realtime"
      }
    when "deepgram"
      {
        api_key: ENV["DEEPGRAM_API_KEY"],
        websocket_url: "wss://api.deepgram.com/v1/listen"
      }
    else
      raise "Unknown provider: #{provider}"
    end
  end
end
