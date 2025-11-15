# Voice System Monitoring & Optimization Guide

Complete guide to monitoring, optimizing, and managing the STT voice transcription system with Eleven Labs and Deepgram providers.

## Table of Contents

1. [Health Monitoring](#health-monitoring)
2. [Error Recovery](#error-recovery)
3. [Metrics & Analytics](#metrics--analytics)
4. [Performance Optimization](#performance-optimization)
5. [API Endpoints](#api-endpoints)
6. [Configuration](#configuration)

---

## Health Monitoring

### Overview

The voice system includes comprehensive health checks for both STT providers:
- **Eleven Labs Scribe v2** (primary)
- **Deepgram** (fallback)

Health checks monitor:
- Provider availability
- API response latency
- Connection reliability
- Circuit breaker status

### Service: `VoiceProviderHealthService`

**Purpose**: Monitor provider health and generate system status reports

**Key Methods**:

```ruby
# Check health of a specific provider
health = VoiceProviderHealthService.new.check_provider_health("eleven_labs")
# Returns: { status: "healthy"|"unhealthy"|"timeout"|"error", available: bool, latency_ms: int, ... }

# Check all providers
all_health = service.check_all_providers_health
# Returns: { timestamp, eleven_labs, deepgram, summary }

# Get provider metrics
metrics = service.get_provider_metrics("deepgram")
# Returns: { provider, total_attempts, successful, failed, avg_latency_ms, ... }

# Get health summary
summary = service.get_health_summary
# Returns: { timestamp, providers, recommended_provider }
```

**Health Status Values**:
- ✅ **healthy** - Provider responding normally
- ⚠️ **unhealthy** - Provider responded with error
- ⏱️ **timeout** - Health check timed out
- ❌ **error** - Network or other error

**Example Usage**:

```ruby
service = VoiceProviderHealthService.new
health = service.check_provider_health("eleven_labs")

if health[:available]
  puts "✅ Eleven Labs ready (#{health[:latency_ms]}ms latency)"
else
  puts "⚠️ Eleven Labs unavailable: #{health[:error]}"
end
```

---

## Error Recovery

### Overview

Intelligent error recovery with exponential backoff and circuit breaker pattern:
- Automatic retry with exponential backoff
- Circuit breaker to prevent cascading failures
- Intelligent provider fallback
- Detailed failure logging

### Service: `VoiceConnectionRetryService`

**Purpose**: Handle connection failures with smart retry logic

**Configuration**:
```ruby
INITIAL_BACKOFF_MS = 100      # Start with 100ms
MAX_BACKOFF_MS = 5000         # Cap at 5 seconds
MAX_RETRIES = 3               # Max retry attempts
CIRCUIT_BREAKER_THRESHOLD = 5 # Failures before circuit opens
```

**Key Methods**:

```ruby
# Retry with exponential backoff
success = service.connect_with_retries("eleven_labs", creds) do |c|
  # Connection attempt block
end

# Fallback to secondary provider
result = service.connect_with_fallback(
  "eleven_labs", "deepgram",
  primary_creds, fallback_creds
) do |provider, creds|
  # Connection attempt
end
# Returns: { success: bool, provider: string, error: string }

# Check circuit breaker status
open = service.circuit_breaker_open?("eleven_labs")

# Get retry statistics
stats = service.get_statistics
# Returns: { current_retry_count, providers_in_circuit, timestamp }
```

**Retry Flow**:

```
Attempt 1 (immediate)
  ↓ FAIL
Wait 100ms (+ jitter)
Attempt 2
  ↓ FAIL
Wait 200ms (+ jitter)
Attempt 3
  ↓ FAIL
Wait 400ms (+ jitter)
Attempt 4
  ↓ FAIL
Circuit Breaker Opens (1 hour)
```

**Exponential Backoff with Jitter**:
- Prevents thundering herd problem
- Each retry: `backoff_ms * 2^(attempt-1)`
- Random jitter: ±20%
- Capped at MAX_BACKOFF_MS (5s)

**Example Usage**:

```ruby
service = VoiceConnectionRetryService.new(voice_session)

# Try with automatic retry
success = service.connect_with_retries("eleven_labs", creds) do |c|
  # Eleven Labs WebSocket connection
  voice_assistant_controller.connectElevenLabs(c)
end

if !success
  # Fallback to Deepgram
  deepgram_creds = service.getDeepgramCredentials()
  service.connect_with_retries("deepgram", deepgram_creds) do |c|
    voice_assistant_controller.connectDeepgram(c)
  end
end
```

---

## Metrics & Analytics

### Overview

Track and analyze voice transcription usage:
- Session metrics (duration, provider, success/failure)
- Provider performance statistics
- Entity usage reports
- System health alerts
- Comparative provider analysis

### Service: `VoiceMetricsService`

**Purpose**: Record, aggregate, and analyze voice session metrics

**Key Methods**:

```ruby
service = VoiceMetricsService.new

# Record session metrics
metric = service.record_session_metric(
  voice_session,
  "eleven_labs",
  connection_time_ms: 150,
  transcript_count: 3,
  duration_seconds: 45,
  success: true,
  fallback_used: false
)

# Get provider statistics
stats = service.get_provider_statistics("eleven_labs", days: 7)
# Returns: {
#   provider, period_days, total_sessions, successful_sessions,
#   failed_sessions, success_rate_percent, avg_connection_time_ms,
#   avg_session_duration_seconds, fallback_sessions, fallback_rate_percent,
#   common_errors
# }

# Compare providers
comparison = service.compare_providers("eleven_labs", "deepgram", days: 7)
# Returns: { provider1, provider2, winner, recommendation }

# Get entity usage
report = service.get_entity_usage_report(entity_id, days: 7)
# Returns: { entity_id, period_days, total_sessions, provider_breakdown }

# Get recent sessions
sessions = service.get_recent_sessions(limit: 10)

# Check system health with alerts
health = service.check_voice_system_health
# Returns: { seven_day_stats, one_day_stats, alerts }
```

**Metrics Retention**: 30 days (configurable)

**Example Report**:

```
Provider: Eleven Labs
Period: 7 days
Total Sessions: 142
Success Rate: 98.6%
Avg Connection Time: 156ms
Fallback Rate: 1.4%
Common Errors:
  - Timeout after 30s: 2 occurrences
```

---

## Performance Optimization

### Overview

Optimize voice connection performance:
- Credential caching
- Connection pre-warming
- Connection pooling
- Performance monitoring

### Service: `VoiceConnectionOptimizer`

**Purpose**: Optimize connection performance and reduce latency

**Configuration**:
```ruby
CREDENTIAL_CACHE_TTL = 1.hour
CONNECTION_POOL_SIZE = 5
PREWARM_INTERVAL = 5.minutes
```

**Key Methods**:

```ruby
optimizer = VoiceConnectionOptimizer.new

# Get or cache credentials
creds = optimizer.get_or_cache_credentials("eleven_labs", ttl: 1.hour)

# Check if credentials are cached
valid = optimizer.has_valid_cached_credentials?("eleven_labs")

# Pre-warm connections (reduce initial latency)
result = optimizer.prewarm_connections
# Returns: { timestamp, providers: { eleven_labs: {...}, deepgram: {...} } }

# Clear credential cache (after rotation)
optimizer.clear_credential_cache("eleven_labs")  # Single provider
optimizer.clear_credential_cache               # All providers

# Get cache statistics
stats = optimizer.get_cache_statistics
# Returns: { timestamp, cached_providers, total_cached }

# Get optimization metrics
metrics = optimizer.get_optimization_metrics
# Returns: { timestamp, cache_statistics, provider_health, recommendations }

# Check connection pool
pool_status = optimizer.get_connection_pool_status("eleven_labs")
# Returns: { provider, pool_size, max_size, active_connections, utilization_percent }
```

**Benefits**:

| Feature | Impact | Benefit |
|---------|--------|---------|
| Credential Caching | 10-20ms faster | Reduced API calls |
| Connection Pre-warming | 50-100ms faster | Instant availability |
| Connection Pooling | Concurrent sessions | Better resource usage |

**Example Usage - Pre-warming on Startup**:

```ruby
# In initializer or background job
def warm_up_voice_system
  optimizer = VoiceConnectionOptimizer.new
  result = optimizer.prewarm_connections

  result[:providers].each do |provider, status|
    if status[:status] == "ready"
      Rails.logger.info "✅ #{provider} pre-warmed (#{status[:warmup_time_ms]}ms)"
    else
      Rails.logger.warn "⚠️ #{provider} pre-warming failed: #{status[:error]}"
    end
  end
end
```

---

## API Endpoints

### Health Monitoring Endpoints

All health endpoints are authenticated (except `/api/voice/health/status`).

#### GET `/api/voice/health/status`
Overall voice system health status

**Response**:
```json
{
  "timestamp": "2024-11-15T10:30:00Z",
  "status": "ok",
  "voice_system": {
    "overall_status": "healthy",
    "both_providers_available": true,
    "recommended_action": "OK: Both providers healthy and available."
  },
  "endpoints": {
    "eleven_labs": {
      "status": "healthy",
      "available": true,
      "latency_ms": 150
    },
    "deepgram": {
      "status": "healthy",
      "available": true,
      "latency_ms": 200
    }
  }
}
```

#### GET `/api/voice/health/providers`
Detailed provider status and metrics

**Response**:
```json
{
  "timestamp": "2024-11-15T10:30:00Z",
  "providers": {
    "eleven_labs": {
      "health": {...},
      "metrics": {
        "total_attempts": 250,
        "successful": 245,
        "failed": 5,
        "avg_latency_ms": 156
      }
    },
    "deepgram": {...}
  }
}
```

#### GET `/api/voice/health/metrics?days=7`
Usage and performance metrics

**Query Parameters**:
- `days` (optional): Number of days to analyze (default: 7)

**Response**:
```json
{
  "timestamp": "2024-11-15T10:30:00Z",
  "period_days": 7,
  "providers": {
    "eleven_labs": {
      "total_sessions": 142,
      "successful_sessions": 140,
      "success_rate_percent": 98.6,
      "avg_connection_time_ms": 156,
      "fallback_rate_percent": 1.4,
      "common_errors": [...]
    },
    "deepgram": {...}
  },
  "comparison": {
    "winner": "eleven_labs",
    "recommendation": "Eleven Labs has lower latency (156ms vs 200ms)"
  }
}
```

#### GET `/api/voice/health/optimization`
Performance optimization recommendations

**Response**:
```json
{
  "timestamp": "2024-11-15T10:30:00Z",
  "optimization_metrics": {
    "recommendations": [
      {
        "category": "caching",
        "priority": "high",
        "recommendation": "Enable credential caching...",
        "expected_benefit": "10-20ms faster"
      }
    ]
  },
  "cache_statistics": {...},
  "connection_pools": {...},
  "recommendations": [...]
}
```

#### POST `/api/voice/health/prewarm`
Manually trigger connection pre-warming

**Response**:
```json
{
  "timestamp": "2024-11-15T10:30:00Z",
  "prewarm_result": {
    "eleven_labs": {
      "status": "ready",
      "warmup_time_ms": 145
    },
    "deepgram": {
      "status": "ready",
      "warmup_time_ms": 195
    }
  },
  "message": "Connection pre-warming completed"
}
```

---

## Configuration

### Environment Variables

```bash
# Required for Eleven Labs (primary provider)
ELEVEN_LABS_API_KEY=your_api_key

# Recommended for Deepgram (fallback provider)
DEEPGRAM_API_KEY=your_api_key
```

### Redis Configuration

Services use Rails cache (Redis recommended) for:
- Health check metrics
- Circuit breaker state
- Credential caching
- Session metrics

**Ensure Redis is configured**:
```ruby
# config/environments/production.rb
config.cache_store = :redis_cache_store, { url: ENV['REDIS_URL'] }
```

### Background Jobs (Optional)

For periodic pre-warming and health checks:

```ruby
# config/sidekiq.yml or SolidQueue config
cron:
  voice_prewarm:
    cron: '*/5 * * * *'  # Every 5 minutes
    class: VoicePrewarmJob

  voice_health_check:
    cron: '*/10 * * * *'  # Every 10 minutes
    class: VoiceHealthCheckJob
```

---

## Monitoring Dashboard

### Key Metrics to Track

**Provider Availability**:
- Uptime % (target: >99%)
- Fallback rate (target: <2%)
- Average latency (Eleven Labs: <200ms, Deepgram: <300ms)

**System Health**:
- Success rate % (target: >98%)
- Connection failures (target: <1%)
- Circuit breaker trips (target: 0)

**Performance**:
- Average connection time
- Peak concurrent sessions
- Cache hit rate

### Alerts to Configure

**Critical**:
- Both providers unavailable
- Success rate <50%
- Circuit breaker open

**Warning**:
- Success rate <80%
- Provider unavailable (fallback active)
- High latency (>500ms)

---

## Testing

### Unit Tests

```bash
# Health checks
bundle exec rails test test/services/voice_provider_health_service_test.rb

# Error recovery
bundle exec rails test test/services/voice_connection_retry_service_test.rb

# Metrics
bundle exec rails test test/services/voice_metrics_service_test.rb

# Optimization
bundle exec rails test test/services/voice_connection_optimizer_test.rb

# All voice tests
bundle exec rails test test/services/voice_*_test.rb
```

### Integration Tests

```bash
# Health endpoints
bundle exec rails test test/controllers/api/voice/health_controller_test.rb

# Full voice system
bundle exec rails test test/controllers/api/voice/
```

---

## Troubleshooting

### Provider Unavailable

1. Check health endpoint: `/api/voice/health/status`
2. Verify API credentials in environment
3. Check network connectivity
4. Review provider status page (elevenlabs.io, deepgram.com)

### High Failure Rate

1. Check metrics: `/api/voice/health/metrics`
2. Review common errors in metric response
3. Examine circuit breaker status
4. Check provider latency

### Slow Connections

1. Check optimization metrics: `/api/voice/health/optimization`
2. Verify credential caching is enabled
3. Run pre-warming: `POST /api/voice/health/prewarm`
4. Check connection pool utilization

### Memory Issues

1. Check Redis cache size
2. Review metrics retention (30 days max)
3. Monitor circuit breaker state cleanup
4. Verify connection pool size is reasonable

---

## Best Practices

1. **Monitor regularly** - Check health endpoint at least every 5 minutes
2. **Cache credentials** - Use credential caching to reduce API calls
3. **Pre-warm connections** - Run pre-warming on startup and periodically
4. **Track metrics** - Monitor success rates and latency trends
5. **Alert on failures** - Set up alerts for critical issues
6. **Test fallback** - Regularly verify fallback provider works
7. **Rotate credentials** - Clear cache after credential updates
8. **Review logs** - Check voice system logs for errors and patterns

---

## Support

For issues or questions:
1. Check health status: `/api/voice/health/status`
2. Review metrics: `/api/voice/health/metrics`
3. Check logs for error details
4. Contact provider support if API issues
