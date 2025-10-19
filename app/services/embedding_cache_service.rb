class EmbeddingCacheService
  CACHE_PREFIX = "embedding_cache"
  MAX_CACHE_SIZE = 10_000
  TTL = 30.days
  STATS_PREFIX = "embedding_stats"

  def initialize
    @redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))
  rescue Redis::CannotConnectError => e
    Rails.logger.error "❌ Redis connection failed: #{e.message}"
    @redis = nil
  end

  # Check if cache is available
  def available?
    @redis&.ping == "PONG"
  rescue
    false
  end

  # Get cached embedding
  def get(text)
    return nil unless available?

    cache_key = generate_key(text)
    cached = @redis.get(cache_key)

    if cached
      increment_stat(:hits)
      Rails.logger.debug "✅ Embedding cache hit"
      JSON.parse(cached)
    else
      increment_stat(:misses)
      Rails.logger.debug "❌ Embedding cache miss"
      nil
    end
  rescue => e
    Rails.logger.error "Embedding cache get error: #{e.message}"
    nil
  end

  # Store embedding
  def put(text, embedding)
    return unless available?

    cache_key = generate_key(text)

    # Check cache size and evict if needed
    if cache_size > MAX_CACHE_SIZE
      evict_oldest
    end

    # Store with TTL
    @redis.setex(
      cache_key,
      TTL.to_i,
      embedding.to_json
    )

    Rails.logger.debug "💾 Cached embedding: #{cache_key[0..20]}..."
  rescue => e
    Rails.logger.error "Embedding cache put error: #{e.message}"
  end

  # Batch get - returns array with nil for cache misses
  def get_batch(texts)
    return Array.new(texts.length) unless available?

    keys = texts.map { |t| generate_key(t) }

    # Use MGET for batch retrieval
    values = @redis.mget(*keys)

    # Track stats
    hits = values.count { |v| v.present? }
    misses = values.count { |v| v.nil? }
    increment_stat(:hits, hits)
    increment_stat(:misses, misses)

    Rails.logger.debug "📊 Batch cache: #{hits} hits, #{misses} misses"

    # Parse JSON values
    values.map { |v| v ? JSON.parse(v) : nil }
  rescue => e
    Rails.logger.error "Embedding cache batch get error: #{e.message}"
    Array.new(texts.length)
  end

  # Batch put
  def put_batch(texts, embeddings)
    return unless available?

    texts.zip(embeddings).each do |text, embedding|
      put(text, embedding)
    end
  end

  # Get cache statistics
  def stats
    return default_stats unless available?

    hits = @redis.get("#{STATS_PREFIX}:hits").to_i
    misses = @redis.get("#{STATS_PREFIX}:misses").to_i
    total = hits + misses

    {
      enabled: true,
      total_keys: cache_size,
      memory_usage: @redis.info["used_memory_human"],
      hits: hits,
      misses: misses,
      total_requests: total,
      hit_rate: total.zero? ? 0 : (hits.to_f / total * 100).round(2),
      max_size: MAX_CACHE_SIZE,
      ttl_days: TTL / 1.day
    }
  rescue => e
    Rails.logger.error "Embedding cache stats error: #{e.message}"
    default_stats
  end

  # Clear cache
  def clear!
    return unless available?

    keys = @redis.keys("#{CACHE_PREFIX}:*")
    @redis.del(*keys) if keys.any?

    # Reset stats
    @redis.del("#{STATS_PREFIX}:hits")
    @redis.del("#{STATS_PREFIX}:misses")

    Rails.logger.info "🗑️  Cleared #{keys.length} cached embeddings"
  end

  # Clear stats only
  def reset_stats!
    return unless available?

    @redis.del("#{STATS_PREFIX}:hits")
    @redis.del("#{STATS_PREFIX}:misses")

    Rails.logger.info "📊 Reset embedding cache stats"
  end

  private

  def generate_key(text)
    # Use SHA256 hash of normalized text as key
    normalized = text.to_s.strip.downcase
    digest = Digest::SHA256.hexdigest(normalized)
    "#{CACHE_PREFIX}:#{digest}"
  end

  def cache_size
    @redis.keys("#{CACHE_PREFIX}:*").length
  rescue
    0
  end

  def evict_oldest
    # Get all cache keys
    keys = @redis.keys("#{CACHE_PREFIX}:*")
    return if keys.empty?

    # Get TTL for each key
    keys_with_ttl = keys.map { |k| [k, @redis.ttl(k)] }

    # Delete 10% of keys with shortest TTL
    to_delete_count = [1, (keys.length * 0.1).to_i].max
    to_delete = keys_with_ttl.sort_by { |_, ttl| ttl }
                              .first(to_delete_count)
                              .map(&:first)

    deleted = @redis.del(*to_delete)
    Rails.logger.info "🗑️  Evicted #{deleted} oldest embeddings (LRU)"
  rescue => e
    Rails.logger.error "Embedding cache eviction error: #{e.message}"
  end

  def increment_stat(stat_type, count = 1)
    @redis.incrby("#{STATS_PREFIX}:#{stat_type}", count)
  rescue => e
    Rails.logger.error "Embedding cache stat increment error: #{e.message}"
  end

  def default_stats
    {
      enabled: false,
      total_keys: 0,
      memory_usage: "N/A",
      hits: 0,
      misses: 0,
      total_requests: 0,
      hit_rate: 0,
      max_size: MAX_CACHE_SIZE,
      ttl_days: TTL / 1.day,
      error: "Redis not available"
    }
  end
end
