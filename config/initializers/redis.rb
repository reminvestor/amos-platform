# Configure Redis connection
require 'openssl'
require 'uri'

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
redis_options = {}

if Rails.env.production?
  # On Heroku: Keep the SSL scheme but disable SSL verification
  redis_options[:ssl_params] = { verify_mode: OpenSSL::SSL::VERIFY_NONE }
  redis_options[:url] = redis_url
  
  # Add additional options to improve reliability
  redis_options[:reconnect_attempts] = 5
  redis_options[:network_timeout] = 5
  redis_options[:timeout] = 5
  
  # Log the Redis connection setup for debugging
  Rails.logger.info("Configuring Redis with: #{parsed_uri.scheme}://#{parsed_uri.host}:#{parsed_uri.port}")
else
  # For development, just use the URL as-is
  redis_options[:url] = redis_url
end

# Configure Sidekiq server
Sidekiq.configure_server do |config|
  config.redis = redis_options
end

# Configure Sidekiq client
Sidekiq.configure_client do |config|
  config.redis = redis_options
end 