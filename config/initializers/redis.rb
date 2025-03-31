# Configure Redis connection
uri = ENV["REDIS_URL"] || "redis://localhost:6379"

# Configure Sidekiq with SSL verification disabled
Sidekiq.configure_server do |config|
  ssl_params = { verify_mode: OpenSSL::SSL::VERIFY_NONE }
  config.redis = { url: uri, ssl_params: ssl_params }
end

Sidekiq.configure_client do |config|
  ssl_params = { verify_mode: OpenSSL::SSL::VERIFY_NONE }
  config.redis = { url: uri, ssl_params: ssl_params }
end 