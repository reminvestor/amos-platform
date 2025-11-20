# Prevents AWS Bedrock throttling by queuing requests
# Ensures fair distribution across all users/entities
class BedrockRateLimiter
  REDIS_KEY = "bedrock:rate_limit"

  # AWS Bedrock limits (conservative estimates per region)
  # Actual limits depend on account quotas - check AWS Console
  # Set to 80% of actual limit to leave buffer for spikes
  REQUESTS_PER_MINUTE = 80  # Adjust based on your AWS quota (100 * 0.8)

  # Warn threshold - when to start showing "high demand" indicators
  WARN_THRESHOLD = 60  # 75% of limit

  def initialize
    @redis = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1"))
  end

  # Acquire permission to make Bedrock request
  # Returns: { allowed: true/false, wait_time: seconds }
  def acquire
    current_count = @redis.get(REDIS_KEY).to_i

    if current_count < REQUESTS_PER_MINUTE
      # Increment counter with 60s expiry (rolling window)
      @redis.multi do |r|
        r.incr(REDIS_KEY)
        r.expire(REDIS_KEY, 60)
      end

      { allowed: true, wait_time: 0 }
    else
      # Calculate wait time until window resets
      ttl = @redis.ttl(REDIS_KEY)
      wait_time = ttl > 0 ? ttl : 60

      { allowed: false, wait_time: wait_time }
    end
  end

  # Check current usage without incrementing
  def current_usage
    current = @redis.get(REDIS_KEY).to_i
    remaining = [REQUESTS_PER_MINUTE - current, 0].max

    {
      current: current,
      limit: REQUESTS_PER_MINUTE,
      remaining: remaining,
      usage_percent: (current.to_f / REQUESTS_PER_MINUTE * 100).round(1)
    }
  end

  # Reset counter (admin use only)
  def reset!
    @redis.del(REDIS_KEY)
  end
end
