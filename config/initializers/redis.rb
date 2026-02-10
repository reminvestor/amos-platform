# Configure Redis connection
require "openssl"
require "uri"
require "redis"

# Add a NullRedis implementation that won't break the app if Redis is unavailable
class NullRedis
  def ping
    "PONG" # Simulate successful connection
  end

  def get(key)
    nil # Always return nil for any key
  end

  def set(key, value)
    true # Pretend we saved it
  end

  def expire(key, seconds)
    true # Pretend we set expiration
  end

  def hset(key, field, value)
    true # Pretend we saved it
  end

  def hgetall(key)
    {} # Return empty hash
  end

  def method_missing(method, *args, &block)
    nil # Return nil for any other method
  end
end

# Get the Redis URL from environment or use default localhost
redis_url = ENV["REDIS_URL"] || "redis://localhost:6379"

# Log the raw Redis URL (without credentials for security)
begin
  parsed_uri = URI.parse(redis_url)
  masked_url = "#{parsed_uri.scheme}://#{parsed_uri.host}:#{parsed_uri.port}"
  Rails.logger.info("Redis URL detected: #{masked_url}")
rescue URI::InvalidURIError => e
  Rails.logger.error("Invalid Redis URL format: #{e.message}")
  # Use default as fallback
  redis_url = "redis://localhost:6379"
  parsed_uri = URI.parse(redis_url)
end

# Configure Redis options based on environment
REDIS_OPTIONS = {}

if Rails.env.production?
  REDIS_OPTIONS[:url] = redis_url

  # Add additional options to improve reliability - use options compatible with Redis 5.x
  REDIS_OPTIONS[:reconnect_attempts] = 5
  REDIS_OPTIONS[:timeout] = 5
  REDIS_OPTIONS[:read_timeout] = 5
  REDIS_OPTIONS[:write_timeout] = 5

  # Log the Redis connection setup for debugging
  Rails.logger.info("Configuring Redis with: #{masked_url}")
else
  # For development, just use the URL as-is
  REDIS_OPTIONS[:url] = redis_url
end

# Create a global Redis connection for the application
$redis = nil

# Initialize Redis client safely
begin
  $redis = Redis.new(REDIS_OPTIONS)
  $redis.ping # Test connection
  Rails.logger.info("Redis connection established successfully")
rescue => e
  # Catch ALL errors (Redis::BaseError, RedisClient::CannotConnectError,
  # Errno::ECONNREFUSED, SocketError, etc.) so Rails can still boot
  # for tasks like db:migrate that don't need Redis.
  Rails.logger.error("Failed to connect to Redis: #{e.message}")
  Rails.logger.error(e.backtrace.first(10).join("\n"))
  # Initialize with a dummy Redis that won't crash the app
  $redis = NullRedis.new
end

# Add a safe_redis method for global access to Redis
def safe_redis
  begin
    return $redis if $redis && !$redis.is_a?(NullRedis) && $redis.ping == "PONG"
  rescue => e
    Rails.logger.error("Redis connection error: #{e.message}")
  end

  begin
    # Try to reconnect
    $redis = Redis.new(REDIS_OPTIONS)
    $redis.ping
    $redis
  rescue => e
    Rails.logger.error("Failed to reconnect to Redis: #{e.message}")
    # Return NullRedis if Redis is unavailable
    $redis = NullRedis.new
    $redis
  end
end

# Make safe_redis available to Redis class for backward compatibility
module RedisHelper
  def self.safe
    safe_redis
  end
end

# Add the safe method to Redis
Redis.singleton_class.prepend(RedisHelper)

# Sidekiq is not being used - this app uses Solid::Queue
# Keeping these configurations commented in case they're needed in the future
# begin
#   # Configure Sidekiq server
#   Sidekiq.configure_server do |config|
#     config.redis = REDIS_OPTIONS
#   end
#
#   # Configure Sidekiq client
#   Sidekiq.configure_client do |config|
#     config.redis = REDIS_OPTIONS
#   end
# rescue => e
#   Rails.logger.error("Failed to configure Sidekiq with Redis: #{e.message}")
# end
